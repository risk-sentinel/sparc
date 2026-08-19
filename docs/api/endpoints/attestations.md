# Evidence Attestations API

REST API for evidence **attestations** (#440) — periodic-review records signed off by a reviewer (control owner / system owner / ISSO / CISO / assessor / AO) that an evidence artifact accurately represents the current state of its linked controls. Each attestation carries a tamper-evident SHA-256 `signature_hash` for non-repudiation. This controller fills the API gap left by the previously UI-only attestation flow (per SPARC's api-first rule) and adds the CMS / SAF CLI export introduced in #440.

All endpoints are nested under a specific **evidence** record.

> **Note:** Evidence itself is managed through the [Evidence API](evidences.md)
> (#756). Create an evidence record there first, then attest against the
> returned id or slug. Before #756 there was no evidence-creation endpoint and
> callers had to operate on a UI-created or seeded record.

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
| `GET` | `/api/v1/attestations/eligible` | Who may attest on a boundary, and under which role (#981) |

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

## GET /api/v1/attestations/eligible

Who may attest on a boundary, and under which role. Backs the evidence form's attester picker so it cannot offer a pair the server will refuse (#981).

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `authorization_boundary_id` | integer | No | The system the evidence belongs to. **Omit it for instance-wide evidence**, which has a deliberately wider rule — see below. |

**Response** `200 OK`

```json
{
  "data": {
    "attesters": [ { "id": 42, "label": "Jane Okafor" } ],
    "roles_by_attester": {
      "42": [ { "name": "isso", "label": "ISSO" } ]
    }
  },
  "meta": { "authorization_boundary_id": "5" }
}
```

### The instance / boundary asymmetry

Omitting `authorization_boundary_id` returns the eligible set for **instance-wide evidence**, which includes **instance-scoped** attesting roles such as `policy_manager`. Naming a boundary withdraws them, returning only boundary-scoped roles the person actually holds *there*.

That is deliberate, not an inconsistency. Boundary-less evidence is provider material arriving from a leveraged SSP, so it belongs to no single system and Policy is exactly who speaks for it. But an instance-scoped grant satisfies `has_permission?` on *every* boundary, so allowing it through on a named boundary would hand one role estate-wide authority to sign for every system. Policy reaches global evidence; it does not thereby gain authority over any individual system's.

`Attestation` enforces the same rule on save, so this endpoint only narrows what is *offered* — it can never widen what is *accepted*.

**Authorization:** `evidence.write` on the boundary in question. Unlike catalog lookups this is not global reference data: it discloses which accounts hold an attesting role on a named system.

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
