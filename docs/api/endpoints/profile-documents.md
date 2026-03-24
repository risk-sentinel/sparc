# Profile Documents

Profile documents represent security baselines and resolved control profiles derived from a control catalog. They define which controls apply to a system and at what baseline level (e.g., FedRAMP HIGH). All authenticated users can read and write profile documents. No boundary scoping is applied.

## Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `GET` | `/api/v1/profile_documents` | List profile documents (paginated, filterable) | Any authenticated user |
| `GET` | `/api/v1/profile_documents/:slug` | Get a single profile document | Any authenticated user |
| `POST` | `/api/v1/profile_documents` | Create a new profile document | Any authenticated user |
| `PUT` | `/api/v1/profile_documents/:slug` | Update a profile document | Any authenticated user |
| `DELETE` | `/api/v1/profile_documents/:slug` | Soft-delete a profile document | Any authenticated user |

---

### GET /api/v1/profile_documents

Returns a paginated list of profile documents.

#### Path Parameters

None.

#### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `page` | integer | Page number (default: `1`) |
| `items` | integer | Items per page (default: `25`) |
| `status` | string | Filter by document status |
| `name` | string | Case-insensitive partial match on document name |
| `baseline_level` | string | Filter by baseline level (e.g., `low`, `moderate`, `high`) |
| `control_catalog_id` | integer | Filter by associated control catalog |

#### Response Body

```json
{
  "data": [
    {
      "id": 12,
      "slug": "fedramp-high-baseline",
      "uuid": "b8c9d0e1-f2a3-4567-bcde-890123456789",
      "name": "FedRAMP HIGH Baseline",
      "status": "published",
      "lifecycle_status": "active",
      "file_type": "catalog",
      "baseline_level": "high",
      "profile_version": "1.0",
      "oscal_version": "1.1.2",
      "created_at": "2025-03-01T10:00:00Z",
      "updated_at": "2025-06-15T12:00:00Z"
    },
    {
      "id": 13,
      "slug": "fedramp-moderate-baseline",
      "uuid": "c9d0e1f2-a3b4-5678-cdef-901234567890",
      "name": "FedRAMP Moderate Baseline",
      "status": "published",
      "lifecycle_status": "active",
      "file_type": "catalog",
      "baseline_level": "moderate",
      "profile_version": "1.0",
      "oscal_version": "1.1.2",
      "created_at": "2025-03-01T10:00:00Z",
      "updated_at": "2025-06-15T12:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "pages": 1,
    "count": 2,
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
  "https://sparc.example.com/api/v1/profile_documents?page=1&items=25&baseline_level=high" | jq .
```

---

### GET /api/v1/profile_documents/:slug

Returns a single profile document with detailed fields including description, associated catalog, and control count.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier (e.g., `fedramp-high-baseline`) |

#### Query Parameters

None.

#### Response Body

```json
{
  "data": {
    "id": 12,
    "slug": "fedramp-high-baseline",
    "uuid": "b8c9d0e1-f2a3-4567-bcde-890123456789",
    "name": "FedRAMP HIGH Baseline",
    "status": "published",
    "lifecycle_status": "active",
    "file_type": "catalog",
    "baseline_level": "high",
    "profile_version": "1.0",
    "oscal_version": "1.1.2",
    "created_at": "2025-03-01T10:00:00Z",
    "updated_at": "2025-06-15T12:00:00Z",
    "description": "FedRAMP HIGH baseline profile derived from NIST SP 800-53 Rev 5. Includes 370 controls.",
    "control_catalog_id": 1,
    "catalog_name": "NIST SP 800-53 Rev 5",
    "controls_count": 370
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document returned successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `404 Not Found` | No document matches the given slug |

#### cURL Example

```bash
curl -s \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/profile_documents/fedramp-high-baseline" | jq .
```

---

### POST /api/v1/profile_documents

Creates a new profile document.

#### Path Parameters

None.

#### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `profile_document[name]` | string | yes | Document name |
| `profile_document[description]` | string | no | Document description |
| `profile_document[baseline_level]` | string | no | Baseline level (e.g., `low`, `moderate`, `high`) |
| `profile_document[profile_version]` | string | no | Profile version string |
| `profile_document[oscal_version]` | string | no | OSCAL schema version |
| `profile_document[control_catalog_id]` | integer | no | Associated control catalog ID |
| `profile_document[lifecycle_status]` | string | no | Lifecycle status (e.g., `active`, `draft`) |
| `profile_document[file_type]` | string | no | File type (e.g., `catalog`, `profile`) |

#### Response Body

```json
{
  "data": {
    "id": 14,
    "slug": "fedramp-high-baseline",
    "uuid": "d0e1f2a3-b4c5-6789-defa-012345678901",
    "name": "FedRAMP HIGH Baseline",
    "status": "draft",
    "lifecycle_status": "draft",
    "file_type": "catalog",
    "baseline_level": "high",
    "profile_version": "1.0",
    "oscal_version": "1.1.2",
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
| `422 Unprocessable Entity` | Validation errors (see `error` and `details` fields) |

#### cURL Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "profile_document": {
      "name": "FedRAMP HIGH Baseline",
      "description": "FedRAMP HIGH baseline profile derived from NIST SP 800-53 Rev 5. Includes 370 controls.",
      "baseline_level": "high",
      "profile_version": "1.0",
      "oscal_version": "1.1.2",
      "control_catalog_id": 1,
      "lifecycle_status": "draft",
      "file_type": "catalog"
    }
  }' \
  "https://sparc.example.com/api/v1/profile_documents" | jq .
```

---

### PUT /api/v1/profile_documents/:slug

Updates an existing profile document. Only the fields provided in the request body are changed.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier |

#### Request Body

Same fields as [POST create](#post-apiv1profile_documents). All fields are optional for update.

#### Response Body

```json
{
  "data": {
    "id": 12,
    "slug": "fedramp-high-baseline",
    "uuid": "b8c9d0e1-f2a3-4567-bcde-890123456789",
    "name": "FedRAMP HIGH Baseline",
    "status": "published",
    "lifecycle_status": "active",
    "file_type": "catalog",
    "baseline_level": "high",
    "profile_version": "1.1",
    "oscal_version": "1.1.2",
    "created_at": "2025-03-01T10:00:00Z",
    "updated_at": "2025-12-10T11:00:00Z"
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document updated successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `404 Not Found` | No document matches the given slug |
| `422 Unprocessable Entity` | Validation errors |

#### cURL Example

```bash
curl -s -X PUT \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "profile_document": {
      "profile_version": "1.1",
      "lifecycle_status": "active"
    }
  }' \
  "https://sparc.example.com/api/v1/profile_documents/fedramp-high-baseline" | jq .
```

---

### DELETE /api/v1/profile_documents/:slug

Soft-deletes a profile document. The record is marked as deleted but retained in the database for audit purposes.

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
    "id": 12,
    "slug": "fedramp-high-baseline",
    "deleted": true
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document soft-deleted successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `404 Not Found` | No document matches the given slug |

#### cURL Example

```bash
curl -s -X DELETE \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/profile_documents/fedramp-high-baseline" | jq .
```

---

## Common Errors

| Status | Body | Cause |
|--------|------|-------|
| `401 Unauthorized` | `{"error": "Unauthorized"}` | Bearer token is missing, expired, or invalid |
| `404 Not Found` | `{"error": "Not found"}` | No document exists with the provided slug |
| `422 Unprocessable Entity` | `{"error": "Validation failed: ...", "details": [...]}` | Request body failed model validations |
