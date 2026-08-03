# Control Families API

Manage the families within a control catalog — the `AC`, `AU`, `CM` groupings that controls belong to. All endpoints are nested under a catalog.

Added in #895. Before that the catalog container had a full API while its contents had none: you could create a catalog over the API but not put a single family in it.

## Base URL

```
https://sparc.example.com/api/v1/control_catalogs/:control_catalog_id/control_families
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

Reads require an authenticated caller. Every mutation requires the `catalogs.write` permission; instance admins bypass. All mutations are audited (`api_control_family_created` / `_updated` / `_deleted`).

## Identifying a catalog

The catalog may be addressed three ways:

| Form | Example | Notes |
|---|---|---|
| **OSCAL uuid** | `5ba2a3ba-1aa2-47d8-ad69-5beef7372b98` | **Preferred.** Stable — it pins the source document and does not change when the catalog is renamed |
| slug | `nist-800-53-rev-5` | Derived from the catalog name and **regenerated if the name changes**, so it is not a durable reference |
| numeric id | `12` | Internal; accepted for backwards compatibility |

`show` returns the uuid in the `control_catalog` block. Prefer it when storing a reference.

## Identifying a family

A family is addressed by its **code**, case-insensitively, scoped to the catalog:

```
GET /api/v1/control_catalogs/<uuid>/control_families/ac
```

Codes are unique per catalog, so a bare code is meaningless without the catalog. A code belonging to a *different* catalog returns `404` rather than resolving.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `…/control_families` | List the catalog's families |
| `GET` | `…/control_families/:code` | Show a single family |
| `POST` | `…/control_families` | Create a family |
| `PATCH`/`PUT` | `…/control_families/:code` | Update a family |
| `DELETE` | `…/control_families/:code` | Delete a family (must be empty) |

---

### GET List Families

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | integer | No | Page number (default: `1`) |
| `items` | integer | No | Items per page (default: `25`) |
| `code` | string | No | Filter by code, case-insensitive |

```bash
curl -X GET "https://sparc.example.com/api/v1/control_catalogs/5ba2a3ba-1aa2-47d8-ad69-5beef7372b98/control_families" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response** `200 OK`

```json
{
  "data": [
    {
      "id": 7,
      "code": "AC",
      "name": "Access Control",
      "description": "Policies and procedures for account and access management.",
      "sort_order": 1,
      "control_catalog_id": 3,
      "controls_count": 142,
      "created_at": "2026-08-03T12:00:00Z",
      "updated_at": "2026-08-03T12:00:00Z"
    }
  ],
  "meta": { "page": 1, "items": 25, "count": 20, "pages": 1 }
}
```

---

### POST Create a Family

**Body Parameters** — these are the *only* accepted fields. Anything else in the payload is ignored.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `code` | string | **Yes** | Family code, e.g. `AC`. Unique within the catalog |
| `name` | string | **Yes** | Human-readable family name |
| `description` | string | No | Free text |
| `sort_order` | integer | No | Display ordering within the catalog |

```bash
curl -X POST "https://sparc.example.com/api/v1/control_catalogs/<uuid>/control_families" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"control_family": {"code": "AU", "name": "Audit and Accountability", "sort_order": 2}}'
```

**Response** `201 Created`

**Errors**

| Status | Cause |
|--------|-------|
| `401` | Missing or invalid Bearer token |
| `403` | Caller lacks `catalogs.write` |
| `404` | Catalog not found |
| `422` | Missing `code`/`name`, malformed code, or a duplicate code in this catalog |

---

### DELETE a Family

```bash
curl -X DELETE "https://sparc.example.com/api/v1/control_catalogs/<uuid>/control_families/ac" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response** `200 OK`

```json
{ "data": { "code": "AC", "deleted": true } }
```

> **A family holding controls will not be deleted.** Deleting it would take its controls with it, and catalog controls are referenced by SSP, SAP and SAR content — so removing a family could silently invalidate delivered package content. Delete the controls first.

**Response when the family is not empty** — `422 Unprocessable Content`

```json
{ "error": "Family AC still has 142 control(s). Delete them first." }
```
