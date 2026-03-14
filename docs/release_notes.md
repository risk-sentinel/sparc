<!-- markdownlint-disable MD024 -->

# SPARC Release Notes

---

## 2026-03-14 -- Comprehensive Automated Regression Testing Suite (#100)

**Branch:** `feature/100_regression_testing_suite`

### Summary

Added ~210 new RSpec tests across 32 new spec files, bringing the total
from 564 to 772 tests (0 failures). Installed SimpleCov for code
coverage tracking with dual HTML + JSON output. Updated CI to run
RSpec with coverage and upload reports as artifacts for SCA pipeline
integration.

### What Changed

- **SimpleCov integration** -- added `simplecov` gem with
  `MultiFormatter` producing both HTML (local viewing via
  `open coverage/index.html`) and JSON (`coverage/coverage.json`
  for SCA bundle ingestion). Coverage output in `coverage/`
  directory, git-ignored.

- **CI pipeline updated** -- `.github/workflows/ci.yml` now runs
  `bundle exec rspec` instead of `bin/rails test`, sets `COVERAGE=1`,
  and uploads `coverage/` as a downloadable CI artifact (90-day
  retention).

- **10 new request specs** -- full controller coverage for
  `SspDocuments`, `SarDocuments`, `CdefDocuments`, `SapDocuments`,
  `PoamDocuments`, `ProfileDocuments`, `Home`, `Evidences`,
  `Attestations`, and `Api::V1::SspDocuments`. Tests cover index,
  show, new, create, delete (including SafeDestroyable blocking),
  export (JSON/YAML/XML), metadata update, status, wizard, and
  copy actions.

- **12 new model specs** -- coverage for `CdefDocument`,
  `ProfileDocument`, `SapDocument`, `PoamDocument`,
  `AuthorizationBoundary`, `Converter`, `SspComponent`, `PoamItem`,
  `SparcConfig`, `DocumentTypeRegistry`, `SspDocumentCdefDocument`,
  and `BoundaryCdefDocument`. Tests cover validations, associations,
  SafeDestroyable behavior, scopes, and instance methods.

- **3 new service specs** -- `JsonExportService` (all 6 document type
  exports), `SspUpdateService` (editable/non-editable field updates),
  and `OscalSchemaValidationService` (schema availability, validation).

- **4 new job specs** -- `DocumentConversionJob`, `CatalogImportJob`,
  `ConverterRefreshJob`, `InactivityCheckJob`. Tests cover queue
  assignment and basic perform behavior.

- **3 new concern specs** -- `SafeDestroyable` (blocks with deps,
  allows without, error messages), `OscalMetadata` (constants,
  metadata builder, accessors), `ProgressTrackable` (processing
  stages constant).

- **Issue Process documented** -- added standard 11-step issue workflow
  to `docs/Implemenation_plan.md` covering branch creation, planning,
  implementation, doc updates, testing, and PR workflow.

### Files Created (32 spec files)

- `spec/requests/home_spec.rb`
- `spec/requests/ssp_documents_spec.rb`
- `spec/requests/sar_documents_spec.rb`
- `spec/requests/cdef_documents_spec.rb`
- `spec/requests/sap_documents_spec.rb`
- `spec/requests/poam_documents_spec.rb`
- `spec/requests/profile_documents_spec.rb`
- `spec/requests/evidences_spec.rb`
- `spec/requests/attestations_spec.rb`
- `spec/requests/api/v1/ssp_documents_spec.rb`
- `spec/models/cdef_document_spec.rb`
- `spec/models/profile_document_spec.rb`
- `spec/models/sap_document_spec.rb`
- `spec/models/poam_document_spec.rb`
- `spec/models/authorization_boundary_spec.rb`
- `spec/models/converter_spec.rb`
- `spec/models/ssp_component_spec.rb`
- `spec/models/poam_item_spec.rb`
- `spec/models/sparc_config_spec.rb`
- `spec/models/document_type_registry_spec.rb`
- `spec/models/ssp_document_cdef_document_spec.rb`
- `spec/models/boundary_cdef_document_spec.rb`
- `spec/services/json_export_service_spec.rb`
- `spec/services/ssp_update_service_spec.rb`
- `spec/services/oscal_schema_validation_service_spec.rb`
- `spec/jobs/document_conversion_job_spec.rb`
- `spec/jobs/catalog_import_job_spec.rb`
- `spec/jobs/converter_refresh_job_spec.rb`
- `spec/jobs/inactivity_check_job_spec.rb`
- `spec/models/concerns/safe_destroyable_spec.rb`
- `spec/models/concerns/oscal_metadata_spec.rb`
- `spec/models/concerns/progress_trackable_spec.rb`

### Files Modified (5)

- `.gitignore` -- added `/coverage`
- `Gemfile` -- added `simplecov` to test group
- `spec/spec_helper.rb` -- SimpleCov config (MultiFormatter, coverage groups)
- `.github/workflows/ci.yml` -- `COVERAGE=1`, rspec, artifact upload
- `docs/Implemenation_plan.md` -- Issue Process section, #100 marked complete

### What is NOT Changed

- **No application code changes** -- test-only addition
- **No database migrations** -- tests use existing schema
- **No new routes or controllers** -- test infrastructure only
- **Existing 564 tests untouched** -- only added new specs

### Verification

- 772 RSpec tests pass (0 failures)
- RuboCop clean (0 offenses)
- `COVERAGE=1 bundle exec rspec` generates dual reports in `coverage/`

---

## 2026-03-14 -- Safe Delete Confirmation with Dependency Checks (#178)

**Branch:** `feature/178_safe_delete_confirmation`

### Summary

All delete actions across SPARC now check for cross-document
dependencies before allowing deletion. If an entity is referenced by
other documents (e.g., a Profile linked to SSPs), the delete is
blocked with a clear error message. Additionally, all confirmation
dialogs now use a styled Bootstrap modal instead of the browser's
native `window.confirm()`.

### What Changed

- **New `SafeDestroyable` concern** -- reusable model concern with
  `before_destroy :check_deletion_dependencies`. Each including model
  defines a `deletion_dependencies` method that returns human-readable
  dependency strings. If any exist, the destroy is aborted with an
  error on `:base`.

- **Dependency checks across all models** -- `ControlCatalog` (profiles,
  mappings), `ProfileDocument` (SSPs, SAPs), `SspDocument` (SAPs),
  `SapDocument` (SARs), `CdefDocument` (SSP join table, boundary join
  table). Leaf nodes (`SarDocument`, `PoamDocument`) include the concern
  with empty dependencies.

- **Safe controller destroy pattern** -- all 7 controllers now check
  `destroy` return value. On success: audit log + flash success +
  redirect to index. On failure: audit log "delete_blocked" with
  reason + flash error + redirect back to show page.

- **7 new audit actions** -- `*_delete_blocked` events registered in
  `AuditEvent` for compliance audit trail when deletion is prevented.

- **Bootstrap confirmation modal** -- `Turbo.setConfirmMethod()` override
  in `application.js` replaces browser-native `window.confirm()` with a
  styled Bootstrap 5 modal for all `turbo_confirm` dialogs app-wide.
  Features red "Delete" button, Cancel default, auto-cleanup.

- **Normalized all confirmation dialogs** -- migrated 9 views from
  old Rails UJS `data: { confirm: }` pattern to Turbo-compatible
  `form: { data: { turbo_confirm: } }` so all confirmations trigger
  the new Bootstrap modal.

### Files Created (1)

- `app/models/concerns/safe_destroyable.rb`

### Files Modified (17)

- `app/models/control_catalog.rb`
- `app/models/ssp_document.rb`
- `app/models/sar_document.rb`
- `app/models/cdef_document.rb`
- `app/models/profile_document.rb`
- `app/models/sap_document.rb`
- `app/models/poam_document.rb`
- `app/models/audit_event.rb`
- `app/controllers/ssp_documents_controller.rb`
- `app/controllers/sar_documents_controller.rb`
- `app/controllers/cdef_documents_controller.rb`
- `app/controllers/profile_documents_controller.rb`
- `app/controllers/sap_documents_controller.rb`
- `app/controllers/poam_documents_controller.rb`
- `app/controllers/control_catalogs_controller.rb`
- `app/javascript/application.js`
- `spec/models/control_catalog_spec.rb`

### Views Updated (9)

- `app/views/control_catalogs/index.html.erb`
- `app/views/control_catalogs/show.html.erb`
- `app/views/control_families/show.html.erb`
- `app/views/evidences/index.html.erb`
- `app/views/evidences/show.html.erb`
- `app/views/cdef_documents/index.html.erb`
- `app/views/cdef_documents/show.html.erb`
- `app/views/profile_documents/show.html.erb`

### What is NOT Changed

- **No database migrations** -- dependency checks use existing FK columns.
- **No new routes** -- dependency info is in model error messages.
- **No new Stimulus controller** -- uses official `Turbo.setConfirmMethod`.
- **Child record cascading unchanged** -- `dependent: :destroy` still works.
- **AuthorizationBoundary** -- already has `dependent: :nullify`, no change.

### Verification

- 564 RSpec tests pass
- RuboCop clean (0 offenses)

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
