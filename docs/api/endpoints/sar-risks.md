# SAR Risks API

REST API for **SAR risks** (#1090) — the risks an assessment identified, and how
severe they are.

This endpoint exists because SAR risks previously had **no API at all**. POA&M
has eight sub-resource controllers; SAR had none, so a risk was reachable only
through the enrich screen, which accepted `title`, `description` and `status`.
The OSCAL rating — `impact` and `likelihood` — could not be set anywhere, and no
integrator could create or read one.

> **Note:** SAR documents themselves are managed through the
> [SAR Documents API](sar-documents.md). A risk belongs to a **result** within
> the document; supply `sar_result_id` to choose one, or omit it and the
> document's first result is used.

## Base URL

```
https://sparc.example.com/api/v1/sar_documents/:sar_document_id/risks
https://sparc.example.com/api/v1/sar_risks/:id
```

The parent document accepts either its **slug or its id**, matching what the
document listing hands out.

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

| Action | Permission |
|--------|-----------|
| `index`, `show` | `sar.read` (or Instance Admin) |
| `create`, `update`, `destroy` | `sar.write` (or Instance Admin) |

Permissions are scoped to the authorization boundary of the parent SAR document.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/sar_documents/:sar_document_id/risks` | List risks for a SAR (paginated) |
| `POST` | `/api/v1/sar_documents/:sar_document_id/risks` | Create a risk |
| `GET` | `/api/v1/sar_risks/:id` | Show a single risk (detailed) |
| `PATCH/PUT` | `/api/v1/sar_risks/:id` | Update a risk |
| `DELETE` | `/api/v1/sar_risks/:id` | Delete a risk (audit-logged) |

---

## Required fields

OSCAL requires these on a risk in assessment-results. A request missing any of
them is refused with `422` and a `missing_fields` list, at the point of entry
rather than at export.

| Field | Why |
|-------|-----|
| `title` | OSCAL required |
| `description` | OSCAL required |
| `statement` | OSCAL required — what could happen, and to what |
| `status` | OSCAL required — see the status vocabulary below |

`deadline` is **not** required here. POA&M risks require one because a plan
without a time commitment is not a plan; that is a SPARC rule about POA&Ms, not
an OSCAL rule, and it does not apply to an assessment result.

## The rating

`impact` and `likelihood` are the risk rating. They are stored as columns and
**exported as OSCAL facets**, under `characterizations[].facets[]` — OSCAL has no
top-level field for either.

| Value |
|-------|
| `very-low` |
| `low` |
| `moderate` |
| `high` |
| `very-high` |

Five levels, matching the qualitative scale NIST SP 800-30 and FedRAMP work in.
`medium` is **not** part of the vocabulary; existing rows were migrated to
`moderate`.

The `system` a facet is published under is preserved from whatever the document
was imported with, so a SAR imported under one framework re-exports under the
same one. When nothing says otherwise, `SPARC_OSCAL_RISK_SYSTEM` applies
(default `http://csrc.nist.gov/ns/oscal`). See #1091 for making this
user-configurable per organization.

## Status vocabulary

`open`, `investigating`, `remediating`, `deviation-requested`,
`deviation-approved`, `closed`.

## The OSCAL collections (#1092)

A risk carries four collections beyond its scalar fields. All four are stored as
`jsonb`, all four are **emitted by the exporter** and **populated on import** —
and until #1092 none of them could be authored, so an operator could round-trip
someone else's content but never produce or amend their own. Measured on the demo
estate before the fix: 0 of 17 SAR risks carried any of them.

| Attribute | OSCAL | Authorable in the UI? |
|-----------|-------|-----------------------|
| `threat_ids_data` | `threat-ids[]` | Yes — the SAR enrich screen |
| `mitigating_factors_data` | `mitigating-factors[]` | Yes — the SAR enrich screen |
| `origins_data` | `origins[]` | **API only** |
| `risk_log_data` | `risk-log` | **API only** |
| `remediations_data` | `remediations[]` (`response`) | No — SAR-only, API only |

`origins` is attribution for a rating and `risk-log` is append-only history;
neither is something to type into a form, so the UI does not offer them. They are
here because an integrator migrating an existing risk register has to be able to
bring them across. `remediations_data` is SAR-only — POA&M models responses as
real `poam_remediations` rows with their own endpoints.

### Keys are hyphenated

The stored JSON is **OSCAL as it arrived**: the parser writes `threat-ids`
verbatim, so nested keys are `implementation-uuid`, `actor-uuid`,
`status-change`, `logged-by`, `related-responses`, `required-assets` — not their
snake_case spellings. A snake_case key is silently dropped.

### Accepted shapes

Each collection is permitted as an explicit **shape**, not as an opaque blob, so
a key outside the OSCAL shape cannot land in the column and surface later as a
schema-invalid export.

| Collection | Keys |
|------------|------|
| `threat_ids_data[]` | `system`, `href`, `id` (`system` + `id` are the meaningful pair) |
| `mitigating_factors_data[]` | `uuid`, `implementation-uuid`, `description`, `props[]`, `links[]` |
| `origins_data[]` | `actors[]` — each `type`, `actor-uuid`, `role-id`, `props[]`, `links[]` |
| `risk_log_data.entries[]` | `uuid`, `title`, `description`, `start`, `end`, `status-change`, `logged-by{party-uuid, role-id}`, `related-responses[]{response-uuid}`, `props[]`, `links[]` |
| `remediations_data[]` | `uuid`, `lifecycle`, `title`, `description`, `props[]`, `links[]`, `origins[]`, `required-assets[]{uuid, title, description}` |

`props[]` accepts `name`, `uuid`, `ns`, `value`, `class`, `group`, `remarks`;
`links[]` accepts `href`, `rel`, `media-type`, `resource-fragment`, `text`.

### Reading them back

The detailed body (`show`, `create`, `update`) returns each collection under its
name **without** the `_data` suffix — `threat_ids`, `mitigating_factors`,
`origins`, `risk_log`, `remediations` — alongside `characterizations`, the facets
the rating will actually export as. The write name and the read name differ; a
client that writes `threat_ids_data` reads back `threat_ids`.

### Two different rejections

An unknown key at the **top level** of the payload — `sar_risk[threat_ids_dat]` —
is a `422` naming the field. An unknown key **nested inside** a collection —
`threat_ids_data[0][not_an_oscal_key]` — is **silently dropped** by strong
parameters: the request succeeds and that value simply never lands. A `200` does
not mean every field you sent was stored. Read the response body back.

### Example

```bash
curl -X PATCH -H "Authorization: Bearer $SPARC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "sar_risk": {
          "threat_ids_data": [
            { "system": "https://attack.mitre.org", "id": "T1078" },
            { "system": "https://cve.mitre.org", "id": "CVE-2026-80212" }
          ],
          "mitigating_factors_data": [
            { "description": "Egress restricted to an allowlisted proxy." }
          ]
        }
      }' \
  "https://sparc.example.com/api/v1/sar_risks/42"
```

Sending a collection **replaces** it. Omitting the key leaves it unchanged;
sending `[]` clears it. (The enrich form models the same distinction with a
hidden `collections_present` marker, because an absent key means "unchanged" to
`update!` and removing the last row would otherwise keep the old value.)

---

## `GET /api/v1/sar_documents/:sar_document_id/risks`

Paginated. Envelope: `data` plus `meta` with `page`, `pages`, `count`, `items`.

```bash
curl -H "Authorization: Bearer $SPARC_TOKEN" \
  "https://sparc.example.com/api/v1/sar_documents/acme-hr-portal-sar/risks"
```

```json
{
  "data": [
    {
      "id": 42,
      "uuid": "0f1e2d3c-4b5a-4968-8776-a5b4c3d2e1f0",
      "title": "Unpatched TLS library in the web tier",
      "status": "open",
      "deadline": null,
      "likelihood": "moderate",
      "impact": "high",
      "sar_result_id": 7
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 1, "items": 50 }
}
```

A risk that is missing OSCAL-required content carries a `missing_fields` array on
every response, so a client can show what needs completing rather than
discovering it one failed edit at a time. Such rows arrive through **import** —
SPARC preserves an imperfect artifact rather than refusing it — and can no longer
be created through this API.

## `POST /api/v1/sar_documents/:sar_document_id/risks`

```bash
curl -X POST -H "Authorization: Bearer $SPARC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "sar_risk": {
          "title": "Unpatched TLS library in the web tier",
          "description": "The deployed image carries a TLS library with a known flaw.",
          "statement": "An attacker on the path could downgrade the connection.",
          "status": "open",
          "impact": "high",
          "likelihood": "moderate"
        }
      }' \
  "https://sparc.example.com/api/v1/sar_documents/acme-hr-portal-sar/risks"
```

`201 Created`. The detailed body also returns `characterizations` — the facets
this risk will actually export as, so a client can verify the rating landed
rather than inferring it.

## `GET /api/v1/sar_risks/:id`

Detailed: adds `description`, `statement`, `remarks`, `characterizations`,
`created_at`, `updated_at`.

## `PATCH /api/v1/sar_risks/:id`

```bash
curl -X PATCH -H "Authorization: Bearer $SPARC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"sar_risk": {"impact": "very-high", "likelihood": "low"}}' \
  "https://sparc.example.com/api/v1/sar_risks/42"
```

## `DELETE /api/v1/sar_risks/:id`

Audit-logged as `sar_risk_deleted`. Returns the deleted record's `id` and `uuid`.

## Errors

| Status | When |
|--------|------|
| `401` | No or invalid Bearer token |
| `403` | Token's user lacks `sar.read` / `sar.write` on the boundary |
| `404` | Unknown document or risk, or a `sar_result_id` not on this document |
| `422` | Missing OSCAL-required content, or a field this endpoint does not accept |

## Related

- [SAR Documents API](sar-documents.md)
- [POA&M Risks API](poam-risks.md) — the same shape for a POA&M
