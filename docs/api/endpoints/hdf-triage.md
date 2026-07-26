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
evidence permissions: `evidence.read` to view findings/dispositions, export, and
download the signed package; `evidence.write` to ingest scans, set/clear
dispositions, and aggregate. **Approving/rejecting** an amendment additionally
requires admin or the `amendment.approve` permission. Instance admins bypass. The
`:authorization_boundary_id` segment accepts a numeric id or slug;
finding/disposition segments use the finding **uuid**.

## Ingest a scan

```
POST /api/v1/authorization_boundaries/:authorization_boundary_id/scan_runs
```

Multipart (`file=@scan.hdf.json`) or a raw HDF JSON body. Accepts a single HDF
results document or a `saf convert` bundle (array of HDF docs). Findings are kept
per-scan-run as history (`current` flag) with a re-occurrence lifecycle; a fresh
scan supersedes the prior current findings and preserves their dispositions.

Optional params tie the scan to what it assessed (#811):

| Param | Notes |
|---|---|
| `cdef_document_id` | the component/target this scan assessed (id or slug); omit for boundary-wide scans |
| `scanner_scope` | `target` (default) or `boundary` |

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

`scanner_findings` is the triage worklist (filter `status=failed`). It returns the
**current** scan by default; add `include_history=true` for superseded rows.
Additional filters: `lifecycle=new|carried_forward|re_failed|expired|superseded`,
`cdef_document_id=…`. Each finding surfaces its `lifecycle_status`, `current`,
`component_ref`, `cdef_document_id`, `source_location`, and its current
`disposition_kind` + `disposition_approval` (or null).

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

A new disposition starts `approval_status=draft` and SPARC computes its
`valid_until` from the boundary profile's ODP (else the admin Remediation
Timelines SLA table); an active POA&M for the control means no expiry.

## Approve / reject an amendment (#809)

```
POST /api/v1/scanner_findings/:uuid/disposition/approve
POST /api/v1/scanner_findings/:uuid/disposition/reject
```

Requires admin or `amendment.approve`. A disposition only suppresses its finding
during aggregation/export once **approved** and within its `valid_until` window.
Returns the disposition with `approval_status`, `approved_by`, `approved_at`.

## Aggregate into SSP / SAP / SAR / POA&M (#809)

```
POST /api/v1/authorization_boundaries/:authorization_boundary_id/aggregate[?async=true]
```

Maps current findings to controls via their HDF `tags.nist`, writes a
non-destructive `hdf_scan_result` annotation on matching SSP/SAP/SAR controls, and
opens POA&M items for un-suppressed failures. Synchronous by default (`200` with a
per-document count summary); `?async=true` enqueues `AggregateFindingsJob` (`202`).
Requires `evidence.write`.

## Download the signed package (#809)

```
GET /api/v1/authorization_boundaries/:authorization_boundary_id/hdf_package
```

An HMAC-SHA256 signed bundle (amendments + findings summary + dispositions summary)
keyed from `SPARC_HASH` — tamper-evident and provably from this instance. Returns
`{ payload, encoded_payload, signature, algorithm }`. Requires `evidence.read`.

## Remediation Timelines (admin)

```
GET /api/v1/admin/remediation_timelines
PUT /api/v1/admin/remediation_timelines
```

Admin-only. The SLA fallback grid of baseline (Low/Moderate/High) × NIST
criticality (Critical/High/Moderate/Low/Informational/Unknown) → days, used to
compute amendment validity when the boundary profile carries no ODP.

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
