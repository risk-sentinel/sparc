# Evidence Control Links API

REST API for associating **evidence** with the controls it supports (#756).

An evidence control link ties a piece of [evidence](evidences.md) to a specific control (e.g. `AC-2`), optionally scoped to the document that control lives in (SSP / SAR / SAP / CDEF / POA&M).

## Why the document scope matters

A link that carries **both** `document_type` and `document_id` is what drives OSCAL output. Creating one automatically creates a managed `BackMatterResource` on that document, which is emitted into the document's OSCAL back-matter with the evidence's durable resolver href (#680).

A link without a document scope is a plain evidence-to-control association: useful for search and traceability, but it does **not** appear in any OSCAL export.

> The web UI never sets `document_type` / `document_id`, so this API is the only surface that can establish OSCAL back-matter linkage.

## Base URL

```
https://sparc.example.com/api/v1/evidences/:evidence_id/control_links
```

The `:evidence_id` segment accepts either a numeric id or the evidence slug.

## Authentication

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

| Action | Permission |
|--------|-----------|
| `index` | `evidence.read` (or Instance Admin) |
| `create`, `destroy` | `evidence.write` (or Instance Admin) |

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/evidences/:evidence_id/control_links` | List links for the evidence (paginated) |
| `POST` | `/api/v1/evidences/:evidence_id/control_links` | Link a control |
| `DELETE` | `/api/v1/evidences/:evidence_id/control_links/:id` | Unlink |

---

### GET List Control Links

```
GET /api/v1/evidences/:evidence_id/control_links
```

**Response** `200 OK`

```json
{
  "data": [
    {
      "id": 7,
      "evidence_id": 42,
      "control_id": "AC-2",
      "control_type": null,
      "document_type": "SspDocument",
      "document_id": 3,
      "created_at": "2026-07-18T14:10:02Z"
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 1, "items": 25 }
}
```

---

### POST Create Control Link

```
POST /api/v1/evidences/:evidence_id/control_links
```

**Body parameters** (under the `control_link` key)

| Field | Required | Notes |
|---|---|---|
| `control_id` | yes | e.g. `AC-2` |
| `control_type` | no | Optional discriminator |
| `document_type` | no | One of `SspDocument`, `SarDocument`, `SapDocument`, `CdefDocument`, `PoamDocument` |
| `document_id` | no | Required alongside `document_type` to produce back-matter |

`document_type` is validated against that list. An arbitrary class name is rejected with `422` rather than being resolved.

**Example** — link evidence to `AC-2` on an SSP, producing OSCAL back-matter:

```bash
curl -X POST https://sparc.example.com/api/v1/evidences/42/control_links \
  -H "Authorization: Bearer $SPARC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"control_link": {"control_id": "AC-2", "document_type": "SspDocument", "document_id": 3}}'
```

**Response** `201 Created`

```json
{
  "data": {
    "id": 7,
    "evidence_id": 42,
    "control_id": "AC-2",
    "control_type": null,
    "document_type": "SspDocument",
    "document_id": 3,
    "created_at": "2026-07-18T14:10:02Z",
    "back_matter_resource_uuid": "6f1c0c4e-2b7a-4e51-9a0d-8f2b1c3d4e5f",
    "oscal_href": "https://sparc.example.com/artifacts/6f1c0c4e-2b7a-4e51-9a0d-8f2b1c3d4e5f"
  }
}
```

`back_matter_resource_uuid` and `oscal_href` are present only when the link is document-scoped; they confirm the back-matter resource was created.

Linking the same `control_id` to the same evidence and document scope twice returns `422` — the pair is unique.

---

### DELETE Control Link

```
DELETE /api/v1/evidences/:evidence_id/control_links/:id
```

Removes the association. When the last document-scoped link between that evidence and that document is removed, the corresponding `BackMatterResource` is torn down, so the evidence stops appearing in the document's OSCAL back-matter.

**Response** `204 No Content`

---

## Errors

Standard envelope — see [errors.md](../errors.md).

| Status | When |
|---|---|
| `400` | The `control_link` root key is missing from the body |
| `401` | Missing or invalid token |
| `403` | Lacks `evidence.read` / `evidence.write` |
| `404` | No such evidence, or the link belongs to different evidence |
| `422` | Missing `control_id`, unknown `document_type`, or duplicate link |

## NIST 800-53 mapping

| Control | How |
|---|---|
| IA-2 | Bearer token required |
| AC-3 | `evidence.read` / `evidence.write` |
| AU-12 | Link and unlink are audit-logged |
| CA-2 | Evidence-to-control traceability |
| CM-8 | Back-matter resource provenance |
