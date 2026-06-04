# Evidence Attestations API

REST API for evidence **attestations** (#440) — periodic-review records signed off by a reviewer (control owner / system owner / ISSO / CISO / assessor / AO) that an evidence artifact accurately represents the current state of its linked controls. Each attestation carries a tamper-evident SHA-256 `signature_hash` for non-repudiation. This controller fills the API gap left by the previously UI-only attestation flow (per SPARC's api-first rule) and adds the CMS / SAF CLI export introduced in #440.

All endpoints are nested under a specific **evidence** record.

> **Note:** SPARC does not (currently) expose an Evidence-creation API — Evidence
> is created through the UI or seeded. API callers therefore operate on an
> existing `:evidence_id`.

## Base URL

```
https://sparc.example.com/api/v1/evidences/:evidence_id/attestations
```

The `:evidence_id` segment accepts either a numeric id or the evidence slug.

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

| Action | Permission |
|--------|-----------|
| `index`, `show`, `export` | `evidence.read` (or Instance Admin) |
| `create`, `destroy` | `evidence.write` (or Instance Admin) |

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/evidences/:evidence_id/attestations` | List attestations for the evidence (paginated, newest first) |
| `GET` | `/api/v1/evidences/:evidence_id/attestations/:id` | Show a single attestation (detailed) |
| `POST` | `/api/v1/evidences/:evidence_id/attestations` | Create + cryptographically sign an attestation |
| `DELETE` | `/api/v1/evidences/:evidence_id/attestations/:id` | Delete an attestation (audit-logged) |
| `GET` | `/api/v1/evidences/:evidence_id/attestations/export` | CMS / SAF CLI JSON export (one record per linked control_id) |

---

### GET List Attestations

```
GET /api/v1/evidences/:evidence_id/attestations
```

Returns a paginated list (see [pagination.md](../pagination.md)), ordered by `attested_at` descending.

**Response** `200 OK`

```json
{
  "data": [
    {
      "id": 12,
      "evidence_id": 7,
      "attester_name": "Jane Reviewer",
      "role": "isso",
      "role_label": "ISSO",
      "attested_at": "2026-06-01T14:00:00Z",
      "frequency": "quarterly",
      "status": "current",
      "created_at": "2026-06-01T14:00:05Z"
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 1, "items": 25 }
}
```

### GET Show Attestation

```
GET /api/v1/evidences/:evidence_id/attestations/:id
```

Returns the detailed shape, which additionally includes `attester_email`, `statement`, `signature_hash`, and `frequency_label`.

### POST Create Attestation

```
POST /api/v1/evidences/:evidence_id/attestations
```

Creates and signs an attestation, and marks the parent evidence `attested` if it was not already.

**Request body**

```json
{
  "attestation": {
    "attester_name": "Jane Reviewer",
    "attester_email": "jane@example.com",
    "role": "isso",
    "statement": "Evidence reviewed and accurate as of this date.",
    "attested_at": "2026-06-01T14:00:00Z",
    "frequency": "quarterly",
    "status": "current"
  }
}
```

**Response** `201 Created` — the detailed attestation (including the generated `signature_hash`).

`422 Unprocessable Entity` with `{"error": "Validation failed", "details": [...]}` on invalid input.

### DELETE Attestation

```
DELETE /api/v1/evidences/:evidence_id/attestations/:id
```

**Response** `204 No Content`. The deletion is audit-logged.

### GET Export (CMS / SAF CLI shape)

```
GET /api/v1/evidences/:evidence_id/attestations/export
```

Emits CMS / SAF CLI attestation JSON for all attestations on the evidence, **denormalized one record per linked `control_id`**. Returns an empty array if the evidence has no control links (the CMS shape is meaningless without a control_id).

**Response** `200 OK`

```json
{
  "data": [ { "control_id": "ac-3", "...": "..." } ],
  "meta": { "count": 1, "schema": "cms-attestation-v1" }
}
```

## Errors

| Status | When |
|--------|------|
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Lacking `evidence.read` (reads) or `evidence.write` (writes) |
| `404 Not Found` | Unknown `:evidence_id` or attestation `:id` |
| `422 Unprocessable Entity` | Invalid attestation payload |

Errors follow the standard SPARC error envelope; see [errors.md](../errors.md).

## NIST 800-53 controls

`IA-2` (Bearer auth), `AC-3` (`evidence.read`/`evidence.write` RBAC), `AU-12` (mutations audit-logged), `CA-7` (periodic re-attestation cadence via `frequency`), `CA-2` (attestation as assessment evidence).
