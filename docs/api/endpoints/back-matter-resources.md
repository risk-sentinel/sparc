# Back-Matter Resources API

Manage OSCAL back-matter resources with control-level linking, organization scoping, and global availability. Back-matter resources represent policies, evidence, external references, and other supporting documentation that controls reference via `href="#uuid"` in OSCAL exports.

## Base URL

```
https://sparc.example.com/api/v1/back_matter_resources
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Endpoints

| Method | Path | Description | Permission |
|--------|------|-------------|------------|
| `GET` | `/api/v1/back_matter_resources` | List resources (filterable) | `back_matter.read` |
| `GET` | `/api/v1/back_matter_resources/:id` | Show resource with linked controls | `back_matter.read` |
| `POST` | `/api/v1/back_matter_resources` | Create a new resource | `back_matter.write` |
| `PATCH` | `/api/v1/back_matter_resources/:id` | Update a resource | `back_matter.write` |
| `DELETE` | `/api/v1/back_matter_resources/:id` | Delete a resource | `back_matter.write` |
| `POST` | `/api/v1/back_matter_resources/:id/link` | Link resource to a control | `back_matter.write` |
| `DELETE` | `/api/v1/back_matter_resources/:id/unlink` | Unlink resource from a control | `back_matter.write` |

---

### GET List Resources

Returns a paginated list of back-matter resources with optional filters.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | integer | No | Page number (default: `1`) |
| `items` | integer | No | Items per page (default: `25`) |
| `organization_id` | integer | No | Filter by organization |
| `globally_available` | boolean | No | Filter by global availability (`true`/`false`) |
| `rel` | string | No | Filter by OSCAL relationship type |
| `source` | string | No | Filter by source (`managed`, `imported`, `sparc`, `authoritative`) |
| `document_type` | string | No | Filter by parent document type (e.g., `SspDocument`) |
| `document_id` | integer | No | Filter by parent document ID |
| `control_type` | string | No | Filter by linked control type (e.g., `CdefControl`) |
| `control_id` | integer | No | Filter by linked control ID |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/back_matter_resources?source=managed&rel=reference&page=1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": [
    {
      "id": 1,
      "uuid": "a1b2c3d4-e5f6-4890-abcd-ef1234567890",
      "title": "Access Control Policy v2.1",
      "rel": "reference",
      "media_type": "application/pdf",
      "href": "https://policies.example.com/ac-policy-v2.1.pdf",
      "source": "managed",
      "globally_available": true,
      "organization_id": 1,
      "created_at": "2026-04-14T10:00:00Z",
      "updated_at": "2026-04-14T10:00:00Z"
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

---

### GET Show Resource

Returns a single resource with full details and linked controls.

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/back_matter_resources/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "uuid": "a1b2c3d4-e5f6-4890-abcd-ef1234567890",
    "title": "Access Control Policy v2.1",
    "rel": "reference",
    "media_type": "application/pdf",
    "href": "https://policies.example.com/ac-policy-v2.1.pdf",
    "source": "managed",
    "globally_available": true,
    "organization_id": 1,
    "created_at": "2026-04-14T10:00:00Z",
    "updated_at": "2026-04-14T10:00:00Z",
    "description": "Organization-wide access control policy document",
    "resource_data": {},
    "evidence_id": null,
    "resourceable_type": "SspDocument",
    "resourceable_id": 42,
    "linked_controls": [
      { "type": "SspControl", "id": 15 },
      { "type": "CdefControl", "id": 88 }
    ]
  }
}
```

---

### POST Create Resource

Creates a new back-matter resource with a UUID v4 auto-generated.

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | **Yes** | Resource title |
| `description` | string | No | Resource description |
| `rel` | string | No | OSCAL relationship type (default: `reference`) |
| `media_type` | string | No | IANA media type (e.g., `application/pdf`) |
| `href` | string | No | URL or URI reference |
| `globally_available` | boolean | No | Make available to all organizations (default: `false`) |
| `organization_id` | integer | No | Scope to an organization (auto-set from user if omitted) |
| `resourceable_type` | string | No | Parent document type (e.g., `SspDocument`) |
| `resourceable_id` | integer | No | Parent document ID |
| `source` | string | No | Source type: `managed` (default), `authoritative` (admin only) |

**Valid `rel` values:** `reference`, `depends-on`, `validation`, `proof-of-compliance`, `provided-by`, `used-by`, `uses-service`, `baseline-template`, `diagram`, `predecessor-version`, `successor-version`, `incorporated-into`

**Valid `media_type` values (common):** `application/pdf`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document`, `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`, `text/html`, `text/plain`, `image/png`, `image/jpeg`, `application/oscal+json`, `application/oscal+xml`, `application/oscal+yaml`, `application/json`, `application/xml`, `text/csv`

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/back_matter_resources" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "back_matter_resource": {
      "title": "Access Control Policy v2.1",
      "description": "Organization-wide AC policy",
      "rel": "reference",
      "media_type": "application/pdf",
      "href": "https://policies.example.com/ac-policy-v2.1.pdf",
      "globally_available": true,
      "resourceable_type": "SspDocument",
      "resourceable_id": 42
    }
  }'
```

**Response:** `201 Created` with resource data (same as show)

---

### PATCH Update Resource

**Example Request**

```bash
curl -X PATCH "https://sparc.example.com/api/v1/back_matter_resources/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "back_matter_resource": {
      "title": "Access Control Policy v3.0",
      "href": "https://policies.example.com/ac-policy-v3.0.pdf"
    }
  }'
```

---

### DELETE Delete Resource

Deletes the resource and all control links.

```bash
curl -X DELETE "https://sparc.example.com/api/v1/back_matter_resources/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response:** `200 OK` with `{ "data": { "id": 1, "deleted": true } }`

---

### POST Link Resource to Control

Links an existing resource to a control. Creates an OSCAL `href="#uuid"` reference in the control's export.

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `linkable_type` | string | **Yes** | Control model: `CatalogControl`, `CdefControl`, `ProfileControl`, `SspControl`, `SarControl`, `SapControl` |
| `linkable_id` | integer | **Yes** | Control record ID |

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/back_matter_resources/1/link" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{ "linkable_type": "SspControl", "linkable_id": 15 }'
```

---

### DELETE Unlink Resource from Control

Removes a control link. Does NOT delete the resource.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `link_id` | integer | **Yes** | ID of the ControlBackMatterLink record to remove |

**Example Request**

```bash
curl -X DELETE "https://sparc.example.com/api/v1/back_matter_resources/1/unlink?link_id=42" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

---

## Authoritative Resources

Resources with `source: "authoritative"` are instance-level provider resources. They:

- Can only be created by admin users or service accounts
- Are included in ALL document OSCAL exports automatically
- Cannot be overridden by organization-level resources with the same UUID
- Represent canonical references (corporate policies, baseline configurations, shared STIGs)

---

## Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Insufficient permissions or non-admin creating authoritative resource |
| `404 Not Found` | Resource or linked control not found |
| `422 Unprocessable Entity` | Validation failed (invalid `rel`, missing `title`, duplicate link) |
