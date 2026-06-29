# Control Catalogs

Control catalogs represent collections of security controls such as NIST SP 800-53 Rev 4 and Rev 5. All authenticated users can read catalogs. Write operations (create, update, delete) are restricted to admin users only. Catalogs are identified by numeric ID in API paths but are looked up internally by slug.

## Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `GET` | `/api/v1/control_catalogs` | List control catalogs (paginated, filterable) | Any authenticated user |
| `GET` | `/api/v1/control_catalogs/:id` | Get a single control catalog | Any authenticated user |
| `POST` | `/api/v1/control_catalogs` | Create a new control catalog | Admin only |
| `PUT` | `/api/v1/control_catalogs/:id` | Update a control catalog | Admin only |
| `DELETE` | `/api/v1/control_catalogs/:id` | Delete a control catalog (hard-delete) | Admin only |

---

### GET /api/v1/control_catalogs

Returns a paginated list of control catalogs. Available to all authenticated users.

#### Path Parameters

None.

#### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `page` | integer | Page number (default: `1`) |
| `items` | integer | Items per page (default: `25`) |
| `status` | string | Filter by catalog status |
| `name` | string | Case-insensitive partial match on catalog name |
| `q` | string | Case-insensitive search across name and description (#672) |
| `lifecycle_status` | string | Filter by lifecycle status (e.g., `active`, `deprecated`) |

#### Response Body

```json
{
  "data": [
    {
      "id": 1,
      "slug": "nist-sp-800-53-rev-5",
      "oscal_uuid": "d4e5f6a7-b8c9-0123-defa-456789012345",
      "name": "NIST SP 800-53 Rev 5",
      "version": "5.1.1",
      "source": "NIST",
      "status": "published",
      "lifecycle_status": "active",
      "oscal_version": "1.1.2",
      "published": true,
      "created_at": "2025-01-15T12:00:00Z",
      "updated_at": "2025-06-01T08:00:00Z"
    },
    {
      "id": 2,
      "slug": "nist-sp-800-53-rev-4",
      "oscal_uuid": "e5f6a7b8-c9d0-1234-efab-567890123456",
      "name": "NIST SP 800-53 Rev 4",
      "version": "4.0",
      "source": "NIST",
      "status": "published",
      "lifecycle_status": "deprecated",
      "oscal_version": "1.1.2",
      "published": true,
      "created_at": "2025-01-15T12:00:00Z",
      "updated_at": "2025-06-01T08:00:00Z"
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
  "https://sparc.example.com/api/v1/control_catalogs?page=1&items=25" | jq .
```

---

### GET /api/v1/control_catalogs/:id

Returns a single control catalog with detailed fields including description, total control count, family count, and digest.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Catalog ID (e.g., `1`) |

#### Query Parameters

None.

#### Response Body

```json
{
  "data": {
    "id": 1,
    "slug": "nist-sp-800-53-rev-5",
    "oscal_uuid": "d4e5f6a7-b8c9-0123-defa-456789012345",
    "name": "NIST SP 800-53 Rev 5",
    "version": "5.1.1",
    "source": "NIST",
    "status": "published",
    "lifecycle_status": "active",
    "oscal_version": "1.1.2",
    "published": true,
    "created_at": "2025-01-15T12:00:00Z",
    "updated_at": "2025-06-01T08:00:00Z",
    "description": "NIST Special Publication 800-53 Revision 5 — Security and Privacy Controls for Information Systems and Organizations.",
    "total_controls": 1189,
    "families_count": 20,
    "short_digest": "a1b2c3d4"
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Catalog returned successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `404 Not Found` | No catalog matches the given ID |

#### cURL Example

```bash
curl -s \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/control_catalogs/1" | jq .
```

---

### POST /api/v1/control_catalogs

Creates a new control catalog. Only admin users can perform this operation.

#### Path Parameters

None.

#### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `control_catalog[name]` | string | yes | Catalog name |
| `control_catalog[description]` | string | no | Catalog description |
| `control_catalog[version]` | string | no | Catalog version string |
| `control_catalog[source]` | string | no | Origin of the catalog (e.g., `NIST`, `CIS`) |
| `control_catalog[oscal_version]` | string | no | OSCAL schema version |
| `control_catalog[lifecycle_status]` | string | no | Lifecycle status (e.g., `active`, `draft`) |

#### Response Body

```json
{
  "data": {
    "id": 3,
    "slug": "cis-controls-v8",
    "oscal_uuid": "f6a7b8c9-d0e1-2345-fabc-678901234567",
    "name": "CIS Controls v8",
    "version": "8.0",
    "source": "CIS",
    "status": "draft",
    "lifecycle_status": "draft",
    "oscal_version": "1.1.2",
    "published": false,
    "created_at": "2025-12-10T10:00:00Z",
    "updated_at": "2025-12-10T10:00:00Z"
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `201 Created` | Catalog created successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller is not an admin |
| `422 Unprocessable Entity` | Validation errors (see `error` and `details` fields) |

#### cURL Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "control_catalog": {
      "name": "CIS Controls v8",
      "description": "Center for Internet Security Controls version 8.",
      "version": "8.0",
      "source": "CIS",
      "oscal_version": "1.1.2",
      "lifecycle_status": "draft"
    }
  }' \
  "https://sparc.example.com/api/v1/control_catalogs" | jq .
```

---

### PUT /api/v1/control_catalogs/:id

Updates an existing control catalog. Only admin users can perform this operation. Only the fields provided in the request body are changed.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Catalog ID |

#### Request Body

Same fields as [POST create](#post-apiv1control_catalogs). All fields are optional for update.

#### Response Body

```json
{
  "data": {
    "id": 1,
    "slug": "nist-sp-800-53-rev-5",
    "oscal_uuid": "d4e5f6a7-b8c9-0123-defa-456789012345",
    "name": "NIST SP 800-53 Rev 5",
    "version": "5.1.1",
    "source": "NIST",
    "status": "published",
    "lifecycle_status": "active",
    "oscal_version": "1.1.2",
    "published": true,
    "created_at": "2025-01-15T12:00:00Z",
    "updated_at": "2025-12-10T11:00:00Z"
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Catalog updated successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller is not an admin |
| `404 Not Found` | No catalog matches the given ID |
| `422 Unprocessable Entity` | Validation errors |

#### cURL Example

```bash
curl -s -X PUT \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "control_catalog": {
      "lifecycle_status": "active",
      "version": "5.1.2"
    }
  }' \
  "https://sparc.example.com/api/v1/control_catalogs/1" | jq .
```

---

### DELETE /api/v1/control_catalogs/:id

Permanently deletes a control catalog. Only admin users can perform this operation. This is a hard-delete -- the record is removed from the database. Deletion will fail if the catalog has dependent records (e.g., profile documents referencing it).

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Catalog ID |

#### Request Body

None.

#### Response Body

```json
{
  "data": {
    "id": 3,
    "deleted": true
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Catalog deleted successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller is not an admin |
| `404 Not Found` | No catalog matches the given ID |
| `422 Unprocessable Entity` | Cannot delete catalog with dependent records |

#### cURL Example

```bash
curl -s -X DELETE \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/control_catalogs/3" | jq .
```

---

## Common Errors

| Status | Body | Cause |
|--------|------|-------|
| `401 Unauthorized` | `{"error": "Unauthorized"}` | Bearer token is missing, expired, or invalid |
| `403 Forbidden` | `{"error": "Forbidden"}` | Caller is not an admin (write operations) |
| `404 Not Found` | `{"error": "Not found"}` | No catalog exists with the provided ID |
| `422 Unprocessable Entity` | `{"error": "Validation failed: ...", "details": [...]}` | Request body failed model validations |
| `422 Unprocessable Entity` | `{"error": "Cannot delete catalog with dependencies: ..."}` | Catalog has dependent profile documents or other records |
