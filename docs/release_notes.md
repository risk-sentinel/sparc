<!-- markdownlint-disable MD024 -->

# SPARC Release Notes

---

## 2026-03-15 -- Unified Publication Process for Profiles and CDEFs (#176)

**Branch:** `feature/176_unified_publication_profiles_cdefs`

### Summary

Unifies the Profile publication workflow into the shared Publishable concern,
eliminating ~35 lines of duplicated metadata-fix and validation code. Adds a
`before_publish_lifecycle` hook so Profile can run its unique resolved-catalog
generation step within the shared publish flow. Adds version auto-management
on publish for all document types and standardizes copy button UI.

### What Changed

- **Publishable concern** -- added `before_publish_lifecycle` hook (controllers
  can override to run custom pre-publish logic; return `{ error: "..." }` to
  abort). Added `auto_increment_version!` that sets blank versions to `"1.0.0"`
  and increments semver patch on republish. Flash message now includes version.
- **ProfileDocumentsController** -- refactored to `include Publishable` with
  `publish_config` and `before_publish_lifecycle` override for resolved catalog
  generation. Removed 3 duplicate methods: `publish`, `publish_check`,
  `apply_profile_metadata_fixes!`.
- **CDEF show page** -- copy button now shows "Create Editable Copy" for
  published documents (matching Profile pattern).

### Files Modified (3)

- `app/controllers/concerns/publishable.rb`
- `app/controllers/profile_documents_controller.rb`
- `app/views/cdef_documents/show.html.erb`

### Files Created (1)

- `spec/requests/unified_publication_spec.rb`

### Verification

- 932 RSpec examples, 0 failures
- Rubocop: no new offenses

---

## 2026-03-15 -- OSCAL-Compliant Publication Process (#148)

**Branch:** `feature/148_oscal_publication_process`

### Summary

Adds a standardized publication workflow to all document types (SSP, SAR, SAP,
CDEF, POA&M, Catalog, Profile). Before publishing, OSCAL metadata completeness
is validated (creator role, contact party, responsible-parties). A smart
publication modal shows a readiness checklist with inline fix fields pre-filled
from the current user's profile and organization.

### What Changed

- **PublicationValidationService** -- new service validates metadata completeness
  before publication; auto-populates defaults from user profile and organization
- **Publishable concern** -- shared controller concern providing `publish` and
  `publish_check` actions for SSP, SAR, SAP, CDEF, POA&M, and Catalog controllers
- **Smart publication modal** -- Stimulus controller + shared partial renders a
  readiness checklist with inline fix fields and "Full Metadata Editor" link
- **6 controllers wired up** -- SSP, SAR, SAP, CDEF, POA&M, ControlCatalog
  controllers now include Publishable with publish_config
- **ProfileDocumentsController** -- existing publish action now validates metadata
  and supports inline fixes from the modal; added publish_check endpoint
- **Show pages** -- all 7 document show pages display a Publish button (draft only)
  that opens the smart modal
- **Metadata editor** -- "Pre-fill from my profile" button populates roles/parties
  from current user's display name, email, and organization
- **Routes** -- added `patch :publish` and `get :publish_check` to all document
  types including profiles

### Files Created (5)

- `app/services/publication_validation_service.rb`
- `app/controllers/concerns/publishable.rb`
- `app/javascript/controllers/publish_modal_controller.js`
- `app/views/shared/_publish_button.html.erb`
- `spec/services/publication_validation_service_spec.rb`
- `spec/requests/publication_spec.rb`

### Files Modified (14)

- `config/routes.rb`
- `app/controllers/ssp_documents_controller.rb`
- `app/controllers/sar_documents_controller.rb`
- `app/controllers/sap_documents_controller.rb`
- `app/controllers/cdef_documents_controller.rb`
- `app/controllers/poam_documents_controller.rb`
- `app/controllers/control_catalogs_controller.rb`
- `app/controllers/profile_documents_controller.rb`
- `app/views/ssp_documents/show.html.erb`
- `app/views/sar_documents/show.html.erb`
- `app/views/sap_documents/show.html.erb`
- `app/views/cdef_documents/show.html.erb`
- `app/views/poam_documents/show.html.erb`
- `app/views/control_catalogs/show.html.erb`
- `app/views/profile_documents/show.html.erb`
- `app/views/shared/_oscal_metadata_section.html.erb`

### Verification

- 917 RSpec examples, 0 failures
- Rubocop: no new offenses
- Brakeman: 0 warnings

---

## 2026-03-15 -- Catalog Baseline Management (#177)

**Branch:** `feature/177_extend_catalog_import`

### Summary

Adds the ability for users to assign baseline impact levels (LOW/MODERATE/HIGH)
to catalog controls that lack this data. Supports both per-control inline
editing and bulk selection + assign on the control family page.

### What Changed

- **CatalogControl model** -- added `BASELINE_LEVELS` constant and helper
  methods: `baseline_levels`, `has_baseline_level?`, `add_baseline_level`,
  `remove_baseline_level` for clean comma-separated string manipulation.

- **Controller actions** -- `update_baseline` (single control inline edit) and
  `bulk_update_baselines` (multi-control add/remove/set) on
  `ControlCatalogsController` with `ensure_editable!` and
  `authorize_catalog_write!` guards.

- **Baseline editor Stimulus controller** -- `baseline_editor_controller.js`
  handles inline level toggling via fetch PATCH, bulk checkbox selection,
  select-all, and bulk apply/clear operations.

- **Control family show page** -- "Manage Baselines" toggle reveals inline
  checkboxes per control and a bulk toolbar. Baseline impact displayed as
  colored badges (LOW=green, MODERATE=blue, HIGH=orange) via shared partial.

- **Shared partial** -- `_baseline_badges.html.erb` renders colored badges
  from a `baseline_impact` string. Reusable across views.

- **Tests** -- 25 new specs: model methods (parsing, add, remove, edge cases),
  request specs (inline update, bulk add/remove/set, published guard, auth).

### Notes

- No database migration required -- uses existing `baseline_impact` column.
- No changes to OSCAL export schema -- existing export handles the field.
- Published catalogs are read-only; "Manage Baselines" button hidden.

---

## 2026-03-15 -- Document Lifecycle Status Tracking (#149)

**Branch:** `feature/149_status_tracking`

### Summary

Adds document lifecycle tracking (started / in-progress / published) separate
from the existing processing status. Published documents become read-only.
Catalog traceability shows source catalog name and content digest in profiles.

### What Changed

- **New `Lifecycle` concern** -- shared module included in all 7 document
  models providing lifecycle_status validation, scopes (`draft`,
  `published_lifecycle`), predicate helpers, and `publish_lifecycle!`.

- **Migration** -- adds `lifecycle_status` column (default `"in_progress"`)
  with index to all 7 document tables. Adds `catalog_content_digest` to
  `control_catalogs`. Backfills existing records.

- **Catalog content digest** -- SHA-256 computed on import. Short 8-char
  digest shown in profile views alongside source catalog name.

- **Lifecycle status at entry points** -- profiles created from catalogs
  start as `"started"`, file imports complete as `"in_progress"`, catalogs
  import as `"published"`. Publish action sets `"published"`.

- **Published = read-only** -- all 7 controllers enforce
  `ensure_editable!` before mutation actions. Published profiles show
  "Create Editable Copy" instead of edit buttons.

- **Duplication service** -- copies reset `lifecycle_status` to
  `"in_progress"` and clear `published` timestamp.

- **Lifecycle badges** -- all 7 index views show lifecycle status with
  color-coded badges (started=amber, in-progress=blue, published=green).

- **Audit events** -- added `*_published` actions for all 7 document types.

### Files Created (2)

- `app/models/concerns/lifecycle.rb`
- `db/migrate/20260315180000_add_lifecycle_status_and_catalog_digest.rb`

### Files Modified (25+)

- 7 models (include Lifecycle), 7 controllers (ensure_editable!),
  7 index views (lifecycle badges), profile show view (catalog traceability,
  read-only mode), `document_duplication_service.rb`,
  `document_conversion_job.rb`, `catalog_import_service.rb`,
  `audit_event.rb`, `sparc-theme.css`

---

## 2026-03-15 -- Unified Catalog Import/Export: JSON, YAML, XML Interoperability (#163)

**Branch:** `feature/163_unified_catalog_import_export`

### Summary

Adds OSCAL YAML import support, NIST XML legacy enhancement import,
export enhancement nesting, and import format traceability metadata.
All four supported formats (OSCAL JSON, OSCAL YAML, OSCAL XML, NIST XML
Legacy) now converge to canonical OSCAL-style control IDs and produce
consistent round-trip exports.

### What Changed

- **YAML import** -- `.yaml`/`.yml` files are now accepted. The importer
  parses YAML to a hash, serializes to JSON, and delegates to the
  existing JSON importer for zero code duplication.

- **NIST XML legacy enhancements** -- `<control-enhancement>` elements
  in SCAP SP 800-53 feeds are now imported (previously skipped). IDs
  are converted from NIST format (`AC-2(1)`) to canonical OSCAL
  (`ac-2.1`) with padded sort IDs (`AC-02.01`).

- **Export enhancement nesting** -- OSCAL JSON exports now nest
  enhancements as `controls[]` children of their parent control,
  matching the OSCAL schema requirement.

- **Import format metadata** -- `metadata_extra["import_format"]` is
  now stored on every import (`oscal_json`, `oscal_yaml`, `oscal_xml`,
  or `nist_xml`) for traceability.

- **Import view updated** -- accepts `.yaml`/`.yml`, adds a YAML format
  reference card, and updates hint text.

- **Format comparison table** -- `docs/data_mapping/catalogs.md` now
  documents field availability across all four import formats.

### Files Created (1)

- `spec/fixtures/files/catalogs/nist_legacy_sample.xml`

### Files Modified (6)

- `app/services/catalog_import_service.rb`
- `app/services/oscal_catalog_export_service.rb`
- `app/views/control_catalogs/import.html.erb`
- `spec/services/catalog_import_service_spec.rb`
- `spec/services/oscal_catalog_export_service_spec.rb`
- `docs/data_mapping/catalogs.md`

---

## 2026-03-15 -- Slug-Based URLs for All Resources (#195)

**Branch:** `bug/195_slug_urls`

### Summary

All resource URLs now use human-readable slugs instead of numeric
database IDs. For example, `/control_catalogs/5` becomes
`/control_catalogs/nist-sp-800-53-rev-5`. A shared `Sluggable` concern
handles slug generation, uniqueness, and `to_param` override for all 12
models (including Converter which was refactored to use the concern).

### What Changed

- **New `Sluggable` concern** -- reusable module that auto-generates
  URL-safe slugs from a configurable source field (defaults to `name`,
  Evidence uses `title`). Handles uniqueness collisions with numeric
  suffixes. Overrides `to_param` so all Rails URL helpers automatically
  use slugs.

- **Migration** -- adds `slug` column with unique index to 11 tables
  (control_catalogs, ssp_documents, sar_documents, cdef_documents,
  sap_documents, poam_documents, profile_documents, evidences,
  authorization_boundaries, control_mappings, organizations).
  Backfills existing records from name/title fields.

- **Converter refactored** -- inline slug logic replaced with
  `include Sluggable` concern.

- **All controllers updated** -- `find(params[:id])` replaced with
  `find_by!(slug: params[:id])` across 15 controllers (including
  nested resource parent lookups and admin controllers).

- **DocumentDuplicationService** -- now skips `slug` attribute when
  copying so the duplicate gets a fresh slug.

### Files Created (2)

- `app/models/concerns/sluggable.rb`
- `db/migrate/20260315120000_add_slugs_to_all_models.rb`

### Files Modified (27)

- 11 models: `control_catalog.rb`, `ssp_document.rb`, `sar_document.rb`,
  `cdef_document.rb`, `sap_document.rb`, `poam_document.rb`,
  `profile_document.rb`, `evidence.rb`, `authorization_boundary.rb`,
  `control_mapping.rb`, `organization.rb` (add `include Sluggable`)
- `converter.rb` (refactored to use `Sluggable` concern)
- 14 controllers updated to `find_by!(slug:)`
- `document_duplication_service.rb` (skip slug on copy)

### Verification

- 799 RSpec tests pass
- RuboCop clean
- Brakeman clean

---

## 2026-03-15 -- Home Screen Card Alignment + Converters Card (#192)

**Branch:** `bug/192_home_card_alignment`

### Summary

Fixes inconsistent button alignment across home screen navigation cards
and adds the missing Converters card to the Implementation layer.

### What Changed

- **Button alignment** -- card bodies now use flexbox column layout with
  `mt-auto` on the button container so View/New buttons are consistently
  bottom-aligned across all cards regardless of content height.
- **Larger icons** -- card icons increased from 1.75rem to 2.5rem for
  more visual prominence.
- **Converters card added** -- Implementation layer now includes a
  Converters card with View/New buttons matching the existing pattern.
- **Converters stat tile** -- Implementation stat group in the hero
  banner now shows a Converters count.

### Files Modified (2)

- `app/controllers/home_controller.rb` (add `@converter_count`)
- `app/views/home/index.html.erb` (card alignment, larger icons, Converters card + stat)

### Verification

- 799 RSpec tests pass
- RuboCop clean

---

## 2026-03-15 -- STIG XCCDF Parser + Drag-and-Drop Upload UX (#185)

**Branch:** `feature/185_stig_xccdf_parser`

### Summary

Adds a STIG XCCDF parser as a new converter type (`stig_to_nist`) that
extracts SV/V-ID to CCI to NIST SP 800-53 control mappings from DISA
STIG benchmark files. Each uploaded STIG extends a single cumulative
converter. Also introduces a reusable drag-and-drop file upload
component applied retroactively to all 9 existing upload forms, and
adds slug-based URLs for all converters.

### What Changed

- **New `stig_to_nist` converter type** -- parses XCCDF XML via
  `StigConverterService`, resolves CCI references to NIST controls
  using `cci_to_nist.json`, and creates `ConverterEntry` records.
  Each STIG upload extends the same cumulative converter (duplicates
  skipped).

- **Client-side STIG preview** -- `stig_parser_controller.js` parses
  XCCDF in-browser with DOMParser for instant preview. Includes
  severity filtering, CCI-only toggle, free-text search, and
  CSV/JSON export. Handles XCCDF namespaces 1.0/1.1/1.2.

- **Reusable drag-and-drop upload** -- new `dropzone_controller.js`
  Stimulus controller and `shared/_dropzone.html.erb` partial provide
  drag-drop + browse file upload with extension/size validation,
  file preview, and error display. Applied to all 9 upload forms.

- **Slug-based converter URLs** -- converters now use parameterized
  name slugs (e.g., `/converters/disa-cci-to-nist-sp-800-53` instead
  of `/converters/4`). Migration adds `slug` column with unique index
  and backfills existing records.

- **Navigation** -- added "STIG Parser" link under Implementation
  dropdown in the main navigation.

### Files Created (8)

- `db/migrate/20260315104927_add_slug_to_converters.rb`
- `app/javascript/controllers/dropzone_controller.js`
- `app/views/shared/_dropzone.html.erb`
- `app/services/stig_converter_service.rb`
- `app/javascript/controllers/stig_parser_controller.js`
- `app/views/converters/stig_parser.html.erb`
- `public/data/cci_to_nist.json`
- `spec/services/stig_converter_service_spec.rb`
- `spec/requests/stig_parser_spec.rb`

### Files Modified (16)

- `app/models/converter.rb` (slug, to_param, stig_to_nist type)
- `app/controllers/converters_controller.rb` (slug lookup, stig_parser/import_stig actions)
- `config/routes.rb` (stig_parser + import_stig collection routes)
- `app/assets/stylesheets/sparc-theme.css` (dropzone + STIG parser styles)
- `app/views/layouts/application.html.erb` (STIG Parser nav link)

### Views Updated (9 upload forms retrofitted with dropzone)

- `app/views/ssp_documents/new.html.erb`
- `app/views/sar_documents/new.html.erb`
- `app/views/cdef_documents/new.html.erb`
- `app/views/sap_documents/new.html.erb`
- `app/views/poam_documents/new.html.erb`
- `app/views/profile_documents/new.html.erb`
- `app/views/control_catalogs/import.html.erb`
- `app/views/converters/import.html.erb`
- `app/views/evidences/_form.html.erb`

### What is NOT Changed

- **Existing converter types** -- CCI-to-NIST, CIS-to-NIST, SCAP-to-NIST
  are untouched. STIG parser is additive.
- **No form submission behavior changes** -- dropzone wraps the existing
  `<input type="file">` so all form submissions work identically.
- **No new gems** -- uses existing Nokogiri for server-side XML parsing.

### Verification

- 799 RSpec tests pass (14 new service specs + 5 new request specs)
- RuboCop clean (0 offenses)
- Brakeman clean (0 warnings)

---

## 2026-03-14 -- Enable HTTPS in Development Environment (#134)

**Branch:** `feature/134_https_dev_environment`

### Summary

Added opt-in HTTPS support for the development environment using
mkcert-generated TLS certificates. Developers can enable HTTPS by
running `bin/setup-ssl` once, then starting the server with
`SSL_DEV=true bin/dev`. No new gem dependencies. HTTPS is disabled
by default to preserve the existing HTTP workflow.

### What Changed

- **`bin/setup-ssl`** -- new one-time setup script that installs the
  mkcert local CA and generates certificates in `ssl/` for localhost,
  127.0.0.1, and ::1.

- **Puma SSL binding** -- `config/puma.rb` conditionally binds an
  HTTPS listener on port 3443 when `SSL_DEV=true`, using the mkcert
  certificates. Falls back to HTTP-only when disabled.

- **Rails development config** -- `config/environments/development.rb`
  conditionally enables `force_ssl` and configures SSL redirect
  options (with `/up` health check exclusion and port 3443 redirect)
  when `SSL_DEV=true`. No HSTS in development.

- **`bin/dev`** -- updated to validate certificate existence and
  display HTTPS URL when `SSL_DEV=true`.

- **Docker Compose** -- `docker-compose.yaml` volume-mounts `ssl/`
  (read-only), exposes port 3443, and includes commented `SSL_DEV`
  environment variable.

- **`.gitignore`** -- added `/ssl/` to prevent certificate commits.

- **Documentation** -- new `docs/development-https.md` with full
  setup guide, troubleshooting tips, and usage instructions for both
  local and Docker workflows. Updated `docs/DOCKER.md` with HTTPS
  section.

- **Tests** -- updated `spec/config/https_enforcement_spec.rb` with
  tests for conditional SSL_DEV configuration in Puma and development
  environment. Verified no unconditional force_ssl in development.

### ENV Variables Added

| Variable | Default | Description |
| --- | --- | --- |
| `SSL_DEV` | `false` | Enable HTTPS in development |
| `SSL_PORT` | `3443` | Override HTTPS port |

### Files Created

- `bin/setup-ssl`
- `docs/development-https.md`

### Files Modified

- `config/puma.rb`
- `config/environments/development.rb`
- `bin/dev`
- `docker-compose.yaml`
- `.gitignore`
- `.env.example`
- `.env`
- `docs/ENVIRONMENT_VARIABLES.md`
- `docs/DOCKER.md`
- `spec/config/https_enforcement_spec.rb`

### What is NOT Changed

- **No new gem dependencies** -- mkcert is an external CLI tool
- **HTTP still works** -- port 3000 unchanged when SSL_DEV is unset
- **Production config untouched** -- SSL_DEV is dev-only
- **No database migrations**

### Verification

- `bin/setup-ssl` generates certs in `ssl/`
- `SSL_DEV=true bin/dev` serves HTTPS on port 3443
- `https://localhost:3443` shows green padlock
- `http://localhost:3000` redirects to HTTPS:3443
- `bundle exec rspec` -- all tests pass
- `bundle exec rubocop` -- no offenses

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
