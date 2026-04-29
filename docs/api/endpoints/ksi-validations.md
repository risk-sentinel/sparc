# KSI Validations API

Track and manage KSI (Key Security Indicator) validation evidence for authorization boundaries. Validations record the compliance status of individual KSI indicators, including evidence references, validation methods, and scheduling. All endpoints are nested under a specific authorization boundary.

## Base URL

```
https://sparc.example.com/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

Validations are scoped to the authorization boundary. Users can only access validations for boundaries they are authorized to view.

## Endpoints

All endpoints are nested under an authorization boundary; the boundary id appears as the first path segment.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations` | List all validations for the boundary |
| `GET` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/:id` | Show a single validation |
| `POST` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations` | Create a new validation |
| `PUT` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/:id` | Update a validation |
| `DELETE` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/:id` | Delete a validation |
| `GET` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/summary` | Dashboard aggregation |
| `GET` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/export` | Export validations as compliance report |

---

### GET List All Validations

Returns a paginated list of KSI validations for the specified authorization boundary.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | integer | No | Page number (default: `1`) |
| `items` | integer | No | Items per page (default: `25`) |
| `status` | string | No | Filter by status: `validated`, `pending`, `failed`, `not_assessed` |
| `theme` | string | No | Filter by KSI theme key (e.g., `access_control`) |
| `overdue` | boolean | No | Filter for overdue validations (`true` or `false`) |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/authorization_boundaries/1/ksi_validations?status=pending&overdue=true&page=1&items=25" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": [
    {
      "id": 1,
      "authorization_boundary_id": 1,
      "catalog_control_id": 42,
      "indicator_id": "KSI-AC-01",
      "theme": "access_control",
      "status": "pending",
      "validation_method": "automated",
      "evidence_format": "oscal_json",
      "evidence_id": "ev-2026-001",
      "last_validated_at": "2026-02-15T10:00:00Z",
      "next_validation_due": "2026-03-15T10:00:00Z",
      "overdue": true,
      "notes": "Awaiting updated MFA enrollment evidence from IdP",
      "created_at": "2026-01-10T08:00:00Z",
      "updated_at": "2026-03-01T14:30:00Z"
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
| `200` | Validations returned successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Authorization boundary not found |

---

### GET Show a Single Validation

Returns a single KSI validation with full details including validation metadata.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Numeric validation ID |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/authorization_boundaries/1/ksi_validations/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "authorization_boundary_id": 1,
    "catalog_control_id": 42,
    "indicator_id": "KSI-AC-01",
    "theme": "access_control",
    "status": "validated",
    "validation_method": "automated",
    "evidence_format": "oscal_json",
    "evidence_id": "ev-2026-001",
    "last_validated_at": "2026-03-20T10:00:00Z",
    "next_validation_due": "2026-06-20T10:00:00Z",
    "overdue": false,
    "notes": "MFA enrollment verified across all user accounts via Okta API",
    "validation_metadata": {
      "tool": "okta-mfa-checker",
      "version": "2.1.0",
      "total_users": 1250,
      "mfa_enrolled": 1250,
      "compliance_rate": 100.0
    },
    "created_at": "2026-01-10T08:00:00Z",
    "updated_at": "2026-03-20T10:00:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Validation returned successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Authorization boundary or validation not found |

---

### POST Create a New Validation

Create a new KSI validation record for the authorization boundary.

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `catalog_control_id` | integer | Yes | ID of the catalog control being validated |
| `evidence_id` | string | No | Reference to the evidence artifact |
| `status` | string | Yes | Validation status: `validated`, `pending`, `failed`, `not_assessed` |
| `validation_method` | string | Yes | Method: `automated`, `manual`, `hybrid` |
| `evidence_format` | string | No | Format: `oscal_json`, `oscal_xml`, `spreadsheet`, `document` |
| `last_validated_at` | datetime | No | ISO 8601 timestamp of last validation |
| `next_validation_due` | datetime | No | ISO 8601 timestamp for next scheduled validation |
| `notes` | string | No | Free-text notes about the validation |
| `validation_metadata` | object | No | Arbitrary JSON metadata about the validation run |

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/authorization_boundaries/1/ksi_validations" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "ksi_validation": {
      "catalog_control_id": 42,
      "evidence_id": "ev-2026-001",
      "status": "validated",
      "validation_method": "automated",
      "evidence_format": "oscal_json",
      "last_validated_at": "2026-03-20T10:00:00Z",
      "next_validation_due": "2026-06-20T10:00:00Z",
      "notes": "MFA enrollment verified across all user accounts via Okta API",
      "validation_metadata": {
        "tool": "okta-mfa-checker",
        "version": "2.1.0",
        "total_users": 1250,
        "mfa_enrolled": 1250,
        "compliance_rate": 100.0
      }
    }
  }'
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "authorization_boundary_id": 1,
    "catalog_control_id": 42,
    "status": "validated",
    "validation_method": "automated",
    "evidence_format": "oscal_json",
    "evidence_id": "ev-2026-001",
    "last_validated_at": "2026-03-20T10:00:00Z",
    "next_validation_due": "2026-06-20T10:00:00Z",
    "notes": "MFA enrollment verified across all user accounts via Okta API",
    "validation_metadata": {
      "tool": "okta-mfa-checker",
      "version": "2.1.0",
      "total_users": 1250,
      "mfa_enrolled": 1250,
      "compliance_rate": 100.0
    },
    "created_at": "2026-03-20T10:00:00Z",
    "updated_at": "2026-03-20T10:00:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `201` | Validation created successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Authorization boundary not found |
| `422` | Validation error -- check response body for details |

---

### PUT Update a Validation

Update an existing KSI validation. Only include the fields you want to change.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Numeric validation ID |

**Example Request**

```bash
curl -X PUT "https://sparc.example.com/api/v1/authorization_boundaries/1/ksi_validations/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "ksi_validation": {
      "status": "failed",
      "notes": "3 service accounts missing MFA enrollment",
      "validation_metadata": {
        "tool": "okta-mfa-checker",
        "version": "2.1.0",
        "total_users": 1250,
        "mfa_enrolled": 1247,
        "compliance_rate": 99.76
      }
    }
  }'
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "authorization_boundary_id": 1,
    "status": "failed",
    "notes": "3 service accounts missing MFA enrollment",
    "validation_metadata": {
      "tool": "okta-mfa-checker",
      "version": "2.1.0",
      "total_users": 1250,
      "mfa_enrolled": 1247,
      "compliance_rate": 99.76
    },
    "updated_at": "2026-03-23T14:00:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Validation updated successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Authorization boundary or validation not found |
| `422` | Validation error -- check response body for details |

---

### DELETE Delete a Validation

Delete a KSI validation record.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Numeric validation ID |

**Example Request**

```bash
curl -X DELETE "https://sparc.example.com/api/v1/authorization_boundaries/1/ksi_validations/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "deleted": true
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Validation deleted successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Authorization boundary or validation not found |

---

### GET Summary (Dashboard Aggregation)

Returns an aggregated summary of KSI validation status across the authorization boundary, suitable for dashboard display.

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/authorization_boundaries/1/ksi_validations/summary" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": {
    "authorization_boundary_id": 1,
    "total_validations": 48,
    "by_status": {
      "validated": 35,
      "pending": 8,
      "failed": 3,
      "not_assessed": 2
    },
    "overdue_count": 5,
    "compliance_rate": 72.9,
    "by_theme": [
      {
        "theme": "access_control",
        "total": 8,
        "validated": 6,
        "pending": 1,
        "failed": 1,
        "not_assessed": 0
      },
      {
        "theme": "audit_accountability",
        "total": 6,
        "validated": 5,
        "pending": 1,
        "failed": 0,
        "not_assessed": 0
      }
    ],
    "generated_at": "2026-03-23T12:00:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Summary returned successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Authorization boundary not found |

---

### GET Export Validations

Download all KSI validations for the boundary in JSON, YAML, or XML format.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `format` | string | No | Export format: `json` (default), `yaml`, or `xml` |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/authorization_boundaries/1/ksi_validations/export?format=json" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -o ksi-validations-export.json
```

**Response Body (JSON)**

```json
{
  "data": {
    "authorization_boundary_id": 1,
    "boundary_name": "North America Prod",
    "exported_at": "2026-03-23T12:00:00Z",
    "format": "json",
    "validations": [
      {
        "id": 1,
        "indicator_id": "KSI-AC-01",
        "theme": "access_control",
        "status": "validated",
        "validation_method": "automated",
        "evidence_id": "ev-2026-001",
        "last_validated_at": "2026-03-20T10:00:00Z",
        "next_validation_due": "2026-06-20T10:00:00Z"
      }
    ],
    "summary": {
      "total": 48,
      "validated": 35,
      "pending": 8,
      "failed": 3,
      "not_assessed": 2
    }
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Export generated successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Authorization boundary not found |
| `406` | Unsupported format requested |

---

## Common Errors

| Code | Error | Description |
|------|-------|-------------|
| `401` | `Unauthorized` | Missing or invalid Bearer token |
| `404` | `Not Found` | Authorization boundary or validation does not exist |
| `406` | `Not Acceptable` | Requested export format is not supported |
| `422` | `Unprocessable Entity` | Validation failed -- missing required fields or invalid values |
| `500` | `Internal Server Error` | Unexpected server error -- contact your administrator |
