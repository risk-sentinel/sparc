# FedRAMP 20x KSI Catalog API

The FedRAMP 20x Key Security Indicators (KSI) catalog, built from what FedRAMP publishes.

The source is FedRAMP's consolidated rules ([`FedRAMP/rules`](https://github.com/FedRAMP/rules)), vendored in `lib/data/fedramp` with a provenance sidecar recording the upstream commit, `info.version` and retrieval date. Themes map to control families, indicators to catalog controls, and each indicator's `controls[]` becomes the KSI-to-NIST SP 800-53 Rev 5 crosswalk. FedRAMP authors that crosswalk, not SPARC.

## Base URL

```
https://sparc.example.com/api/v1/ksi_catalog
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

| Endpoint | Who |
|----------|-----|
| All `GET` endpoints | Any authenticated user |
| `POST /import` | Instance administrator, or a role with `catalogs.write` |

## Current and retired entries

FedRAMP re-keys its catalog. When a theme or indicator stops being published, SPARC **retires** it rather than deleting it, so the assessments recorded against it (`ksi_validations`) survive as history.

- The list endpoints return the **current** catalog. Add `include_retired=true` to include retired entries too.
- Every theme and indicator carries `retired_at`, which is `null` while current. Every indicator also carries `superseded_by`: FedRAMP's closest successor ids. That is a pointer only; it does not claim an assessment carries over.
- `GET /indicators/:id` resolves a retired id as well, so an old reference still finds what it was.
- A **new** KSI validation cannot be recorded on a retired indicator. The API answers `422` and names the successor. Existing validations on retired indicators stay readable and editable, and report `ksi_retired: true`.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/ksi_catalog/themes` | List KSI themes |
| `GET` | `/api/v1/ksi_catalog/indicators` | List indicators (paginated) |
| `GET` | `/api/v1/ksi_catalog/indicators/:id` | Show one indicator with its mapped NIST controls |
| `GET` | `/api/v1/ksi_catalog/mappings` | List KSI-to-NIST crosswalk entries (paginated) |
| `POST` | `/api/v1/ksi_catalog/import` | Import the vendored FedRAMP/rules snapshot |

---

### GET List KSI Themes

Returns the whole collection; it is not paginated.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `include_retired` | boolean | No | Include retired themes (default `false`) |

**Example Request**

```bash
curl "https://sparc.example.com/api/v1/ksi_catalog/themes" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response Body**

```json
{
  "data": [
    {
      "code": "CED",
      "name": "Cybersecurity Education",
      "sort_order": 1,
      "indicators_count": 1,
      "retired_at": null
    },
    {
      "code": "IAM",
      "name": "Identity and Access Management",
      "sort_order": 4,
      "indicators_count": 6,
      "retired_at": null
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 10, "items": 10 }
}
```

`indicators_count` counts current indicators only.

| Code | Description |
|------|-------------|
| `200` | Themes returned |
| `401` | Missing or invalid token |
| `404` | No KSI catalog on this instance |

---

### GET List Indicators

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | integer | No | Page number (default `1`) |
| `items` | integer | No | Items per page (default `25`, max `200`) |
| `theme` | string | No | Theme code, e.g. `IAM`, `CMT` |
| `impact_level` | string | No | Substring match on `baseline_impact` |
| `include_retired` | boolean | No | Include retired indicators (default `false`) |

FedRAMP's rules carry no impact level per indicator; some indicators instead state a requirement per class (`varies_by_class`). `baseline_impact` is therefore only set where an operator has set it, and `impact_level` filters on that value.

**Example Request**

```bash
curl "https://sparc.example.com/api/v1/ksi_catalog/indicators?theme=IAM" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response Body**

```json
{
  "data": [
    {
      "control_id": "ksi-iam-elp",
      "label": "KSI-IAM-ELP",
      "title": "Ensuring Least Privilege",
      "theme_code": "IAM",
      "theme_name": "Identity and Access Management",
      "baseline_impact": null,
      "baseline_levels": [],
      "retired_at": null,
      "superseded_by": []
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 6, "items": 25 }
}
```

`control_id` is FedRAMP's id in lowercase; `label` is FedRAMP's id as published.

| Code | Description |
|------|-------------|
| `200` | Indicators returned |
| `401` | Missing or invalid token |
| `404` | No KSI catalog on this instance |

---

### GET Show One Indicator

`:id` is the indicator id in either case, e.g. `ksi-iam-elp` or `KSI-IAM-ELP`. Retired ids resolve too.

**Example Request**

```bash
curl "https://sparc.example.com/api/v1/ksi_catalog/indicators/KSI-IAM-ELP" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response Body**

```json
{
  "data": {
    "control_id": "ksi-iam-elp",
    "label": "KSI-IAM-ELP",
    "title": "Ensuring Least Privilege",
    "theme_code": "IAM",
    "theme_name": "Identity and Access Management",
    "baseline_impact": null,
    "baseline_levels": [],
    "retired_at": null,
    "superseded_by": [],
    "description": "Identity and access management measures are used and persistently reviewed to ensure each user or device can only access the resources they need.",
    "validation_frequency": null,
    "evidence_type": null,
    "automation_required": null,
    "mapped_nist_controls": [
      { "target": "ac-2.5", "relationship": "intersects" },
      { "target": "ac-6", "relationship": "intersects" }
    ]
  }
}
```

`description` is FedRAMP's statement. Where FedRAMP states the requirement per class, it holds one line per class, e.g. `Class B: …` / `Class C: …`.

`validation_frequency`, `evidence_type` and `automation_required` are operator-set guidance; FedRAMP does not publish them.

| Code | Description |
|------|-------------|
| `200` | Indicator returned |
| `401` | Missing or invalid token |
| `404` | Unknown indicator, or no KSI catalog |

---

### GET List KSI-to-NIST Mappings

Returns the crosswalk entries, 50 per page. Every entry uses the relationship `intersects`: FedRAMP lists the related controls without qualifying each one.

**Example Request**

```bash
curl "https://sparc.example.com/api/v1/ksi_catalog/mappings?page=1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response Body**

```json
{
  "data": [
    {
      "source_control_id": "ksi-iam-elp",
      "target_control_id": "ac-2.5",
      "relationship": "intersects",
      "source_type": "control",
      "target_type": "control"
    }
  ],
  "meta": {
    "page": 1,
    "pages": 8,
    "count": 373,
    "items": 50,
    "mapping_name": "FedRAMP 20x KSI to NIST SP 800-53 Rev 5",
    "mapping_status": "complete"
  }
}
```

The crosswalk is built only when a NIST SP 800-53 Rev 5 catalog is loaded; the importer finds it by framework and version. Targets that catalog does not hold are skipped and counted in the import's `changes`. With no mapping at all, `data` is `[]` and `meta.message` says so.

| Code | Description |
|------|-------------|
| `200` | Entries returned (possibly empty) |
| `401` | Missing or invalid token |
| `404` | No KSI catalog on this instance |

---

### POST Import the KSI Catalog

Imports the FedRAMP 20x KSI catalog from the vendored FedRAMP/rules snapshot. The same import is `bin/rails ksi:import`. Behaviour:

- **Never fetches from the network.** Moving to a newer FedRAMP release means vendoring a new snapshot. `bin/rails ksi:upstream_diff` reports how upstream differs from the vendored copy.
- **Validates first.** The snapshot is checked against FedRAMP's own JSON Schema; if it does not validate, nothing is written.
- **All or nothing.** The import runs in one transaction.
- **Re-keys in place.** A catalog built by an earlier SPARC keeps its row identities: an owner-approved map (`lib/data/fedramp/ksi_legacy_map.yml`) renames indicators that correspond one-to-one, and their validations follow them. Every other old indicator is retired, never deleted.
- **Idempotent.** Once the snapshot and its crosswalk are in place, re-importing returns `unchanged`.
- Synchronous, and audited as `ksi_catalog_imported` / `ksi_catalog_import_refused`.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `dry_run` | boolean | No | Run the import, report the changes, then roll everything back (default `false`) |

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/ksi_catalog/import?dry_run=true" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response Body**

```json
{
  "data": {
    "status": "planned",
    "upstream_version": "2026.09.13.02",
    "dry_run": true,
    "changes": {
      "renamed": 10,
      "retired": 44,
      "indicators_created": 36,
      "themes_retired": 1,
      "crosswalk_entries": 373
    },
    "errors": []
  }
}
```

`status` is one of:

| `status` | HTTP | Meaning |
|----------|------|---------|
| `imported` | `200` | The snapshot was imported |
| `unchanged` | `200` | Already imported; nothing to do |
| `planned` | `200` | Dry run; nothing was kept |
| `refused` | `422` | Schema-invalid data or an inapplicable map; `errors` says why; nothing written |

| Code | Description |
|------|-------------|
| `200` | Imported, unchanged, or planned |
| `401` | Missing or invalid token |
| `403` | Requires `catalogs.write` or instance administrator |
| `422` | Import refused |
