<!-- markdownlint-disable MD013 MD024 MD060 -->

# SPARC Release Notes

---

## 2026-03-21 -- feat: Baseline Parameter and Enumeration Management API (#240)

**Branch:** `feature/229_api_crud_expansion`

### Summary

New `BaselineParameterService` and API controller for managing OSCAL parameters and enumerations
from profile baselines. Endpoints are nested under `profile_documents` in the `/api/v1/` namespace.

### What Changed

- **BaselineParameterService** (`app/services/baseline_parameter_service.rb`) -- extracts OSCAL
  parameters and enumerations from profile baseline resolved catalogs, supports reading, updating,
  and exporting parameter data.
- **BaselineParametersController** (`app/controllers/api/v1/baseline_parameters_controller.rb`) --
  `GET .../parameters` (list parameters), `PUT .../parameters` (update parameters),
  `GET .../parameters/export` (export as JSON/YAML/XML).
- **25 new specs** covering service and controller endpoints.

### Stats

- **Spec count:** 1326 total, 0 failures
- **New files:** 2 (service + controller)

---

## 2026-03-21 -- REST API Phase 2: CRUD for Catalogs, Profiles, CDEFs, Control Mappings (#242)

**Branch:** `feature/229_api_crud_expansion`

### Summary

REST API Phase 2 extends the `/api/v1/` namespace with full CRUD for the remaining OSCAL resource
types: Control Catalogs, Profile Documents, Component Definitions (CDEFs), and Control Mappings.
Bearer token authentication (SPARC tokens + Okta JWT). Admin-only write access on catalogs and
control mappings; all-authenticated access on profiles and CDEFs. Soft-delete support added for
ProfileDocument and CdefDocument.

### What Changed

- **Control Catalogs controller** (`app/controllers/api/v1/control_catalogs_controller.rb`) -- full
  CRUD for catalogs. Admin-only gates on create, update, and destroy. Read-only access for all
  authenticated users.
- **Profile Documents controller** (`app/controllers/api/v1/profile_documents_controller.rb`) -- full
  CRUD with soft-delete. All authenticated users can read and write profiles scoped to their boundary.
- **CDEF Documents controller** (`app/controllers/api/v1/cdef_documents_controller.rb`) -- full CRUD
  with soft-delete. All authenticated users can read and write CDEFs scoped to their boundary.
- **Control Mappings controller** (`app/controllers/api/v1/control_mappings_controller.rb`) -- full
  CRUD for control mappings. Admin-only gates on create, update, and destroy.
- **Soft-delete** -- `SoftDeletable` concern now included in `ProfileDocument` and `CdefDocument`
  models. `deleted_at` column added via migration.
- **Routes** -- added API resource routes for `control_catalogs`, `profile_documents`,
  `cdef_documents`, and `control_mappings` under `/api/v1/`.
- **50 new request specs** -- comprehensive coverage for all 4 controllers: auth (401), admin gates
  (403), boundary-scoped reads, soft-delete, CRUD operations.

### Verification

- `bundle exec rspec spec/requests/api/v1/` -- all API specs pass
- `bundle exec rspec` -- 1301 examples, 0 failures
- Admin-only gates: non-admin users get 403 on catalog/mapping mutations
- Soft-delete: `DELETE` sets `deleted_at` on profiles/CDEFs, subsequent `GET` returns 404

---

## 2026-03-20 -- REST API Phase 1: Full CRUD for SSP, SAR, SAP, POA&M (#229)

**Branch:** `feature/229_api_crud_phase1`

### Summary

Full REST API CRUD endpoints for SSP, SAR, SAP, and POA&M documents with Bearer token
authentication, boundary-scoped RBAC, soft-delete, audit logging, and Okta JWT introspection.
Security fix: rewrote the existing unauthenticated SSP API controller to require Bearer auth.

### What Changed

- **DocumentBaseController** (`app/controllers/api/v1/document_base_controller.rb`) -- shared CRUD
  base for all document API controllers. Provides boundary-scoped index, slug-based lookup, Pagy
  pagination, filtering (status, name, boundary), and audit logging on all mutations.
- **SSP controller rewrite** -- security fix: changed from inheriting `ActionController::API`
  (no auth) to `DocumentBaseController` (requires Bearer token). All existing endpoints
  (`convert`, `update_fields`, `export`) now require authentication. Added `index`, `show`,
  `create`, `update`, `destroy` (soft-delete).
- **SAR controller** (`app/controllers/api/v1/sar_documents_controller.rb`) -- new full CRUD
  controller with legacy `convert`, `update_fields`, `export` actions, now with auth.
- **SAP controller** (`app/controllers/api/v1/sap_documents_controller.rb`) -- new CRUD controller.
- **POA&M controller** (`app/controllers/api/v1/poam_documents_controller.rb`) -- new CRUD controller.
- **SoftDeletable concern** (`app/models/concerns/soft_deletable.rb`) -- `default_scope` excludes
  deleted records; `with_deleted`/`only_deleted` scopes; `soft_delete!`/`restore!` methods.
  Included in all 4 document models.
- **Migration** -- adds `deleted_at` (datetime, indexed) to `ssp_documents`, `sar_documents`,
  `sap_documents`, `poam_documents`.
- **Okta JWT introspection** -- API now accepts two auth methods: SPARC tokens (`sparc_` prefix)
  and Okta-issued JWTs (`eyJ` prefix). JWT validated via RS256 against OIDC provider JWKS
  endpoint. JWKS keys cached in-memory with 1-hour TTL. New env var: `SPARC_API_OIDC_AUDIENCE`.
- **Routes** -- expanded SSP/SAR routes to include full CRUD; added SAP and POA&M resource routes.
- **63 request specs** -- comprehensive coverage for all 4 controllers: auth (401), admin CRUD,
  boundary-scoped reads, permission-gated writes (403), soft-delete, audit events, legacy actions.

### Breaking Change

Existing SSP API endpoints (`convert`, `update_fields`, `export`) now require Bearer token
authentication. Any integrations using unauthenticated access will break. This is intentional --
closing a security gap.

### Verification

- `bundle exec rspec spec/requests/api/v1/` -- 63 examples, 0 failures
- `bundle exec rspec` -- full suite passes
- Boundary scoping: non-admin users see only their boundary's documents
- Soft-delete: `DELETE` sets `deleted_at`, subsequent `GET` returns 404

---

## 2026-03-20 -- Document NIST SP 800-53 Rev 5 Controls Mapping (#217)

**Branch:** `feature/217_nist_rev5_mapping_docs`

### Summary

Comprehensive NIST SP 800-53 Rev 5 HIGH baseline compliance documentation for the SPARC
application. Central mapping document covers all 370 HIGH baseline controls across 20 families,
five OSCAL v1.1.2 component-definition JSON files document application-level implementations,
and inline compliance comments annotate 10 security-critical source files. Includes sparc-iac
alignment via `system-id` in `.github/oscal-metadata.json` for cross-repo FedRAMP SSP assembly.

### What Changed

- **Central mapping document** (`docs/compliance/nist-sp800-53-rev5-mapping.md`) -- 370 controls
  categorized by responsibility (Application, Infrastructure/sparc-iac, CSP Inherited,
  Organizational Policy, Hybrid). Each control includes implementation summary, code/config
  location, and status. Summary: 133 Implemented, 22 Partial, 59 Planned, 28 CSP Inherited, 5 N/A.
- **5 OSCAL CDEFs** in `docs/compliance/oscal/cdefs/`:
  - `component-definition-authentication.json` -- AC-2, AC-3, AC-5, AC-6, AC-7, AC-8, AC-11,
    AC-12, AC-14, AC-17, IA-2, IA-4, IA-5, IA-8, IA-11, IA-12
  - `component-definition-audit.json` -- AU-2, AU-3, AU-4, AU-5, AU-6, AU-8, AU-9, AU-11, AU-12
  - `component-definition-config-mgmt.json` -- CM-2, CM-3, CM-5, CM-6, CM-7, CM-8, CM-11, SA-11, SA-15
  - `component-definition-security-scanning.json` -- RA-5, SI-2, SI-3, SI-4, SI-5, SI-7, SI-10
  - `component-definition-session-mgmt.json` -- SC-8, SC-12, SC-13, SC-23, SC-28
- **Inline NIST control comments** added to 10 security-critical files:
  `authentication.rb`, `authorization.rb`, `api_authentication.rb`, `user.rb`, `api_token.rb`,
  `audit_event.rb`, `sparc_config.rb`, `ldap_auth_service.rb`, `omniauth_callbacks_controller.rb`,
  `production.rb`
- **Compliance README** (`docs/compliance/README.md`) -- Process guide for maintaining compliance
  docs, sparc-iac integration model, security scanning evidence mapping, baseline rationale
- **sparc-iac alignment** -- Added `"system-id": "sparc-application"` to `.github/oscal-metadata.json`
  for cross-repo correlation in FedRAMP SSP assembly pipeline
- **Cross-repo artifact publishing** -- New `publish_for_sparc_iac` job in
  `.github/workflows/security.yml` bundles HDF scan results, OSCAL CDEFs, SBOMs, and metadata
  into a `sparc-compliance-latest` artifact with a `manifest.json` for traceability. Sends a
  `repository_dispatch` (`sparc-compliance-updated`) to `sparc-iac` with the run ID so it can
  fetch artifacts via the GitHub REST API. Requires `SPARC_IAC_DISPATCH_TOKEN` secret.

### Verification

- Documentation and workflow changes only (no application logic changes) -- all existing tests pass
- OSCAL CDEFs follow v1.1.2 component-definition schema with unique UUIDs and code references
- Inline comments are Ruby comment blocks only -- zero functional impact

---

## 2026-03-20 -- Map XCCDF/InSpec SV/V IDs to NIST Control IDs (#213)

**Branch:** `feature/213_xccdf_nist_control_mapping`

### Summary

CDEF imports from XCCDF (DISA STIGs), InSpec profiles, and STIG Viewer JSON now resolve
source-specific identifiers (SV/V IDs) to NIST 800-53 control IDs using a two-tier lookup:
Converter entries first, then CCI-to-NIST fallback. Original SV/V IDs are preserved in a
new `stig_id` column. InSpec NIST tags are normalized to OSCAL dot notation. OSCAL export
metadata no longer includes internal processing state keys.

### What Changed

- **New `CciNistResolvable` concern** -- Shared two-tier NIST resolution for all CDEF parsers:
  - `resolve_nist_for_stig(sv_id, ccis)` -- Converter lookup first, CCI-to-NIST fallback
  - `normalize_nist_tag(tag)` -- InSpec tag normalization (`"CM-6 b"` -> `"cm-6.b"`, `"AC-2 (1)"` -> `"ac-2.1"`)
  - `nist_family_from_id(nist_id)` -- Extract NIST family prefix (e.g., `"CM"` from `"cm-6.b"`)
  - `extract_sv_id(rule_id)` -- Strip revision suffix (`"SV-257777r925318_rule"` -> `"SV-257777"`)
  - Caches Converter entries and CCI lookup data for batch performance
- **XCCDF parser** (`CdefXccdfParserService`) -- Resolves SV->NIST via `extract_sv_id` +
  `resolve_nist_for_stig`, sets `control_id` to NIST ID, preserves original in `stig_id`,
  stores `nist_controls` field when resolution succeeds
- **InSpec parser** (`CdefJsonParserService`) -- Resolves from `tags.nist` first via
  `normalize_nist_tag`, falls back to Converter/CCI resolution
- **STIG Viewer parser** (`CdefJsonParserService`) -- Resolves via `resolve_nist_for_stig`
  using `vuln_num` and `cci_ref`
- **`stig_id` column** -- New column on `cdef_controls` with composite index on
  `(cdef_document_id, stig_id)`. Conditionally included in `to_hash` output
- **CDEF show view** -- Purple `stig_id` badge displayed when different from `control_id`
- **OSCAL CDEF export** -- `stig-id` added as a prop in `build_props`. Internal
  `ProgressTrackable` keys (`processing_stage`, `processing_message`, etc.) stripped from
  export metadata to fix schema validation errors
- **Missing `api_tokens` migration** -- Recovered idempotent migration lost during PR #95
  squash merge, resolving 26 pre-existing test failures

### Files Created/Modified

- `app/services/concerns/cci_nist_resolvable.rb` -- NEW
- `app/services/cdef_xccdf_parser_service.rb` -- Modified `parse_rule` for NIST resolution
- `app/services/cdef_json_parser_service.rb` -- Modified InSpec + STIG Viewer parsers
- `app/models/cdef_control.rb` -- Added `stig_id` to `to_hash`
- `app/services/oscal_component_definition_export_service.rb` -- Strip internal metadata keys, add `stig-id` prop
- `app/views/cdef_documents/show.html.erb` -- Purple `stig_id` badge
- `db/migrate/20260320140536_add_stig_id_to_cdef_controls.rb` -- NEW
- `db/migrate/20260320163212_create_api_tokens.rb` -- NEW (recovered)
- `spec/services/concerns/cci_nist_resolvable_spec.rb` -- NEW (17 tests)
- `spec/services/cdef_xccdf_parser_service_spec.rb` -- 7 new tests
- `spec/services/cdef_json_parser_service_spec.rb` -- 5 new tests
- `spec/fixtures/files/components/test-stig-xccdf.xml` -- NEW fixture

### Verification

- 1207 RSpec examples, 0 failures (29 new + 26 previously failing now fixed)
- Rubocop clean
- OSCAL CDEF export validates against NIST schema
- XCCDF STIG import resolves SV IDs to NIST control IDs
- InSpec profile import normalizes NIST tags to OSCAL format
- STIG Viewer JSON import resolves V IDs to NIST control IDs

---

## 2026-03-20 -- Enhance Catalog Import: Detect & Report Missing Data (#207)

**Branch:** `feature/207_catalog_import_validation`

### Summary

Post-import quality checks now run automatically after catalog imports, detecting missing
required data and displaying actionable warnings in a dismissible modal on the catalog
show page.

### What Changed

- **New `CatalogImportValidationService`** -- Runs 6 quality checks after import:
  - Missing priority designations (P1/P2/P3) on base controls
  - Missing baseline impact levels (LOW/MODERATE/HIGH)
  - Missing control statement text
  - Missing assessment objectives (Rev 5+ catalogs only)
  - Controls referencing parameters with none defined
  - Empty control families (zero controls)
- **Integrated into `CatalogImportJob`** -- Validation runs as a "validating" processing
  stage after import, warnings stored in `metadata_extra["import_warnings"]`
- **Import Quality Report modal** -- Bootstrap 5 modal auto-opens on catalog show page
  after import with warnings. Accordion-grouped by category with severity badges and
  expandable control ID lists. "Acknowledge & Dismiss" persists via PATCH request.
- **New route** -- `PATCH /control_catalogs/:id/acknowledge_warnings`
- **New Stimulus controller** -- `import_warnings_controller.js` for modal lifecycle
- **Filed #237** for future persistent Data Quality card on catalog show page

### Files Created/Modified

- `app/services/catalog_import_validation_service.rb` -- NEW
- `app/jobs/catalog_import_job.rb` -- Added validation call
- `app/views/shared/_import_warnings_modal.html.erb` -- NEW
- `app/javascript/controllers/import_warnings_controller.js` -- NEW
- `app/controllers/control_catalogs_controller.rb` -- Added `acknowledge_warnings`
- `config/routes.rb` -- Added route
- `app/views/control_catalogs/show.html.erb` -- Render modal
- `spec/services/catalog_import_validation_service_spec.rb` -- NEW (13 tests)

### Verification

- 1179 RSpec examples, 0 failures (13 new)
- Rubocop clean
- Re-import a catalog to see quality warnings modal
- Existing import flow unaffected

---

## 2026-03-19 -- Accept Fully Resolved OSCAL Profiles Without Prioritization (#205)

**Branch:** `feature/205_resolved_profile_import`

### Summary

NIST-published resolved profile catalogs (e.g., LOW/MODERATE/HIGH baselines) can now be
uploaded directly as profiles. They are auto-detected, parsed from their catalog structure,
and auto-published without requiring P1/P2/P3 prioritization. Supports JSON, YAML, and XML
formats.

### What Changed

- **Resolved profile detection** -- `ProfileJsonParserService` detects catalog-rooted documents
  with a `resolution-tool` prop or `source-profile` link in metadata and routes them to a
  dedicated parsing path instead of raising "missing profile root key"
- **Resolved catalog parsing** -- Walks `groups[].controls[]` (including nested enhancements)
  to extract control IDs, titles, props, parameters, and guidelines. Stores the entire
  resolved catalog JSON directly in `resolved_catalog_json` (no regeneration needed)
- **Auto-publish** -- `DocumentConversionJob` checks for `auto_publish` flag in metadata_extra
  and sets `lifecycle_status: "published"` with a published timestamp automatically
- **Skip prioritization** -- `publish_check` and `before_publish_lifecycle` in the profile
  controller skip P1/P2/P3 and parameter customization checks for resolved profiles
- **Catalog auto-linking** -- Source catalog matched by revision pattern in the source-profile
  href filename (e.g., "rev5" + "800-53")
- **XML support** -- `ProfileXmlParserService` detects resolved catalog XML, converts to JSON
  hash, and delegates to the JSON parser
- **YAML support** -- Already delegates to JSON parser, gets resolved profile support for free

### Files Created/Modified

- `app/services/profile_json_parser_service.rb` -- resolved profile detection + parsing
- `app/services/profile_xml_parser_service.rb` -- resolved catalog XML detection + conversion
- `app/jobs/document_conversion_job.rb` -- auto-publish on `auto_publish` flag
- `app/controllers/profile_documents_controller.rb` -- skip prioritization for resolved profiles
- `spec/services/profile_resolved_catalog_parser_spec.rb` -- NEW (28 tests)
- `spec/fixtures/files/profiles/small-resolved-profile-catalog.json` -- NEW test fixture

### Verification

- 1166 RSpec examples, 0 failures (28 new)
- Rubocop clean
- Resolved profiles auto-parse, auto-link catalog, auto-publish
- Existing profile upload workflow unaffected

---

## 2026-03-19 -- Fix Control Catalog Index Summary Counts (#203)

**Branch:** `feature/203_catalog_counts`

### Summary

Fixes misleading hero tile counts on the Control Catalogs index page. Families and Controls
tiles now show unique values (distinct family codes and control IDs) instead of totals across
all catalogs. Adds a new "Revisions" tile showing distinct catalog versions.

### What Changed

- **Unique family count** -- `ControlFamily.distinct.count(:code)` replaces `ControlFamily.count`
- **Unique control count** -- `CatalogControl.distinct.count(:control_id)` replaces `CatalogControl.count`
- **New "Revisions" tile** -- shows distinct version strings across all catalogs
- **Updated tile labels** -- "Families" → "Unique Families", "Controls" → "Unique Controls"

### Files Modified

- `app/controllers/control_catalogs_controller.rb` -- unique counts + revision count
- `app/views/control_catalogs/index.html.erb` -- updated tile labels + new Revisions tile

---

## 2026-03-19 -- Container Image Security Remediation (#210)

**Branch:** `feature/210_container_security`

### Summary

Remediates 339 container image CVEs (21 critical, 133 high) identified by the Trivy
security scanning pipeline. Eliminates ~200+ CVEs by removing unused `libvips` and its
transitive dependency chain. Adds local Trivy scanning with HDF output for MITRE SAF
Heimdall compatibility.

### What Changed

- **Removed `libvips` from Dockerfile** -- libvips pulled in ImageMagick, libtiff, libhdf5,
  poppler, OpenJPEG, OpenEXR, libaom, and dozens more packages accounting for ~200+ CVEs.
  The `image_processing` gem was commented out and no Active Storage variant/transformation
  calls exist in the codebase. All file attachments store/serve files as-is.
- **Added `apt-get upgrade -y`** -- picks up Debian security patches for remaining OS
  packages (curl, OpenSSL, glibc, GnuTLS, NSS, expat, SQLite)
- **Pinned `resolv` gem to >= 0.7.0** -- fixes CVE-2025-24294 (ReDoS vulnerability in
  Ruby stdlib bundled 0.6.0)
- **Documented CVE suppressions in `.trivyignore`** -- 3 disputed/false-positive CVEs
  suppressed with inline classification, justification, mitigating controls, and references:
  - CVE-2019-1010022 (DISPUTED -- glibc stack guard bypass, no exploit exists)
  - CVE-2011-3389 (MITIGATED -- BEAST attack, TLS 1.2+ enforced)
  - CVE-2005-2541 (FALSE POSITIVE -- tar setuid behavior, expected per GNU docs)
- **New local Trivy scanning script** (`scripts/trivy-scan.sh`) -- builds Docker image,
  runs Trivy with CI-matching flags, generates CycloneDX SBOM, converts to HDF via SAF
  CLI for MITRE Heimdall viewing. Auto-installs Trivy via direct binary download (no
  brew/apt required).

### Files Created/Modified

- `Dockerfile` -- removed `libvips`, added `apt-get upgrade`
- `Gemfile` / `Gemfile.lock` -- added `resolv >= 0.7.0` pin
- `.trivyignore` -- documented CVE suppressions
- `scripts/trivy-scan.sh` -- NEW local scanning script with HDF output

### Verification

- Docker image builds successfully without libvips
- Local Trivy scan: **0 CRITICAL/HIGH CVEs** (down from 154 critical+high, 339 total)
- 1138 RSpec examples, 0 failures
- File uploads (documents, avatars) unaffected -- no transformation needed

---

## 2026-03-19 -- Squash Migrations to Single Consolidated File (#183)

**Branch:** `feature/183_squash_migrations`

### Summary

Consolidates all 64 database migrations into a single squash migration file.
Prior migrations archived to `db/migrate_archive/` for reference. New environments
should use `bin/rails db:schema:load` (recommended) or `bin/rails db:migrate`.

### What Changed

- **Squash migration** (`20260319100000_squash_migrations_to_current_schema.rb`) --
  loads the complete schema from `db/schema.rb` in a single migration
- **64 archived migrations** moved to `db/migrate_archive/` (preserved for reference)
- Fresh `db:drop db:create db:migrate` creates identical schema from one migration

### Verification

- 1138 RSpec examples, 0 failures (on fresh database from squash)

---

## 2026-03-19 -- Full CRUD API for Users and Authorization Boundaries (#95)

**Branch:** `feature/95_crud_api`

### Summary

Adds REST API endpoints for Users and Authorization Boundaries under `/api/v1/`
with Bearer token authentication, RBAC enforcement, and admin token management UI.

### What Changed

- **API Token Authentication** -- new `api_tokens` table with SHA-256 digest storage,
  `ApiToken` model with secure generation/authentication, `ApiAuthentication` concern
  for Bearer token extraction from Authorization header
- **API Base Controller** -- shared auth, RBAC, JSON error handling, pagination via pagy
- **Users API** (`/api/v1/users`) -- full CRUD with admin-or-self RBAC, paginated list
  with email/name/status filters, detailed view with roles and sign-in history
- **Authorization Boundaries API** (`/api/v1/authorization_boundaries`) -- full CRUD
  with boundary-scoped permissions, non-admins see only assigned boundaries, detailed
  view with artifact summary and environments
- **Admin Token Management** -- generate/revoke API tokens on admin user show page,
  plaintext shown once at creation, optional expiry (30/60/90 days)
- **docs/API.md** -- comprehensive endpoint reference with curl examples

### Files Created (7)

- `db/migrate/20260319000000_create_api_tokens.rb`
- `app/models/api_token.rb`
- `app/controllers/concerns/api_authentication.rb`
- `app/controllers/api/v1/base_controller.rb`
- `app/controllers/api/v1/users_controller.rb`
- `app/controllers/api/v1/authorization_boundaries_controller.rb`
- `app/controllers/admin/api_tokens_controller.rb`

### Verification

- 1138 RSpec examples, 0 failures

---

## 2026-03-19 -- Interactive OSCAL Document Relationship Diagram (#171)

**Branch:** `feature/171_oscal_relationship_diagram`

### Summary

Adds an interactive Mermaid.js-based OSCAL document relationship diagram to the
application, accessible at `/oscal-overview` via the "OSCAL" nav link. The diagram
visually maps all three OSCAL layers (Control, Implementation, Assessment) plus the
Enterprise layer, showing import/traceability relationships between document types.

### What Changed

- **OSCAL Overview page** -- new `/oscal-overview` route with Mermaid flowchart showing
  Catalog, Profile, CDEF, SSP, SAP, SAR, POA&M, Control Mapping, Organization, and
  Authorization Boundary relationships with color-coded layer grouping
- **Mermaid.js CDN** -- conditionally loaded only on pages that request it via
  `content_for :mermaid` (no JS overhead on other pages)
- **Layer description cards** -- three-column summary explaining Control, Implementation,
  and Assessment layers
- **Quick navigation** -- links to all document type index pages
- **Nav link** -- "OSCAL" link added to top navigation bar (desktop only)

### Verification

- 1110 RSpec examples, 0 failures

---

## 2026-03-19 -- OSCAL Data Mapping Documentation & Guidance (#133)

**Branch:** `feature/133_oscal_data_mapping_docs`

### Summary

Comprehensive documentation for OSCAL data mappings across all document types. Creates
a master guide and per-document field mapping references for SSP, SAR, SAP, POA&M, and
CDEF, covering the full import-to-export pipeline.

### What Changed

- **Master guide** (`docs/oscal-data-mapping.md`) -- central reference covering the
  transformation pipeline, document type reference table, three-level model architecture,
  data mapping config files, schema validation, developer guide for adding fields, and
  common validation error troubleshooting
- **SSP mapping** (`docs/data_mapping/ssp.md`) -- field-level mappings for
  system-security-plan including system characteristics, components, users, controls
- **SAR mapping** (`docs/data_mapping/sar.md`) -- enriched vs synthesized export paths,
  results/observations/findings/risks model
- **SAP mapping** (`docs/data_mapping/sap.md`) -- assessment-plan field mappings with
  method assignment (examine/interview/test)
- **POA&M mapping** (`docs/data_mapping/poam.md`) -- plan-of-action-and-milestones with
  PoamItem model (risk status, milestones, remediation)
- **CDEF mapping** (`docs/data_mapping/cdef.md`) -- component-definition with multiple
  import formats (OSCAL, XCCDF/STIG, InSpec)

### Files Created (6)

- `docs/oscal-data-mapping.md`
- `docs/data_mapping/ssp.md`
- `docs/data_mapping/sar.md`
- `docs/data_mapping/sap.md`
- `docs/data_mapping/poam.md`
- `docs/data_mapping/cdef.md`

### Verification

- Documentation only -- no code changes, no test regressions

---

## 2026-03-19 -- Enterprise/Organization Visibility and Navigation (#167)

**Branch:** `feature/167_enterprise_org_visibility`

### Summary

Adds Organization visibility to the homepage and navigation. Renames "Environments"
to "Enterprise" throughout the UI for better semantic clarity in multi-organization
contexts.

### What Changed

- **Homepage stat tiles**: "ENVIRONMENTS" badge renamed to "ENTERPRISE"; Organizations
  count tile added alongside Auth Boundaries
- **Homepage nav grid**: Organizations card (with View/New links to admin org pages)
  added to the left of Auth Boundaries in the Enterprise section
- **Nav header**: "Auth Boundaries" dropdown renamed to "Enterprise" with Organizations
  link (including count badge) and Auth Boundaries sub-section

### Verification

- 1110 RSpec examples, 0 failures

---

## 2026-03-19 -- End-to-End ATO Authorization Package Wizard (#125)

**Branch:** `feature/125_ato_wizard`

### Summary

Adds an 8-step guided wizard for building a complete ATO Authorization Package from
an Authorization Boundary. Users can create new documents or select existing ones at
each step, then download the full package as a ZIP of OSCAL JSON files. This is the
capstone of Phase 3, tying together all OSCAL document types (Profile, CDEFs, SSP,
SAP, SAR, POA&M) into a single traceable package.

### What Changed

- **ATO Package Wizard** -- 8-step single-page form with collapsible sections accessible
  from the Authorization Boundary show page via "Build ATO Package" button. Each step
  offers Create New / Select Existing / Skip options for its document type.

- **AtoPackageService** -- orchestrates document creation and linking in a single
  transaction. Delegates to existing services (SspWizardService, SapGeneratorService,
  SarWizardService) for new document creation. Links all documents to the authorization
  boundary.

- **AtoPackageExportService** -- generates a ZIP bundle containing OSCAL JSON exports
  for all linked documents (ssp.json, sap.json, sar.json, poam-N.json, cdef-slug.json)
  plus a manifest.json with document list and per-document validation status.

- **Authorization Boundary show page** -- "Build ATO Package" and "Download ATO Package"
  buttons added to the action bar. Download button conditionally shown when documents
  are linked.

- **Wizard steps**: (1) Confirm Boundary with role warnings, (2) Select Profile,
  (3) Select CDEFs, (4) SSP, (5) SAP, (6) SAR, (7) POA&M, (8) Review & Submit.

### Files Created (5)

- `app/services/ato_package_service.rb`
- `app/services/ato_package_export_service.rb`
- `app/views/authorization_boundaries/ato_wizard.html.erb`
- `spec/services/ato_package_service_spec.rb`
- `spec/services/ato_package_export_service_spec.rb`

### Files Modified (4)

- `app/controllers/authorization_boundaries_controller.rb` (3 new actions)
- `app/views/authorization_boundaries/show.html.erb` (buttons)
- `config/routes.rb` (3 new member routes)
- `spec/requests/authorization_boundaries_spec.rb` (new request specs)

### Verification

- 1110 RSpec examples, 0 failures
- RuboCop clean

---

## 2026-03-18 -- SAR Creation from Profile/SSP, SAP Assessment Improvements (#174)

**Branch:** `feature/174_sar_oscal_import`

### Summary

Adds "Create SAR from Published Profile" and "Create SAR from Existing SSP" workflows,
completing the Phase 3 entity creation trilogy (CDEF #172, SSP #173, SAR #174). Also
improves the SAP (Security Assessment Plan) control edit with auto-populated assessor
name and assessment objectives from NIST catalog data, auto-populating baseline profile
when SSP is selected in the wizard, and collapsible family grouping on the SAP show page.

### What Changed

- **SAR creation from Published Profile** -- new `SarFromProfileService` creates a SAR
  from a published profile's resolved catalog with pre-populated assessment placeholder
  fields (result, working_status, notes_weakness, recommended_fix, working_comments, date)
  and default SarResult/SarFinding records per control.

- **SAR creation from Existing SSP** -- new `SarFromSspService` copies SSP controls into
  SAR controls with read-only context fields (stated_requirement, description, ssp_status)
  and editable assessment fields. Inherits profile_document_id from SSP for traceability.

- **Migration** -- adds `profile_document_id` and `ssp_document_id` FK columns to
  `sar_documents` for source traceability.

- **SAP control edit improvements** -- Assessor Name auto-populates from the logged-in
  user. Assessment Objective auto-populates from catalog assessment data (Rev 5 objectives
  preferred, then Rev 4/5 assessment methods, then statement/guidance fallback).

- **SAP wizard SSP-Profile auto-link** -- selecting an SSP in the SAP creation wizard now
  auto-populates the Baseline Profile dropdown with the profile the SSP was built from.

- **OSCAL assessment data capture** -- `CatalogImportService` now extracts assessment
  objectives (Rev 5 nested `assessment-objective` parts) and assessment methods (Rev 4
  `assessment` / Rev 5 `assessment-method` parts with EXAMINE/INTERVIEW/TEST + objects)
  into `guidance_data` during catalog import.

- **SAP collapsible family grouping** -- SAP show page now groups controls by family in
  collapsible sections with Expand All / Collapse All buttons, matching SSP and Profile.

- **Updated SAR new page** -- "Create from Published Profile" and "Create from Existing
  SSP" cards with OSCAL format reference table.

- **Deletion dependency tracking** -- SSP and Profile deletion_dependencies now warn
  about linked SAR documents.

### Files Created (6)

- `db/migrate/20260318000000_add_profile_and_ssp_to_sar_documents.rb`
- `app/services/sar_from_profile_service.rb`
- `app/services/sar_from_ssp_service.rb`
- `app/views/sar_documents/select_profile.html.erb`
- `app/views/sar_documents/select_ssp.html.erb`
- `docs/regression_testing/regression_plan.md` (tracked)

### Files Modified (10)

- `app/models/sar_document.rb` (associations, creation_method expansion)
- `app/models/ssp_document.rb` (has_many :sar_documents, deletion_dependencies)
- `app/models/profile_document.rb` (deletion_dependencies for SAR)
- `app/controllers/sar_documents_controller.rb` (4 new actions)
- `app/controllers/sap_documents_controller.rb` (family grouping)
- `app/services/catalog_import_service.rb` (assessment data extraction)
- `app/views/sar_documents/new.html.erb` (creation cards, format table)
- `app/views/sap_documents/new.html.erb` (SSP-Profile auto-link)
- `app/views/sap_documents/show.html.erb` (family grouping, objective/assessor defaults)
- `config/routes.rb` (4 new SAR collection routes)

### Verification

- 1073 RSpec examples, 0 failures
- RuboCop clean

---

## 2026-03-18 -- SSP OSCAL Import, Create from Profile & Unified Export Validation (#173)

**Branch:** `feature/173_ssp_oscal_import`

### Summary

Adds SSP OSCAL import (JSON/YAML/XML), "Create SSP from Published Profile" workflow,
OSCAL UUID regeneration on content change (per NIST spec), unified OSCAL export
validation modal across all document types, and SSP enrichment card edit links.

### What Changed

- **SSP OSCAL import** -- parse OSCAL SSP files in JSON, YAML, and XML formats into
  the SspDocument model with controls and fields. Collapsible family grouping on the
  show page for better navigation of large control sets.

- **"Create from Published Profile" flow** -- new UI on the SSP creation page allows
  users to select a published profile and generate an SSP. Controls, statements, and
  guidance are pre-populated from the profile's resolved catalog.

- **SspFromProfileService** -- new service converts a profile's `resolved_catalog_json`
  into an SspDocument with controls, fields, a "this-system" component, default
  information type, and default user. SspByComponent records link each control to the
  this-system component with `implementation_status: "planned"`.

- **Editable placeholder fields** -- generated SSPs include editable `status` (defaulting
  to "Deferred"), `control_type`, `responsible_entities`, `implementation_statement`,
  `implementation_summary`, and `notes` fields. Read-only `stated_requirement` and
  `description` fields are pre-populated from catalog data.

- **New `creation_method: "profile"`** -- SspDocument model now supports a `profile`
  creation method distinct from `wizard` and `oscal_import`, with a `profile_created?`
  convenience method.

- **OSCAL UUID regeneration on content change** -- per NIST OSCAL spec, the root UUID
  and last-modified timestamp now regenerate when document content is saved (not on
  export). `regenerate_oscal_uuid!` method added to OscalMetadata concern, called from
  all content modification paths (update, update_metadata, update_enrich, update_controls,
  publish) across all 6 document types. Uses `update_column` to bypass the immutability
  guard. Includes column existence check for models without UUID column (e.g., ControlCatalog).

- **Unified OSCAL export validation modal** -- replaces per-document validated/unvalidated
  export dropdowns with a reusable pattern across all 7 document types:
  - `OscalExportable` concern provides shared `validate_oscal_export` JSON endpoint
  - `oscal_export_controller.js` Stimulus controller intercepts export clicks, validates
    via fetch, and shows a Bootstrap modal if validation fails
  - `_oscal_export_dropdown.html.erb` shared partial used by all show views
  - Modal displays document type, first 5 validation errors, and Cancel/Continue buttons
  - Continue downloads the unvalidated file; YAML/XML use `?skip_validation=true` param

- **SSP enrichment card edit links** -- System Characteristics, Components, and Users
  cards on the SSP show page now have edit links back to the enrich page (signed-in
  users on draft documents only).

- **Updated SSP new page** -- "Create from Published Profile" card and supported formats
  table added to the SSP upload page, matching the CDEF pattern.

### Files Created (3)

- `app/controllers/concerns/oscal_exportable.rb`
- `app/javascript/controllers/oscal_export_controller.js`
- `app/views/shared/_oscal_export_dropdown.html.erb`

### Files Modified (19)

- `app/controllers/ssp_documents_controller.rb` (OscalExportable, UUID regen, edit links)
- `app/controllers/sar_documents_controller.rb` (OscalExportable, UUID regen)
- `app/controllers/cdef_documents_controller.rb` (OscalExportable, UUID regen)
- `app/controllers/profile_documents_controller.rb` (OscalExportable, UUID regen)
- `app/controllers/sap_documents_controller.rb` (OscalExportable, UUID regen)
- `app/controllers/poam_documents_controller.rb` (OscalExportable, UUID regen)
- `app/controllers/control_catalogs_controller.rb` (OscalExportable, skip_validation)
- `app/controllers/concerns/publishable.rb` (UUID regen before publish)
- `app/models/concerns/oscal_metadata.rb` (regenerate_oscal_uuid! method)
- `app/models/ssp_document.rb` (creation_method: "profile")
- `app/services/oscal_ssp_export_service.rb` (use stored UUID, not random)
- `app/services/ssp_update_service.rb` (UUID regen on control updates)
- `app/views/ssp_documents/show.html.erb` (edit links, shared export dropdown)
- `app/views/sar_documents/show.html.erb` (shared export dropdown)
- `app/views/cdef_documents/show.html.erb` (shared export dropdown)
- `app/views/profile_documents/show.html.erb` (shared export dropdown)
- `app/views/sap_documents/show.html.erb` (shared export dropdown)
- `app/views/poam_documents/show.html.erb` (shared export dropdown)
- `app/views/control_catalogs/show.html.erb` (shared export dropdown)
- `app/views/control_catalogs/index.html.erb` (shared export dropdown)
- `config/routes.rb` (validate_oscal_export routes for all doc types)

### New Specs

- `SspFromProfileService`, `SspJsonParserService`, `SspXmlParserService` service specs
- Request spec additions for `select_profile` and `create_from_profile`

### Verification

- 1034 RSpec examples, 0 failures
- RuboCop clean

---

## 2026-03-16 -- CDEF Creation and Import in OSCAL Format (#172)

**Branch:** `feature/172_cdef_creation_import`

### Summary

Adds full Component Definition (CDEF) creation and import support in OSCAL format.
XML uploads now auto-detect between XCCDF Benchmark and OSCAL component-definition
formats. A new "Create from Published Profile" flow generates CDEFs from a profile's
resolved catalog with pre-populated controls, parameters, and guidance.

### What Changed

- **OSCAL XML auto-detection in XCCDF parser** -- `.xml` file uploads now
  auto-detect whether the file is a XCCDF Benchmark or an OSCAL
  component-definition, routing to the correct parser automatically.

- **Full OSCAL component-definition import** -- supports JSON, YAML, and XML
  formats for importing OSCAL component-definition documents into CdefDocument
  records with controls and fields.

- **"Create from Published Profile" flow** -- new UI allows users to generate
  a CDEF from any published profile's resolved catalog. Controls, parameters,
  and guidance are pre-populated from the profile data.

- **CdefFromProfileService** -- new service converts a profile's
  `resolved_catalog_json` into a CdefDocument with controls and fields,
  mapping profile priorities to severity levels (P1=high, P2=medium, P3=low).

- **Editable placeholder fields** -- generated CDEFs include editable
  `implementation_narrative`, `notes`, and `status_override` fields for
  user customization.

- **41 new tests** -- brings total to 1001. Includes NIST sample fixtures
  for OSCAL component definitions across JSON, YAML, and XML formats.

### Verification

- 1001 RSpec examples, 0 failures
- RuboCop clean
- Brakeman clean

---

## 2026-03-15 -- Login Consent/Warning Banner (#190)

**Branch:** `feature/190_login_consent_banner`

### Summary

Adds a mandatory consent/warning banner modal to the login page. The banner
is configurable via environment variables and displays sanitized HTML content
loaded from an external file. Users must acknowledge the banner before
accessing the login form.

### What Changed

- **Consent banner modal** -- a Bootstrap 5 modal displays on the login page
  when enabled. Users must click "Proceed" to access the login form or
  "Cancel" to be denied access.

- **Environment variable configuration** -- `SPARC_BANNER_ENABLED` controls
  whether the banner is shown (default: disabled). `SPARC_BANNER_MESSAGE`
  specifies the path to an external HTML file containing the banner content.

- **XSS-safe content loading** -- banner HTML is loaded from the configured
  external file and sanitized before rendering to prevent cross-site
  scripting attacks.

### ENV Variables

| Variable | Default | Description |
| --- | --- | --- |
| `SPARC_BANNER_ENABLED` | `false` | Enable the login consent banner |
| `SPARC_BANNER_MESSAGE` | (none) | Path to external HTML file with banner content |

### Verification

- Banner displays when `SPARC_BANNER_ENABLED=true` and valid HTML file path provided
- "Proceed" grants access to the login form
- "Cancel" denies access
- Banner content is sanitized against XSS
- Banner does not appear when disabled

---

## 2026-03-15 -- Homepage Card Layout Redesign (#200)

**Branch:** `feature/200_homepage_horizontal_layout`

### Summary

Redesigns the homepage navigation cards from a vertical 5-column grid to a
horizontal 3-column layout. Cards now display icon, title, and action buttons
in a single row for improved scannability and a more professional appearance.

### What Changed

- **3-column responsive grid** -- Cards display 3 per row on desktop, 2 on
  tablet, and 1 on mobile (was 5/3/2).

- **Horizontal card layout** -- Each card shows icon (left), title (center),
  and View/New buttons (right) in a single row instead of vertically stacked.

- **Left-accent border** -- Cards use a 3px left border with the OSCAL layer
  color instead of the previous 2px full border for a cleaner visual accent.

- **Compact spacing** -- Reduced card padding and layer group margins for a
  tighter, more scannable layout.

### Files Modified

| File | Change |
|------|--------|
| `app/views/home/index.html.erb` | Grid columns, card body layout, spacing |
| `app/assets/stylesheets/sparc-theme.css` | Card border style (left-accent) |

### Also Included

- Marked #185 (STIG XCCDF parser) as completed in `docs/Implemenation_plan.md`

---

## 2026-03-15 -- Unified Hybrid Security Scanning Pipeline (#186)

**Branch:** `feature/186_hybrid_security_scanning`

### Summary

Consolidates all security scanning into a single unified GitHub Actions workflow
(`security.yml`) with 11 jobs, MITRE SAF CLI HDF normalization, and OSCAL metadata
enrichment. Brakeman and CodeQL run as always-on SAST scanners for maximum depth
and breadth. Semgrep is available as an opt-in via workflow_dispatch. All scan
outputs are normalized to Heimdall Data Format (HDF) for consistent visualization
and compliance reporting.

### What Changed

- **Unified security workflow** -- replaced the previous `security.yml` with a
  comprehensive 11-job pipeline: 9 parallel scan jobs, 1 HDF normalization job,
  and 1 bundle/summary job.

- **Always-on SAST scanners** -- Brakeman (Rails-specific, fast) and CodeQL
  (deep semantic analysis, Ruby + JavaScript/TypeScript) run on every PR, push
  to main, and weekly schedule. CodeQL produces per-language SARIF files merged
  into a single artifact via `jq`. Replaces GitHub's default CodeQL setup.

- **Optional Semgrep** -- pattern-based SAST with Ruby/Rails rulesets, enabled
  via `run_semgrep` boolean input on manual workflow_dispatch triggers.

- **Trivy multi-format output** -- filesystem and container image scans produce
  three output formats each: SARIF (for GitHub Code Scanning), ASFF (for SAF CLI
  `trivy2hdf` conversion), and CycloneDX (for `cyclonedx_sbom2hdf` conversion).

- **MITRE SAF CLI HDF normalization** -- all scan outputs converted to HDF via
  `mitre/saf_action@v1` GitHub Action. Conversion map:
  - SARIF (Gitleaks, Brakeman, CodeQL, Semgrep, Trivy FS) -> `sarif2hdf`
  - ASFF (Trivy Container) -> `trivy2hdf`
  - CycloneDX (Trivy FS SBOM, Trivy Container SBOM, Ruby SBOM) -> `cyclonedx_sbom2hdf`

- **OSCAL metadata enrichment** -- each HDF file supplemented with OSCAL v1.1.2
  metadata via SAF CLI `supplement passthrough write`, sourcing from
  `.github/oscal-metadata.json` (organization party, scanner/preparer roles,
  responsible-parties).

- **Bundle and summary** -- `bundle_results` job creates organized ZIP archive
  (`hdf/`, `sarif/`, `sbom/`, `asff/` directories), generates GitHub Step Summary
  via `saf view summary`, and evaluates configurable severity threshold gate.

- **Removed scanning from ci.yml** -- `scan_ruby` and `scan_js` jobs removed
  from CI workflow. `ci.yml` now only runs `lint` and `test`.

- **Configurable inputs** -- `workflow_dispatch` supports `run_semgrep`,
  `rails_app_path`, `dockerfile_path`, `org_metadata_file`, `fail_on_severity`,
  and `upload_to_code_scanning`.

- **Error resilience** -- all scan steps use `continue-on-error: true`. Missing
  artifacts produce `::warning::` annotations, not failures. Only the severity
  threshold in `bundle_results` is a hard failure point.

- **Security findings issue** -- initial scan results analyzed and documented in
  issue #210 (339 container image CVEs, 1 suppressed SAST finding).

### Files Created (3)

- `.github/oscal-metadata.json`
- `docs/security-scanning.md`
- `.gitignore` entry for `/docs/hdf/`

### Files Modified (2)

- `.github/workflows/security.yml` (replaced -- unified 11-job pipeline)
- `.github/workflows/ci.yml` (removed `scan_ruby` and `scan_js` jobs)

### Artifacts Produced (per run)

| Artifact | Contents | Retention |
|----------|----------|-----------|
| `gitleaks-sarif` | Gitleaks SARIF | 90 days |
| `brakeman-sarif` | Brakeman SARIF | 90 days |
| `codeql-sarif` | CodeQL merged multi-language SARIF | 90 days |
| `semgrep-sarif` | Semgrep SARIF (when enabled) | 90 days |
| `bundler-audit-json` | bundler-audit JSON | 90 days |
| `trivy-fs-results` | Trivy FS SARIF + CycloneDX | 90 days |
| `trivy-container-results` | Trivy container SARIF + ASFF + CycloneDX | 90 days |
| `sbom-cyclonedx` | Ruby CycloneDX SBOM | 90 days |
| `hdf-results` | All HDF files with OSCAL metadata | 90 days |
| `security-scan-archive` | Combined ZIP of all results | 90 days |

### What is NOT Changed

- **No application code changes** -- CI/CD pipeline only
- **No database migrations**
- **No new gems or dependencies**
- **Production deployment untouched**

### Verification

- All 9 parallel scan jobs complete successfully
- HDF normalization converts all scan outputs
- OSCAL metadata injected into HDF files
- ZIP archive and GitHub Step Summary generated
- SARIF uploads appear in GitHub Code Scanning tab

---

## 2026-03-15 -- Published Profile Creation from Baseline (#175)

**Branch:** `feature/175_published_profile_from_baseline`

### Summary

Delivers the complete baseline-to-published-profile workflow, providing reliable
published profiles with proper OSCAL references, auto-assigned priorities, and
populated parameters for downstream consumption by CDEFs (#172) and SSPs (#173).

### What Changed

- **Auto-priority assignment** -- new `ProfilePriorityAssignmentService` assigns
  P1/P2/P3 to controls when creating a profile from a catalog baseline. Uses
  explicit catalog priority if available (P1/P2/P3), otherwise applies a
  heuristic based on baseline breadth (3 levels→P1, 2→P2, 1 or 0→P3). Applied
  on both initial creation and when adding controls later.

- **Profile-from-Profile creation (tailoring)** -- new `select_profile` and
  `create_from_profile` actions let users create a tailored profile from any
  published profile. Uses `DocumentDuplicationService` to clone controls and
  fields, sets `source_profile_id` for lineage tracking. "Create from Profile"
  button added to the profile index page.

- **Parameter completeness block on publish** -- `publish_check` now detects
  parameters that still match their default catalog labels. When uncustomized
  parameters exist, a blocking modal popup (matching the prioritization warning
  pattern) prevents the publish modal from opening until all parameters are
  reviewed.

- **OSCAL back-matter source references** -- Profile OSCAL exports now include
  the source catalog as a back-matter resource with proper `oscal_uuid` reference.
  Import hrefs use `#<catalog-oscal-uuid>` instead of `"#"` placeholder. Resolved
  profile catalogs include source profile and catalog resources in back-matter,
  and the source-profile link uses the actual profile UUID.

- **Migration** -- adds `source_profile_id` self-referencing FK on
  `profile_documents` for profile lineage. Adds `oscal_uuid` column on
  `control_catalogs` for reliable OSCAL cross-referencing (backfilled from
  `metadata_extra["catalog_uuid"]`).

- **Catalog import** -- `CatalogImportService` now sets the `oscal_uuid` column
  from the imported catalog's UUID for all import formats.

### Files Created (4)

- `db/migrate/20260315200000_add_profile_lineage_and_catalog_oscal_uuid.rb`
- `app/services/profile_priority_assignment_service.rb`
- `spec/services/profile_priority_assignment_service_spec.rb`
- `app/views/profile_documents/select_profile.html.erb`

### Files Modified (10)

- `app/controllers/profile_documents_controller.rb`
- `app/models/profile_document.rb`
- `config/routes.rb`
- `app/views/profile_documents/index.html.erb`
- `app/views/profile_documents/show.html.erb`
- `app/javascript/controllers/publish_modal_controller.js`
- `app/services/oscal_profile_export_service.rb`
- `app/services/oscal_resolved_profile_catalog_service.rb`
- `app/services/catalog_import_service.rb`
- `spec/requests/unified_publication_spec.rb`

### Verification

- All RSpec tests pass
- RuboCop clean (0 offenses)

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
