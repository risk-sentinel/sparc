# Baseline Parameters API

Manage baseline parameter values and selections for a profile document. Parameters define configurable thresholds, timeframes, and selections within NIST 800-53 controls (e.g., session lock timeout, audit retention period). All endpoints are nested under a specific profile document.

## Base URL

```
https://sparc.example.com/api/v1/profile_documents/:profile_document_id/parameters
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `.../parameters` | Show parameter schema |
| `PUT` | `.../parameters` | Bulk update parameters |
| `GET` | `.../parameters/export` | Export parameters |
| `POST` | `.../parameters/import/preview` | Dry-run an ODP import file (diff, no writes) |
| `POST` | `.../parameters/import/confirm` | Apply an ODP import file |

---

### GET Show Parameter Schema

Returns the full parameter schema for the profile, including all assignable parameters and selectable options organized by control family.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `family` | string | No | Filter parameters by control family (e.g., `ac`, `au`, `si`) |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/profile_documents/fedramp-high-baseline/parameters?family=ac" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": {
    "profile_document_id": "fedramp-high-baseline",
    "profile_name": "FedRAMP High Baseline",
    "parameters": [
      {
        "param_id": "ac-2_prm_1",
        "family": "ac",
        "control_id": "ac-2",
        "label": "organization-defined frequency",
        "value": "annually",
        "guideline": "At least annually or when a significant change occurs"
      },
      {
        "param_id": "ac-2_prm_2",
        "family": "ac",
        "control_id": "ac-2",
        "label": "organization-defined time period",
        "value": "90 days",
        "guideline": "No more than 90 days of inactivity"
      }
    ],
    "selections": [
      {
        "select_id": "ac-2_sel_1",
        "family": "ac",
        "control_id": "ac-2",
        "label": "Account management actions",
        "options": ["notify", "disable", "remove"],
        "selected": ["notify", "disable"]
      }
    ]
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Parameter schema returned successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Profile document not found |

---

### PUT Bulk Update Parameters

Update parameter values and selections in bulk. Only the parameters and selections included in the request body are modified; others remain unchanged.

**Request Body**

```json
{
  "parameters": [
    {
      "param_id": "ac-2_prm_1",
      "value": "quarterly"
    },
    {
      "param_id": "ac-2_prm_2",
      "value": "60 days"
    }
  ],
  "selections": [
    {
      "select_id": "ac-2_sel_1",
      "selected": ["notify", "disable", "remove"]
    }
  ]
}
```

**Example Request**

```bash
curl -X PUT "https://sparc.example.com/api/v1/profile_documents/fedramp-high-baseline/parameters" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "parameters": [
      { "param_id": "ac-2_prm_1", "value": "quarterly" },
      { "param_id": "ac-2_prm_2", "value": "60 days" }
    ],
    "selections": [
      { "select_id": "ac-2_sel_1", "selected": ["notify", "disable", "remove"] }
    ]
  }'
```

**Response Body**

```json
{
  "data": {
    "profile_document_id": "fedramp-high-baseline",
    "updated_parameters": 2,
    "updated_selections": 1,
    "parameters": [
      {
        "param_id": "ac-2_prm_1",
        "value": "quarterly"
      },
      {
        "param_id": "ac-2_prm_2",
        "value": "60 days"
      }
    ],
    "selections": [
      {
        "select_id": "ac-2_sel_1",
        "selected": ["notify", "disable", "remove"]
      }
    ]
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Parameters updated successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Profile document not found |
| `422` | Validation error -- invalid param_id or select_id |

---

### GET Export Parameters

Download the resolved parameter schema in JSON, YAML, or XML format.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `format` | string | No | Export format: `json` (default), `yaml`, or `xml` |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/profile_documents/fedramp-high-baseline/parameters/export?format=json" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -o parameters-export.json
```

**Response Body (JSON)**

```json
{
  "data": {
    "profile_document_id": "fedramp-high-baseline",
    "profile_name": "FedRAMP High Baseline",
    "exported_at": "2026-03-23T12:00:00Z",
    "format": "json",
    "parameters": [
      {
        "param_id": "ac-2_prm_1",
        "family": "ac",
        "control_id": "ac-2",
        "label": "organization-defined frequency",
        "value": "annually"
      }
    ],
    "selections": [
      {
        "select_id": "ac-2_sel_1",
        "family": "ac",
        "control_id": "ac-2",
        "label": "Account management actions",
        "selected": ["notify", "disable"]
      }
    ]
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Export generated successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Profile document not found |
| `406` | Unsupported format requested |

---

### POST Import ODP File — Preview

**Issue #697.** Controller action `baseline_parameters#import_preview`. Upload an Organization-Defined Parameter (OSCAL `set-parameter`) file and receive a **non-destructive diff** — what would change, unchanged rows, unknown ids, and selection values that aren't an allowed choice. **No writes.** This is the authoritative Catalog/Baseline/Profile ODP layer; downstream documents (CDEF/SSP/SAP/SAR) inherit these values from the upstream profile.

**Request** — `multipart/form-data`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `file` | file | Yes | ODP file in **JSON**, **YAML/YML**, or **XML** (round-trips `.../parameters/export`). 5 MB max. |
| `format` | string | No | Override the format inferred from the filename extension. |

Canonical file shape (JSON):

```json
{
  "parameters": [
    { "param_id": "ac-1_prm_1", "value": "ISSO and System Administrators" },
    { "param_id": "ac-1_prm_2", "value": "quarterly" }
  ],
  "selections": [
    { "select_id": "ac-2_prm_1", "selected": ["removes", "disables"] }
  ]
}
```

A flat `{ "param_id": "value" }` map is also accepted. A ready-to-edit template is at `spec/fixtures/files/odp/sample_odp.{json,yaml,xml}`.

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/profile_documents/fedramp-high-baseline/parameters/import/preview" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -F "file=@sample_odp.json;type=application/json"
```

**Response Body**

```json
{
  "data": {
    "profile_id": 42,
    "profile_slug": "fedramp-high-baseline",
    "stats": { "total": 3, "changes": 3, "unchanged": 0, "unknown": 0, "invalid": 0 },
    "rows": [
      { "param_id": "ac-1_prm_1", "control_id": "ac-1", "kind": "parameter",
        "current_value": "", "new_value": "ISSO and System Administrators", "status": "change" }
    ]
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Diff computed |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Profile document not found |
| `422` | No file provided, unsupported format, or unparseable file |

---

### POST Import ODP File — Confirm

Controller action `baseline_parameters#import_confirm`. Apply the same file **atomically** with partial-success reporting: unknown parameter ids are skipped (reported in `validation_errors`) and selection values outside the allowed choices are dropped (never persisted). Audited (`odp_file_import`). Same request shape as preview.

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/profile_documents/fedramp-high-baseline/parameters/import/confirm" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -F "file=@sample_odp.yaml;type=application/x-yaml"
```

**Response Body**

```json
{
  "data": {
    "status": "updated",
    "baseline_id": "fedramp-high-baseline",
    "parameters_updated": 2,
    "selections_updated": 1,
    "validation_errors": []
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Applied (fully or partially) |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Profile document not found |
| `422` | Nothing could be applied (e.g. every id unknown), or unparseable file |

---

## Common Errors

| Code | Error | Description |
|------|-------|-------------|
| `401` | `Unauthorized` | Missing or invalid Bearer token |
| `404` | `Not Found` | Profile document does not exist or is not accessible |
| `406` | `Not Acceptable` | Requested export format is not supported |
| `422` | `Unprocessable Entity` | Invalid parameter or selection IDs in request body |
| `500` | `Internal Server Error` | Unexpected server error -- contact your administrator |
