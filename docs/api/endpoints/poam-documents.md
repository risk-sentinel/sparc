# POA&M Documents

Plan of Action and Milestones (POA&M) documents track security weaknesses, planned remediation actions, and milestone dates for an information system. POA&M documents are scoped to an authorization boundary -- non-admin users can only access POA&Ms within boundaries they are members of. Reading requires the `poam.read` permission; creating, updating, and deleting require `poam.write`.

## Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `GET` | `/api/v1/poam_documents` | List POA&M documents (paginated, filterable) | `poam.read` |
| `GET` | `/api/v1/poam_documents/:slug` | Get a single POA&M document | `poam.read` |
| `POST` | `/api/v1/poam_documents` | Create a new (empty) POA&M document | `poam.write` |
| `POST` | `/api/v1/poam_documents/generate` | **Generate a populated POA&M** from a SAR's open risks | `poam.write` |
| `POST` | `/api/v1/poam_documents/import` | **Ingest a POA&M from an OSCAL file** (JSON / XML / YAML) | `poam.write` |
| `PUT` | `/api/v1/poam_documents/:slug` | Update a POA&M document | `poam.write` |
| `DELETE` | `/api/v1/poam_documents/:slug` | Soft-delete a POA&M document | `poam.write` |
| `GET` | `/api/v1/poam_documents/:slug/export` | Export the POA&M — field JSON by default, or the OSCAL plan of action and milestones (`?format=oscal`, `oscal-yaml`, `oscal-xml`) — see **Export formats** | `poam.read` |

---

### POST /api/v1/poam_documents/generate

Builds a POA&M **populated from an assessment**, rather than the empty document `POST /api/v1/poam_documents` creates. Added in #843.

This is the lifecycle step that closes the loop: the assessment produced findings, so a POA&M is opened to track their remediation. A SAR's **open** risks become POA&M items, carrying their findings and observations across with the assessor's own linkage intact.

#### Request Body

All fields nested under `poam_document`.

| Field | Type | Description |
|---|---|---|
| `authorization_boundary_id` | integer \| string | Boundary id or slug. Its SAR is used when no explicit source is given, and the POA&M is attached to it. |
| `sar_document_id` | integer | Explicit source assessment. Scoped: non-admins may only name a SAR within their boundaries. |
| `name` | string | Defaults to `POA&M — <boundary> — <date>`. |
| `description` | string | Optional. |

Supplying neither a SAR nor a boundary with one yields an **empty scaffold** — a team starting a POA&M before a full assessment is a supported flow, not an error.

#### Nothing is synthesised

A source risk that cannot form a valid POA&M entry is **skipped and reported**, never completed on your behalf. `PoamRisk` requires title, description, statement, status and deadline; `PoamFinding` requires title, description and target — these are compliance content an assessor and AO read, so inventing them would fabricate an assessment record (see #832).

The one derived value is `deadline`, and only when the source has none: it comes from the admin-provisioned **RemediationTimeline** SLA table, keyed by the boundary's profile baseline and the risk's severity. That is a policy your organisation configured. If no window resolves, the risk is skipped rather than given an arbitrary date.

#### Response

`201 Created` **even when some risks were skipped** — the POA&M genuinely was created, and returning an error would discard it over source data the assessor still has to fix.

```json
{
  "data": { "id": 42, "name": "POA&M — Cloud ATO — 2026-07-28", "lifecycle_status": "in_progress" },
  "meta": { "items_created": 7, "risks_created": 7, "findings_created": 12, "complete": false },
  "skipped": [
    { "type": "risk", "uuid": "…", "title": "Weak TLS config", "reason": "source risk is missing statement" }
  ]
}
```

Check `meta.complete` — when `false`, `skipped` lists every omission with its reason.

#### Status Codes

| Code | Meaning |
|---|---|
| `201 Created` | POA&M generated (possibly with skipped entries). |
| `401 Unauthorized` | Missing or invalid token. |
| `403 Forbidden` | Caller lacks `poam.write` on the boundary. |
| `404 Not Found` | Boundary not found, or the named SAR is outside the caller's boundaries. |

#### cURL Example

```bash
curl -X POST https://sparc.example.org/api/v1/poam_documents/generate \
  -H "Authorization: Bearer $SPARC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"poam_document": {"authorization_boundary_id": 7}}'
```

---

### GET /api/v1/poam_documents

Returns a paginated list of POA&M documents. Admin users see all documents; non-admin users see only documents within their assigned authorization boundaries.

#### Path Parameters

None.

#### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `page` | integer | Page number (default: `1`) |
| `items` | integer | Items per page (default: `25`) |
| `status` | string | Filter by document status |
| `name` | string | Case-insensitive partial match on document name |
| `q` | string | Case-insensitive search across name and description (#672) |
| `authorization_boundary_id` | integer | Filter by authorization boundary |

#### Response Body

```json
{
  "data": [
    {
      "id": 3,
      "slug": "acme-cloud-platform-poam-2025",
      "uuid": "a7b8c9d0-e1f2-3456-abcd-789012345678",
      "name": "ACME Cloud Platform POA&M 2025",
      "status": "active",
      "lifecycle_status": "active",
      "authorization_boundary_id": 7,
      "created_at": "2025-10-01T10:00:00Z",
      "updated_at": "2025-11-20T15:30:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "pages": 1,
    "count": 1,
    "items": 25
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | List returned successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |

#### cURL Example

```bash
curl -s \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/poam_documents?page=1&items=25" | jq .
```

---

### GET /api/v1/poam_documents/:slug

Returns a single POA&M document with detailed fields including version, system ID, and counts for items, risks, findings, and observations.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier (e.g., `acme-cloud-platform-poam-2025`) |

#### Query Parameters

None.

#### Response Body

```json
{
  "data": {
    "id": 3,
    "slug": "acme-cloud-platform-poam-2025",
    "uuid": "a7b8c9d0-e1f2-3456-abcd-789012345678",
    "name": "ACME Cloud Platform POA&M 2025",
    "status": "active",
    "lifecycle_status": "active",
    "authorization_boundary_id": 7,
    "created_at": "2025-10-01T10:00:00Z",
    "updated_at": "2025-11-20T15:30:00Z",
    "description": "Tracks remediation milestones for findings from the 2025 annual assessment.",
    "poam_version": "2.0",
    "system_id": "ACME-CP-001",
    "items_count": 14,
    "risks_count": 8,
    "findings_count": 22,
    "observations_count": 35
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document returned successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `poam.read` for this boundary |
| `404 Not Found` | No document matches the given slug |

#### cURL Example

```bash
curl -s \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/poam_documents/acme-cloud-platform-poam-2025" | jq .
```

---

### POST /api/v1/poam_documents

Creates a new POA&M document. The caller must have `poam.write` permission for the target authorization boundary.

#### Path Parameters

None.

#### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `poam_document[name]` | string | yes | Document name |
| `poam_document[description]` | string | no | Document description |
| `poam_document[authorization_boundary_id]` | integer | no | Associated authorization boundary |
| `poam_document[poam_version]` | string | no | POA&M document version |
| `poam_document[system_id]` | string | no | System identifier |
| `poam_document[lifecycle_status]` | string | no | Lifecycle status (e.g., `active`, `draft`) |

#### Response Body

```json
{
  "data": {
    "id": 4,
    "slug": "acme-cloud-platform-poam-2025",
    "uuid": "b8c9d0e1-f2a3-4567-bcde-890123456789",
    "name": "ACME Cloud Platform POA&M 2025",
    "status": "draft",
    "lifecycle_status": "draft",
    "authorization_boundary_id": 7,
    "created_at": "2025-12-10T10:00:00Z",
    "updated_at": "2025-12-10T10:00:00Z"
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `201 Created` | Document created successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `poam.write` for the target boundary |
| `422 Unprocessable Entity` | Validation errors (see `error` and `details` fields) |

#### cURL Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "poam_document": {
      "name": "ACME Cloud Platform POA&M 2025",
      "description": "Tracks remediation milestones for findings from the 2025 annual assessment.",
      "authorization_boundary_id": 7,
      "poam_version": "2.0",
      "system_id": "ACME-CP-001",
      "lifecycle_status": "draft"
    }
  }' \
  "https://sparc.example.com/api/v1/poam_documents" | jq .
```

---

### PUT /api/v1/poam_documents/:slug

Updates an existing POA&M document. Only the fields provided in the request body are changed.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier |

#### Request Body

Same fields as [POST create](#post-apiv1poam_documents). All fields are optional for update.

#### Response Body

```json
{
  "data": {
    "id": 3,
    "slug": "acme-cloud-platform-poam-2025",
    "uuid": "a7b8c9d0-e1f2-3456-abcd-789012345678",
    "name": "ACME Cloud Platform POA&M 2025",
    "status": "active",
    "lifecycle_status": "active",
    "authorization_boundary_id": 7,
    "created_at": "2025-10-01T10:00:00Z",
    "updated_at": "2025-12-10T11:00:00Z"
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document updated successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `poam.write` for this boundary |
| `404 Not Found` | No document matches the given slug |
| `422 Unprocessable Entity` | Validation errors |

#### cURL Example

```bash
curl -s -X PUT \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "poam_document": {
      "lifecycle_status": "active",
      "poam_version": "2.1"
    }
  }' \
  "https://sparc.example.com/api/v1/poam_documents/acme-cloud-platform-poam-2025" | jq .
```

---

### DELETE /api/v1/poam_documents/:slug

Soft-deletes a POA&M document. The record is marked as deleted but retained in the database for audit purposes.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier |

#### Request Body

None.

#### Response Body

```json
{
  "data": {
    "id": 3,
    "slug": "acme-cloud-platform-poam-2025",
    "deleted": true
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document soft-deleted successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `poam.write` for this boundary |
| `404 Not Found` | No document matches the given slug |

#### cURL Example

```bash
curl -s -X DELETE \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/poam_documents/acme-cloud-platform-poam-2025" | jq .
```

---

## Export formats (#1181)

```
GET /api/v1/poam_documents/:slug/export[?format=&validate=]
```

New in #1181: until then a POA&M had no API export at all — the OSCAL document
the web downloads was reachable only from a browser session.

Requires `poam.read` on the document's authorization boundary (instance admins
always pass). The check is the same one `show` makes: a caller whose `poam.read`
is on a different boundary is refused `403`, whatever the format.

| `format` | Returns |
|---|---|
| `fields` *(default)* | SPARC's own control-field JSON — the document's name, version and system id, its risk/observation/finding counts and its items (`JsonExportService`) |
| `oscal` | the OSCAL plan of action and milestones, JSON (root key `plan-of-action-and-milestones`) |
| `oscal-yaml` | the same document as YAML (`application/x-yaml`) |
| `oscal-xml` | the same document as OSCAL-namespaced XML |

`validate` defaults to **true** for the OSCAL formats: the OSCAL JSON is checked
against the NIST schema, and a non-conforming document is **refused** rather than returned as
a file the caller discovers is unusable later. YAML and XML are serialised from
that same validated JSON, exactly as the web downloads are.

```json
{
  "error": "The plan of action and milestones does not conform to the OSCAL schema",
  "details": ["... up to ten lines ..."],
  "hint": "Re-request with validate=false to export it anyway"
}
```

`validate=false` is the deliberate escape hatch and returns the document as
built. Each delivered OSCAL export is audited as `poam_document_exported` with the
format and whether it was validated.

An unknown `format` is refused with `422`:

```json
{ "error": "Unknown export format \"pdf\"", "expected": ["fields", "oscal", "oscal-yaml", "oscal-xml"] }
```

### Conditional GET (ETag / 304)

Every response carries a **strong** `ETag`. Send it back as `If-None-Match` and
an unchanged export answers **`304 Not Modified`** with an empty body.

The ETag is a digest of the document id, its `updated_at`, the `format`, the
`validate` flag, the instance's default OSCAL version **and the exported bytes**.
The bytes are in it on purpose: a control, a field, an item or a back-matter
resource can change without touching the document's own `updated_at`, so an
ETag built from `updated_at` alone would answer `304` over content that had
changed. Each `format` (and each `validate` setting) therefore has its own
ETag. A `304` still builds and validates the export on the server; what it
saves is the transfer. A `304` is not audited — nothing was delivered.

```bash
curl -si -H "Authorization: Bearer $TOKEN" \
  -H 'If-None-Match: "<etag from the previous response>"' \
  "https://sparc.example.com/api/v1/poam_documents/<slug>/export?format=oscal"          # HTTP/1.1 304 Not Modified
```

### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Export returned |
| `304 Not Modified` | `If-None-Match` matched the current ETag |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `poam.read` for this boundary |
| `404 Not Found` | No document matches the given slug |
| `422 Unprocessable Content` | Unknown `format`, or the document does not conform (`validate=true`) |

### cURL Example

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sparc.example.com/api/v1/poam_documents/<slug>/export?format=oscal" | jq '."plan-of-action-and-milestones".metadata'
```

---

## Common Errors

| Status | Body | Cause |
|--------|------|-------|
| `401 Unauthorized` | `{"error": "Unauthorized"}` | Bearer token is missing, expired, or invalid |
| `403 Forbidden` | `{"error": "Forbidden"}` | Caller lacks required permission for the target boundary |
| `404 Not Found` | `{"error": "Not found"}` | No document exists with the provided slug |
| `422 Unprocessable Entity` | `{"error": "Validation failed: ...", "details": [...]}` | Request body failed model validations |
