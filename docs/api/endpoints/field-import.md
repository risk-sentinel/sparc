# Bulk Field Import API

Bulk file import of editable control **fields** for the downstream document types
— **SSP, SAR, SAP, CDEF** (#716, P1 follow-on to the ODP parameter import #715).
Upload a structured file, get a non-destructive **preview** diff, then **confirm**
to apply atomically with partial-success reporting.

For the Catalog/Baseline/Profile **ODP `set-parameter`** import, see
[Baseline Parameters](baseline-parameters.md) (`.../parameters/import/{preview,confirm}`).

## Endpoints

```
POST /api/v1/ssp_documents/:id/fields/import/preview
POST /api/v1/ssp_documents/:id/fields/import/confirm
POST /api/v1/sar_documents/:id/fields/import/preview
POST /api/v1/sar_documents/:id/fields/import/confirm
POST /api/v1/sap_documents/:id/fields/import/preview
POST /api/v1/sap_documents/:id/fields/import/confirm
POST /api/v1/cdef_documents/:id/fields/import/preview
POST /api/v1/cdef_documents/:id/fields/import/confirm
```

`:id` is a slug or numeric id. Bearer token required. Authorization is
boundary-scoped: `ssp.write` / `sar.write` / `sap.write` for those types, and
`converters.write` for CDEF (matching its bulk-apply gate). Admins bypass.

## Request

`multipart/form-data` with a `file` field (and optional `format` = `json` |
`yaml`; inferred from the filename otherwise). **JSON and YAML only** — no
CSV/XLSX (structured formats only). Size-guarded per the shared upload limit (SI-10).

Body shape — a map of control id → field updates (a top-level `controls` key is
optional):

```json
{
  "controls": {
    "AC-1": { "status": "Implemented", "implementation_statement": "..." },
    "AC-2": { "status": "Deferred", "notes": "tracked in POA&M" }
  }
}
```

Only each type's `*ControlField::EDITABLE_FIELDS` are writable; fields with a
controlled vocabulary (e.g. SSP `status`, SAR `result`, CDEF
`implementation_status`) are validated against it.

## Preview response (non-destructive)

```json
{
  "data": {
    "rows": [
      { "control_id": "AC-1", "field_name": "status", "current_value": "Deferred",
        "new_value": "Implemented", "status": "change" },
      { "control_id": "AC-1", "field_name": "class", "new_value": "x",
        "status": "non_editable", "message": "Field is not editable" }
    ],
    "stats": { "total": 2, "changes": 1, "unchanged": 0, "unknown": 0,
               "non_editable": 1, "invalid": 0 }
  }
}
```

Row `status`: `change` · `unchanged` · `unknown` (control id not in the document)
· `non_editable` · `invalid` (allowed-values violation).

## Confirm response (atomic apply, partial success)

`confirm` writes only the editable, allowed `change`/`unchanged` rows; unknown /
non-editable / invalid rows are reported but never written. The apply is
transactional and audited.

```json
{ "data": { "applied": 1, "stats": { ... }, "rows": [ ... ] } }
```

## Errors

`422` — empty / malformed file, unsupported format, no control updates, or a file
over the upload limit. `401` — no token. `403` — missing the write permission.

## Sample templates

- [`field-import-ssp.json`](../samples/field-import-ssp.json) — SSP editable fields.

Note: SAR controls may share a `control_id` across multiple test rows; the import
applies to the first matching control (mirrors `update_fields`).
