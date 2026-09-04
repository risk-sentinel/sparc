# POA&M Risks API

REST API for **POA&M risks** (#832) — the risk records that give a Plan of Action & Milestones its substance: what the risk is, how it affects the system, its current status, and the date it is committed to be resolved by.

This endpoint exists because a risk missing required content used to be **accepted** and only fail much later, when the POA&M was exported and rejected by OSCAL schema validation — with nothing to indicate which record caused it. Risks are now validated at the point of entry and an incomplete one is rejected with a `422` naming the missing fields.

> **Note:** POA&M documents themselves are managed through the
> [POA&M Documents API](poam-documents.md). Create the document first, then add
> risks to it.

## Base URL

```
https://sparc.example.com/api/v1/poam_documents/:poam_document_id/risks
https://sparc.example.com/api/v1/poam_risks/:id
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

| Action | Permission |
|--------|-----------|
| `index`, `show` | `poam.read` (or Instance Admin) |
| `create`, `update`, `destroy` | `poam.write` (or Instance Admin) |

Permissions are scoped to the authorization boundary of the parent POA&M document.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/poam_documents/:poam_document_id/risks` | List risks for a POA&M (paginated) |
| `POST` | `/api/v1/poam_documents/:poam_document_id/risks` | Create a risk |
| `GET` | `/api/v1/poam_risks/:id` | Show a single risk (detailed) |
| `PATCH/PUT` | `/api/v1/poam_risks/:id` | Update a risk |
| `DELETE` | `/api/v1/poam_risks/:id` | Delete a risk (audit-logged) |

---

## Required fields

| Field | Required by | Why |
|-------|-------------|-----|
| `title` | OSCAL | `risk/title` |
| `description` | OSCAL | `risk/description` |
| `statement` | OSCAL | `risk/statement` — how the risk affects the system |
| `status` | OSCAL | `risk/status` |
| `deadline` | **SPARC** | A POA&M item with no time commitment is not a plan of action |

`uuid` is generated when omitted.

`deadline` is a SPARC rule rather than an OSCAL one. OSCAL does not require it, but a POA&M whose items carry no date is not acceptable to an assessor or AO, and `hdf convert --from oscal-poam --to hdf-amendments` refuses an item whose risks carry no usable deadline. (hdf-cli 3.3.2 silently invented "conversion time + one year"; 3.4.1 correctly stopped.)

None of these are defaulted or synthesised. A risk statement and a deadline are commitments, and generating them would produce a POA&M that is schema-valid and untrue.

## Create a risk

```bash
curl -s -X POST https://sparc.example.com/api/v1/poam_documents/12/risks \
  -H "Authorization: Bearer $SPARC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "poam_risk": {
      "title": "Hard-coded credentials in the admin panel",
      "description": "Static credentials are present in the deployed configuration.",
      "statement": "An attacker with read access to the image can authenticate as an administrator.",
      "status": "open",
      "deadline": "2026-10-31T00:00:00Z",
      "impact": "high",
      "likelihood": "medium"
    }
  }'
```

`201 Created`:

```json
{
  "data": {
    "id": 41,
    "uuid": "9f2c1f1e-6a1e-4f0e-9a3a-1c2d3e4f5a6b",
    "title": "Hard-coded credentials in the admin panel",
    "status": "open",
    "deadline": "2026-10-31T00:00:00Z",
    "likelihood": "medium",
    "impact": "high",
    "poam_document_id": 12,
    "description": "Static credentials are present in the deployed configuration.",
    "statement": "An attacker with read access to the image can authenticate as an administrator.",
    "created_at": "2026-07-27T18:22:03Z",
    "updated_at": "2026-07-27T18:22:03Z"
  }
}
```

## Rejection of an incomplete risk

Omitting any required field returns `422 Unprocessable Content` naming it:

```json
{
  "error": "Validation failed: Statement can't be blank, Deadline can't be blank",
  "details": [
    "Statement can't be blank",
    "Deadline can't be blank"
  ]
}
```

## Pre-existing incomplete rows

Risks created before these rules exist in databases upgraded from earlier versions. They are readable, but **cannot be saved again until completed** — including an edit to an unrelated field.

Any response describing such a risk carries a machine-readable `missing_fields` list, so a client can flag them without parsing the prose above:

```json
{
  "data": {
    "id": 17,
    "uuid": "0b1d...",
    "title": "Legacy risk",
    "missing_fields": [ "statement", "deadline" ]
  }
}
```

To find them all at once, operators can run:

```bash
bin/rails sparc:poam:audit_risks
```

which reports every incomplete risk grouped by document, with the exact fields each is missing. There is deliberately no auto-fix.

## Status values

`open`, `investigating`, `remediating`, `deviation-requested`, `deviation-approved`, `closed`

## The OSCAL collections (#1092)

A POA&M risk carries four collections beyond its scalar fields. All four are
stored as `jsonb` and emitted by the exporter, and until #1092 none of them could
be authored through any surface — measured on the demo estate, 0 of 18 POA&M
risks carried any.

| Write attribute | Read attribute | OSCAL |
|-----------------|----------------|-------|
| `threat_ids_data` | `threat_ids` | `threat-ids[]` |
| `mitigating_factors_data` | `mitigating_factors` | `mitigating-factors[]` |
| `origins_data` | `origins` | `origins[]` |
| `risk_log_data` | `risk_log` | `risk-log` |

The write name carries the `_data` suffix and the read name does not.

There is **no `remediations_data` here** — a POA&M models responses as real
`poam_remediations` rows with their own endpoints (see
[poam-subresources.md](poam-subresources.md)), not as jsonb on the risk. That is
the one place the POA&M and SAR risk shapes deliberately differ.

The accepted key shapes, the hyphenated-key rule, and the difference between a
top-level `422` and a silently-dropped nested key are identical to the SAR side
and documented once, in
[sar-risks.md § The OSCAL collections](sar-risks.md#the-oscal-collections-1092).

## NIST 800-53 controls

`IA-2` (token authentication), `AC-3` / `AC-6` (boundary-scoped RBAC), `AU-12` (audit record generation), `CA-5` (plan of action and milestones).
