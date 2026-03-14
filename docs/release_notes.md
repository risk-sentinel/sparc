# SPARC Release Notes

---

## 2026-03-14 -- Background Upload Processing UX (#142)

**Branch:** `feature/142_background_upload_ux`

### Summary

All document uploads (SSP, SAR, CDEF, Profile, SAP, POAM, Catalog)
now display real-time processing stage messages instead of an
indefinite spinner. Users see what stage the background job is at
(reading file, parsing rows, creating records, etc.) during upload
processing.

### What Changed

- **New `ProgressTrackable` concern** -- reusable service concern
  that writes processing stages to `metadata_extra` JSONB via
  `update_columns` (fast, no callbacks). Uses `processing_*`
  namespace to avoid collision with CCI Refresh's `refresh_*`
  namespace.

- **Shared processing banner partial** -- extracted 7 duplicated
  processing banner blocks into a single `_processing_banner.html.erb`
  partial. Supports configurable title, back link, refresh interval,
  and displays stage messages from `metadata_extra`.

- **Job-level progress bookends** -- `DocumentConversionJob` and
  `CatalogImportJob` now write `processing_started_at`, stage
  tracking, and `processing_completed_at` to `metadata_extra`.
  On failure, captures the last known stage for debugging.

- **Parser-level progress reporting** -- all 20 parser services
  (2 Excel, 1 XCCDF, 6 JSON, 6 XML, 5 YAML) and
  `CatalogImportService` now include `ProgressTrackable` and report
  stages during parsing. Excel parsers report row-by-row progress
  every 500 rows for large files.

- **Index view enhancements** -- all 7 index views auto-refresh
  (10s interval) when any document is processing/pending, and show
  the current processing stage message under the status badge.

### Files Created (2)

- `app/services/concerns/progress_trackable.rb`
- `app/views/shared/_processing_banner.html.erb`

### Files Modified (39)

- `app/jobs/document_conversion_job.rb`
- `app/jobs/catalog_import_job.rb`
- `app/services/catalog_import_service.rb`
- `app/services/ssp_excel_parser_service.rb`
- `app/services/sar_excel_parser_service.rb`
- `app/services/ssp_json_parser_service.rb`
- `app/services/sar_json_parser_service.rb`
- `app/services/cdef_json_parser_service.rb`
- `app/services/profile_json_parser_service.rb`
- `app/services/sap_json_parser_service.rb`
- `app/services/poam_json_parser_service.rb`
- `app/services/ssp_xml_parser_service.rb`
- `app/services/sar_xml_parser_service.rb`
- `app/services/poam_xml_parser_service.rb`
- `app/services/profile_xml_parser_service.rb`
- `app/services/sap_xml_parser_service.rb`
- `app/services/cdef_yaml_parser_service.rb`
- `app/services/ssp_yaml_parser_service.rb`
- `app/services/sar_yaml_parser_service.rb`
- `app/services/poam_yaml_parser_service.rb`
- `app/services/profile_yaml_parser_service.rb`
- `app/services/sap_yaml_parser_service.rb`
- `app/services/cdef_xccdf_parser_service.rb`
- `app/views/ssp_documents/show.html.erb`
- `app/views/sar_documents/show.html.erb`
- `app/views/cdef_documents/show.html.erb`
- `app/views/profile_documents/show.html.erb`
- `app/views/sap_documents/show.html.erb`
- `app/views/poam_documents/show.html.erb`
- `app/views/control_catalogs/show.html.erb`
- `app/views/ssp_documents/index.html.erb`
- `app/views/sar_documents/index.html.erb`
- `app/views/cdef_documents/index.html.erb`
- `app/views/profile_documents/index.html.erb`
- `app/views/sap_documents/index.html.erb`
- `app/views/poam_documents/index.html.erb`
- `app/views/control_catalogs/index.html.erb`

### What is NOT Changed

- **CCI Refresh** -- untouched. Uses separate `refresh_*` namespace.
- **No database migrations** -- uses existing `metadata_extra` JSONB.
- **No new routes** -- progress shown via existing show/index pages.
- **No new Stimulus controllers** -- continues `meta http-equiv=refresh`
  pattern for auto-refresh.

### Verification

- 564 RSpec tests pass
- RuboCop clean (0 offenses)
