# Boundary Readiness API

What SPARC knows about an authorization boundary, and what is still missing. A
read-only completeness report for a boundary that is onboarding — sections map
onto the decisions in the wiki's [Adopting OSCAL](https://github.com/risk-sentinel/sparc/wiki/Adopting-OSCAL)
guide, so a gap points at the page that explains how to close it.

Added in #940. The same service backs the **Adoption readiness** card on the
boundary screen, so the endpoint and the screen cannot disagree.

## Base URL

```
https://sparc.example.com/api/v1/authorization_boundaries/:authorization_boundary_id/readiness
```

The boundary may be addressed by numeric id or by slug.

## Authentication

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

Requires read access to the parent boundary
(`authorization_boundaries.read`). Instance admins bypass it.

**Strictly read-only.** It mutates nothing, which is what makes it safe to poll
from a pipeline and to render on every page load.

## GET — the report

```http
GET /api/v1/authorization_boundaries/acme-prod/readiness
```

```json
{
  "data": {
    "boundary": { "id": 1, "uuid": "…", "name": "ACME Prod", "slug": "acme-prod" },
    "sections": [
      {
        "key": "personnel",
        "title": "Personnel and roles",
        "status": "complete",
        "count": 7,
        "detail": "7 on the roster: assessor, authorizing_official, ciso, isso, …",
        "guide_anchor": "1-who-is-on-the-team-and-what-are-their-roles"
      }
    ],
    "summary": { "complete": 4, "partial": 1, "absent": 5, "not_modelled": 0 }
  }
}
```

### Status values

| Status | Meaning |
|---|---|
| `complete` | SPARC holds what it needs |
| `partial` | Present but incomplete — the most actionable state |
| `absent` | Nothing recorded |
| `not_modelled` | **SPARC cannot answer this.** Not a failure of the boundary |

`not_modelled` exists so a report never implies "nothing to do" when the truth is
"nobody can tell". No section returns it today.

### Sections

| `key` | What it reports |
|---|---|
| `personnel` | The roster. `partial` until System Owner, ISSO and AO are all present |
| `classification` | FIPS-199 categorization, derived as the high water mark across the boundary's SP 800-60 information types. `partial` when a level is recorded that no information type justifies, or when the recorded objectives contradict them |
| `profile` | The baseline bound to the boundary |
| `ssp` | The System Security Plan, and how it was created |
| `components` | Components, ports and protocols. `partial` when every component is typed `this-system`, or when none carries ports/protocols |
| `back_matter` | Registered boundary documents — diagrams, inventory, PPSM, CRM |
| `leveraged` | Leveraged authorizations |
| `cdefs` | Bound component definitions |
| `evidence` | Uploaded evidence and how much links to controls |
| `scans` | Ingested HDF scan results |
| `environments` | Environments the boundary runs in, from its sub-boundaries |

`guide_anchor` is the fragment of the Adopting OSCAL wiki page for that section.

## Status codes

| Code | Meaning |
| --- | --- |
| `200` | The report |
| `401` | Missing or invalid token |
| `403` | No read access to the boundary |
| `404` | No such boundary |
