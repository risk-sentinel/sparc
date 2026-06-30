# SAR Documents

Security Assessment Results (SAR) documents record the findings from a security assessment of an information system. SAR documents are scoped to an authorization boundary -- non-admin users can only access SARs within boundaries they are members of. Reading requires the `sar.read` permission; creating, updating, and deleting require `sar.write`.

## Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `GET` | `/api/v1/sar_documents` | List SAR documents (paginated, filterable) | `sar.read` |
| `GET` | `/api/v1/sar_documents/:slug` | Get a single SAR document | `sar.read` |
| `POST` | `/api/v1/sar_documents` | Create a new SAR document | `sar.write` |
| `PUT` | `/api/v1/sar_documents/:slug` | Update a SAR document | `sar.write` |
| `DELETE` | `/api/v1/sar_documents/:slug` | Soft-delete a SAR document | `sar.write` |
| `POST` | `/api/v1/sar_documents/convert` | Upload and parse a document file into a SAR | `sar.write` |
| `PUT` | `/api/v1/sar_documents/:slug/update_fields` | Bulk-update editable control fields on one SAR | `sar.write` |
| `GET` | `/api/v1/sar_documents/:slug/export` | Export SAR as JSON | `sar.read` |

---

### GET /api/v1/sar_documents

Returns a paginated list of SAR documents. Admin users see all documents; non-admin users see only documents within their assigned authorization boundaries.

#### Path Parameters

None.

#### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `page` | integer | Page number (default: `1`) |
| `items` | integer | Items per page (default: `25`) |
| `status` | string | Filter by document status (e.g., `completed`, `processing`, `failed`) |
| `name` | string | Case-insensitive partial match on document name |
| `q` | string | Case-insensitive search across name and description (#672) |
| `authorization_boundary_id` | integer | Filter by authorization boundary |

#### Response Body

```json
{
  "data": [
    {
      "id": 18,
      "slug": "acme-annual-assessment-2025",
      "uuid": "c3d4e5f6-a7b8-9012-cdef-345678901234",
      "name": "ACME Annual Assessment 2025",
      "status": "completed",
      "lifecycle_status": "active",
      "file_type": "json",
      "creation_method": "upload",
      "authorization_boundary_id": 7,
      "created_at": "2025-09-01T08:00:00Z",
      "updated_at": "2025-09-15T16:30:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "pages": 1,
    "count": 4,
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
  "https://sparc.example.com/api/v1/sar_documents?page=1&items=25&status=completed" | jq .
```

---

### GET /api/v1/sar_documents/:slug

Returns a single SAR document with detailed fields including description, related document IDs, and control count.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier (e.g., `acme-annual-assessment-2025`) |

#### Query Parameters

None.

#### Response Body

```json
{
  "data": {
    "id": 18,
    "slug": "acme-annual-assessment-2025",
    "uuid": "c3d4e5f6-a7b8-9012-cdef-345678901234",
    "name": "ACME Annual Assessment 2025",
    "status": "completed",
    "lifecycle_status": "active",
    "file_type": "json",
    "creation_method": "upload",
    "authorization_boundary_id": 7,
    "created_at": "2025-09-01T08:00:00Z",
    "updated_at": "2025-09-15T16:30:00Z",
    "description": "Annual security assessment results for the ACME Cloud Platform.",
    "controls_count": 370,
    "sap_document_id": 5,
    "profile_document_id": 12,
    "ssp_document_id": 42
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document returned successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `sar.read` for this boundary |
| `404 Not Found` | No document matches the given slug |

#### cURL Example

```bash
curl -s \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/sar_documents/acme-annual-assessment-2025" | jq .
```

---

### POST /api/v1/sar_documents

Creates a new SAR document. The caller must have `sar.write` permission for the target authorization boundary.

#### Path Parameters

None.

#### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `sar_document[name]` | string | yes | Document name |
| `sar_document[description]` | string | no | Document description |
| `sar_document[authorization_boundary_id]` | integer | no | Associated authorization boundary |
| `sar_document[sap_document_id]` | integer | no | Related Security Assessment Plan |
| `sar_document[profile_document_id]` | integer | no | Associated profile/baseline |
| `sar_document[ssp_document_id]` | integer | no | Related System Security Plan |
| `sar_document[lifecycle_status]` | string | no | Lifecycle status (e.g., `active`, `draft`) |

#### Response Body

```json
{
  "data": {
    "id": 19,
    "slug": "acme-annual-assessment-2025",
    "uuid": "d4e5f6a7-b8c9-0123-defa-456789012345",
    "name": "ACME Annual Assessment 2025",
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
| `403 Forbidden` | Caller lacks `sar.write` for the target boundary |
| `422 Unprocessable Entity` | Validation errors (see `error` and `details` fields) |

#### cURL Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "sar_document": {
      "name": "ACME Annual Assessment 2025",
      "description": "Annual security assessment results for the ACME Cloud Platform.",
      "authorization_boundary_id": 7,
      "sap_document_id": 5,
      "profile_document_id": 12,
      "ssp_document_id": 42,
      "lifecycle_status": "draft"
    }
  }' \
  "https://sparc.example.com/api/v1/sar_documents" | jq .
```

---

### PUT /api/v1/sar_documents/:slug

Updates an existing SAR document. Only the fields provided in the request body are changed.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier |

#### Request Body

Same fields as [POST create](#post-apiv1sar_documents). All fields are optional for update.

#### Response Body

```json
{
  "data": {
    "id": 18,
    "slug": "acme-annual-assessment-2025",
    "uuid": "c3d4e5f6-a7b8-9012-cdef-345678901234",
    "name": "ACME Annual Assessment 2025",
    "status": "completed",
    "lifecycle_status": "active",
    "file_type": "json",
    "creation_method": "upload",
    "authorization_boundary_id": 7,
    "created_at": "2025-09-01T08:00:00Z",
    "updated_at": "2025-12-10T11:00:00Z"
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document updated successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `sar.write` for this boundary |
| `404 Not Found` | No document matches the given slug |
| `422 Unprocessable Entity` | Validation errors |

#### cURL Example

```bash
curl -s -X PUT \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "sar_document": {
      "lifecycle_status": "active"
    }
  }' \
  "https://sparc.example.com/api/v1/sar_documents/acme-annual-assessment-2025" | jq .
```

---

### DELETE /api/v1/sar_documents/:slug

Soft-deletes a SAR document. The record is marked as deleted but retained in the database for audit purposes.

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
    "id": 18,
    "slug": "acme-annual-assessment-2025",
    "deleted": true
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document soft-deleted successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `sar.write` for this boundary |
| `404 Not Found` | No document matches the given slug |

#### cURL Example

```bash
curl -s -X DELETE \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/sar_documents/acme-annual-assessment-2025" | jq .
```

---

### POST /api/v1/sar_documents/convert

Uploads a document file and parses it into a SAR document with controls and control fields. The file is processed synchronously and the resulting document is returned in the response.

#### Path Parameters

None.

#### Request Body (multipart/form-data)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `excel_file` | file | yes | Document file containing SAR data |

#### Response Body

```json
{
  "success": true,
  "message": "Conversion successful",
  "data": {
    "name": "ACME Annual Assessment 2025",
    "controls": [
      {
        "control_id": "AC-1",
        "fields": {
          "assessment_result": "satisfied",
          "assessor_notes": "All sub-controls verified."
        }
      }
    ]
  },
  "document_id": 20
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | File parsed and SAR created successfully |
| `400 Bad Request` | No file provided in the request |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `sar.write` |
| `500 Internal Server Error` | File parsing failed |

#### cURL Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -F "excel_file=@/path/to/acme-annual-assessment-2025.json" \
  "https://sparc.example.com/api/v1/sar_documents/convert" | jq .
```

---

### PUT /api/v1/sar_documents/:slug/update_fields

Bulk-update editable control fields on a single SAR. Mirrors the `ssp_documents` endpoint of the same name — accepts a `controls` map keyed by control identifier, with each value being a partial map of field updates the controller applies in one save. Only fields whose backing `SarControlField` is `editable?` are mutated; non-editable fields silently skip.

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
      "assessor_finding": "satisfied",
      "assessor_remarks": "Policy reviewed; signed by SO on 2026-04-15.",
      "evidence_url": "https://evidence.example.com/AC-1-policy-2026.pdf"
    },
    "AC-2": {
      "assessor_finding": "other_than_satisfied",
      "assessor_remarks": "Provisioning automated; deprovisioning manual."
    }
  }
}
```

#### Response Body

```json
{
  "success": true,
  "message": "Controls updated successfully",
  "data": { /* serialized SAR document with updated controls */ }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Bulk update applied |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `sar.write` |
| `404 Not Found` | No SAR document matches the slug, or one of the requested control identifiers does not exist on this document |
| `422 Unprocessable Entity` | A field update failed validation; the response body's `error` field contains the offending message |

#### Side effects

A successful call writes one row to `audit_events`:

- `action`: `sar_document_updated`
- `metadata.controls_updated`: number of distinct control identifiers in the request

#### cURL Example

```bash
curl -X PUT "https://sparc.example.com/api/v1/sar_documents/acme-annual-assessment-2025/update_fields" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  --data-binary @sar-bulk-edit.json
```

---

### GET /api/v1/sar_documents/:slug/export

Exports a full SAR document as a JSON download, including all controls and control fields.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier |

#### Query Parameters

None.

#### Response Body

The response is the full JSON export of the SAR document, structured by the `JsonExportService`.

```json
{
  "sar_document": {
    "name": "ACME Annual Assessment 2025",
    "uuid": "c3d4e5f6-a7b8-9012-cdef-345678901234",
    "controls": [
      {
        "control_id": "AC-1",
        "title": "Policy and Procedures",
        "fields": [
          {
            "field_name": "assessment_result",
            "field_value": "satisfied",
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
| `403 Forbidden` | Caller lacks `sar.read` for this boundary |
| `404 Not Found` | No document matches the given slug |

#### cURL Example

```bash
curl -s \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/sar_documents/acme-annual-assessment-2025/export" | jq .
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
