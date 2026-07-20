# HDF ↔ OSCAL Translation Bridge — Pipeline Demo

End-to-end demo of the SPARC translation surface introduced in
[#449](https://github.com/risk-sentinel/sparc/issues/449). Tenant
pipelines can move scan data between the HDF and OSCAL ecosystems
without writing any code or installing the `hdf` CLI on their side —
SPARC bakes the binary into the container and exposes it via three
authenticated REST endpoints.

**SPARC's role here is translation + audit, not source of truth.** The
tenant's scanner output, POA&M tracker, and AO sign-offs remain
authoritative; SPARC's translation records are an artefact of the
pipeline, not the canonical state.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/v1/oscal/sar_from_hdf` | HDF results → OSCAL Assessment Results |
| POST | `/api/v1/oscal/poam_from_hdf` | HDF results → OSCAL Plan of Action & Milestones |
| POST | `/api/v1/hdf/amendments_from_oscal_poam` | OSCAL POA&M → HDF Amendments JSON |

All three accept either:

- **Multipart upload** with a `:file` field, or
- **Raw JSON request body** (set `Content-Type: application/json`)

All three require a Bearer API token. No additional permission is
required beyond authentication for the base translation. Adding
`?authorization_boundary_id=N` to either OSCAL emission endpoint
enriches the output with SPARC-hosted Evidence records as OSCAL
back-matter `resource[]` entries; this requires `evidence.read` on
the boundary (or admin).

## Prerequisites

```bash
# 1. SPARC API token
export SPARC_TOKEN="your-bearer-token"
export SPARC_URL="https://sparc.example.com"

# 2. (For the local sanity check)
hdf version  # 3.4.1 or compatible
```

## Demo 1 — HDF results → OSCAL SAR

```bash
# Tenant has a Trivy scan output already converted to HDF (any of the
# 33+ scanner formats works — see `hdf convert --help`):
hdf convert --from trivy /tmp/trivy-scan.json -o /tmp/scan.hdf.json

# SPARC emits the OSCAL Assessment Results equivalent
curl -fsSL -X POST "$SPARC_URL/api/v1/oscal/sar_from_hdf" \
  -H "Authorization: Bearer $SPARC_TOKEN" \
  -H "Content-Type: application/json" \
  --data @/tmp/scan.hdf.json \
  -o /tmp/sar.oscal.json

# Validate the output (sanity check; SPARC's response is already valid)
hdf validate --type results /tmp/sar.oscal.json   # validates HDF; substitute oscal validator as desired
```

## Demo 2 — HDF results → OSCAL POA&M (with evidence back-matter)

When the tenant hosts evidence in SPARC for an AuthorizationBoundary,
the OSCAL output auto-includes those records:

```bash
BOUNDARY_ID=42

curl -fsSL -X POST \
  "$SPARC_URL/api/v1/oscal/poam_from_hdf?authorization_boundary_id=$BOUNDARY_ID" \
  -H "Authorization: Bearer $SPARC_TOKEN" \
  -H "Content-Type: application/json" \
  --data @/tmp/scan.hdf.json \
  -o /tmp/poam.oscal.json

# Inspect back-matter
jq '.["plan-of-action-and-milestones"]["back-matter"].resources | length' /tmp/poam.oscal.json
jq '.["plan-of-action-and-milestones"]["back-matter"].resources[0].props' /tmp/poam.oscal.json
```

Each evidence resource carries:

- `uuid`, `title`, `description`
- `props[]`: `source`, `evidence-type`, `status`, `control-id` (one per linked control), and `attestation` lines (one per Attestation row, with name + role + ISO-8601 timestamp + status)
- `rlinks[]`: pointer to the SPARC evidence path with media-type when known

## Demo 3 — OSCAL POA&M → HDF Amendments (reverse direction)

For tenants whose POA&M tracker emits OSCAL POA&M and who want to feed
it back into a `hdf amend apply` gate:

```bash
curl -fsSL -X POST "$SPARC_URL/api/v1/hdf/amendments_from_oscal_poam" \
  -H "Authorization: Bearer $SPARC_TOKEN" \
  -H "Content-Type: application/json" \
  --data @/tmp/external-poam.oscal.json \
  -o /tmp/amendments.hdf.json

# Apply the amendments to a fresh scan in the tenant's CI:
hdf amend apply \
  --results /tmp/scan.hdf.json \
  --amendments /tmp/amendments.hdf.json \
  -o /tmp/scan.amended.hdf.json

# Threshold gate
saf validate threshold -F /tmp/scan.amended.hdf.json -T threshold.yml
```

SPARC validates the generated amendments via `hdf amend verify` before
serving, so a payload that comes out of this endpoint is guaranteed to
apply cleanly.

## Full circle — any order, any format

The three endpoints compose:

```
                ┌────────────────────────┐
                │ Native scanner output  │
                │  (Trivy / Brakeman /   │
                │   SARIF / Snyk / …)    │
                └────────────┬───────────┘
                             │ tenant: hdf convert --from <fmt>
                             ▼
                ┌────────────────────────┐
                │ HDF results JSON       │
                └─────────┬──────────────┘
                          │
            ┌─────────────┼──────────────────┐
            ▼             ▼                  ▼
   ┌──────────────┐  ┌──────────────┐  (tenant: hdf amend apply
   │ /oscal/sar_  │  │ /oscal/poam_ │      with amendments below)
   │  from_hdf    │  │  from_hdf    │              ▲
   └──────┬───────┘  └──────┬───────┘              │
          │                 │                      │
          ▼                 ▼                      │
   ┌──────────────┐  ┌──────────────┐              │
   │ OSCAL SAR    │  │ OSCAL POA&M  │──┐           │
   └──────────────┘  └──────────────┘  │           │
                                       │           │
                                       ▼           │
                              ┌────────────────────┴┐
                              │ /hdf/amendments_    │
                              │  from_oscal_poam    │
                              └─────────────────────┘
```

A tenant can:

- Upload native scanner output → get OSCAL SAR/POA&M for their package
- Maintain POA&Ms in OSCAL (e.g. eMASS, FedRAMP-style) → fold those decisions back into their CI gate via Amendments
- Mix and match — there's no required order

## Audit

Every successful translation creates an `AuditEvent` record:

| Endpoint | `AuditEvent.action` |
|---|---|
| `oscal/sar_from_hdf` | `translation_hdf_to_oscal_sar` |
| `oscal/poam_from_hdf` | `translation_hdf_to_oscal_poam` |
| `hdf/amendments_from_oscal_poam` | `translation_oscal_poam_to_hdf_amendments` |

When `authorization_boundary_id` is supplied, the metadata records
the boundary id for forensic traceability.

## Local development

```bash
# One-time: install hdf binary into your shell's PATH
bin/install-hdf.sh   # installs the pinned version (3.4.1)

# Verify
hdf version

# Run SPARC locally
bin/rails server

# Smoke-test the endpoints with a fixture HDF
curl -fsSL -X POST "http://localhost:3000/api/v1/oscal/sar_from_hdf" \
  -H "Authorization: Bearer $SPARC_TOKEN" \
  -H "Content-Type: application/json" \
  --data @spec/fixtures/files/hdf/sample-results.hdf.json
```

## References

- Issue [#449](https://github.com/risk-sentinel/sparc/issues/449) — umbrella for this slice
- Issue [#447](https://github.com/risk-sentinel/sparc/issues/447) — Plan B / future expansion (hosted multi-reviewer disposition workflow)
- [MITRE hdf-libs](https://github.com/mitre/hdf-libs) — Apache 2.0
- [HDF Amendments schema v3.4.0](https://mitre.github.io/hdf-libs/schemas/hdf-amendments/v3.4.0/)
- NIST SP 800-53 mapping: CA-7, RA-3, SI-2 — see `docs/compliance/nist-sp800-53-rev5-mapping.md`
