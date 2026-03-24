# POA&M Documents

Plan of Action and Milestones (POA&M) documents track security weaknesses, planned remediation actions, and milestone dates for an information system. POA&M documents are scoped to an authorization boundary -- non-admin users can only access POA&Ms within boundaries they are members of. Reading requires the `poam.read` permission; creating, updating, and deleting require `poam.write`.

## Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `GET` | `/api/v1/poam_documents` | List POA&M documents (paginated, filterable) | `poam.read` |
| `GET` | `/api/v1/poam_documents/:slug` | Get a single POA&M document | `poam.read` |
| `POST` | `/api/v1/poam_documents` | Create a new POA&M document | `poam.write` |
| `PUT` | `/api/v1/poam_documents/:slug` | Update a POA&M document | `poam.write` |
| `DELETE` | `/api/v1/poam_documents/:slug` | Soft-delete a POA&M document | `poam.write` |

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

## Common Errors

| Status | Body | Cause |
|--------|------|-------|
| `401 Unauthorized` | `{"error": "Unauthorized"}` | Bearer token is missing, expired, or invalid |
| `403 Forbidden` | `{"error": "Forbidden"}` | Caller lacks required permission for the target boundary |
| `404 Not Found` | `{"error": "Not found"}` | No document exists with the provided slug |
| `422 Unprocessable Entity` | `{"error": "Validation failed: ...", "details": [...]}` | Request body failed model validations |
