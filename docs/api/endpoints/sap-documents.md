# SAP Documents

Security Assessment Plan (SAP) documents define the scope, methodology, and schedule for a security assessment. SAP documents are scoped to an authorization boundary -- non-admin users can only access SAPs within boundaries they are members of. Reading requires the `sap.read` permission; creating, updating, and deleting require `sap.write`.

## Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `GET` | `/api/v1/sap_documents` | List SAP documents (paginated, filterable) | `sap.read` |
| `GET` | `/api/v1/sap_documents/:slug` | Get a single SAP document | `sap.read` |
| `POST` | `/api/v1/sap_documents` | Create a new (empty) SAP document | `sap.write` |
| `POST` | `/api/v1/sap_documents/generate` | **Generate a populated SAP** from an SSP, profile, or boundary | `sap.write` |
| `PUT` | `/api/v1/sap_documents/:slug` | Update a SAP document | `sap.write` |
| `DELETE` | `/api/v1/sap_documents/:slug` | Soft-delete a SAP document | `sap.write` |

---

### POST /api/v1/sap_documents/generate

Builds a SAP **populated with controls** from an existing control basis, rather than the empty shell `POST /api/v1/sap_documents` creates. Added in #844.

Use this when a 3PAO or an automated pipeline needs an assessment plan, or when a boundary needs a fresh plan between assessments — the SAP is not a once-per-authorization artifact.

#### Request Body

All fields are nested under `sap_document`.

| Field | Type | Description |
|---|---|---|
| `authorization_boundary_id` | integer \| string | Boundary id or slug. Its SSP (then its profile) is used as the control basis when no explicit source is given, and the generated SAP is attached to it. |
| `ssp_document_id` | integer | Explicit control basis. Takes precedence over the boundary's own SSP. Scoped: non-admins may only name an SSP within their boundaries. |
| `profile_document_id` | integer | Control basis when there is no SSP. Profiles are shared baselines and are not boundary-scoped. |
| `name` | string | Defaults to `SAP — <boundary or SSP name> — <date>`. |
| `assessment_type` | string | Defaults to `initial`. |
| `assessment_start` / `assessment_end` | date | Optional. |
| `description` | string | Optional. |
| `control_ids` | array | Restrict the plan to these controls. Matching is **case-insensitive but not padding-insensitive** — `ac-2` will not match a control stored as `AC-02`. |
| `assessment_methods` | object | Per-control method overrides, e.g. `{"AC-2": "examine"}`. |

At minimum, supply either a source document or a boundary that has one.

#### Status Codes

| Code | Meaning |
|---|---|
| `201 Created` | SAP generated. |
| `401 Unauthorized` | Missing or invalid token. |
| `403 Forbidden` | Caller lacks `sap.write` on the boundary. |
| `404 Not Found` | Boundary not found, or the named SSP is outside the caller's boundaries. |
| `422 Unprocessable Entity` | No control basis available, or the plan would have covered no controls (nothing is saved). |

Two cases deliberately fail rather than returning an empty plan, because a SAP covering no controls looks like success while being wrong: no source resolves at all, and `control_ids` matching nothing. The generation is transactional, so a rejected request leaves no partial SAP behind.

#### cURL Example

```bash
# Between assessments: a fresh plan for a boundary, using its own SSP
curl -X POST https://sparc.example.org/api/v1/sap_documents/generate \
  -H "Authorization: Bearer $SPARC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"sap_document": {"authorization_boundary_id": 7, "assessment_type": "annual"}}'
```

---

### GET /api/v1/sap_documents

Returns a paginated list of SAP documents. Admin users see all documents; non-admin users see only documents within their assigned authorization boundaries.

#### Path Parameters

None.

#### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `page` | integer | Page number (default: `1`) |
| `items` | integer | Items per page (default: `25`) |
| `status` | string | Filter by document status |
| `name` | string | Case-insensitive partial match on document name |
| `q` | string | Case-insensitive search across name and description (#672) |
| `authorization_boundary_id` | integer | Filter by authorization boundary |

#### Response Body

```json
{
  "data": [
    {
      "id": 5,
      "slug": "acme-cloud-platform-sap-2025",
      "uuid": "e5f6a7b8-c9d0-1234-efab-567890123456",
      "name": "ACME Cloud Platform SAP 2025",
      "status": "completed",
      "lifecycle_status": "active",
      "authorization_boundary_id": 7,
      "created_at": "2025-07-01T09:00:00Z",
      "updated_at": "2025-07-15T14:00:00Z"
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
  "https://sparc.example.com/api/v1/sap_documents?page=1&items=25" | jq .
```

---

### GET /api/v1/sap_documents/:slug

Returns a single SAP document with detailed fields including assessment type, date range, and related document IDs.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier (e.g., `acme-cloud-platform-sap-2025`) |

#### Query Parameters

None.

#### Response Body

```json
{
  "data": {
    "id": 5,
    "slug": "acme-cloud-platform-sap-2025",
    "uuid": "e5f6a7b8-c9d0-1234-efab-567890123456",
    "name": "ACME Cloud Platform SAP 2025",
    "status": "completed",
    "lifecycle_status": "active",
    "authorization_boundary_id": 7,
    "created_at": "2025-07-01T09:00:00Z",
    "updated_at": "2025-07-15T14:00:00Z",
    "description": "Security Assessment Plan for the 2025 annual assessment of the ACME Cloud Platform.",
    "assessment_type": "full",
    "assessment_start": "2025-08-01",
    "assessment_end": "2025-08-31",
    "sap_version": "1.0",
    "controls_count": 370,
    "ssp_document_id": 42,
    "profile_document_id": 12
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document returned successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `sap.read` for this boundary |
| `404 Not Found` | No document matches the given slug |

#### cURL Example

```bash
curl -s \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/sap_documents/acme-cloud-platform-sap-2025" | jq .
```

---

### POST /api/v1/sap_documents

Creates a new SAP document. The caller must have `sap.write` permission for the target authorization boundary.

#### Path Parameters

None.

#### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `sap_document[name]` | string | yes | Document name |
| `sap_document[description]` | string | no | Document description |
| `sap_document[authorization_boundary_id]` | integer | no | Associated authorization boundary |
| `sap_document[ssp_document_id]` | integer | no | Related System Security Plan |
| `sap_document[profile_document_id]` | integer | no | Associated profile/baseline |
| `sap_document[assessment_type]` | string | no | Assessment type (e.g., `full`, `delta`, `annual`) |
| `sap_document[assessment_start]` | date | no | Assessment start date (ISO 8601) |
| `sap_document[assessment_end]` | date | no | Assessment end date (ISO 8601) |
| `sap_document[sap_version]` | string | no | SAP document version |
| `sap_document[lifecycle_status]` | string | no | Lifecycle status (e.g., `active`, `draft`) |

#### Response Body

```json
{
  "data": {
    "id": 6,
    "slug": "acme-cloud-platform-sap-2025",
    "uuid": "f6a7b8c9-d0e1-2345-fabc-678901234567",
    "name": "ACME Cloud Platform SAP 2025",
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
| `403 Forbidden` | Caller lacks `sap.write` for the target boundary |
| `422 Unprocessable Entity` | Validation errors (see `error` and `details` fields) |

#### cURL Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "sap_document": {
      "name": "ACME Cloud Platform SAP 2025",
      "description": "Security Assessment Plan for the 2025 annual assessment of the ACME Cloud Platform.",
      "authorization_boundary_id": 7,
      "ssp_document_id": 42,
      "profile_document_id": 12,
      "assessment_type": "full",
      "assessment_start": "2025-08-01",
      "assessment_end": "2025-08-31",
      "sap_version": "1.0",
      "lifecycle_status": "draft"
    }
  }' \
  "https://sparc.example.com/api/v1/sap_documents" | jq .
```

---

### PUT /api/v1/sap_documents/:slug

Updates an existing SAP document. Only the fields provided in the request body are changed.

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | URL-friendly document identifier |

#### Request Body

Same fields as [POST create](#post-apiv1sap_documents). All fields are optional for update.

#### Response Body

```json
{
  "data": {
    "id": 5,
    "slug": "acme-cloud-platform-sap-2025",
    "uuid": "e5f6a7b8-c9d0-1234-efab-567890123456",
    "name": "ACME Cloud Platform SAP 2025",
    "status": "completed",
    "lifecycle_status": "active",
    "authorization_boundary_id": 7,
    "created_at": "2025-07-01T09:00:00Z",
    "updated_at": "2025-12-10T11:00:00Z"
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document updated successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `sap.write` for this boundary |
| `404 Not Found` | No document matches the given slug |
| `422 Unprocessable Entity` | Validation errors |

#### cURL Example

```bash
curl -s -X PUT \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "sap_document": {
      "lifecycle_status": "active",
      "assessment_end": "2025-09-15"
    }
  }' \
  "https://sparc.example.com/api/v1/sap_documents/acme-cloud-platform-sap-2025" | jq .
```

---

### DELETE /api/v1/sap_documents/:slug

Soft-deletes a SAP document. The record is marked as deleted but retained in the database for audit purposes.

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
    "id": 5,
    "slug": "acme-cloud-platform-sap-2025",
    "deleted": true
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Document soft-deleted successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `sap.write` for this boundary |
| `404 Not Found` | No document matches the given slug |

#### cURL Example

```bash
curl -s -X DELETE \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/sap_documents/acme-cloud-platform-sap-2025" | jq .
```

---

## Common Errors

| Status | Body | Cause |
|--------|------|-------|
| `401 Unauthorized` | `{"error": "Unauthorized"}` | Bearer token is missing, expired, or invalid |
| `403 Forbidden` | `{"error": "Forbidden"}` | Caller lacks required permission for the target boundary |
| `404 Not Found` | `{"error": "Not found"}` | No document exists with the provided slug |
| `422 Unprocessable Entity` | `{"error": "Validation failed: ...", "details": [...]}` | Request body failed model validations |
