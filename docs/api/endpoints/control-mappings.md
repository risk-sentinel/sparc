# Control Mappings API

Manage control mappings between source and target control catalogs. Mappings define relationships between controls in different frameworks or catalog revisions (e.g., NIST 800-53 Rev 4 to Rev 5, or NIST to ISO 27001). Mappings are addressed by numeric id or slug. Write operations (create, update, delete) require an instance admin or the `mappings.write` permission.

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
| List, Show, Export | Any authenticated user |
| Create, Update, Delete | Admin, or `mappings.write` |

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/control_mappings` | List all mappings |
| `GET` | `/api/v1/control_mappings/:id` | Show a single mapping |
| `POST` | `/api/v1/control_mappings` | Create a new mapping (admin) |
| `PUT` | `/api/v1/control_mappings/:id` | Update a mapping (admin) |
| `DELETE` | `/api/v1/control_mappings/:id` | Delete a mapping (admin) |
| `GET` | `/api/v1/control_mappings/:id/export` | Export the mapping as an OSCAL mapping collection (`?format=oscal` or `oscal-yaml`) — see **Export** below |
| `GET` | `/api/v1/control_mappings/:control_mapping_id/entries` | List the mapping's entries; `meta.unresolved` counts those whose identifiers no longer resolve |
| `POST` | `/api/v1/control_mappings/:control_mapping_id/entries` | Add a control-to-control relationship (`mappings.write`) |
| `PATCH`/`PUT` | `/api/v1/control_mappings/:control_mapping_id/entries/:id` | Correct an entry (`mappings.write`) |
| `DELETE` | `/api/v1/control_mappings/:control_mapping_id/entries/:id` | Remove an entry (`mappings.write`) |

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
      "oscal_version": "1.2.1",
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
    "oscal_version": "1.2.1",
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
| `oscal_version` | string | No | OSCAL schema version. The `control_mappings` column defaults to `1.2.1` — the one document type that carries its own default rather than deferring to `OscalSchema::DEFAULT_VERSION` |
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
      "oscal_version": "1.2.1",
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
    "oscal_version": "1.2.1",
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

---

## Export as an OSCAL mapping collection (#1154)

```
GET /api/v1/control_mappings/:id/export[?format=&validate=]
```

The crosswalk as a **document**, not only as rows — the OSCAL `mapping-collection`
built by `OscalMappingExportService`. `:id` is the numeric id or the slug.

Read by **any authenticated caller**, as `show` is; writes stay gated.

| `format` | Returns |
|---|---|
| `oscal` *(default)* | the OSCAL mapping collection, JSON (root key `mapping-collection`) |
| `oscal-yaml` | the same document as YAML (`application/x-yaml`) |

There is no `fields` format — a mapping has no SPARC field-JSON export; read the
rows from `…/entries`.

**`oscal-xml` is not offered, and is refused by name.** SPARC carries no OSCAL
XSD for the mapping model, and so no XSD element order for it either: XML could
be neither written in the order OSCAL requires nor validated. Rather than serve
a file that only looks like OSCAL, the request is refused:

```json
{
  "error": "Unknown export format \"oscal-xml\"",
  "expected": ["oscal", "oscal-yaml"],
  "reason": "oscal-xml is not offered for mapping collections: SPARC carries no OSCAL XSD for the mapping model, so XML could be neither ordered nor validated. Use oscal (JSON) or oscal-yaml."
}
```

`validate` defaults to **true**: the collection is checked against the NIST
mapping schema and a non-conforming one is refused. A mapping with **no
entries** does not conform — OSCAL requires at least one map — so an empty
mapping is refused by the default path; `validate=false` returns it anyway.

```json
{
  "error": "The mapping collection does not conform to the OSCAL schema",
  "details": ["... up to ten lines ..."],
  "hint": "Re-request with validate=false to export it anyway"
}
```

Each delivered export is audited as `control_mapping_exported`.

### Provenance

Provenance is **collection-level**, in `mapping-collection.provenance`:

| field | from |
|---|---|
| `method` | `method_type` — `human`, `automation`, `hybrid` |
| `matching-rationale` | `matching_rationale` — `syntactic`, `semantic`, `functional` |
| `status` | `status` |
| `mapping-description` | `description`, or a generated "Control mapping between … and …" |

Per entry, each `maps[]` item carries its `relationship` and, where recorded,
its own `matching-rationale` and `remarks`. There is **no confidence score** —
none is recorded, and none is invented (follow-up #1196).

For the **FedRAMP 20x KSI → NIST SP 800-53 Rev 5** crosswalk, the source is
recorded in the mapping's description — *"FedRAMP's own crosswalk … from the
controls[] of FedRAMP/rules &lt;upstream version&gt;. FedRAMP authors it; SPARC
does not."* — and so reaches `mapping-description`; `mapping_version` (and so
`metadata.version`) is the same upstream version. The upstream **commit** is
recorded on the KSI *catalog*, not on the mapping, and does not appear in the
mapping document.

### Conditional GET (ETag / 304)

Every response carries a **strong** `ETag`; send it back as `If-None-Match` and
an unchanged export answers **`304 Not Modified`** with an empty body. The ETag
digests the mapping id, its `updated_at`, the `format`, `validate`, the
instance's default OSCAL version **and the exported bytes**, so a changed entry
yields a new ETag even if it bypassed the parent's `updated_at`. A `304` is not
audited.

### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Export returned |
| `304 Not Modified` | `If-None-Match` matched the current ETag |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `404 Not Found` | No mapping matches the id or slug |
| `422 Unprocessable Content` | Unknown or unoffered `format`, or the collection does not conform (`validate=true`) |

### cURL Example

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sparc.example.com/api/v1/control_mappings/<slug>/export" | jq '."mapping-collection".provenance'
```

---

## Mapping entries (#945)

The mapping SHELL had a full API; its entries had none, so the only way to add
or remove a control-to-control relationship was the web form — and that form has
no update, so an entry could be created and deleted but never corrected.

```
GET    /api/v1/control_mappings/:control_mapping_id/entries
POST   /api/v1/control_mappings/:control_mapping_id/entries
PATCH  /api/v1/control_mappings/:control_mapping_id/entries/:id
DELETE /api/v1/control_mappings/:control_mapping_id/entries/:id
```

Writes require `mappings.write` (admins bypass). **Authorization is checked
before the mapping is looked up**, so a caller without permission gets `403`
rather than a `404` that would reveal whether the mapping exists.

### Entry fields

| Field | Notes |
|---|---|
| `source_control_id` / `target_control_id` | validated on the model against the mapping's own source and target catalogs |
| `source_type` / `target_type` | the vocabulary each identifier belongs to |
| `relationship` | how the two controls relate |
| `matching_rationale` | why the relationship was drawn |
| `remarks` | free text |
| `row_order` | ordering within the mapping |

Unrecognized fields are refused with `422` rather than dropped.

### Reading entries

The list carries `meta.unresolved` — the number of entries whose identifiers no
longer resolve against the catalogs. Each entry also reports `resolved`
individually. SPARC does **not** rewrite an identifier someone recorded; it
reports that it no longer resolves, so an integrator can find entries stored
before the identifiers were validated and correct them deliberately.
