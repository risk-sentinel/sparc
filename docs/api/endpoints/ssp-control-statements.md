# SSP Control Statements

The per-statement implementation prose of a System Security Plan — how the
system satisfies each **addressable part** of a control, rather than the control
as a whole.

## Why this endpoint exists

OSCAL models an SSP this way: `implemented-requirement.statements` is an array
whose members "identify which statements within a control are addressed", and
each carries its own implementation prose. SPARC has stored statements since
#393, but the only route that could WRITE `implementation_prose` was the HTML
member action `PATCH /ssp_documents/:id/update_statement`. The web UI was the
sole way to author the field that carries the actual system security plan —
exactly the inversion the API-first guardrail exists to prevent.

AC-2 divides into 22 addressable parts. Answering it in one box, which is what
the control-level field does, asserts that one narrative covers all 22.

| | |
|---|---|
| **Base path** | `/api/v1/ssp_documents/:ssp_document_id/statements` (list) |
| | `/api/v1/ssp_control_statements/:id` (read, update) |
| **Auth** | Bearer token |
| **Read** | `ssp.read` on the SSP's authorization boundary |
| **Write** | `ssp.write` on the SSP's authorization boundary |

`:ssp_document_id` accepts the SSP's slug or its numeric id.

## No create, no destroy — and that is deliberate

Statements are DERIVED from the catalog's part tree by
`CatalogPartExtractorService`. Their `statement_id` and derived UUID are what an
exported document references (#397), and what `CdefToSspInheritanceService` and
`LeveragedAuthorizationService` join on. Structure comes from the catalog; only
the prose is authored.

`permit_strictly` therefore REJECTS the whole request if a caller sends
`statement_id` or `parent_statement_id`, rather than silently dropping them — a
client is told, instead of being left believing a write landed.

## Endpoints

| method | path | action |
|---|---|---|
| `GET` | `/api/v1/ssp_documents/:ssp_document_id/statements` | `ssp_control_statements#index` |
| `GET` | `/api/v1/ssp_control_statements/:id` | `ssp_control_statements#show` |
| `PATCH/PUT` | `/api/v1/ssp_control_statements/:id` | `ssp_control_statements#update` |

### `GET /api/v1/ssp_documents/:ssp_document_id/statements`

Every statement on the document, ordered by control then by the catalog's own
part order. Optionally narrowed to one control with `?control_id=ac-2`, which is
what an editor showing a single card needs.

```
GET /api/v1/ssp_documents/acme-hr-portal-ssp/statements?control_id=ac-2
Authorization: Bearer <token>
```

```json
{
  "data": [
    {
      "id": 4211,
      "uuid": "0a5f...",
      "statement_id": "ac-2_smt.a",
      "parent_statement_id": "ac-2_smt",
      "label": "a.",
      "row_order": 1,
      "control_id": "ac-2",
      "answered": true,
      "source_kind": "authored"
    }
  ],
  "meta": { "count": 22, "items": 100, "page": 1, "pages": 1 }
}
```

`answered` reports whether the statement carries implementation prose. That is
the question the per-statement model exists to make askable, and a client should
not have to infer it from an empty string.

### `GET /api/v1/ssp_control_statements/:id`

One statement, with its prose, remarks and responsible roles.

### `PATCH /api/v1/ssp_control_statements/:id`

Writes the prose.

```json
{
  "ssp_control_statement": {
    "implementation_prose": "Account types are defined in POL-AC-001.",
    "remarks": "Reviewed 2026-09-01",
    "responsible_roles_data": [ { "role-id": "system-owner" } ]
  }
}
```

`responsible_roles_data` is permitted as a SHAPE, not a blob: OSCAL models
`responsible-roles` as objects carrying a `role-id`, and `OscalSspExportService`
writes this column straight into the document, so a bare array of strings would
emit schema-invalid OSCAL.

> **Note.** A `role-id` must reference a role declared in `metadata.roles`.
> Nothing enforces that yet — see #1116.

## Errors

| status | when |
|---|---|
| `401` | no or invalid bearer token |
| `403` | the caller lacks `ssp.read` / `ssp.write` on the boundary |
| `404` | no such statement, or no such SSP |
| `422` | the body carried a field this endpoint does not accept |
