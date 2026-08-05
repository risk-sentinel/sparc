# Control Lookup API

Cross-catalog control search and identifier resolution.

Added in #902 (follow-up). Every other control endpoint is **catalog-scoped** —
`/api/v1/control_catalogs/:id/controls` — which is right for browsing a catalog
but cannot answer the question a caller that belongs to no catalog needs to ask:
*does this identifier name a real control, and what are my options?*

That question matters because control identifiers have three legitimate forms
(#852), and SPARC **displays** one while catalogs **store** another:

| Form | Example | Where it appears |
|---|---|---|
| canonical | `ac-2.1` | stored in catalogs; written into OSCAL |
| padded | `AC-02.01` | SPARC's display and sort convention |
| human | `AC-2 (1)` | how NIST SP 800-53 writes it |

Evidence control links used to be free text, so a user copying the padded id off
the screen produced a link that matched nothing — silently. This endpoint backs
a picker that can only emit identifiers that exist, and gives any client a way to
validate one before submitting it.

## Base URL

```
https://sparc.example.com/api/v1/controls
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

Read-only over catalog content, which is global reference data rather than
boundary-scoped — knowing that `AC-2` exists discloses nothing about any system.
Any authenticated principal may call it.

> The web UI does **not** call this endpoint. `Api::V1` is Bearer-only and
> excludes cookie/CSRF middleware, so the browser cannot reach it; the evidence
> control picker calls the session-authenticated `GET /controls/lookup` instead.
> Both run the same `ControlLookupService`, so the identifiers offered and the
> identifiers accepted cannot drift apart.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/controls` | Search controls across all loaded catalogs |
| `GET` | `/api/v1/controls/resolve` | Resolve a single identifier in any form |

---

### GET Search Controls

```
GET /api/v1/controls
```

**Query parameters**

| Parameter | Description |
|---|---|
| `q` | Matches the identifier (in any form) or the title |
| `family` | Restrict to a family code, e.g. `AC` |
| `authorization_boundary_id` | Prefer that boundary's baseline — see below |
| `limit` | Results to return (default 25, max 100) |

**Response** `200 OK`

```json
{
  "data": [
    {
      "control_id": "ac-2.1",
      "display_id": "AC-2(1)",
      "padded_id": "AC-02.01",
      "title": "Automated System Account Management",
      "family_code": "AC",
      "family_name": "Access Control",
      "catalog_id": 2,
      "enhancement": true
    }
  ],
  "meta": {
    "total": 1,
    "limit": 25,
    "scoped_to_profile": false,
    "profile_title": null
  }
}
```

`control_id` is the value to store and to submit elsewhere. `padded_id` and
`display_id` are provided so a client never has to re-derive them — re-deriving
identifier forms by hand is what #852 existed to stop.

`enhancement` is `true` when the control is a sub-part (`ac-2.1`). An
enhancement is a control in its own right: linking to `ac-2.1` is a different
claim from linking to `ac-2`.

#### Baseline scoping

When `authorization_boundary_id` names a boundary that carries a baseline
(a profile, #395 — one per system), results are narrowed to that baseline's
controls and `meta.scoped_to_profile` is `true`. A client should say so rather
than implying it searched everything.

When the boundary has no baseline — the common case today, not an edge case —
the search falls back to every loaded catalog and `scoped_to_profile` is `false`.

---

### GET Resolve Identifier

```
GET /api/v1/controls/resolve?id=AC-02
```

Answers the single question a validating client needs. Accepts any of the three
forms.

**Response** `200 OK`

```json
{
  "data": {
    "control_id": "ac-2",
    "display_id": "AC-2",
    "padded_id": "AC-02",
    "title": "Account Management",
    "family_code": "AC",
    "enhancement": false,
    "resolved": true,
    "submitted": "AC-02"
  }
}
```

**Response** `404 Not Found` — the identifier names no control in any loaded
catalog. `canonical` shows what it was normalised to before the lookup, which is
usually enough to see why it failed.

```json
{
  "error": "Unknown control identifier",
  "details": ["AC-999 does not match any control in a loaded catalog"],
  "data": { "resolved": false, "submitted": "AC-999", "canonical": "ac-999" }
}
```

---

## Scope

This endpoint is **read-only discovery**. It tells a caller which controls exist
and what their canonical identifiers are; it does not enforce anything.

Validating identifiers *stored* by other records — evidence, profiles, converter
output, control mappings — is deliberately out of scope here. Catalogs are the
source of truth every document type depends on, so that rule needs designing
once, across every entry point, and has to account for Rev 4 ↔ Rev 5 translation
(`ControlIdNormalizer`). That work is
[#911](https://github.com/risk-sentinel/sparc/issues/911).

## Related

- [Evidence](evidences.md) — the evidence control picker is the first consumer
- [Catalog Controls](catalog-controls.md) — managing controls within a catalog
- [Control Families](control-families.md)
