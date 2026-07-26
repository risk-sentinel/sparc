# HDF Amendment Triage API

REST API for the HDF Amendment triage workflow (#447): ingest scanner findings
(in Heimdall Data Format), triage failed controls into dispositions, and export a
per-boundary HDF Amendments document for `hdf amend apply`.

This is the persistent, human-in-the-loop layer over the stateless
[HDF ↔ OSCAL translation bridge](translations.md) (#449). SPARC is a translation
artefact store, not the system of record — dispositions are re-derivable from the
tenant's own scanner output and supporting records.

Related surfaces:

- [Evidence](evidences.md) / [Attestations](attestations.md) — justify `falsePositive` / `waiver`
- [POA&M Documents](poam-documents.md) — the tracker `poam` / `vendorDependency` link to
- [Authorization Boundaries](authorization-boundaries.md) — the scope for all triage

## Authentication & authorization

All endpoints require a Bearer token. Access is boundary-scoped and reuses the
evidence permissions: `evidence.read` to view findings/dispositions and export,
`evidence.write` to ingest scans and set/clear dispositions. Instance admins
bypass. The `:authorization_boundary_id` segment accepts a numeric id or slug;
finding/disposition segments use the finding **uuid**.

## Ingest a scan

```
POST /api/v1/authorization_boundaries/:authorization_boundary_id/scan_runs
```

Multipart (`file=@scan.hdf.json`) or a raw HDF JSON body. Accepts a single HDF
results document or a `saf convert` bundle (array of HDF docs). Idempotent by
`(boundary, control_id)`: a fresh scan updates existing findings and preserves
their dispositions.

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -F "file=@scan.hdf.json" \
  https://sparc.example.com/api/v1/authorization_boundaries/my-system/scan_runs
```

Returns `201` with the run summary (`scanner`, `finding_count`, `failed_count`, …).
`422` on malformed HDF or a document with no controls.

## List runs & findings

```
GET /api/v1/authorization_boundaries/:authorization_boundary_id/scan_runs
GET /api/v1/authorization_boundaries/:authorization_boundary_id/scanner_findings?status=failed&severity=HIGH
GET /api/v1/scanner_findings/:uuid
```

`scanner_findings` is the triage worklist (filter `status=failed`). Each finding
surfaces its current `disposition_kind` (or null).

## Set / clear a disposition

```
GET    /api/v1/scanner_findings/:uuid/disposition
POST   /api/v1/scanner_findings/:uuid/disposition
DELETE /api/v1/scanner_findings/:uuid/disposition
```

`POST` creates or replaces the one disposition for the finding.

| Param | Notes |
|---|---|
| `kind` | one of `falsePositive`, `waiver`, `poam`, `vendorDependency`, `inherited`, `riskAdjustment`, `operationalRequirement` |
| `reason` | required justification |
| `linked_subject_type` / `linked_subject_id` | the supporting record (`Evidence`, `Attestation`, `PoamFinding`, `AuthorizationBoundary`, `RiskAssessment`) |
| `expiration` | required for `waiver` / `operationalRequirement` |

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -d "kind=falsePositive" -d "reason=unreachable code path" \
  -d "linked_subject_type=Evidence" -d "linked_subject_id=42" \
  https://sparc.example.com/api/v1/scanner_findings/$UUID/disposition
```

Enforced rules (`422` on violation): the linked type must match the kind; `waiver`
/ `operationalRequirement` need an *Authorizing Official* attestation; CRITICAL
findings cannot be waived, downgraded, or marked operational (remediate or POA&M).

## Export amendments

```
GET /api/v1/authorization_boundaries/:authorization_boundary_id/hdf_amendments[?verify=false]
```

Returns the raw HDF Amendments JSON (schema v3.4.0) — one override per current,
non-expired disposition, deterministic (stable ordering + content-seeded
`amendmentId`). The output is validated with `hdf amend verify` before it is
returned (`?verify=false` skips this); a schema drift returns `422`.

```bash
curl -H "Authorization: Bearer $TOKEN" \
  https://sparc.example.com/api/v1/authorization_boundaries/my-system/hdf_amendments \
  > amendments.hdf.json
hdf amend apply --results scan.hdf.json --amendments amendments.hdf.json -o amended.hdf.json
saf validate threshold -i amended.hdf.json -F threshold.yml
```
