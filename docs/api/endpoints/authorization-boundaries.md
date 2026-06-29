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
      "name": "North America Prod",
      "description": "Production environment for North American operations",
      "status": "active",
      "authorization_boundary_description": "Encompasses all AWS us-east-1 and us-west-2 resources including EC2, RDS, S3, and VPC components supporting the ACME Cloud Platform",
      "ksi_validations_count": 48,
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
    "name": "North America Prod",
    "description": "Production environment for North American operations",
    "status": "active",
    "authorization_boundary_description": "Encompasses all AWS us-east-1 and us-west-2 resources including EC2, RDS, S3, and VPC components supporting the ACME Cloud Platform",
    "ksi_validations_count": 48,
    "created_at": "2026-01-05T08:00:00Z",
    "updated_at": "2026-03-15T11:30:00Z"
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
    "name": "North America Prod",
    "description": "Production environment for North American operations",
    "status": "active",
    "authorization_boundary_description": "Encompasses all AWS us-east-1 and us-west-2 resources including EC2, RDS, S3, and VPC components supporting the ACME Cloud Platform",
    "ksi_validations_count": 0,
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
    "name": "North America Prod",
    "description": "Decommissioned -- migrated to EMEA region",
    "status": "inactive",
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

## Common Errors

| Code | Error | Description |
|------|-------|-------------|
| `401` | `Unauthorized` | Missing or invalid Bearer token |
| `404` | `Not Found` | Boundary does not exist or user lacks access |
| `422` | `Unprocessable Entity` | Validation failed -- missing required fields or invalid values |
| `500` | `Internal Server Error` | Unexpected server error -- contact your administrator |
