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

## Common Errors

| Code | Error | Description |
|------|-------|-------------|
| `401` | `Unauthorized` | Missing or invalid Bearer token |
| `404` | `Not Found` | CDEF document does not exist or has been deleted |
| `422` | `Unprocessable Entity` | Validation failed -- missing required fields or invalid values |
| `500` | `Internal Server Error` | Unexpected server error -- contact your administrator |
