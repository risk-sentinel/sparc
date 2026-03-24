# FedRAMP 20x KSI Catalog API

Read-only access to the FedRAMP 20x Key Security Indicators (KSI) catalog. KSIs define 11 security themes with measurable indicators that map to NIST SP 800-53 controls. Use these endpoints to browse themes, query indicators by impact level, and retrieve KSI-to-NIST control mappings.

## Base URL

```
https://sparc.example.com/api/v1/ksi_catalog
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

All endpoints are read-only. Any authenticated user can access the KSI catalog.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/ksi_catalog/themes` | List all KSI themes |
| `GET` | `/api/v1/ksi_catalog/indicators` | List indicators (paginated) |
| `GET` | `/api/v1/ksi_catalog/indicators/:id` | Show a single indicator |
| `GET` | `/api/v1/ksi_catalog/mappings` | List KSI-to-NIST mappings |

---

### GET List All KSI Themes

Returns all 11 KSI security themes.

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/ksi_catalog/themes" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": [
    {
      "id": 1,
      "key": "access_control",
      "name": "Access Control",
      "description": "Policies and mechanisms that restrict system access to authorized users",
      "indicators_count": 8
    },
    {
      "id": 2,
      "key": "awareness_training",
      "name": "Awareness and Training",
      "description": "Security awareness programs and role-based training requirements",
      "indicators_count": 4
    },
    {
      "id": 3,
      "key": "audit_accountability",
      "name": "Audit and Accountability",
      "description": "Audit logging, monitoring, and accountability mechanisms",
      "indicators_count": 6
    }
  ]
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Themes returned successfully |
| `401` | Unauthorized -- missing or invalid token |

---

### GET List Indicators (Paginated)

Returns a paginated list of KSI indicators with optional filtering by theme and impact level.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | integer | No | Page number (default: `1`) |
| `items` | integer | No | Items per page (default: `25`) |
| `theme` | string | No | Filter by theme key (e.g., `access_control`, `audit_accountability`) |
| `impact_level` | string | No | Filter by impact level: `low`, `moderate`, `high` |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/ksi_catalog/indicators?theme=access_control&impact_level=high&page=1&items=25" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": [
    {
      "id": 1,
      "indicator_id": "KSI-AC-01",
      "theme": "access_control",
      "name": "Multi-Factor Authentication",
      "description": "All privileged and non-privileged users authenticate with phishing-resistant MFA",
      "impact_level": "high",
      "assessment_method": "automated",
      "mapped_controls_count": 5
    },
    {
      "id": 2,
      "indicator_id": "KSI-AC-02",
      "theme": "access_control",
      "name": "Least Privilege Enforcement",
      "description": "System enforces least privilege access for all user accounts and processes",
      "impact_level": "high",
      "assessment_method": "hybrid",
      "mapped_controls_count": 3
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

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Indicators returned successfully |
| `401` | Unauthorized -- missing or invalid token |

---

### GET Show a Single Indicator

Returns a single KSI indicator with its full details and mapped NIST 800-53 controls.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Numeric indicator ID |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/ksi_catalog/indicators/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "indicator_id": "KSI-AC-01",
    "theme": "access_control",
    "name": "Multi-Factor Authentication",
    "description": "All privileged and non-privileged users authenticate with phishing-resistant MFA",
    "impact_level": "high",
    "assessment_method": "automated",
    "validation_guidance": "Verify MFA configuration for all user accounts. Check authentication logs for MFA bypass attempts.",
    "mapped_controls": [
      {
        "control_id": "ia-2",
        "title": "Identification and Authentication (Organizational Users)",
        "catalog_name": "NIST SP 800-53 Rev 5"
      },
      {
        "control_id": "ia-2.1",
        "title": "Multi-Factor Authentication to Privileged Accounts",
        "catalog_name": "NIST SP 800-53 Rev 5"
      },
      {
        "control_id": "ia-2.2",
        "title": "Multi-Factor Authentication to Non-Privileged Accounts",
        "catalog_name": "NIST SP 800-53 Rev 5"
      },
      {
        "control_id": "ia-2.6",
        "title": "Access to Accounts -- Separate Device",
        "catalog_name": "NIST SP 800-53 Rev 5"
      },
      {
        "control_id": "ia-2.8",
        "title": "Access to Accounts -- Replay Resistant",
        "catalog_name": "NIST SP 800-53 Rev 5"
      }
    ]
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Indicator returned successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Indicator not found |

---

### GET List KSI-to-NIST Mappings

Returns a paginated list of KSI-to-NIST control mapping entries.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | integer | No | Page number (default: `1`) |
| `items` | integer | No | Items per page (default: `25`) |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/ksi_catalog/mappings?page=1&items=25" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": [
    {
      "id": 1,
      "indicator_id": "KSI-AC-01",
      "indicator_name": "Multi-Factor Authentication",
      "theme": "access_control",
      "control_id": "ia-2",
      "control_title": "Identification and Authentication (Organizational Users)",
      "relationship": "primary"
    },
    {
      "id": 2,
      "indicator_id": "KSI-AC-01",
      "indicator_name": "Multi-Factor Authentication",
      "theme": "access_control",
      "control_id": "ia-2.1",
      "control_title": "Multi-Factor Authentication to Privileged Accounts",
      "relationship": "supporting"
    }
  ],
  "meta": {
    "page": 1,
    "pages": 5,
    "count": 112,
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

## Common Errors

| Code | Error | Description |
|------|-------|-------------|
| `401` | `Unauthorized` | Missing or invalid Bearer token |
| `404` | `Not Found` | Indicator does not exist |
| `500` | `Internal Server Error` | Unexpected server error -- contact your administrator |
