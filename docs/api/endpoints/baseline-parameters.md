# Baseline Parameters API

Manage the organization-defined parameter (ODP) values and selections of a profile document (a baseline). Parameters are the blanks NIST leaves for an organization to fill in — who receives a policy, how often it is reviewed, which of several options applies. All endpoints are nested under a specific profile document.

## Base URL

```
https://sparc.example.com/api/v1/profile_documents/:profile_document_id/parameters
```

`:profile_document_id` is the profile's numeric `id` or its `slug`.

## Authentication

All endpoints require a valid Bearer token. Writes (`PUT`, `import/confirm`) also need the `profiles.write` permission.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `.../parameters` | Show parameter schema |
| `PUT` | `.../parameters` | Bulk update parameters |
| `GET` | `.../parameters/export` | Export parameters |
| `POST` | `.../parameters/import/preview` | Dry-run an ODP import file (diff, no writes) |
| `POST` | `.../parameters/import/confirm` | Apply an ODP import file |

---

## Parameter ids

Use the ids the profile's catalog declares. For NIST SP 800-53 **Rev 5** those are the `odp` form, `ac-01_odp.03`; `GET .../parameters` lists every one a profile has.

Rev 5 kept the Rev 4-style id each parameter replaced as an `alt-identifier` (`ac-01_odp.03` carries `ac-1_prm_2`). **An `alt-identifier` is accepted wherever an id is** and is stored against the parameter that declares it; the response's `resolved_aliases` (or the preview row's `message`) says when that happened. A real id always wins over an alias spelled the same way. Rev 4 catalogs use the `ac-1_prm_2` form as their real ids.

Two things in Rev 5 to know about:

- **Selections are separate from parameters.** `ac-01_odp.03` (organization-level / mission/business process-level / system-level) is a selection: send it under `selections` with a `selected` array. The schema lists it under `selections`.
- **Aggregate parameters.** NIST declares some parameters as the union of others — `ac-1_prm_1` aggregates `ac-01_odp.01` and `ac-01_odp.02`. Set the ODPs it aggregates rather than the aggregate; a value set on the aggregate is stored separately and can disagree with its parts.

## Worksheets — Rev 5 catalog and baselines

Ready-to-fill request bodies for NIST SP 800-53 Rev 5 (catalog v5.2.0) are in [`docs/api/samples/`](../samples/):

| File | Covers | Parameters | Selections |
|------|--------|-----------:|-----------:|
| [`rev5-catalog-odp.json`](../samples/rev5-catalog-odp.json) | every control in the catalog (1,196) | 1,327 | 131 |
| [`rev5-low-odp.json`](../samples/rev5-low-odp.json) | the NIST LOW baseline (149 controls) | 364 | 41 |
| [`rev5-moderate-odp.json`](../samples/rev5-moderate-odp.json) | the NIST MODERATE baseline (287 controls) | 521 | 63 |
| [`rev5-high-odp.json`](../samples/rev5-high-odp.json) | the NIST HIGH baseline (370 controls) | 624 | 75 |

Each worksheet **is** a request body for `PUT .../parameters` and an upload for `import/preview` → `import/confirm`. Every entry starts unset (`"value": null` / `"selected": null`), and carries the control, NIST's label and guidance, the `alt_identifier`, and for a selection its `choices`, `how_many` and any parameters a choice depends on (`depends_on`) — reference the API ignores. Fill in the entries you have decided and send the file as it stands; the entries left `null` are skipped. Aggregate parameters are left out (see above).

To tailor a NIST baseline, create or duplicate a profile on the Rev 5 catalog with that baseline's controls, then send its worksheet to the new profile. A published profile is read-only (see `422` below).

The worksheets are generated from the bundled catalog and NIST's baseline profiles with `bin/rails samples:odp_worksheets`.

---

### GET Show Parameter Schema

Returns every parameter and selection the profile has, with its current value.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `family` | string | No | Filter by control family (e.g., `ac`, `au`, `si`) |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/profile_documents/my-moderate-baseline/parameters?family=ac" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": {
    "baseline": "My MODERATE Baseline",
    "baseline_level": "moderate",
    "version": "1.0.0",
    "profile_id": 42,
    "profile_slug": "my-moderate-baseline",
    "parameters": [
      {
        "param_id": "ac-01_odp.04",
        "alt_identifier": "ac-1_prm_3",
        "control_id": "ac-1",
        "control_title": "Policy and Procedures",
        "label": "official",
        "description": "an official to manage the access control policy and procedures is defined;",
        "type": "text",
        "constraint": null,
        "current_value": "Chief Information Security Officer",
        "value": "Chief Information Security Officer"
      }
    ],
    "selections": [
      {
        "select_id": "ac-01_odp.03",
        "alt_identifier": "ac-1_prm_2",
        "control_id": "ac-1",
        "control_title": "Policy and Procedures",
        "label": null,
        "description": null,
        "how_many": "one-or-more",
        "choices": ["organization-level", "mission/business process-level", "system-level"],
        "choice_details": [
          { "text": "organization-level", "display": "organization-level", "references": [] },
          { "text": "mission/business process-level", "display": "mission/business process-level", "references": [] },
          { "text": "system-level", "display": "system-level", "references": [] }
        ],
        "depends_on": [],
        "selected": ["system-level"]
      }
    ]
  }
}
```

`alt_identifier` is `null` for a parameter that has none. `choices` is the verbatim OSCAL text — what is written back — and `choice_details` adds the readable form and any parameter a choice embeds (`{{ insert: param, ... }}`).

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Parameter schema returned successfully |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Profile document not found |

---

### PUT Bulk Update Parameters

Update parameter values and selections in bulk. Only the entries in the request body are touched; every other value stays as it is.

`parameters` and `selections` are **arrays of objects at the top level of the body**, and at least one of them must be present. Any other top-level key is ignored (a worksheet's `_about`, for example). A body the endpoint cannot parse into that shape is refused with `422` and changes nothing — it does not report success for work it did not do (#994).

**Request Body**

```json
{
  "parameters": [
    { "param_id": "ac-01_odp.01", "value": "ISSO and System Owner" },
    { "param_id": "ac-1_prm_3",   "value": "Chief Information Security Officer" },
    { "param_id": "ac-01_odp.05", "value": null }
  ],
  "selections": [
    { "select_id": "ac-01_odp.03", "selected": ["system-level"] }
  ]
}
```

| Value sent | Effect |
|------------|--------|
| a string / an array of choices | stored |
| `""` / `[]` | clears the stored value |
| `null`, or `selected` absent | **not provided** — skipped, the stored value is kept, and the entry is listed under `skipped` |

`selection_id` is accepted as an alias for `select_id` **on input only**; `select_id` stays canonical and is what `GET .../parameters/export` emits. `selected` must be an array even when one choice is selected — a bare string is refused rather than coerced, because there is no honest way to tell whether `"a, b"` was one choice or two.

**Example Request**

```bash
curl -X PUT "https://sparc.example.com/api/v1/profile_documents/my-moderate-baseline/parameters" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  --data-binary @rev5-moderate-odp.json
```

**Response Body**

```json
{
  "data": {
    "status": "updated",
    "baseline_id": "my-moderate-baseline",
    "parameters_updated": 2,
    "selections_updated": 1,
    "skipped": [
      { "param_id": "ac-01_odp.05", "reason": "value is null (not provided)" }
    ],
    "resolved_aliases": [
      { "given": "ac-1_prm_3", "param_id": "ac-01_odp.04" }
    ],
    "validation_errors": []
  }
}
```

`status` is `"updated"` when `validation_errors` is empty and `"partial"` otherwise. **A response carrying any validation error is returned with `422`, but the valid entries in the same request were still stored** — read `parameters_updated` / `selections_updated` and `validation_errors` together rather than treating `422` as "nothing happened". An unknown id is reported as `{ "param_id": "...", "error": "Unknown parameter ID" }` (or `select_id` / `"Unknown selection ID"`).

**A refused body** names what was expected and states plainly that nothing changed:

```json
{
  "error": "The request body could not be parsed as a baseline parameter update. Nothing was changed.",
  "details": [
    "`parameters` must be an ARRAY of objects, each carrying `param_id` and `value`. Received an object."
  ],
  "expected": {
    "parameters": [{ "param_id": "string", "value": "string" }],
    "selections": [{ "select_id": "string", "selected": ["string"] }]
  }
}
```

**A published profile is read-only** (#1008). The update is refused with `422` before anything is read, whatever the body says:

```json
{
  "error": "This profile is published and cannot be edited. Duplicate it to create an editable draft.",
  "details": ["lifecycle_status is \"published\""]
}
```

Check `lifecycle_status` on `GET /api/v1/profile_documents/:id` for the profile you are writing to. `status` (`completed`) is whether the profile finished processing and says nothing about whether it can be edited. The seeded NIST LOW and MODERATE baselines are published.

Sending `{"parameters": [], "selections": []}` is a legitimate no-op and returns `200` with both counts at zero — "nothing to do" and "I did not understand you" are deliberately different responses.

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Every entry stored or skipped, or an explicitly empty request accepted as a no-op |
| `401` | Unauthorized -- missing or invalid token |
| `403` | Forbidden -- the token's user lacks `profiles.write` |
| `404` | Profile document not found |
| `422` | Body could not be parsed (nothing changed); the profile is published (nothing changed); or some ids were unknown (the rest were stored) |

---

### GET Export Parameters

Download the parameter schema — the same document as `GET .../parameters`, without the `data` wrapper — in JSON, YAML, or XML. The JSON and YAML exports round-trip through the import endpoints.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `format` | string | No | Export format: `json` (default), `yaml`, or `xml` |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/profile_documents/my-moderate-baseline/parameters/export?format=json" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -o parameters-export.json
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Export generated successfully |
| `400` | Unsupported format requested |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Profile document not found |

---

### POST Import ODP File — Preview

**Issue #697.** Controller action `baseline_parameters#import_preview`. Upload an Organization-Defined Parameter (OSCAL `set-parameter`) file and receive a **non-destructive diff** — what would change, unchanged rows, unknown ids, skipped (`null`) entries, and selection values that aren't an allowed choice. **No writes**, so it is available on a published profile too. This is the authoritative Catalog/Baseline/Profile ODP layer; downstream documents (CDEF/SSP/SAP/SAR) inherit these values from the upstream profile.

**Request** — `multipart/form-data`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `file` | file | Yes | ODP file in **JSON**, **YAML/YML**, or **XML** (round-trips `.../parameters/export`). 5 MB max. |
| `format` | string | No | Override the format inferred from the filename extension. |

The file is the same shape as the `PUT` body — a [worksheet](#worksheets--rev-5-catalog-and-baselines) uploads as it stands. A flat `{ "param_id": "value" }` map is also accepted.

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/profile_documents/my-moderate-baseline/parameters/import/preview" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -F "file=@rev5-moderate-odp.json;type=application/json"
```

**Response Body**

```json
{
  "data": {
    "profile_id": 42,
    "profile_slug": "my-moderate-baseline",
    "stats": { "total": 3, "changes": 2, "unchanged": 0, "unknown": 0, "invalid": 0, "skipped": 1 },
    "rows": [
      { "param_id": "ac-01_odp.04", "control_id": "ac-1", "kind": "parameter",
        "current_value": "", "new_value": "Chief Information Security Officer", "status": "change",
        "message": "ac-1_prm_3 is an alt-identifier for ac-01_odp.04" },
      { "param_id": "ac-01_odp.05", "control_id": "ac-1", "kind": "parameter",
        "current_value": "", "status": "skipped", "message": "value is null (not provided)" },
      { "param_id": "ac-01_odp.03", "control_id": "ac-1", "kind": "selection",
        "current_value": "", "new_value": "system-level", "status": "change" }
    ]
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Diff computed |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Profile document not found |
| `422` | No file provided, unsupported format, or unparseable file |

---

### POST Import ODP File — Confirm

Controller action `baseline_parameters#import_confirm`. Apply the same file with partial-success reporting: unknown ids are skipped and reported in `validation_errors`, `null` entries are skipped, and selection values outside the allowed choices are dropped (never persisted). Audited (`odp_file_import`). Same request shape as preview; refused on a published profile.

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/profile_documents/my-moderate-baseline/parameters/import/confirm" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -F "file=@rev5-moderate-odp.json;type=application/json"
```

**Response Body** — the same summary as `PUT`:

```json
{
  "data": {
    "status": "updated",
    "baseline_id": "my-moderate-baseline",
    "parameters_updated": 1,
    "selections_updated": 1,
    "skipped": [{ "param_id": "ac-01_odp.05", "reason": "value is null (not provided)" }],
    "resolved_aliases": [{ "given": "ac-1_prm_3", "param_id": "ac-01_odp.04" }],
    "validation_errors": []
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Applied (fully or partially) |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Profile document not found |
| `422` | Nothing could be applied (e.g. every id unknown), the profile is published, or unparseable file |

---

## Common Errors

| Code | Error | Description |
|------|-------|-------------|
| `401` | `Unauthorized` | Missing or invalid Bearer token |
| `403` | `Forbidden` | The token's user lacks `profiles.write` |
| `404` | `Not Found` | Profile document does not exist or is not accessible |
| `422` | `Unprocessable Entity` | Unknown parameter or selection ids, a published profile, or a body that could not be parsed into the documented shape |
| `500` | `Internal Server Error` | Unexpected server error -- contact your administrator |
