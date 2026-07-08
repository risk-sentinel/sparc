# Component Definitions (CDEF) API

Manage Component Definition documents. CDEFs describe the security capabilities and control implementations of individual system components (e.g., web servers, databases, firewalls). Documents use slug-based identifiers derived from the component name.

## Base URL

```
https://sparc.example.com/api/v1/cdef_documents
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/cdef_documents` | List all CDEFs |
| `GET` | `/api/v1/cdef_documents/:slug` | Show a single CDEF |
| `POST` | `/api/v1/cdef_documents` | Create a new CDEF |
| `PUT` | `/api/v1/cdef_documents/:slug` | Update a CDEF |
| `DELETE` | `/api/v1/cdef_documents/:slug` | Delete a CDEF (soft-delete) |
| `DELETE` | `/api/v1/cdef_documents/bulk` | Bulk-delete CDEFs (admin-only) |
| `POST` | `/api/v1/cdef_documents/:id/populate_from_profile` | Populate an empty CDEF from a published profile |
| `POST` | `/api/v1/cdef_documents/:id/bulk_apply_converter/preview` | Preview a bulk Converter apply (no writes) |
| `POST` | `/api/v1/cdef_documents/:id/bulk_apply_converter/confirm` | Confirm and apply a previewed Converter changeset |
| `POST` | `/api/v1/cdef_documents/:id/submit_for_review` | Submit a CDEF for review |
| `POST` | `/api/v1/cdef_documents/:id/approve` | Approve a CDEF under review |
| `POST` | `/api/v1/cdef_documents/:id/reject` | Reject a CDEF under review |

---

### GET List All CDEFs

Returns a paginated list of component definition documents.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | integer | No | Page number (default: `1`) |
| `items` | integer | No | Items per page (default: `25`) |
| `status` | string | No | Filter by lifecycle status (e.g., `draft`, `published`, `archived`) |
| `name` | string | No | Filter by name (partial match) |
| `q` | string | No | Case-insensitive search across name and description (#672) |
| `cdef_type` | string | No | Filter by component type (e.g., `software`, `hardware`, `service`) |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/cdef_documents?status=published&cdef_type=software&page=1&items=25" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": [
    {
      "id": 1,
      "slug": "web-application-server",
      "name": "Web Application Server",
      "description": "Apache Tomcat 10.x component definition for ACME Corp production environment",
      "cdef_type": "software",
      "cdef_version": "1.2.0",
      "benchmark_id": "xccdf_org.stig_benchmark_Apache_Tomcat_10",
      "oscal_version": "1.1.2",
      "lifecycle_status": "published",
      "file_type": "oscal_json",
      "controls_count": 42,
      "created_at": "2026-03-01T10:00:00Z",
      "updated_at": "2026-03-20T14:30:00Z"
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

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | CDEFs returned successfully |
| `401` | Unauthorized -- missing or invalid token |

---

### GET Show a Single CDEF

Returns a single component definition document with its controls and fields.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `slug` | string | Yes | URL-safe slug identifier (e.g., `web-application-server`) |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/cdef_documents/web-application-server" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "slug": "web-application-server",
    "name": "Web Application Server",
    "description": "Apache Tomcat 10.x component definition for ACME Corp production environment",
    "cdef_type": "software",
    "cdef_version": "1.2.0",
    "benchmark_id": "xccdf_org.stig_benchmark_Apache_Tomcat_10",
    "oscal_version": "1.1.2",
    "lifecycle_status": "published",
    "file_type": "oscal_json",
    "controls_count": 42,
    "controls": [
      {
        "id": 101,
        "control_id": "cm-6",
        "title": "Configuration Settings",
        "status": "implemented",
        "fields": [
          {
            "id": 501,
            "field_name": "implementation_narrative",
            "value": "Apache Tomcat is configured per the DISA STIG baseline..."
          },
          {
            "id": 502,
            "field_name": "status_override",
            "value": "implemented"
          }
        ]
      }
    ],
    "created_at": "2026-03-01T10:00:00Z",
    "updated_at": "2026-03-20T14:30:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | CDEF returned successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | CDEF not found |

---

### POST Create a New CDEF

Create a new component definition document.

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Component name |
| `description` | string | No | Description of the component |
| `cdef_type` | string | Yes | Component type: `software`, `hardware`, `service`, `policy`, `process` |
| `cdef_version` | string | No | Version of the component definition |
| `benchmark_id` | string | No | XCCDF benchmark identifier |
| `oscal_version` | string | No | OSCAL schema version (default: `1.1.2`) |
| `lifecycle_status` | string | No | Status: `draft`, `published`, `archived` (default: `draft`) |
| `file_type` | string | No | Source format: `oscal_json`, `oscal_yaml`, `oscal_xml`, `xccdf` |

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/cdef_documents" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "cdef_document": {
      "name": "Web Application Server",
      "description": "Apache Tomcat 10.x component definition for ACME Corp production environment",
      "cdef_type": "software",
      "cdef_version": "1.2.0",
      "benchmark_id": "xccdf_org.stig_benchmark_Apache_Tomcat_10",
      "oscal_version": "1.1.2",
      "lifecycle_status": "draft",
      "file_type": "oscal_json"
    }
  }'
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "slug": "web-application-server",
    "name": "Web Application Server",
    "description": "Apache Tomcat 10.x component definition for ACME Corp production environment",
    "cdef_type": "software",
    "cdef_version": "1.2.0",
    "benchmark_id": "xccdf_org.stig_benchmark_Apache_Tomcat_10",
    "oscal_version": "1.1.2",
    "lifecycle_status": "draft",
    "file_type": "oscal_json",
    "controls_count": 0,
    "created_at": "2026-03-23T12:00:00Z",
    "updated_at": "2026-03-23T12:00:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `201` | CDEF created successfully |
| `401` | Unauthorized -- missing or invalid token |
| `422` | Validation error -- check response body for details |

---

### PUT Update a CDEF

Update an existing component definition document. Only include the fields you want to change.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `slug` | string | Yes | URL-safe slug identifier |

**Example Request**

```bash
curl -X PUT "https://sparc.example.com/api/v1/cdef_documents/web-application-server" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "cdef_document": {
      "lifecycle_status": "published",
      "cdef_version": "1.3.0"
    }
  }'
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "slug": "web-application-server",
    "name": "Web Application Server",
    "lifecycle_status": "published",
    "cdef_version": "1.3.0",
    "updated_at": "2026-03-23T14:00:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | CDEF updated successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | CDEF not found |
| `422` | Validation error -- check response body for details |

---

### DELETE Delete a CDEF

Soft-delete a component definition document. The record is marked as deleted but retained in the database.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `slug` | string | Yes | URL-safe slug identifier |

**Example Request**

```bash
curl -X DELETE "https://sparc.example.com/api/v1/cdef_documents/web-application-server" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "slug": "web-application-server",
    "deleted": true
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | CDEF deleted successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | CDEF not found |

---

### DELETE Bulk-Delete CDEFs

**Admin-only.** Delete multiple component definition documents in one request (#629). Honors the referential-integrity guard and returns a per-id partial-success result — ids that could not be deleted are reported in `blocked`, ids that did not resolve in `missing`.

**Path:** `DELETE /api/v1/cdef_documents/bulk`

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ids` | array of integers/slugs | Yes | Identifiers of the CDEFs to delete |

**Example Request**

```bash
curl -X DELETE "https://sparc.example.com/api/v1/cdef_documents/bulk" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{ "ids": [1, 2, 3] }'
```

**Response Body**

```json
{
  "data": {
    "deleted": [1, 2],
    "blocked": [3],
    "missing": []
  },
  "meta": {
    "deleted": 2,
    "blocked": 1,
    "missing": 0
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Bulk delete attempted -- per-id outcomes are in the response body |
| `401` | Unauthorized -- missing or invalid token |
| `403` | Forbidden -- caller is not an admin |

---

### POST Populate a CDEF from a Published Profile

Populate an existing empty (metadata-only) CDEF with a control basis derived from a published profile (#628), so a shell created by `POST /api/v1/cdef_documents` gains controls instead of being a dead end.

**Path:** `POST /api/v1/cdef_documents/:id/populate_from_profile`

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Slug (or numeric id) of the CDEF to populate |

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `source_profile_id` | string | Yes | Slug or numeric id of a **published** profile to derive controls from |

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/cdef_documents/web-application-server/populate_from_profile" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{ "source_profile_id": "fedramp-moderate" }'
```

**Response Body**

Returns the detailed CDEF representation (same shape as `GET /api/v1/cdef_documents/:slug`) with the newly populated controls.

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | CDEF populated successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | `Published profile not found` -- the `source_profile_id` did not resolve to a published profile |
| `422` | Validation error, or the resulting OSCAL document failed schema validation |

---

### POST Bulk-Apply Converter -- Preview

Return the changeset a `Converter` would apply to this CDEF **without writing anything** (#499 slice 3), plus an HMAC-signed `token` the confirm endpoint replays. Requires `converters.write` (or admin).

**Path:** `POST /api/v1/cdef_documents/:id/bulk_apply_converter/preview`

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Slug (or numeric id) of the CDEF |

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `converter_id` | string | Yes | Numeric id or UUID of the Converter to preview |
| `target_rev` | string | No | Target catalog revision |
| `source_ids` | array | No | Restrict the preview to specific source control ids |
| `only_missing_vs_baseline` | boolean | No | Only propose rows missing versus the baseline |

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/cdef_documents/web-application-server/bulk_apply_converter/preview" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{ "converter_id": 7, "target_rev": "rev5", "only_missing_vs_baseline": true }'
```

**Response Body**

```json
{
  "data": {
    "cdef_id": 1,
    "cdef_slug": "web-application-server",
    "converter_id": 7,
    "converter_uuid": "b1f2...",
    "target_rev": "rev5",
    "token": "<hmac-signed replay token>",
    "stats": { "ready": 12, "conflicts": 1, "skipped": 3 },
    "rows": [ { "target_id": "cm-6", "action": "add", "ready": true } ]
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Preview computed successfully |
| `401` | Unauthorized -- missing or invalid token |
| `403` | Forbidden -- caller lacks `converters.write` |
| `404` | `Converter not found` |
| `422` | Invalid arguments, or the CDEF is AWS-Labs-sourced (clone first) |

---

### POST Bulk-Apply Converter -- Confirm

Replay a preview `token` and apply the selected ready rows transactionally via `CdefMutationService` (OSCAL-validated) (#499 slice 4). Requires `converters.write` (or admin).

**Path:** `POST /api/v1/cdef_documents/:id/bulk_apply_converter/confirm`

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Slug (or numeric id) of the CDEF |

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `token` | string | Yes | The HMAC-signed token returned by the preview endpoint |
| `selected_target_ids` | object | No | Map of target ids the caller chose to apply |

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/cdef_documents/web-application-server/bulk_apply_converter/confirm" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{ "token": "<hmac-signed replay token>", "selected_target_ids": { "cm-6": true } }'
```

**Response Body**

```json
{
  "data": {
    "cdef_id": 1,
    "cdef_slug": "web-application-server",
    "applied": 12,
    "skipped": 3
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Changeset applied successfully |
| `401` | Unauthorized -- missing or invalid token |
| `403` | Forbidden -- caller lacks `converters.write` |
| `422` | Invalid/expired token, AWS-Labs-sourced CDEF, or OSCAL validation failed |

---

### POST Submit a CDEF for Review

Transition a CDEF into the review workflow (#630). Uses the same `DocumentApprovalService` code path as the UI. A CDEF with no control content returns `422` with a "missing required content" error.

**Path:** `POST /api/v1/cdef_documents/:id/submit_for_review`

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Slug (or numeric id) of the CDEF |

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/cdef_documents/web-application-server/submit_for_review" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "slug": "web-application-server",
    "name": "Web Application Server",
    "approval_status": "pending_review",
    "submitted_by_user_id": 42,
    "submitted_at": "2026-06-29T12:00:00Z",
    "approved_by_user_id": null,
    "approved_at": null,
    "rejection_reason": null
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Submitted for review |
| `401` | Unauthorized -- missing or invalid token |
| `404` | CDEF not found |
| `422` | Invalid transition, or missing required content on an empty CDEF |

---

### POST Approve a CDEF

Approve a CDEF that is under review (#630).

**Path:** `POST /api/v1/cdef_documents/:id/approve`

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Slug (or numeric id) of the CDEF |

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/cdef_documents/web-application-server/approve" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "slug": "web-application-server",
    "name": "Web Application Server",
    "approval_status": "approved",
    "submitted_by_user_id": 42,
    "submitted_at": "2026-06-29T12:00:00Z",
    "approved_by_user_id": 7,
    "approved_at": "2026-06-29T13:00:00Z",
    "rejection_reason": null
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Approved |
| `401` | Unauthorized -- missing or invalid token |
| `404` | CDEF not found |
| `422` | Invalid transition (e.g., not currently under review) |

---

### POST Reject a CDEF

Reject a CDEF that is under review, optionally supplying a `reason` (#630).

**Path:** `POST /api/v1/cdef_documents/:id/reject`

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Slug (or numeric id) of the CDEF |

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `reason` | string | No | Free-text rejection reason stored on the document |

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/cdef_documents/web-application-server/reject" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{ "reason": "Missing implementation narratives for CM family" }'
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "slug": "web-application-server",
    "name": "Web Application Server",
    "approval_status": "rejected",
    "submitted_by_user_id": 42,
    "submitted_at": "2026-06-29T12:00:00Z",
    "approved_by_user_id": null,
    "approved_at": null,
    "rejection_reason": "Missing implementation narratives for CM family"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Rejected |
| `401` | Unauthorized -- missing or invalid token |
| `404` | CDEF not found |
| `422` | Invalid transition (e.g., not currently under review) |

---

## Common Errors

| Code | Error | Description |
|------|-------|-------------|
| `401` | `Unauthorized` | Missing or invalid Bearer token |
| `404` | `Not Found` | CDEF document does not exist or has been deleted |
| `422` | `Unprocessable Entity` | Validation failed -- missing required fields or invalid values |
| `500` | `Internal Server Error` | Unexpected server error -- contact your administrator |
