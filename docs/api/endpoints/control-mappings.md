# Control Mappings API

Manage control mappings between source and target control catalogs. Mappings define relationships between controls in different frameworks or catalog revisions (e.g., NIST 800-53 Rev 4 to Rev 5, or NIST to ISO 27001). All endpoints use numeric IDs. Write operations (create, update, delete) require admin privileges.

## Base URL

```
https://sparc.example.com/api/v1/control_mappings
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

| Operation | Required Role |
|-----------|---------------|
| List, Show | Any authenticated user |
| Create, Update, Delete | Admin only |

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/control_mappings` | List all mappings |
| `GET` | `/api/v1/control_mappings/:id` | Show a single mapping |
| `POST` | `/api/v1/control_mappings` | Create a new mapping (admin) |
| `PUT` | `/api/v1/control_mappings/:id` | Update a mapping (admin) |
| `DELETE` | `/api/v1/control_mappings/:id` | Delete a mapping (admin) |

---

### GET List All Mappings

Returns a paginated list of control mappings.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | integer | No | Page number (default: `1`) |
| `items` | integer | No | Items per page (default: `25`) |
| `status` | string | No | Filter by status (e.g., `draft`, `active`, `deprecated`) |
| `name` | string | No | Filter by name (partial match) |
| `source_catalog_id` | integer | No | Filter by source catalog ID |
| `target_catalog_id` | integer | No | Filter by target catalog ID |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/control_mappings?status=active&source_catalog_id=1&page=1&items=25" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": [
    {
      "id": 1,
      "name": "NIST 800-53 Rev 4 to Rev 5",
      "description": "Maps controls from NIST SP 800-53 Revision 4 to Revision 5",
      "status": "active",
      "method_type": "automated",
      "matching_rationale": "Direct identifier mapping with manual review of withdrawn controls",
      "mapping_version": "2.0.0",
      "oscal_version": "1.1.2",
      "source_catalog_id": 1,
      "target_catalog_id": 2,
      "entries_count": 1189,
      "created_at": "2026-01-15T08:00:00Z",
      "updated_at": "2026-03-10T16:45:00Z"
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
| `200` | Mappings returned successfully |
| `401` | Unauthorized -- missing or invalid token |

---

### GET Show a Single Mapping

Returns a single control mapping with its metadata.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Numeric mapping ID |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/control_mappings/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "name": "NIST 800-53 Rev 4 to Rev 5",
    "description": "Maps controls from NIST SP 800-53 Revision 4 to Revision 5",
    "status": "active",
    "method_type": "automated",
    "matching_rationale": "Direct identifier mapping with manual review of withdrawn controls",
    "mapping_version": "2.0.0",
    "oscal_version": "1.1.2",
    "source_catalog_id": 1,
    "target_catalog_id": 2,
    "source_catalog_name": "NIST SP 800-53 Rev 4",
    "target_catalog_name": "NIST SP 800-53 Rev 5",
    "entries_count": 1189,
    "created_at": "2026-01-15T08:00:00Z",
    "updated_at": "2026-03-10T16:45:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Mapping returned successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Mapping not found |

---

### POST Create a New Mapping (Admin Only)

Create a new control mapping between two catalogs.

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Mapping name |
| `description` | string | No | Description of the mapping |
| `status` | string | No | Status: `draft`, `active`, `deprecated` (default: `draft`) |
| `method_type` | string | Yes | Mapping method: `automated`, `manual`, `hybrid` |
| `matching_rationale` | string | No | Explanation of how controls are matched |
| `mapping_version` | string | No | Version of the mapping |
| `oscal_version` | string | No | OSCAL schema version (default: `1.1.2`) |
| `source_catalog_id` | integer | Yes | ID of the source control catalog |
| `target_catalog_id` | integer | Yes | ID of the target control catalog |

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/control_mappings" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "control_mapping": {
      "name": "NIST 800-53 Rev 4 to Rev 5",
      "description": "Maps controls from NIST SP 800-53 Revision 4 to Revision 5",
      "status": "draft",
      "method_type": "automated",
      "matching_rationale": "Direct identifier mapping with manual review of withdrawn controls",
      "mapping_version": "1.0.0",
      "oscal_version": "1.1.2",
      "source_catalog_id": 1,
      "target_catalog_id": 2
    }
  }'
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "name": "NIST 800-53 Rev 4 to Rev 5",
    "description": "Maps controls from NIST SP 800-53 Revision 4 to Revision 5",
    "status": "draft",
    "method_type": "automated",
    "matching_rationale": "Direct identifier mapping with manual review of withdrawn controls",
    "mapping_version": "1.0.0",
    "oscal_version": "1.1.2",
    "source_catalog_id": 1,
    "target_catalog_id": 2,
    "entries_count": 0,
    "created_at": "2026-03-23T12:00:00Z",
    "updated_at": "2026-03-23T12:00:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `201` | Mapping created successfully |
| `401` | Unauthorized -- missing or invalid token |
| `403` | Forbidden -- admin privileges required |
| `422` | Validation error -- check response body for details |

---

### PUT Update a Mapping (Admin Only)

Update an existing control mapping. Only include the fields you want to change.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Numeric mapping ID |

**Example Request**

```bash
curl -X PUT "https://sparc.example.com/api/v1/control_mappings/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "control_mapping": {
      "status": "active",
      "mapping_version": "2.0.0"
    }
  }'
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "name": "NIST 800-53 Rev 4 to Rev 5",
    "status": "active",
    "mapping_version": "2.0.0",
    "updated_at": "2026-03-23T14:00:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Mapping updated successfully |
| `401` | Unauthorized -- missing or invalid token |
| `403` | Forbidden -- admin privileges required |
| `404` | Mapping not found |
| `422` | Validation error -- check response body for details |

---

### DELETE Delete a Mapping (Admin Only)

Delete a control mapping.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Numeric mapping ID |

**Example Request**

```bash
curl -X DELETE "https://sparc.example.com/api/v1/control_mappings/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "name": "NIST 800-53 Rev 4 to Rev 5",
    "deleted": true
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Mapping deleted successfully |
| `401` | Unauthorized -- missing or invalid token |
| `403` | Forbidden -- admin privileges required |
| `404` | Mapping not found |

---

## Common Errors

| Code | Error | Description |
|------|-------|-------------|
| `401` | `Unauthorized` | Missing or invalid Bearer token |
| `403` | `Forbidden` | Admin privileges required for write operations |
| `404` | `Not Found` | Mapping does not exist |
| `422` | `Unprocessable Entity` | Validation failed -- missing required fields or invalid catalog IDs |
| `500` | `Internal Server Error` | Unexpected server error -- contact your administrator |
