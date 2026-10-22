# Boundary Back-Matter API

An authorization boundary's **own** back-matter: the documents that describe the
system rather than one of its documents — boundary and data-flow diagrams, the
hardware/software inventory, the PPSM, a CRM. Added in v1.17.2 (#1249).

This is the API side of the **Back Matter** section on the boundary page. The
**Back-matter documents** row of Boundary Completeness
([Boundary Readiness](boundary-readiness.md)) counts these resources, and the
SSP's OSCAL `back-matter` carries them on export.

For back-matter that belongs to a document (an SSP, CDEF, profile, ...), use
[Back-Matter Resources](back-matter-resources.md).

## Base URL

```
https://sparc.example.com/api/v1/authorization_boundaries/:authorization_boundary_id/back_matter_resources
```

The boundary may be addressed by numeric id or by slug.

## Authentication

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

Each check is made against the boundary in the path. Instance administrators
bypass them.

| Action | Requires |
|---|---|
| List | `authorization_boundaries.read` **and** `back_matter.read` on the boundary, or instance-wide |
| Create, update, delete | `back_matter.write` on the boundary, or instance-wide |

Editable in **any** boundary status (draft, active, authorized, deauthorized).

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `…/back_matter_resources` | List the boundary's own back-matter (paginated, 50 per page) |
| `POST` | `…/back_matter_resources` | Register a resource on the boundary |
| `PATCH` | `…/back_matter_resources/:id` | Update one of the boundary's resources |
| `DELETE` | `…/back_matter_resources/:id` | Delete one of the boundary's resources |

A resource id that belongs to anything other than this boundary answers `404`.

## Request body (create and update)

| Field | Type | Description |
|---|---|---|
| `title` | string | **Required** on create |
| `description` | string | Free text |
| `href` | string | Where the document lives. A scheme, if present, must be `http` or `https` |
| `media_type` | string | IANA media type, e.g. `application/pdf` |
| `rel` | string | OSCAL link relationship, e.g. `diagram`, `reference` |
| `globally_available` | boolean | Offer the resource beyond this boundary |

The owner is always the boundary in the path. `resourceable_type`,
`resourceable_id`, `source` and any other field are refused with `422`, naming
the fields that are accepted. New resources are `source: "managed"` with a
generated UUID.

```http
POST /api/v1/authorization_boundaries/acme-prod/back_matter_resources
Content-Type: application/json

{
  "back_matter_resource": {
    "title": "System boundary diagram",
    "href": "https://example.gov/docs/boundary-diagram.pdf",
    "media_type": "application/pdf",
    "rel": "diagram"
  }
}
```

```json
{
  "data": {
    "id": 412,
    "uuid": "6d1c4f0e-1f7b-4f43-9a51-4f1b7c2f8a10",
    "title": "System boundary diagram",
    "rel": "diagram",
    "media_type": "application/pdf",
    "href": "https://example.gov/docs/boundary-diagram.pdf",
    "source": "managed",
    "globally_available": false,
    "organization_id": 3,
    "created_at": "2026-10-22T14:03:11Z",
    "updated_at": "2026-10-22T14:03:11Z",
    "resourceable_type": "AuthorizationBoundary",
    "resourceable_id": 7
  }
}
```

The response uses the detailed back-matter shape of
[Back-Matter Resources](back-matter-resources.md) (the example above is
abridged).

## Response Codes

| Code | Description |
|---|---|
| `200` | Listed, updated or deleted |
| `201` | Created |
| `401` | Missing or invalid token |
| `403` | The caller lacks the permission on this boundary |
| `404` | No such boundary, or the resource is not this boundary's |
| `422` | Validation failed, or an unrecognised field was sent |
