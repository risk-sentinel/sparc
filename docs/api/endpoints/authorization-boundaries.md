# Authorization Boundaries API

Manage authorization boundaries. An authorization boundary defines the scope of a system's security authorization, encompassing the hardware, software, and network components that are assessed and authorized together. Non-admin users can only access boundaries they are authorized to view.

## Base URL

```
https://sparc.example.com/api/v1/authorization_boundaries
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

| Role | Access |
|------|--------|
| Admin | Full access to all boundaries |
| Non-admin | Read/write access to own boundaries only |

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/authorization_boundaries` | List all boundaries |
| `GET` | `/api/v1/authorization_boundaries/:id` | Show a single boundary |
| `POST` | `/api/v1/authorization_boundaries` | Create a new boundary |
| `PUT` | `/api/v1/authorization_boundaries/:id` | Update a boundary |
| `DELETE` | `/api/v1/authorization_boundaries/:id` | Delete a boundary |
| `DELETE` | `/api/v1/authorization_boundaries/bulk` | Bulk-delete boundaries (admin-only) |
| `PATCH` | `/api/v1/authorization_boundaries/:id/organization` | Assign the boundary to an organization, or clear it with `organization_id: null` |
| `GET` | `/api/v1/authorization_boundaries/:id/hdf_system` | The boundary as an HDF `hdf-system` document — see [HDF System](hdf-system.md) (#1179) |

---

## Response Fields

Every boundary representation (list rows, create/update/organization responses,
and the detail) carries these fields:

| Field | Type | Description |
|-------|------|-------------|
| `id` | integer | Database id. Instance-local; not stable across environments |
| `slug` | string | URL slug; accepted anywhere `:id` is |
| `uuid` | string (RFC 4122) | The boundary's **durable identifier** (#1180, #1178). Use this to key evidence, OSCAL `system-id`, or federation joins -- not `id`, `slug`, or `name`, which are instance-local or mutable |
| `organization_id` | integer or `null` | The owning organization's id; `null` when the boundary is not assigned to one (#1178) |
| `organization_uuid` | string (RFC 4122) or `null` | The owning organization's durable identifier; `null` when unassigned (#1178). With `organization_id`, lets a client build the organization -> boundary tree from the API alone |
| `name` | string | Boundary name |
| `description` | string | Short description |
| `status` | string | Lifecycle status |
| `created_at` / `updated_at` | string (ISO 8601) | Timestamps |

The detail (`GET /api/v1/authorization_boundaries/:id`) additionally carries
`artifact_summary`, `organization` (the organization's name), `members_count`,
`evidences_count`, and `environments`.

---

### GET List All Boundaries

Returns a paginated list of authorization boundaries. Non-admin users see only boundaries they own or are members of.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | integer | No | Page number (default: `1`) |
| `items` | integer | No | Items per page (default: `25`) |
| `status` | string | No | Filter by status (e.g., `active`, `inactive`, `pending`) |
| `name` | string | No | Filter by name (partial match) |
| `q` | string | No | Case-insensitive search across name and description (#672) |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/authorization_boundaries?status=active&page=1&items=25" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": [
    {
      "id": 1,
      "slug": "north-america-prod",
      "uuid": "3f1c9a52-7d4e-4b8a-9c21-5e6f7a8b9c0d",
      "organization_id": 2,
      "organization_uuid": "a7d2e4f6-1b3c-4d5e-8f9a-0b1c2d3e4f5a",
      "name": "North America Prod",
      "description": "Production environment for North American operations",
      "status": "active",
      "created_at": "2026-01-05T08:00:00Z",
      "updated_at": "2026-03-15T11:30:00Z"
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
| `200` | Boundaries returned successfully |
| `401` | Unauthorized -- missing or invalid token |

---

### GET Show a Single Boundary

Returns a single authorization boundary with its metadata.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Numeric boundary ID |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/authorization_boundaries/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "slug": "north-america-prod",
    "uuid": "3f1c9a52-7d4e-4b8a-9c21-5e6f7a8b9c0d",
    "organization_id": 2,
    "organization_uuid": "a7d2e4f6-1b3c-4d5e-8f9a-0b1c2d3e4f5a",
    "name": "North America Prod",
    "description": "Production environment for North American operations",
    "status": "active",
    "created_at": "2026-01-05T08:00:00Z",
    "updated_at": "2026-03-15T11:30:00Z",
    "artifact_summary": {
      "ssp": "North America Prod SSP",
      "sap": null,
      "sar": null,
      "poam_count": 1,
      "boundary_count": 2,
      "component_count": 5
    },
    "organization": "ACME Corp",
    "members_count": 4,
    "evidences_count": 12,
    "environments": [
      { "name": "Production", "environment": "production", "components": 5 }
    ]
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Boundary returned successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Boundary not found or not accessible |

---

### POST Create a New Boundary

Create a new authorization boundary.

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Boundary name |
| `description` | string | No | Short description |
| `status` | string | No | Status: `active`, `inactive`, `pending` (default: `active`) |
| `authorization_boundary_description` | string | No | Detailed description of the boundary scope and included components |
| `authorization_date` | string | No | When the authorization in force was granted, `YYYY-MM-DD` (#1154). `null` or `""` clears it |
| `next_decision_date` | string | No | When the authorizing official is next due to decide, `YYYY-MM-DD` (#1154). Exported on the boundary's SSP as the SPARC-namespace prop `next-decision-date`. `null` or `""` clears it |

Both dates are also accepted on update, are returned on every response
(`null` when unset), and are refused with `422` unless they are a real calendar
date in `YYYY-MM-DD` form.

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/authorization_boundaries" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "authorization_boundary": {
      "name": "North America Prod",
      "description": "Production environment for North American operations",
      "status": "active",
      "authorization_boundary_description": "Encompasses all AWS us-east-1 and us-west-2 resources including EC2, RDS, S3, and VPC components supporting the ACME Cloud Platform"
    }
  }'
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "slug": "north-america-prod",
    "uuid": "3f1c9a52-7d4e-4b8a-9c21-5e6f7a8b9c0d",
    "organization_id": null,
    "organization_uuid": null,
    "name": "North America Prod",
    "description": "Production environment for North American operations",
    "status": "active",
    "created_at": "2026-03-23T12:00:00Z",
    "updated_at": "2026-03-23T12:00:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `201` | Boundary created successfully |
| `401` | Unauthorized -- missing or invalid token |
| `422` | Validation error -- check response body for details |

---

### PUT Update a Boundary

Update an existing authorization boundary. Only include the fields you want to change.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Numeric boundary ID |

**Example Request**

```bash
curl -X PUT "https://sparc.example.com/api/v1/authorization_boundaries/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "authorization_boundary": {
      "status": "inactive",
      "description": "Decommissioned -- migrated to EMEA region"
    }
  }'
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "slug": "north-america-prod",
    "uuid": "3f1c9a52-7d4e-4b8a-9c21-5e6f7a8b9c0d",
    "organization_id": 2,
    "organization_uuid": "a7d2e4f6-1b3c-4d5e-8f9a-0b1c2d3e4f5a",
    "name": "North America Prod",
    "description": "Decommissioned -- migrated to EMEA region",
    "status": "inactive",
    "created_at": "2026-01-05T08:00:00Z",
    "updated_at": "2026-03-23T14:00:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Boundary updated successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Boundary not found or not accessible |
| `422` | Validation error -- check response body for details |

---

### DELETE Delete a Boundary

Delete an authorization boundary. Associated KSI validations are also removed.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Numeric boundary ID |

**Example Request**

```bash
curl -X DELETE "https://sparc.example.com/api/v1/authorization_boundaries/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "name": "North America Prod",
    "deleted": true
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Boundary deleted successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Boundary not found or not accessible |

---

### DELETE Bulk-Delete Boundaries

**Admin-only.** Delete multiple authorization boundaries in one request (#629). Honors the referential-integrity guard (SSP/SAP/SAR/POA&M attached) and returns a per-id partial-success result -- ids that could not be deleted are reported in `blocked`, ids that did not resolve in `missing`.

**Path:** `DELETE /api/v1/authorization_boundaries/bulk`

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ids` | array of integers/slugs | Yes | Identifiers of the boundaries to delete |

**Example Request**

```bash
curl -X DELETE "https://sparc.example.com/api/v1/authorization_boundaries/bulk" \
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

## Common Errors

| Code | Error | Description |
|------|-------|-------------|
| `401` | `Unauthorized` | Missing or invalid Bearer token |
| `404` | `Not Found` | Boundary does not exist or user lacks access |
| `422` | `Unprocessable Entity` | Validation failed -- missing required fields or invalid values |
| `500` | `Internal Server Error` | Unexpected server error -- contact your administrator |
