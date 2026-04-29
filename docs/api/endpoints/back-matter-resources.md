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
| `GET` | `/api/v1/back_matter_resources/:id/changes` | Show change-log for one resource | `back_matter.read` |
| `GET` | `/api/v1/back_matter_resources/promotion_queue` | List pending promotions caller can approve | Authentication only (self-filtering) |
| `POST` | `/api/v1/back_matter_resources` | Create a new resource | `back_matter.write` |
| `POST` | `/api/v1/back_matter_resources/bulk` | Bulk-import multiple resources in one batch | `back_matter.bulk_import` or `back_matter.write` |
| `PATCH` | `/api/v1/back_matter_resources/:id` | Update a resource | `back_matter.write` |
| `DELETE` | `/api/v1/back_matter_resources/:id` | Delete a resource | `back_matter.write` |
| `POST` | `/api/v1/back_matter_resources/:id/link` | Link resource to a control | `back_matter.write` |
| `DELETE` | `/api/v1/back_matter_resources/:id/unlink` | Unlink resource from a control | `back_matter.write` |
| `POST` | `/api/v1/back_matter_resources/:id/promote` | Request promotion to authoritative | `back_matter.promote` or `back_matter.write` |
| `POST` | `/api/v1/back_matter_resources/:id/approve_promotion` | Approve a pending promotion | `back_matter.approve_promotion` or per-resource approver authority |
| `POST` | `/api/v1/back_matter_resources/:id/reject_promotion` | Reject a pending promotion with reason | `back_matter.approve_promotion` or per-resource approver authority |
| `POST` | `/api/v1/back_matter_resources/:id/archive` | Soft-archive a resource | `back_matter.archive` or `back_matter.write` |
| `POST` | `/api/v1/back_matter_resources/:id/restore` | Restore a previously-archived resource | `back_matter.archive` or `back_matter.write` |

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

### POST Request Promotion to Authoritative

Mark an existing organization-scoped resource as **pending** promotion to instance-wide authoritative status. The actual promotion is approved separately by an authorized approver (see `approve_promotion` below).

Requires `back_matter.promote` permission, or `back_matter.write` (the latter is treated as implicitly including `promote` for backwards compatibility). Admins always have it.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Resource ID |

**Response Body** — same detailed resource shape as `GET /:id`, with the resource's promotion state moved to "pending."

**Status Codes**

| Status | Description |
|--------|-------------|
| `200 OK` | Promotion request recorded |
| `403 Forbidden` | Caller lacks `back_matter.promote` / `back_matter.write` |
| `404 Not Found` | Resource not found |
| `409 Conflict` | Resource is already authoritative or already pending |

**Side effects**

Writes `back_matter_resource_promotion_requested` to `audit_events`.

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/back_matter_resources/42/promote" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

---

### POST Approve Promotion

Approve a pending promotion. Caller must hold `back_matter.approve_promotion` **or** be a configured approver for this specific resource (per-resource approver authority — see `BackMatterResourcePromotionService`).

The endpoint does **not** fall back to `back_matter.write`; promotion approval is a deliberately separate authority from write.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Resource ID |

**Status Codes**

| Status | Description |
|--------|-------------|
| `200 OK` | Promotion approved (resource is now `source: "authoritative"`) |
| `403 Forbidden` | Caller is not authorized to approve this resource |
| `404 Not Found` | Resource not found |
| `409 Conflict` | Resource is not in `pending` state |

**Side effects**

Writes `back_matter_resource_promotion_approved` to `audit_events` with `approver_id`.

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/back_matter_resources/42/approve_promotion" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

---

### POST Reject Promotion

Reject a pending promotion. Same authorization rules as `approve_promotion` (`back_matter.approve_promotion` or per-resource approver authority).

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `reason` | string | No | Free-form rejection reason recorded on the resource. Also accepts `back_matter_resource[rejection_reason]`. |

```json
{ "reason": "Provider has not yet completed annual review." }
```

**Status Codes**

| Status | Description |
|--------|-------------|
| `200 OK` | Rejection recorded |
| `403 Forbidden` | Caller is not authorized |
| `404 Not Found` | Resource not found |
| `409 Conflict` | Resource is not in `pending` state |

**Side effects**

Writes `back_matter_resource_promotion_rejected` to `audit_events` with `approver_id`.

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/back_matter_resources/42/reject_promotion" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"reason": "Awaiting annual review."}'
```

---

### POST Archive Resource

Soft-archive a resource. The row is preserved (`archived_at` timestamp set) but excluded from the default `index` and `BackMatterBuilder` collection paths used by document exporters. Archived resources can be restored without data loss.

Requires `back_matter.archive` permission or `back_matter.write`. Admins always have it.

**Status Codes**

| Status | Description |
|--------|-------------|
| `200 OK` | Resource archived |
| `403 Forbidden` | Caller is not authorized |
| `404 Not Found` | Resource not found |
| `409 Conflict` | Resource is already archived |

**Side effects**

Writes `back_matter_resource_archived` to `audit_events` and records a `BackMatterResourceChange` row capturing the archive transition.

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/back_matter_resources/42/archive" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

---

### POST Restore Resource

Reverse a prior archive. Same authorization as `archive`.

**Status Codes**

| Status | Description |
|--------|-------------|
| `200 OK` | Resource restored |
| `403 Forbidden` | Caller is not authorized |
| `404 Not Found` | Resource not found |
| `409 Conflict` | Resource is not archived |

**Side effects**

Writes `back_matter_resource_restored` to `audit_events` and records a `BackMatterResourceChange` row capturing the restore transition.

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/back_matter_resources/42/restore" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

---

### GET Resource Change-Log

Returns the full `BackMatterResourceChange` log for one resource: every archive/restore, federation update, and bulk-import event that touched it, in reverse-chronological order.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Resource ID |

**Response Body**

```json
{
  "data": [
    {
      "id": 87,
      "change_type": "archive",
      "field": "archived_at",
      "from_value": "",
      "to_value": "2026-04-29T14:00:00Z",
      "batch_uuid": "abc12345-...",
      "changed_at": "2026-04-29T14:00:00Z",
      "changed_by": { "id": 5, "email": "approver@acme.example" }
    }
  ],
  "meta": { "count": 1 }
}
```

**Status Codes**

| Status | Description |
|--------|-------------|
| `200 OK` | Log returned |
| `403 Forbidden` | Caller lacks `back_matter.read` |
| `404 Not Found` | Resource not found |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/back_matter_resources/42/changes" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

---

### POST Bulk Import

Create many resources in a single transaction. Useful for federation re-import, OSCAL import workflows, and admin tooling that produces a list of resources to upsert.

Requires `back_matter.bulk_import` or `back_matter.write`. Resources are scoped to the caller's first organization; admins can override `organization_id` per entry.

**Request Body**

```json
{
  "entries": [
    {
      "title": "AC Policy v3",
      "rel": "reference",
      "href": "https://policies.example.gov/ac-v3.pdf",
      "media_type": "application/pdf"
    },
    {
      "title": "AC-2 Evidence Q2 2026",
      "rel": "evidence",
      "href": "...",
      "media_type": "application/pdf"
    }
  ]
}
```

`back_matter_resources` is also accepted as the top-level key for backwards compatibility.

**Response Body — success**

```json
{
  "data": {
    "batch_uuid": "abc12345-...",
    "imported": [ /* serialized resources */ ],
    "skipped":  [ "duplicate uuid 1234..." ],
    "errors":   [ "row 3: title required" ]
  }
}
```

`imported`, `skipped`, and `errors` are independent — a partial success returns 201 with non-empty `errors` so the caller can react per row.

**Status Codes**

| Status | Description |
|--------|-------------|
| `201 Created` | Batch processed (per-entry results in body) |
| `403 Forbidden` | Caller is not authorized |
| `422 Unprocessable Entity` | Top-level batch validation failure (e.g., `entries` empty) |

**Side effects**

Writes `back_matter_resources_bulk_imported` to `audit_events` with the `batch_uuid` and per-bucket counts. Each successfully imported resource also gets a `BackMatterResourceChange` row tagged with the same `batch_uuid` so the import is undoable as a unit.

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/back_matter_resources/bulk" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  --data-binary @bulk-import.json
```

---

### GET Promotion Queue

Lists every back-matter resource currently in `pending` promotion state that the caller is authorized to approve. The list is **self-filtering** — there is no separate permission gate; authentication alone is sufficient because each row is filtered through `BackMatterResourcePromotionService#can_approve?`. Callers who can't approve anything see an empty list.

**Response Body**

Same shape as `GET /` (paginated style with `data` + `meta.count`), returning detailed resources rather than the summary form.

**Status Codes**

| Status | Description |
|--------|-------------|
| `200 OK` | List returned (possibly empty if caller has no approvable resources) |
| `401 Unauthorized` | Missing or invalid Bearer token |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/back_matter_resources/promotion_queue" \
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
| `409 Conflict` | Promotion / archive / restore state transition not allowed (e.g., archiving an already-archived resource) |
| `422 Unprocessable Entity` | Validation failed (invalid `rel`, missing `title`, duplicate link, malformed bulk batch) |
