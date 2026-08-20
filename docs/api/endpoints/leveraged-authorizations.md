# Leveraged Authorizations API

A leveraged authorization records the ATO a system inherits from. OSCAL exports
one `leveraged-authorization` entry per record on every SSP for the leveraging
boundary, so these are not annotations — they are part of the authorization
package.

Added in [#1015](https://github.com/risk-sentinel/sparc/issues/1015); the
records themselves date from #396. Before this they could be created, populated
and deleted only from a browser. The gap was found by the missing-endpoint axis
of [#995](https://github.com/risk-sentinel/sparc/issues/995).

## Base URL

```
https://sparc.example.com/api/v1/authorization_boundaries/:authorization_boundary_id/leveraged_authorizations
```

The boundary may be addressed by **slug** (what the web URLs use) or by numeric
id, so a caller holding an id from a list response need not fetch the slug.

## Authentication

All endpoints require a valid Bearer token.

## Authorization — membership, not a permission key

Access requires **membership of the leveraging boundary**, or instance admin.
It is deliberately *not* `authorization_boundaries.write`.

This mirrors the web controller exactly. The #919 authorization sweep recorded
this as the one place membership and permission still disagree, and narrowing
the API to a permission key would both make a product decision silently and
leave the two surfaces enforcing different rules. Change both together or
neither.

## The three scenarios

`crm_type` selects how the leveraged system's controls reach SPARC, per the
NIST OSCAL Implementation Layers model:

| `crm_type` | `scenario` | Meaning |
|---|---|---|
| `oscal_with_access` | 1 | The leveraged SSP is in SPARC and readable — inheritance links can be imported directly |
| `oscal_no_access` | 2 | The leveraged SSP is OSCAL but access-restricted — an OSCAL CRM/SSRM back-matter is uploaded instead |
| `legacy` | 3 | The leveraged SSP is not OSCAL — a legacy CRM back-matter is uploaded |

Only scenario 1 can populate inheritance links, because it is the only one where
SPARC holds the leveraged SSP.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `…/leveraged_authorizations` | List the boundary's leveraged authorizations (paginated) |
| `POST` | `…/leveraged_authorizations` | Create one; scenario 1 also imports inheritance links |
| `GET` | `…/leveraged_authorizations/:id` | Show one, with link and back-matter counts |
| `POST` | `…/leveraged_authorizations/:id/populate` | Re-import inheritance links from the leveraged SSP |
| `DELETE` | `…/leveraged_authorizations/:id` | Remove the record |

### POST …/leveraged_authorizations

#### Request Body

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Name of the leveraged system |
| `crm_type` | string | yes | One of the three values above |
| `date_authorized` | date | yes | When the leveraged system was authorized |
| `leveraged_boundary_id` | integer | scenario 1 | The boundary being leveraged |
| `description` | string | no | Free text |

**`date_authorized` is required** (#988). Leveraging means relying on someone
else's authorization, so a record without one is a claim to inherit an
authorization that does not exist — and OSCAL requires `date-authorized` on
every entry, so a single dateless row made every SSP on the boundary fail
export validation.

Any field not listed is **refused** with `422`, not discarded.

#### Response Body

```json
{
  "data": {
    "id": 12,
    "uuid": "6b1f9c84-3a6e-4d1a-9f0b-6b2f0c7e8a11",
    "name": "Leveraged PaaS",
    "crm_type": "oscal_with_access",
    "scenario": 1,
    "leveraging_boundary_id": 4,
    "leveraged_boundary_id": 9,
    "date_authorized": "2026-02-01",
    "description": "Inherited controls from the platform ATO",
    "inheritance_link_count": 37,
    "back_matter_resource_count": 0,
    "inheritance_links_populated": 37,
    "created_at": "2026-08-20T14:22:18Z",
    "updated_at": "2026-08-20T14:22:18Z"
  }
}
```

`inheritance_links_populated` appears on `create` and `populate` only, and is
`null` for scenarios 2 and 3.

#### Status Codes

| Status | Description |
|---|---|
| `201 Created` | Record created |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller is not a member of the leveraging boundary |
| `404 Not Found` | No such boundary, or the record belongs to another boundary |
| `422 Unprocessable Entity` | Validation failed, or the body carried a field this endpoint does not accept |

### POST …/leveraged_authorizations/:id/populate

Idempotent re-import of inheritance links from the leveraged SSP, for when the
leveraged system's prose has moved on. Returns the record with
`inheritance_links_populated` set to the number imported.

## Audit

| Action | When |
|---|---|
| `leveraged_authorization_created` | Record created; metadata carries `crm_type` and how many links were populated |
| `leveraged_authorization_populated` | Links re-imported; metadata carries the count |
| `leveraged_authorization_deleted` | Record removed |

## NIST 800-53 Controls

- **CA-3** System Interconnections · **CA-9** Internal System Connections
- **AC-3** Access Enforcement — boundary membership enforced on every action
- **AU-12** Audit Record Generation
