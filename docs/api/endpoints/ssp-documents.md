# SSP Documents

System Security Plan (SSP) documents capture the security controls implemented for an information system. SSP documents are scoped to an authorization boundary -- non-admin users can only access SSPs within boundaries they are members of. Reading requires the `ssp.read` permission; creating, updating, and deleting require `ssp.write`.

## Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `GET` | `/api/v1/ssp_documents` | List SSP documents (paginated, filterable) | `ssp.read` |
| `GET` | `/api/v1/ssp_documents/:slug` | Get a single SSP document | `ssp.read` |
| `POST` | `/api/v1/ssp_documents` | Create a new SSP document | `ssp.write` |
| `PUT` | `/api/v1/ssp_documents/:slug` | Update an SSP document | `ssp.write` |
| `DELETE` | `/api/v1/ssp_documents/:slug` | Soft-delete an SSP document | `ssp.write` |
| `POST` | `/api/v1/ssp_documents/convert` | Upload and parse an Excel file into an SSP | `ssp.write` |
| `PUT` | `/api/v1/ssp_documents/:slug/update_fields` | Bulk-update editable control fields on one SSP | `ssp.write` |
| `GET` | `/api/v1/ssp_documents/:slug/export` | Export SSP as JSON | `ssp.read` |

---

### GET /api/v1/ssp_documents

Returns a paginated list of SSP documents. Admin users see all documents; non-admin users see only documents within their assigned authorization boundaries.

#### Path Parameters

None.

#### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `page` | integer | Page number (default: `1`) |
| `items` | integer | Items per page (default: `25`) |
| `status` | string | Filter by document status (e.g., `completed`, `processing`, `failed`) |
| `name` | string | Case-insensitive partial match on document name |
| `authorization_boundary_id` | integer | Filter by authorization boundary |

#### Response Body

```json
{
  "data": [
    {
      "id": 42,
      "slug": "acme-cloud-platform-ssp",
      "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "ACME Cloud Platform SSP",
      "status": "completed",
      "lifecycle_status": "active",
      "file_type": "excel",
      "creation_method": "upload",
      "authorization_boundary_id": 7,
      "created_at": "2025-11-15T14:30:00Z",
      "updated_at": "2025-12-01T09:45:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "pages": 3,
    "count": 58,
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
  "https://sparc.example.com/api/v1/ssp_documents?page=1&items=25&status=completed" | jq .
```

---

### GET /api/v1/ssp_documents/:slug

Returns a single SSP document with detailed fields including description, version, system status, and control count.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier (e.g., `acme-cloud-platform-ssp`) |

#### Query Parameters

None.

#### Response Body

```json
{
  "data": {
    "id": 42,
    "slug": "acme-cloud-platform-ssp",
    "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "name": "ACME Cloud Platform SSP",
    "status": "completed",
    "lifecycle_status": "active",
    "file_type": "excel",
    "creation_method": "upload",
    "authorization_boundary_id": 7,
    "created_at": "2025-11-15T14:30:00Z",
    "updated_at": "2025-12-01T09:45:00Z",
    "description": "System Security Plan for the ACME Cloud Platform production environment.",
    "ssp_version": "3.1",
    "system_status": "operational",
    "security_sensitivity_level": "high",
    "controls_count": 370,
    "profile_document_id": 12
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document returned successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `ssp.read` for this boundary |
| `404 Not Found` | No document matches the given slug |

#### cURL Example

```bash
curl -s \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/ssp_documents/acme-cloud-platform-ssp" | jq .
```

---

### POST /api/v1/ssp_documents

Creates a new SSP document. The caller must have `ssp.write` permission for the target authorization boundary.

#### Path Parameters

None.

#### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ssp_document[name]` | string | yes | Document name |
| `ssp_document[description]` | string | no | Document description |
| `ssp_document[authorization_boundary_id]` | integer | no | Associated authorization boundary |
| `ssp_document[profile_document_id]` | integer | no | Associated profile/baseline |
| `ssp_document[system_status]` | string | no | System operational status |
| `ssp_document[security_sensitivity_level]` | string | no | FIPS 199 sensitivity level |
| `ssp_document[ssp_version]` | string | no | SSP document version |
| `ssp_document[security_objective_confidentiality]` | string | no | Confidentiality objective (low/moderate/high) |
| `ssp_document[security_objective_integrity]` | string | no | Integrity objective (low/moderate/high) |
| `ssp_document[security_objective_availability]` | string | no | Availability objective (low/moderate/high) |
| `ssp_document[lifecycle_status]` | string | no | Lifecycle status (e.g., `active`, `draft`) |

#### Response Body

```json
{
  "data": {
    "id": 43,
    "slug": "acme-cloud-platform-ssp",
    "uuid": "b2c3d4e5-f6a7-8901-bcde-f23456789012",
    "name": "ACME Cloud Platform SSP",
    "status": "draft",
    "lifecycle_status": "draft",
    "file_type": null,
    "creation_method": "api",
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
| `403 Forbidden` | Caller lacks `ssp.write` for the target boundary |
| `422 Unprocessable Entity` | Validation errors (see `error` and `details` fields) |

#### cURL Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "ssp_document": {
      "name": "ACME Cloud Platform SSP",
      "description": "System Security Plan for the ACME Cloud Platform production environment.",
      "authorization_boundary_id": 7,
      "profile_document_id": 12,
      "system_status": "operational",
      "security_sensitivity_level": "high",
      "ssp_version": "3.1",
      "security_objective_confidentiality": "high",
      "security_objective_integrity": "high",
      "security_objective_availability": "moderate",
      "lifecycle_status": "draft"
    }
  }' \
  "https://sparc.example.com/api/v1/ssp_documents" | jq .
```

---

### PUT /api/v1/ssp_documents/:slug

Updates an existing SSP document. Only the fields provided in the request body are changed.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier |

#### Request Body

Same fields as [POST create](#post-apiv1ssp_documents). All fields are optional for update.

#### Response Body

```json
{
  "data": {
    "id": 42,
    "slug": "acme-cloud-platform-ssp",
    "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "name": "ACME Cloud Platform SSP",
    "status": "completed",
    "lifecycle_status": "active",
    "file_type": "excel",
    "creation_method": "upload",
    "authorization_boundary_id": 7,
    "created_at": "2025-11-15T14:30:00Z",
    "updated_at": "2025-12-10T11:00:00Z"
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document updated successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `ssp.write` for this boundary |
| `404 Not Found` | No document matches the given slug |
| `422 Unprocessable Entity` | Validation errors |

#### cURL Example

```bash
curl -s -X PUT \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "ssp_document": {
      "lifecycle_status": "active",
      "ssp_version": "3.2"
    }
  }' \
  "https://sparc.example.com/api/v1/ssp_documents/acme-cloud-platform-ssp" | jq .
```

---

### DELETE /api/v1/ssp_documents/:slug

Soft-deletes an SSP document. The record is marked as deleted but retained in the database for audit purposes.

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
    "id": 42,
    "slug": "acme-cloud-platform-ssp",
    "deleted": true
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document soft-deleted successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `ssp.write` for this boundary |
| `404 Not Found` | No document matches the given slug |

#### cURL Example

```bash
curl -s -X DELETE \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/ssp_documents/acme-cloud-platform-ssp" | jq .
```

---

### POST /api/v1/ssp_documents/convert

Uploads an Excel file and parses it into an SSP document with controls and control fields. The file is processed synchronously and the resulting document is returned in the response.

#### Path Parameters

None.

#### Request Body (multipart/form-data)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `excel_file` | file | yes | Excel file (.xlsx) containing SSP data |

#### Response Body

```json
{
  "success": true,
  "message": "Conversion successful",
  "data": {
    "name": "ACME Cloud Platform SSP",
    "controls": [
      {
        "control_id": "AC-1",
        "fields": {
          "implementation_status": "implemented",
          "responsible_role": "System Administrator"
        }
      }
    ]
  },
  "document_id": 44
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | File parsed and SSP created successfully |
| `400 Bad Request` | No file provided in the request |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `ssp.write` |
| `500 Internal Server Error` | File parsing failed |

#### cURL Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -F "excel_file=@/path/to/acme-cloud-platform-ssp.xlsx" \
  "https://sparc.example.com/api/v1/ssp_documents/convert" | jq .
```

---

### PUT /api/v1/ssp_documents/:slug/update_fields

Bulk-update editable control fields on a single SSP. The endpoint accepts a `controls` map keyed by control identifier; each entry is a partial map of field updates that the `SspUpdateService` applies in one save. This is the API surface the inline-editing UI uses, but it's also intended for ETL / migration scripts that need to write many fields atomically without going through `PUT /:slug` for each field.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier |

#### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `controls` | object | Yes | Map of control identifier → field-update hash. Field identifiers within each control follow the same key convention exposed in `GET /:slug` (the document's serialized `controls[].fields` array). |

```json
{
  "controls": {
    "AC-1": {
      "implementation_status": "implemented",
      "responsible_role": "System Owner",
      "control_summary": "Updated implementation narrative..."
    },
    "AC-2": {
      "implementation_status": "partial",
      "control_summary": "Account provisioning automated; deprovisioning still manual."
    }
  }
}
```

#### Response Body

```json
{
  "success": true,
  "message": "Controls updated successfully",
  "data": { /* serialized SSP document with updated controls */ }
}
```

The `data` field is the full updated SSP document (same shape as `GET /:slug` detailed response), so the caller can refresh its UI in one round-trip.

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Bulk update applied (the `success: true` flag is also `true` in the body) |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `ssp.write` |
| `404 Not Found` | No SSP document matches the slug |
| `422 Unprocessable Entity` | A field update failed validation; the response body's `error` field contains the offending message |

#### Side effects

A successful call writes one row to `audit_events`:

- `action`: `ssp_document_updated`
- `metadata.controls_updated`: number of distinct control identifiers in the request

Per-field changes are not separately audited — this is bulk-edit by design; the granular history is in the document's serialized controls.

#### cURL Example

```bash
curl -X PUT "https://sparc.example.com/api/v1/ssp_documents/acme-cloud-platform-ssp/update_fields" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  --data-binary @ssp-bulk-edit.json
```

---

### GET /api/v1/ssp_documents/:slug/export

Exports a full SSP document as a JSON download, including all controls and control fields.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier |

#### Query Parameters

None.

#### Response Body

The response is the full JSON export of the SSP document, structured by the `JsonExportService`. The exact shape depends on the document content.

```json
{
  "ssp_document": {
    "name": "ACME Cloud Platform SSP",
    "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "controls": [
      {
        "control_id": "AC-1",
        "title": "Policy and Procedures",
        "fields": [
          {
            "field_name": "implementation_status",
            "field_value": "implemented",
            "editable": true
          },
          {
            "field_name": "responsible_role",
            "field_value": "System Administrator",
            "editable": true
          }
        ]
      }
    ]
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Export returned successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `ssp.read` for this boundary |
| `404 Not Found` | No document matches the given slug |

#### cURL Example

```bash
curl -s \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/ssp_documents/acme-cloud-platform-ssp/export" | jq .
```

---

## Common Errors

| Status | Body | Cause |
|--------|------|-------|
| `401 Unauthorized` | `{"error": "Unauthorized"}` | Bearer token is missing, expired, or invalid |
| `403 Forbidden` | `{"error": "Forbidden"}` | Caller lacks required permission for the target boundary |
| `404 Not Found` | `{"error": "Not found"}` | No document exists with the provided slug |
| `422 Unprocessable Entity` | `{"error": "Validation failed: ...", "details": [...]}` | Request body failed model validations |
| `500 Internal Server Error` | `{"error": "..."}` | Server-side parsing or processing failure (convert endpoint) |
