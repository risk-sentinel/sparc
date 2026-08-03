# Catalog Controls API

Manage the controls inside a control catalog — the `AC-2`, `AU-6` records themselves, their statements and guidance, their organization-defined parameters (ODPs), and their baseline impact.

Added in #895, alongside [Control Families](control-families.md). Before that the catalog container had a full API while its contents had none. The web UI has been able to add and tailor catalog controls all along, so this is the API catching up to a shipping UI rather than new capability.

## Base URL

```
https://sparc.example.com/api/v1/control_catalogs/:control_catalog_id/controls
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

Reads require an authenticated caller. Every mutation requires the `catalogs.write` permission; instance admins bypass. All mutations are audited (`api_catalog_control_created` / `_updated` / `_deleted`), and the update event records which columns changed.

## Identifying a control

A control is addressed by its **canonical identifier** — the same form the readable web URLs use (#881) and the same form every OSCAL exporter writes as `control-id`:

```
GET /api/v1/control_catalogs/<uuid>/controls/ac-2
GET /api/v1/control_catalogs/<uuid>/controls/ac-19.4.b.1
```

| Concept | Example | Notes |
|---|---|---|
| `identifier` | `ac-19.4.b.1` | **What goes in the URL.** URL-safe, derived from `control_id` |
| `control_id` | `ac-19.4.(b).(1)` | The raw catalog id as imported |
| `label` | `AC-19(4)(b)(1)` | Human display form, when the catalog supplies one |

`(catalog, identifier)` is unique across all seeded catalogs, so the family does not appear in the path for reads, updates or deletes. **Creation is family-scoped**, because a new control has to be put somewhere.

Statement sub-parts (`ac-2a`, `ac-19.4.b.1`) are first-class rows — 48% of the seeded catalogs — and are addressed the same way as any other control.

The catalog itself may be addressed by **OSCAL uuid** (preferred and stable), slug, or numeric id. See [Control Families](control-families.md#identifying-a-catalog).

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `…/controls` | List the catalog's controls |
| `GET` | `…/controls/:identifier` | Show a single control |
| `PATCH`/`PUT` | `…/controls/:identifier` | Update / tailor a control |
| `DELETE` | `…/controls/:identifier` | Delete a control (must have no sub-parts) |
| `GET` | `…/control_families/:code/controls` | List one family's controls |
| `POST` | `…/control_families/:code/controls` | Create a control in that family |

---

### GET List Controls

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | integer | No | Page number (default: `1`) |
| `items` | integer | No | Items per page (default: `25`, max `200`) |
| `family` | string | No | Filter by family code, e.g. `AC` |
| `top_level` | boolean | No | Exclude statement sub-parts — base controls and enhancements only |
| `baseline` | string | No | Filter by baseline level, e.g. `HIGH` |
| `q` | string | No | Free-text match on `control_id` or `title` |

```bash
curl -X GET "https://sparc.example.com/api/v1/control_catalogs/<uuid>/controls?family=AC&top_level=true" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response** `200 OK`

```json
{
  "data": [
    {
      "id": 2060,
      "uuid": "3f1c0a4e-9d2b-4e77-9f11-6d8c2a5b7e01",
      "identifier": "ac-2",
      "control_id": "ac-2",
      "label": "AC-2",
      "display_id": "AC-2",
      "title": "Account Management",
      "description": null,
      "priority": "P1",
      "sort_id": "ac-02",
      "baseline_impact": "LOW, MODERATE, HIGH",
      "baseline_levels": ["LOW", "MODERATE", "HIGH"],
      "control_family_id": 7,
      "family_code": "AC",
      "depth": 0,
      "created_at": "2026-08-03T12:00:00Z",
      "updated_at": "2026-08-03T12:00:00Z"
    }
  ],
  "meta": { "page": 1, "items": 25, "count": 142, "pages": 6 }
}
```

---

### GET Show a Control

Adds `guidance_data`, `params_data`, the direct `sub_parts`, and the owning catalog.

```json
{
  "data": {
    "identifier": "ac-2",
    "title": "Account Management",
    "guidance_data": {
      "statement": "Define and document the types of accounts …",
      "supplemental_guidance": "Examples of system account types include …"
    },
    "params_data": [
      { "id": "ac-02_odp.01", "label": "prerequisites and criteria" }
    ],
    "sub_parts": [
      { "identifier": "ac-2a", "control_id": "ac-2a", "title": "Define and document …" }
    ],
    "control_catalog": { "id": 3, "uuid": "5ba2a3ba-…", "name": "NIST SP 800-53 Rev 5" }
  }
}
```

`sub_parts` lists **direct children only**. Prefix matching would be wrong here: `ac-20` starts with `ac-2` but is a separate control, not a sub-part of it.

---

### POST Create a Control

Creation is nested under a family:

```bash
curl -X POST "https://sparc.example.com/api/v1/control_catalogs/<uuid>/control_families/ac/controls" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
        "catalog_control": {
          "control_id": "ac-2",
          "label": "AC-2",
          "title": "Account Management",
          "baseline_levels": ["LOW", "MODERATE", "HIGH"],
          "guidance_data": { "statement": "Manage system accounts …" }
        }
      }'
```

**Response** `201 Created`

---

### Body Parameters

These are the *only* accepted fields, at every level. Anything else in the payload is dropped.

`guidance_data` is a free-form JSONB column read by every OSCAL exporter, so — unlike the web form, which posts a known set of inputs — this endpoint enumerates its keys explicitly. An unenumerated key would otherwise travel straight into a delivered artefact.

**Top level**

| Parameter | Type | Description |
|-----------|------|-------------|
| `control_id` | string | **Required on create.** The catalog id, e.g. `ac-2`. Unique within the family |
| `title` | string | Control title |
| `description` | string | Free text |
| `label` | string | Display form, e.g. `AC-2(1)` |
| `priority` | string | e.g. `P1` |
| `sort_id` | string | Zero-padded ordering key, e.g. `ac-02` |
| `baseline_impact` | string | Comma-joined levels, e.g. `"LOW, MODERATE"` |
| `baseline_levels` | array | The same thing as JSON, e.g. `["LOW","MODERATE"]`. Takes precedence |
| `guidance_data` | object | See below |
| `params_data` | array | OSCAL parameter (ODP) definitions — see below |
| `params_labels` | object | `{ "<param id>": "<new label>" }` — relabel ODPs without resending `params_data` |

Only `LOW`, `MODERATE` and `HIGH` are accepted as baseline levels; anything else returns `422` rather than being stored.

**`guidance_data` keys**

| Key | Description |
|---|---|
| `statement` | The verbatim catalog statement, including `{{ insert: param, … }}` markup |
| `supplemental_guidance` | Catalog-supplied guidance |
| `implementation_guidance` | Organization tailoring |
| `check` | Check procedure |
| `fix` | Fix procedure |
| `related_controls` | e.g. `"AC-3, AC-6"` |
| `nist_references` | e.g. `"NIST SP 800-53 Rev 5, Section 2.1"` |
| `org_ref` | Internal policy or procedure reference |
| `assessment_objective` | SP 800-53A objective prose |
| `assessment` | Array of `{ "method": "EXAMINE\|INTERVIEW\|TEST", "objects": "…" }` |
| `automation_required`, `evidence_type`, `validation_frequency` | FedRAMP KSI catalogs only |

**`params_data` entry keys** — `id`, `label`, `class`, `depends-on`, `values[]`, `props[]` (`name`, `value`, `class`, `ns`, `uuid`, `remarks`), `guidelines[]` (`prose`), `select` (`how-many`, `choice[]`). The two hyphenated names are spelled the way OSCAL spells them, so the payload matches the artefact.

---

### PATCH Update a Control

> **`guidance_data` merges; it does not replace.**
>
> Assigning the column wholesale would silently drop every key the caller did not resend — a one-field update of `statement` would take `supplemental_guidance` with it, and the loss would only surface in an OSCAL export much later. Send just the keys you are changing. To **remove** a key, send it as `null` or `""`.

```bash
curl -X PATCH "https://sparc.example.com/api/v1/control_catalogs/<uuid>/controls/ac-2" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"catalog_control": {"guidance_data": {"implementation_guidance": "Tailored for this system."}}}'
```

`params_data` is an **ordered array**, so sending it replaces it wholesale. Callers who only want to rename an ODP should send `params_labels` instead, which merges by parameter id and preserves each parameter's `guidelines`, `select` and `props`.

Changing `control_id` moves the control's identifier, and therefore its URL — the response's `identifier` is the new address.

**Errors**

| Status | Cause |
|--------|-------|
| `400` | Body is missing the `catalog_control` root key |
| `401` | Missing or invalid Bearer token |
| `403` | Caller lacks `catalogs.write` |
| `404` | Catalog, family, or control not found **in this catalog** |
| `422` | Missing/duplicate `control_id`, or an unknown baseline level |

---

### DELETE a Control

```bash
curl -X DELETE "https://sparc.example.com/api/v1/control_catalogs/<uuid>/controls/ac-2" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response** `200 OK`

```json
{ "data": { "identifier": "ac-2", "deleted": true } }
```

> **A control with sub-parts will not be deleted.** Sub-parts are separate rows with no foreign key to their parent, so a cascade is not available and a silent delete would leave `ac-2a` pointing at a control that no longer exists. Delete the sub-parts first.

**Response when the control has sub-parts** — `422 Unprocessable Content`

```json
{
  "error": "Control ac-2 still has 3 sub-part(s). Delete them first.",
  "sub_parts": ["ac-2a", "ac-2b", "ac-2c"]
}
```
