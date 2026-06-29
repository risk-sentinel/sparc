# SPARC Developer Collision Avoidance Plan

Companion to `Implemenation_plan.md`. Maps every issue to exact
files/domains, assigns developer lanes, and defines branching rules
so 3-5 developers can work in parallel without stepping on each
other.

**Last updated:** 2026-06-29 (v1.10.0 in progress — #682 header bar + #680 Phase 1 resolver + #672 index search + rubyzip #681, one bundled release branch `feature/v1.10.0_header_resolver_search`)

---

## 1. Domain Ownership Map

The codebase divides into **15 isolated domains** (#509–#515 added two
v1.7.0 hardening lanes — Upload Security and Transport/Session
Hardening — that didn't exist when this map was first drawn). Each
issue is assigned to exactly one primary domain. A developer "owns"
a domain lane for a sprint.

<!-- markdownlint-disable MD013 -->

| Domain | Key Files | Primary Owner |
| ------ | --------- | ------------- |
| **Catalog** | `catalog_import_service`, `catalog_builder_service`, `control_catalog.rb`, `catalog_control.rb`, `control_family.rb`, `control_catalogs_controller`, `catalog_controls_controller`, views under `control_catalogs/`, `catalog_controls/` | Dev A |
| **Profile** | `profile_document.rb`, `profile_control.rb`, `profile_documents_controller`, `oscal_profile_export_service`, `oscal_resolved_profile_catalog_service`, views under `profile_documents/`, `profile_controls/` | Dev B |
| **SSP** | `ssp_document.rb`, `ssp_control.rb`, `ssp_documents_controller`, `ssp_wizard_service`, `ssp_*_parser_service`, `oscal_ssp_export_service`, views under `ssp_documents/` | Dev C |
| **SAR** | `sar_document.rb`, `sar_control.rb`, `sar_control_objective.rb`, `sar_finding.rb`, `sar_documents_controller`, `sar_wizard_service`, `sar_*_parser_service`, `oscal_sar_export_service`, `control_objective_extractor_service`, views under `sar_documents/` (incl. `_objectives_table.html.erb`) | Dev C |
| **CDEF** | `cdef_document.rb`, `cdef_control.rb`, `cdef_documents_controller`, `cdef_*_parser_service`, `oscal_component_definition_export_service`, views under `cdef_documents/` | Dev B |
| **Converters** | `converter.rb`, `converter_entry.rb`, `converters_controller.rb`, `cci_refresh_service.rb`, `framework_mapping_generator_service.rb`, views under `converters/` | Dev A |
| **POAM/SAP** | `poam_document.rb`, `sap_document.rb`, `sap_control.rb`, `sap_control_objective.rb`, related controllers/services, `control_objective_extractor_service`, views under `sap_documents/` (incl. `_objectives_table.html.erb`) | Dev C |
| **Auth/Users** | `user.rb`, `role.rb`, `identity.rb`, sessions, registrations, `admin/*` controllers | Dev D |
| **Boundary/Org** | `authorization_boundary.rb`, `organization.rb`, boundary controllers, admin org views | Dev D |
| **Evidence** | `evidence.rb`, `attestation.rb`, `evidences_controller` | Dev D |
| **API (v1)** | `api/v1/*_controller.rb`, API serializers, API auth middleware | Dev D |
| **CI/Infrastructure** | `.github/workflows/`, `docker-compose.yaml`, `Dockerfile`, CI pipelines, `.github/CODEOWNERS`, `.github/required-checks.json` | Dev E |
| **Upload Security** | `lib/xml_security.rb`, `app/controllers/concerns/file_uploadable.rb`, `app/models/concerns/attachment_size_limit.rb`, magic-byte detection logic, zip-bomb checks, executable-signature deny-list. Touches every upload entry point — coordinate with parser services. | Dev D (owns auth) — share lane with Dev E (uploads cross deploy infra) |
| **Transport/Session Hardening** | `config/initializers/content_security_policy.rb`, `config/initializers/rack_attack.rb`, `config/initializers/session_store.rb` (comment-only protective file), `config/environments/production.rb` userdata host wiring, `SparcConfig` rate-limit + userdata accessors | Dev E (deploy posture) |
| **Shared/Cross-cutting** | `OscalMetadata` concern, `oscal_schema_validation_service`, `document_duplication_service`, `application.html.erb` layout, `_processing_banner.html.erb` (#548), shared partials, routes, Stimulus controllers, `db/migrate/`, `app/models/sparc_config.rb` (every new env-var lands here) | Requires PR review from 2 devs |

<!-- markdownlint-enable MD013 -->

---

## 2. Issue-to-Domain Assignment with File Collision Risk

### Phase 1 -- All issues are collision-safe (different domains)

<!-- markdownlint-disable MD013 -->

| Status | Issue | Domain | Files Modified | Collision Risk |
| ------ | ----- | ------ | -------------- | -------------- |
| [x] | **#142** Background upload UX | Shared (Jobs) | `document_conversion_job.rb`, `catalog_import_job.rb`, new `ProgressTrackable` concern, shared `_processing_banner.html.erb` partial, all 20 parser services, all 7 show views, all 7 index views | **LOW** -- touches job infra, not domain logic |
| [x] | **#178** Safe delete | Shared (Models) | New `SafeDestroyable` concern, `before_destroy` callbacks across all 7 document models, all 7 controllers (safe destroy pattern), `audit_event.rb` (7 new actions), `application.js` (Turbo confirm modal), 9 views (turbo_confirm normalization) | **LOW** -- adds callbacks, doesn't change business logic |
| [x] | **#100** Regression testing | Testing | `spec/` directory (new files), `Gemfile`, `.github/workflows/`, `spec_helper.rb` | **NONE** -- additive only, own directory |
| [x] | **#134** HTTPS dev | Infrastructure | `config/puma.rb`, `config/environments/development.rb`, `docker-compose.yaml`, `bin/setup-ssl`, `bin/dev` | **NONE** -- config files only |

<!-- markdownlint-enable MD013 -->

**Phase 1 Parallelism: All 4 issues can run simultaneously
with 4 developers.**

```bash
Dev A: #142 (background upload UX)
Dev B: #178 (safe delete confirmations)
Dev C: #100 (regression test suite)
Dev D: #134 (HTTPS dev environment)
```

> **Merge order:** #134 first (config only), then #100
> (test infra), then #142 and #178 (no conflict).

---

### Phase 2 -- Internal dependency chain requires ordering

<!-- markdownlint-disable MD013 -->

| Status | Issue | Domain | Files Modified | Collision Risk |
| ------ | ----- | ------ | -------------- | -------------- |
| [x] | **#163** Format interop | Catalog | `catalog_import_service.rb`, `oscal_catalog_export_service.rb`, `control_catalogs/import.html.erb`, `docs/data_mapping/catalogs.md` | **NONE** with non-Catalog work -- **COMPLETED 2026-03-15** |
| [x] | **#177** Catalog locking/SHA -- **COMPLETED 2026-03-15** | Catalog | `catalog_import_service.rb`, `control_catalog.rb`, `catalog_control.rb`, catalog views | **HIGH with #163** -- same files |
| [x] | **#149** Status tracking | Shared (Models) | All 7 models (Lifecycle concern), all 7 controllers (ensure_editable! guard), all index/show views (lifecycle badges), `document_duplication_service.rb`, `document_conversion_job.rb`, `catalog_import_service.rb` | **NONE** remaining -- **COMPLETED 2026-03-15** |
| [x] | **#148** Publication metadata -- **COMPLETED 2026-03-15** | Shared (Services) | All document controllers (publish action), `publication_validation_service.rb`, `publishable.rb` concern, `publish_modal_controller.js`, shared publish button/modal partials | **NONE** remaining |
| [x] | **#176** Profile/CDEF publish -- **COMPLETED 2026-03-15** | Profile + CDEF | `profile_documents_controller.rb` (refactored to Publishable), `cdef_documents/show.html.erb`, `publishable.rb` concern (hook + version) | **NONE** remaining |

<!-- markdownlint-enable MD013 -->

**Phase 2 Parallelism Strategy:**

```bash
Sprint 2a (weeks 1-3):
  Dev A: #163 (catalog format interop) -- Catalog domain, solo
  Dev B: #149 (status tracking)        -- Cross-cutting, additive
  Dev C: free for #100 overflow / spec writing

Sprint 2b (weeks 3-6):
  Dev A: #177 (catalog locking/SHA)    -- AFTER #163 merges
  Dev B: #148 (publication metadata)   -- AFTER #149 merges
  Dev C: #176 (profile/CDEF publish)   -- AFTER #149 merges
```

> **Critical rule:** #163 must merge before #177 starts
> (same files). #149 must merge before #148 and #176 start.

---

### Phase 3 -- Entity creation, STIG parsing & ATO Wizard

<!-- markdownlint-disable MD013 -->

| Status | Issue | Domain | Files Modified | Collision Risk |
| ------ | ----- | ------ | -------------- | -------------- |
| [x] | **#175** Profile from baseline -- **COMPLETED 2026-03-15** | Profile | `profile_documents_controller.rb`, `profile_document.rb`, profile views, `oscal_profile_export_service.rb`, `oscal_resolved_profile_catalog_service.rb`, `catalog_import_service.rb` | **NONE** with SSP/SAR/CDEF work |
| [x] | **#185** STIG SV/V to CCI parser + drag-drop UX | Converters + Shared | New `StigConverterService`, `stig_parser_controller.js`, `dropzone_controller.js`, `_dropzone.html.erb`, `stig_parser.html.erb`, `converters_controller` (new actions), slug migration, `converter.rb` (slug + stig_to_nist type), all 9 upload views retrofitted | **NONE** with Profile/SSP/SAR -- different domain |
| [x] | **#172** CDEF from Profile -- **COMPLETED 2026-03-16** | CDEF | `cdef_documents_controller.rb`, `cdef_document.rb`, new `CdefFromProfileService`, CDEF views | **NONE** with SSP/SAR work; uses #185 for validation |
| [x] | **#173** SSP from Profile -- **COMPLETED 2026-03-18** | SSP + Shared | `ssp_documents_controller.rb`, `ssp_document.rb`, new `SspFromProfileService`, SSP views, `config/routes.rb`, new `OscalExportable` concern, `oscal_export_controller.js`, `_oscal_export_dropdown.html.erb`, all 7 show views (export dropdown), all 7 controllers (UUID regen + export validation), `oscal_metadata.rb` (regenerate_oscal_uuid!), `publishable.rb` (UUID regen) | **NONE** remaining |
| [x] | **#174** SAR from Profile/SSP -- **COMPLETED 2026-03-18** | SAR + SAP + Catalog | `sar_documents_controller.rb`, `sar_document.rb`, new `SarFromProfileService`, `SarFromSspService`, SAR views, `sap_documents_controller.rb`, SAP views (family grouping, edit defaults), `catalog_import_service.rb` (assessment data), `config/routes.rb`, migration | **NONE** remaining |
| [x] | **#125** ATO Wizard -- **COMPLETED 2026-03-19** | AuthBoundary + Shared | `authorization_boundaries_controller.rb` (3 new actions), new `AtoPackageService`, `AtoPackageExportService`, `ato_wizard.html.erb`, show page buttons, `config/routes.rb` | **NONE** remaining |

<!-- markdownlint-enable MD013 -->

**Phase 3 Parallelism Strategy:**

```bash
Sprint 3a (weeks 1-3):
  Dev A: #175 (Profile from baseline)  -- Profile domain
  Dev B: #185 (STIG XCCDF parser)      -- Converters domain (parallel with #175)
  Dev C: #173 (SSP from Profile)       -- SSP domain (can start after #175)

Sprint 3b (weeks 3-6):
  Dev A: #172 (CDEF from Profile)      -- CDEF domain (uses #185 for validation)
  Dev C: #174 (SAR from Profile/SSP)   -- SAR domain (uses #185 CDEF validations)
  Dev B: #125 (ATO Wizard)             -- New domain (after all entity types)
```

> **Critical rule:** #175 must merge first (creates Published
> Profiles that #172, #173, #174 consume). #185 can run in
> parallel with #175 (Converters domain, zero file overlap).
> #172 benefits from #185 (STIG/CCI data for CDEF validation).
> #174 needs #173 and #185 (CDEF validation for SAR evidence).
> #125 needs all five.

---

### Phase 4 -- Documentation & UX polish (all parallel)

<!-- markdownlint-disable MD013 -->

| Status | Issue | Domain | Files Modified | Collision Risk |
| ------ | ----- | ------ | -------------- | -------------- |
| [x] | **#133** Mapping docs -- **COMPLETED 2026-03-19** | Documentation | `docs/oscal-data-mapping.md`, `docs/data_mapping/{ssp,sar,sap,poam,cdef}.md` | **NONE** remaining |
| [x] | **#167** Enterprise nav -- **COMPLETED 2026-03-19** | UI/Navigation | `home/index.html.erb`, `application.html.erb` (nav dropdown), `home_controller.rb` | **NONE** remaining |
| [x] | **#171** OSCAL diagram -- **COMPLETED 2026-03-19** | UI (new page) | `home/oscal_overview.html.erb`, `config/routes.rb`, `application.html.erb` (Mermaid CDN + nav link), `home_controller.rb` | **NONE** remaining |

<!-- markdownlint-enable MD013 -->

**Phase 4 Parallelism: All 3 issues can run simultaneously.**

```text
Dev A: #133 (mapping docs)
Dev B: #167 (enterprise nav)
Dev C: #171 (OSCAL diagram)
```

---

### Phase 5 -- API, CI/CD & Database Cleanup

<!-- markdownlint-disable MD013 -->

| Status | Issue | Domain | Files Modified | Collision Risk |
| ------ | ----- | ------ | -------------- | -------------- |
| [x] | **#95** CRUD API -- **COMPLETED 2026-03-19** | API | `api/v1/users_controller.rb`, `api/v1/authorization_boundaries_controller.rb`, `api/v1/base_controller.rb`, `api_authentication.rb`, `api_token.rb`, `admin/api_tokens_controller.rb`, `docs/API.md` | **NONE** remaining |
| [x] | **#186** Hybrid security scanning -- **COMPLETED 2026-03-15** | CI/Infrastructure | `.github/workflows/security.yml`, `.github/oscal-metadata.json`, `docs/security-scanning.md` | **NONE** -- CI pipeline files only |
| [x] | **#183** Migration squash -- **COMPLETED 2026-03-19** | Shared (DB) | 64 migrations archived to `db/migrate_archive/`, single squash migration in `db/migrate/` | **NONE** remaining |

<!-- markdownlint-enable MD013 -->

**Phase 5 Parallelism Strategy:**

```text
Dev A: #95  (CRUD API)
Dev B: #186 (hybrid security scanning)
Dev C: #183 (migration squash) -- AFTER all migration PRs merge
```

> **Critical rule:** #183 (migration squash) must wait until all
> issues with pending migrations (#142, #149, #148, #177, #175,
> #172, #173, #174, #125) have merged. This is a cleanup task that
> should run when schema is stable.

---

### Phase 6 -- Security Remediation & Bug Fixes

<!-- markdownlint-disable MD013 -->

| Status | Issue | Domain | Files Modified | Collision Risk |
| ------ | ----- | ------ | -------------- | -------------- |
| [x] | **#210** Container CVE remediation | Infrastructure | `Dockerfile`, `Gemfile`, `.trivyignore`, `scripts/trivy-scan.sh` | **NONE** -- infra only |
| [x] | **#203** Catalog count bug | Catalog | `control_catalogs_controller.rb`, `control_catalogs/index.html.erb` | **NONE** -- single view fix -- **COMPLETED 2026-03-19** |
| [x] | **#205** Profile import flexibility | Profile | `profile_json_parser_service.rb`, `profile_xml_parser_service.rb`, `document_conversion_job.rb`, publish validation | **NONE** -- parser domain -- **COMPLETED 2026-03-19** |

<!-- markdownlint-enable MD013 -->

---

### Phase 7 -- OSCAL Import Quality & Traceability

<!-- markdownlint-disable MD013 -->

| Status | Issue | Domain | Files Modified | Collision Risk |
| ------ | ----- | ------ | -------------- | -------------- |
| [x] | **#207** Import quality reporting | Catalog | `catalog_import_validation_service.rb`, `catalog_import_job.rb`, `control_catalogs_controller.rb`, `_import_warnings_modal.html.erb` | **NONE** with #213 -- **COMPLETED 2026-03-20** |
| [x] | **#213** XCCDF ID mapping to NIST -- **COMPLETED 2026-03-20** | CDEF/Converters | `cdef_xccdf_parser_service.rb`, `cdef_json_parser_service.rb`, new `CciNistResolvable` concern, `cdef_control.rb`, `oscal_component_definition_export_service.rb`, migration | **NONE** with #207 |
| [x] | **#217** Rev 5 mapping docs -- **COMPLETED 2026-03-20** | Documentation | `docs/compliance/README.md`, `docs/compliance/nist-sp800-53-rev5-mapping.md`, `docs/compliance/oscal/cdefs/*.json` (5 CDEFs), inline NIST comments in 10 source files, `.github/oscal-metadata.json`, `.github/workflows/security.yml` (new `publish_for_sparc_iac` job) | **NONE** -- docs + workflow only |

<!-- markdownlint-enable MD013 -->

---

### Phase 8 -- API Expansion

<!-- markdownlint-disable MD013 -->

| Status | Issue | Domain | Files Modified | Collision Risk |
| ------ | ----- | ------ | -------------- | -------------- |
| [x] | **#229** REST API Phase 1: SSP, SAR, SAP, POA&M CRUD + Okta JWT | API | `api/v1/document_base_controller.rb` (NEW), `api/v1/ssp_documents_controller.rb` (REWRITE), `api/v1/sar_documents_controller.rb` (NEW), `api/v1/sap_documents_controller.rb` (NEW), `api/v1/poam_documents_controller.rb` (NEW), `concerns/api_authentication.rb` (MODIFY), `api/v1/base_controller.rb` (MODIFY), `models/concerns/soft_deletable.rb` (NEW), `config/routes.rb`, migration, 4 spec files | **NONE** -- API namespace isolated |
| [x] | **#240** Baseline Parameter & Enumeration Management API -- **COMPLETED 2026-03-21** | API + Profile | `app/services/baseline_parameter_service.rb` (NEW), `api/v1/baseline_parameters_controller.rb` (NEW), `config/routes.rb`, 1 spec file | **NONE** -- API namespace isolated |
| [x] | **#242** REST API Phase 2: Catalogs, Profiles, CDEFs, Mappings -- **COMPLETED 2026-03-21** | API | `api/v1/control_catalogs_controller.rb` (NEW), `api/v1/profile_documents_controller.rb` (NEW), `api/v1/cdef_documents_controller.rb` (NEW), `api/v1/control_mappings_controller.rb` (NEW), `models/concerns/soft_deletable.rb` (MODIFY -- added to ProfileDocument, CdefDocument), `config/routes.rb`, 4 spec files | **NONE** -- API namespace isolated |

<!-- markdownlint-enable MD013 -->

---

### Phase 9 -- FedRAMP 20x (final phase)

<!-- markdownlint-disable MD013 -->

| Status | Issue | Domain | Files Modified | Collision Risk |
| ------ | ----- | ------ | -------------- | -------------- |
| [x] | **#107** FedRAMP 20x KSI support -- **COMPLETED 2026-03-21** | New (FedRAMP) | `app/models/ksi_validation.rb`, `app/services/ksi_export_service.rb`, `app/controllers/api/v1/ksi_catalog_controller.rb`, `app/controllers/api/v1/ksi_validations_controller.rb`, `db/seeds/fedramp_20x_ksi.rb`, `config/routes.rb` | **LOW** -- mostly new code |
| [x] | **#108** Expanded sample data -- **COMPLETED 2026-03-21** | Seeds/Samples | `db/seeds/sample_artifacts.rb`, `lib/tasks/samples.rake`, `samples/README.md`, `samples/nist-traditional-demo/*.json`, `samples/fedramp-20x-demo/*.json` | **NONE** -- own directory |

<!-- markdownlint-enable MD013 -->

**Phase 9 Strategy:** #107 ships first (defines the FedRAMP schema
and models), then #108 follows (populates sample/seed data that
depends on #107's schema). All core SPARC functionality from
Phases 1-8 is complete before FedRAMP extensions begin.

```text
Dev A: #107 (FedRAMP 20x)          -- Phase 9a ✅ COMPLETE
Dev B: #108 (sample data)          -- Phase 9b ✅ COMPLETE
```

> **Critical rule:** #107 must merge before #108 starts
> (#108 needs #107 schema definitions).
> #107 completed 2026-03-21. #108 completed 2026-03-21.
> **Phase 9 COMPLETE -- all phases finished.**

---

### Ad-hoc -- UI/UX Polish (not on original roadmap)

<!-- markdownlint-disable MD013 -->

| Status | Issue | Domain | Files Modified | Collision Risk |
| ------ | ----- | ------ | -------------- | -------------- |
| [x] | **#253** Logo, text correction & header sizing -- **COMPLETED 2026-03-21** | Shared/UI | `app/assets/stylesheets/sparc-theme.css`, `app/views/home/index.html.erb`, `app/views/layouts/application.html.erb`, `app/views/layouts/login.html.erb`, `app/javascript/controllers/video_easter_egg_controller.js` (NEW), `app/assets/images/sparc_logo.jpg` (NEW), `public/videos/sparc_intro.mp4` (NEW), `CLAUDE.md`, `README.md`, wiki page, compliance docs, 5 OSCAL CDEF JSONs (10 files with text fix) | **NONE** -- all phases complete |
| [x] | **#248** About page with OSCAL, FedRAMP & API docs -- **COMPLETED 2026-03-21** | UI/Documentation | `app/controllers/about_controller.rb` (NEW), `app/views/about/index.html.erb` (NEW), `app/views/about/api_docs.html.erb` (NEW), `app/views/about/quickstart.html.erb` (NEW), `config/routes.rb`, `app/views/layouts/application.html.erb`, `app/views/layouts/login.html.erb`, `spec/requests/about_spec.rb` (NEW) | **NONE** -- all phases complete |

<!-- markdownlint-enable MD013 -->

---

### Phase 10 -- Platform Hardening & Polish (ongoing)

<!-- markdownlint-disable MD013 -->

| Status | Issue | Domain | Files Modified | Collision Risk |
| ------ | ----- | ------ | -------------- | -------------- |
| [x] | **#234** Avatar upload crop/scale/center -- **COMPLETED 2026-03-21** | User/UI | `app/models/user.rb`, `app/controllers/profiles_controller.rb`, `app/views/profiles/edit.html.erb`, `app/javascript/controllers/avatar_crop_controller.js` (NEW), `app/assets/stylesheets/sparc-theme.css`, `app/views/layouts/application.html.erb`, `config/importmap.rb`, `Gemfile`, `db/seeds.rb`, `app/assets/images/sparc_admin.jpg` (NEW) | **NONE** -- isolated to user profile |
| [x] | **#237** Data Quality card on catalog show -- **COMPLETED 2026-03-21** | Catalog UI | `app/views/control_catalogs/_data_quality_card.html.erb` (NEW), `app/views/control_catalogs/show.html.erb`, `app/controllers/control_catalogs_controller.rb` (revalidate action), `config/routes.rb`, `app/assets/stylesheets/sparc-theme.css`, `spec/requests/control_catalogs_revalidate_spec.rb` (NEW) | **NONE** -- Catalog domain only |
| [ ] | **#244** Security gate (threshold merge/deploy blocking) | CI/Infrastructure | `.github/workflows/security.yml` (new gate job), possibly new `.github/security-thresholds.yml` config | **NONE** -- CI files only |
| [ ] | **#461** SBOM-driven vulnerability scanning (Grype) | CI/Infrastructure | `.github/workflows/security.yml` (new `grype_sbom_scan` job; wired into `normalize_hdf` + `bundle_results`), `.github/required-checks.json` (new rule), `docs/compliance/nist-sp800-53-rev5-mapping.md` (RA-5, SR-3, SR-11, SA-11(1)), `docs/compliance/oscal/cdefs/component-definition-security-scanning.json` (RA-5 expanded, new SR-3 + SR-11 entries) | **NONE** -- CI workflow + compliance docs only |
| [x] | **#463** SAF CLI MODULE_NOT_FOUND fix (Node 22 pin + @mitre/saf@1.6.0) -- **COMPLETED 2026-05-14** | CI/Infrastructure | `.github/workflows/security.yml` (`normalize_hdf`: `actions/setup-node@v4` + pin `@mitre/saf@1.6.0`, verify step, per-conversion log capture, dump failed logs, debug `hdf-conversion-logs` artifact), `scripts/trivy-scan.sh` (header docs only), `.github/workflows/required-passed.yml` (sort runs by started_at to fix stale-Map.set aggregator bug), `Gemfile`/`Gemfile.lock` (drop cyclonedx-ruby; use @cyclonedx/cdxgen via npx in sbom_generation) | **NONE** -- completed |
| [x] | **#456** Entrypoint `db:prepare:all` typo (cosmetic noise in prod logs) -- **COMPLETED 2026-05-14** | Infrastructure | `bin/docker-entrypoint` (delete redundant line 28) | **NONE** -- completed |
| [x] | **#466** AWS Labs CDEF runtime ingestion + read-only inventory -- **COMPLETED 2026-05-17** | Core/CDEF + Infrastructure | (see PR #469 for full file list — completed) | **NONE** -- completed |
| [x] | **#470** Migration squash + v1.6.1 release -- **COMPLETED 2026-05-17** | DB/Infrastructure | (released as v1.6.1) | **NONE** -- completed |
| [x] | **#472** SBOM license inventory + policy gate (warn-only initial release) -- **COMPLETED 2026-05-17** | CI/Infrastructure + Compliance | (released; see PR #474) | **NONE** -- completed |
| [x] | **#473** Aggregator: add `edited` to triggers + in-flight-aware short-circuit -- **COMPLETED 2026-05-17** | CI/Infrastructure | (shipped in v1.6.2; see PR #476) | **NONE** -- completed |
| [x] | **#475** License triage + LICENSES/ + baseline dispositions -- **COMPLETED 2026-05-17 / 18** | Compliance/Docs | (shipped in v1.6.2; PRs #477, #478) | **NONE** -- completed |
| [x] | **#479** Drop roo-xls + Excel UI scrub + v1.6.2 -- **COMPLETED 2026-05-18** | CI/Infrastructure + UI | (shipped in v1.6.2; PR #480) | **NONE** -- completed |
| [x] | **#481** Close out 120 unmapped license-inventory components -- **COMPLETED 2026-05-18** | Compliance | (shipped in v1.6.2; PR #482) | **NONE** -- completed |
| [x] | **#483** Apache-2.0 license harmonization + v1.6.3 -- **COMPLETED 2026-05-18** | Legal/Compliance | (shipped in v1.6.3; PR #484) | **NONE** -- completed |
| [ ] | **#487 + #488** AWS Labs CDEF bootstrap-on-boot + "Refresh from AWS Labs" admin button | Core/CDEF + Infrastructure | `config/initializers/aws_labs_cdef_bootstrap.rb` (NEW), `app/controllers/cdef_documents_controller.rb` (refresh_aws_labs action + authorize_converter_write! helper), `config/routes.rb` (collection post route), `app/views/cdef_documents/index.html.erb` (button + modal gated on can_write_converters? + feature flag), `app/models/audit_event.rb` (new `aws_labs_cdef_refresh_requested` action in ACTIONS allowlist), `spec/requests/cdef_documents_spec.rb` (5 new examples), `spec/initializers/aws_labs_cdef_bootstrap_spec.rb` (NEW, 5 examples) | **LOW** -- new files + targeted edits; RBAC reuses existing `converters.write` permission |
| [ ] | **#246** Repository cleanup & OSCAL schema validation overhaul | Shared/Validation | `app/services/oscal_schema_validation_service.rb`, schema fixtures in `spec/fixtures/`, `docs/` cleanup, stale file removal | **LOW** -- validation service shared |
| [x] | **#249** Mutually exclusive API auth modes (local/oidc/hybrid) -- **COMPLETED 2026-03-21** | API/Auth | `app/controllers/concerns/api_authentication.rb` (REWRITE -- 3 mutually exclusive modes), `app/models/sparc_config.rb`, `app/models/user.rb` (service_account boolean), `app/controllers/sessions_controller.rb` (service account web login block), `config/initializers/api_auth.rb` (NEW -- boot-time validation), migration (add service_account to users), `spec/requests/api/v1/api_authentication_spec.rb` (12 new specs) | **NONE** -- completed |
| [x] | **#250** API discovery endpoint (GET /api/v1/available) -- **COMPLETED 2026-03-21** | API | `app/controllers/api/v1/discovery_controller.rb` (NEW), `app/models/user.rb` (has_any_permission?), `config/routes.rb`, `app/views/about/api_docs.html.erb`, `spec/requests/api/v1/discovery_spec.rb` (NEW -- 13 specs) | **NONE** -- completed |
| [x] | **#257** Service Account Management for API Access -- **COMPLETED 2026-03-21** | API/Auth | `app/controllers/admin/service_accounts_controller.rb` (NEW), `app/views/admin/service_accounts/` (NEW -- index, show, new, edit), `app/models/user.rb` (owner association, service_account validations, disable!/enable!), `app/models/api_token.rb` (sparc_sa_ prefix, endpoint_allowed?, cidr_allowed?, created_by), `app/controllers/concerns/api_authentication.rb` (endpoint scoping + CIDR enforcement), `app/views/layouts/application.html.erb` (nav link), migration (owner_id/disabled_at/disabled_reason on users; allowed_endpoints/allowed_cidrs/created_by_id on api_tokens), 18 new specs | **NONE** -- completed |
| [x] | **#259** AWS Secrets Manager integration for ECS deployments -- **COMPLETED 2026-03-21** | Infrastructure/Auth | `config/initializers/00_aws_secrets.rb` (NEW -- boot-time JSON blob unpacker from Secrets Manager), `config/initializers/aws_db_auth.rb` (NEW -- IAM database auth with 15-min auto-rotating tokens), `app/models/sparc_config.rb` (5 new AWS methods), `Gemfile` (aws-sdk-secretsmanager, aws-sdk-rds), `.env` files, `docs/ENVIRONMENT_VARIABLES.md`, 13 new specs | **NONE** -- completed |
| [x] | **#264** Gitleaks pattern for SPARC service account tokens -- **COMPLETED 2026-03-21** | CI/Infrastructure | `.gitleaks.toml` (NEW -- two custom rules: `sparc-api-token` and `sparc-service-account-token` detecting `sparc_`/`sparc_sa_` prefixed tokens, tagged with NIST IA-5) | **NONE** -- config-only, no app code |
| [x] | **#263** Auto-disable service accounts on token expiry and inactivity -- **COMPLETED 2026-03-21** | API/Auth | `app/jobs/service_account_maintenance_job.rb` (NEW), `app/models/sparc_config.rb` (sa_inactivity_days), `app/models/audit_event.rb` (7 new actions), `config/recurring.yml` (daily 3 AM schedule), `spec/jobs/service_account_maintenance_job_spec.rb` (NEW -- 12 specs) | **NONE** -- completed |
| [x] | **#262** Service account token expiry email notifications -- **COMPLETED 2026-03-22** | API/Auth | `app/mailers/service_account_mailer.rb` (NEW), `app/jobs/service_account_notification_job.rb` (NEW), `app/mailers/application_mailer.rb` (updated from address), `config/recurring.yml` (daily 2:30 AM schedule), `app/views/service_account_mailer/` (NEW -- 8 templates: token_expiry_warning, token_expiry_urgent, token_expired_notice, inactivity_warning in HTML + text), `spec/mailers/service_account_mailer_spec.rb` (NEW -- 8 specs), `spec/jobs/service_account_notification_job_spec.rb` (NEW -- 10 specs) | **NONE** -- completed |
| [x] | **#269** Configurable Resources page + support email links -- **COMPLETED 2026-03-22** | UI/Documentation | `app/models/sparc_config.rb` (support_email alias, resources method, default_resources), `app/controllers/about_controller.rb` (resources action), `app/views/about/resources.html.erb` (NEW), `app/views/about/index.html.erb` (Resources section), `app/views/home/index.html.erb` (support mailto), `app/views/layouts/application.html.erb` (Resources nav), `app/views/layouts/login.html.erb` (Resources nav + mailto), `config/routes.rb`, `.env.example`, `.env.production.example`, `docs/ENVIRONMENT_VARIABLES.md`, `spec/requests/about_spec.rb` (4 new specs) | **NONE** -- completed |
| [x] | **#274** Rebrand SPARC acronym -- **COMPLETED 2026-03-22** | Documentation/UI | `CLAUDE.md`, `README.md`, `wiki/Home.md`, `wiki/Core-Functions.md`, `docs/compliance/nist-sp800-53-rev5-mapping.md`, `docs/compliance/oscal/cdefs/*.json` (5 CDEF files), `app/views/about/index.html.erb` | **NONE** -- text-only, no code logic |
| [x] | **#272** Collapsible left sidebar navigation -- **COMPLETED 2026-03-22** | Shared/UI | `app/views/shared/_sidebar.html.erb` (NEW), `app/javascript/controllers/sidebar_controller.js` (NEW), `app/views/layouts/application.html.erb`, `app/assets/stylesheets/sparc-theme.css`, `app/helpers/application_helper.rb` | **NONE** -- completed |
| [x] | **#276** Converter seed fixtures for Docker -- **COMPLETED 2026-03-22** | Converters/Infrastructure | `db/seeds/converters.rb` (NEW), `db/seeds.rb`, `bin/docker-entrypoint`, `.env.example`, `.env.production.example`, `docs/ENVIRONMENT_VARIABLES.md`, `lib/data_mappings/cci_to_nist.json`, `lib/data_mappings/cis_to_nist.json`, `lib/data_mappings/scap_oval_to_nist.json` | **NONE** -- completed |
| [x] | **#271** Consolidate all releases into v1.0.0 -- **COMPLETED 2026-03-22** | Version/Config | `app/models/sparc_config.rb` (VERSION constant) | **NONE** -- completed |
| [x] | **#282** Fix incomplete data seeding on startup -- **COMPLETED 2026-03-23** | Seeds/Infrastructure | `app/models/seed_runner.rb` (NEW), `app/models/seed_section.rb` (NEW), `db/seeds.rb` (REFACTORED), `db/seeds/converters.rb` (FIXED), `db/seeds/sample_artifacts.rb` (FIXED), `bin/docker-entrypoint` (UPDATED), `lib/data/catalogs/` (MOVED), migration (create_seed_sections), `spec/models/seed_runner_spec.rb` (NEW -- 8 specs) | **NONE** -- completed |
| [x] | **#281** Login features list + v1.1.0 version bump -- **COMPLETED 2026-03-23** | Shared/UI + Version | `app/views/layouts/login.html.erb` (13 bullets replaced with 9), `app/models/sparc_config.rb` (VERSION 1.0.0 -> 1.1.0) | **NONE** -- completed |
| [x] | **#291** Postman collection + environments for SPARC API -- **COMPLETED 2026-03-23** | Documentation | `docs/api/SPARC_API_v1.postman_collection.json` (NEW), `docs/api/SPARC_Production.postman_environment.json` (NEW), `docs/api/SPARC_Local.postman_environment.json` (NEW), `docs/api/README.md` (NEW) | **NONE** -- docs only, no code changes |
| [x] | **#296** Downsize hero card size by ~20% -- **COMPLETED 2026-03-25** | Shared/UI | `app/assets/stylesheets/sparc-theme.css`, `app/views/shared/_section_summary.html.erb`, `app/views/home/index.html.erb` | **NONE** -- CSS-only, no code logic |
| [x] | **#300** Compliance artifact pipeline with S3 upload on PRs -- **COMPLETED 2026-03-25** | CI/Infrastructure | `.github/workflows/security.yml` (OIDC + S3 upload in `publish_for_sparc_iac`, `s3_prefix` in dispatch payload), `.github/workflows/compliance.yml` (NEW -- PR-triggered CDEF JSON validation + completeness check), `docs/compliance/README.md` (CI/CD pipeline docs, OIDC trust policy, secrets/variables) | **NONE** -- CI workflow + docs only |
| [x] | **#314** CI pipeline optimization: caching + parallel scans -- **COMPLETED 2026-03-26** | CI/Infrastructure | `.github/workflows/security.yml` (actions/cache for Trivy/Gitleaks/bundler-audit/ASFF template, parallel SAF CLI steps, Docker Buildx with gha layer cache, new pipeline_metrics job), `Gemfile` (bundler-audit + cyclonedx-ruby moved to dev group), `scripts/ci/generate_pipeline_chart.py` (NEW), `docs/ci/pipeline-metrics.csv` (NEW) | **NONE** -- CI workflow + tooling only |
| [x] | **#316** Signed Docker image build pipeline -- **COMPLETED 2026-03-31** | CI/Infrastructure | `.github/workflows/build-sign-publish.yml` (NEW -- reusable workflow: multi-platform build, Docker Hub + ECR push, Cosign keyless signing, SBOM attestation) | **NONE** -- new workflow file only |
| [x] | **#335** Paths filters on CI workflows -- **COMPLETED 2026-04-02** | CI/Infrastructure | `.github/workflows/ci.yml` (dorny/paths-filter conditional), `.github/workflows/security.yml` (dorny/paths-filter conditional on all scan + downstream jobs) | **NONE** -- CI workflow changes only |
| [x] | **#340** Container vulnerability baseline -- **COMPLETED 2026-04-04** | Compliance | `docs/compliance/sparc-findings.yml` (NEW -- 76 CVE dispositions), `docs/compliance/nist-sp800-53-rev5-mapping.md` (RA-5, SI-2, CM-6 updates), `docs/compliance/oscal/cdefs/component-definition-security-scanning.json` (container baseline evidence) | **NONE** -- compliance docs only |
| [x] | **#342** Harden Dockerfile -- **COMPLETED 2026-04-05** | CI/Infrastructure | `Dockerfile` (bootstrap stage, removed curl/gnupg/perl/transitive deps), `app/models/sparc_config.rb` (v1.1.2), `docs/compliance/sparc-findings.yml` (33 CVEs remediated), `.trivyignore` (updated for removed pkgs) | **NONE** -- Dockerfile + compliance docs |
| [x] | **#349** OSCAL schema database -- **COMPLETED 2026-04-06** | Core/OSCAL | `db/migrate/*_create_oscal_schemas.rb` (NEW), `app/models/oscal_schema.rb` (NEW), `lib/tasks/oscal_schemas.rake` (NEW), `app/services/oscal_schema_validation_service.rb` (DB-first loading), `app/services/oscal_*_export_service.rb` (9 services, versioned), `app/models/concerns/oscal_metadata.rb` | **HIGH** -- touches validation + all exports |
| [x] | **#355** Multi-file upload + branding -- **COMPLETED 2026-04-08** | UI/Frontend | `app/views/shared/_dropzone.html.erb` (multi-file), `app/javascript/controllers/dropzone_controller.js` (multi-file), `app/controllers/concerns/file_uploadable.rb` (batch handler), 6 document controllers, `app/assets/stylesheets/sparc-theme.css` (file list CSS), branding text in views/docs/CDEFs | **MEDIUM** -- UI + upload flow |
| [x] | **#356** CDEF prioritization + editable fields -- **COMPLETED 2026-04-12** | Core/CDEF | `db/migrate/*_add_profile_document_id_to_cdef_documents.rb` (NEW), `app/services/cdef_update_service.rb` (NEW), `app/services/cdef_baseline_gap_service.rb` (NEW), `app/models/cdef_control_field.rb` (expanded fields), `app/controllers/cdef_documents_controller.rb` (update_field + gap), `app/views/cdef_documents/show.html.erb` (inline editing + gap UI), `app/services/oscal_component_definition_export_service.rb` (new OSCAL fields) | **HIGH** -- model + UI + export |
| [x] | **#370** OSCAL metadata compliance -- **COMPLETED 2026-04-13** | Core/OSCAL | `app/models/concerns/oscal_metadata.rb` (unified builder, locations/remarks), `db/migrate/*_add_published_to_documents.rb` (NEW), `app/services/oscal_*_export_service.rb` (8 services, unified metadata), `app/models/concerns/lifecycle.rb` (published timestamp) | **HIGH** -- touches all exports |
| [x] | **#371** Back-matter resource management with control-level linking -- **COMPLETED 2026-04-14** | BackMatter + Shared | `back_matter_resource.rb` (NEW), `control_back_matter_link.rb` (NEW), controllers, partials, all 6 control models, all 7 show views, export services, 5 migrations | **HIGH** -- cross-cutting |
| [x] | **#375** Back-matter resource API with authoritative layer -- **COMPLETED 2026-04-14** | API + BackMatter | `api/v1/back_matter_resources_controller.rb` (NEW), all 7 document API serializers (OSCAL fields), `back_matter_builder.rb` (authoritative priority), `config/routes.rb`, docs/api/ | **MEDIUM** -- API namespace + serializers |
| [x] | **#390** SAP/SAR objective-level tracking -- **COMPLETED 2026-04-16** | SAP + SAR + Shared | `db/migrate/*_create_sap_and_sar_control_objectives.rb` (NEW, both tables + `sar_findings` FK + in-migration backfill), `app/models/sap_control_objective.rb` (NEW), `app/models/sar_control_objective.rb` (NEW), `app/models/sar_finding.rb` (FK), `app/services/control_objective_extractor_service.rb` (NEW), `sap_documents_controller.rb` (extractor delegation, `update_objective`, status heatmap, includes), `sar_documents_controller.rb` (`update_objective`, status heatmap, includes), `sap_json_parser_service.rb` (statement-ids), `sar_json_parser_service.rb` (objective-id finding linkage), `oscal_assessment_plan_export_service.rb` (statement-ids), `oscal_sar_export_service.rb` (objective-id target), `_objectives_table.html.erb` (NEW × 2), show view edits + edit modals, `application_helper.rb` (`sap_objective_status_color`), `config/routes.rb` | **HIGH** -- both SAP + SAR domains, schema migration, OSCAL exporters |

<!-- markdownlint-enable MD013 -->

**Phase 10 Parallelism: Remaining issues (#244, #246) can run simultaneously.**

```text
Dev B: #244 (security gate)        -- CI/Infrastructure domain
Dev C: #246 (repo cleanup/schema)  -- Shared/Validation domain
Dev D: #237 (data quality card)    -- Catalog UI domain ✅ COMPLETE
      #234 (avatar upload)        -- User/UI domain ✅ COMPLETE
      #250 (API discovery)        -- API domain (after #249) ✅ COMPLETE
Dev A: #257 (service accounts)     -- API/Auth domain ✅ COMPLETE
Dev A: #259 (AWS secrets)          -- Infrastructure/Auth domain ✅ COMPLETE
Dev A: #264 (gitleaks patterns)    -- CI/Infrastructure domain ✅ COMPLETE
Dev A: #263 (SA auto-disable)     -- API/Auth domain ✅ COMPLETE
Dev A: #262 (SA expiry emails)    -- API/Auth domain ✅ COMPLETE
Dev A: #269 (resources + support) -- UI/Documentation domain ✅ COMPLETE
Dev A: #274 (SPARC rebrand)      -- Documentation/UI domain ✅ COMPLETE
Dev A: #272 (left sidebar nav)   -- Shared/UI domain ✅ COMPLETE
Dev A: #276 (converter seeds)   -- Converters/Infrastructure domain ✅ COMPLETE
Dev A: #271 (v1.0.0 release)   -- Version/Config domain ✅ COMPLETE
Dev A: #282 (seed runner fix)  -- Seeds/Infrastructure domain ✅ COMPLETE
Dev A: #281 (login features + v1.1.0) -- Shared/UI + Version domain ✅ COMPLETE
Dev E: #300 (compliance artifact pipeline) -- CI/Infrastructure domain ✅ COMPLETE
```

> **Recommended order:** #249 and #244 first (security-critical),
> then #246 (tech debt), #237, #250, #234 (UX improvements).

---

### Phase 13 -- v1.7.x Pre-Pen-Test Hardening (COMPLETE)

All 17 issues shipped across v1.7.0 / v1.7.1 / v1.7.2 (2026-05-22 → 2026-05-24). Domain breakdown so future work in these areas knows who touched them last:

<!-- markdownlint-disable MD013 -->

| Status | Issue | Domain | Files Touched | Notes |
| ------ | ----- | ------ | ------------- | ----- |
| [x] | #509 | Upload Security | `file_uploadable.rb`, `parser_service`s, magic-byte deny-list constant | Marcel-driven content-type validation |
| [x] | #510 | Upload Security | `attachment_size_limit.rb` concern, `sparc_config.rb` MB accessors, Roo path size guard | Zip-bomb defense, env-var caps |
| [x] | #511 | Upload Security | `lib/xml_security.rb` (new), 11 Nokogiri call-sites | XXE hardening single funnel |
| [x] | #513 | Transport/Session Hardening | `config/initializers/rack_attack.rb` (new), `sparc_config.rb` throttle accessors | 5 throttle buckets, safelist CIDR |
| [x] | #514 | Transport/Session Hardening | `config/initializers/content_security_policy.rb` | enforce mode, per-request nonces |
| [x] | #515 | Transport/Session Hardening | `config/environments/production.rb`, `sparc_config.rb` userdata host derivation | Cookieless userdata subdomain |
| [x] | #524 | Documentation | `docs/PRODUCTION_SECURITY.md` (new, 388 lines) | Operator hardening guide |
| [x] | #525 | Documentation | `docs/security/SCANNER_FINDINGS_AUDIT.md` (new), `.trivyignore` review | Suppression inventory |
| [x] | #535 | Shared/UI | `app/views/layouts/application.html.erb` admin nav, view spec | One-line nav fix |
| [x] | #536 | Auth/Users | `app/models/user.rb` (drop validation), `admin/service_accounts_controller.rb`, new + edit views | Lift SA admin restriction |
| [x] | #537 | Shared/Cross-cutting | `db/migrate/20260523200000_*.rb`, `cdef_documents_controller.rb` (existing reference), schema | Idempotent migration recovering lost column |
| [x] | #541 | Documentation | `docs/ENVIRONMENT_VARIABLES.md` | Drift audit + 10 new entries |
| [x] | #543 | CI/Infrastructure | `.github/workflows/build-sign-publish.yml`, `.github/workflows/security.yml` | vars → secrets rotation |
| [x] | #547 | CI/Infrastructure | `.github/workflows/build-sign-publish.yml` (workflow_call.secrets block) | Necessary not sufficient for #553 |
| [x] | #548 | Shared/UI | `app/views/shared/_processing_banner.html.erb`, `sparc_config.rb`, view spec | Meta-refresh trap bailout (Tier 1) |
| [x] | #549 | API (v1) | `app/controllers/api/v1/base_controller.rb` | paginate() honors ?items/?per_page |
| [x] | #553 | CI/Infrastructure | `.github/workflows/build-sign-publish.yml` (job-level env hoist) | Real fix for #547 follow-on |

<!-- markdownlint-enable MD013 -->

> **Lesson saved to team memory:** the v1.7.x sprint produced four
> repeatable failure modes worth knowing — initializer autoload order
> (#514), middleware spec patterns (#513), `secrets` context in step
> `if:` (#553), and workflow `on.workflow_call.secrets` declarations
> (#547). Each has a dedicated memory file in the agent's persistent
> store.

---

### Phase 14 -- Pre-Public-Flip + API Test Validation + CDEF Mutations (substantially SHIPPED through v1.9.1)

> **Status (2026-06-28):** the content/feature core of Phase 14 shipped across **v1.8.11 → v1.9.1**:
> #627/#628 (content-completeness gate), #629 (bulk delete), #630–634 (document review/approval — v1.9.0 headline),
> #616 (SBOM/SCA emit), #618 (stuck-doc reaper), and #433/#644 (API contract suite realigned — green, v1.9.1).
> The translation-engine fixes that surfaced post-#637 also shipped: #648 (HDF→OSCAL 3.2.0 baselines/501) and
> #663 (`poam_from_amendments`) in v1.9.1.
> **Items still open roll forward into the Phase 15 deployment model below.**

<!-- markdownlint-disable MD013 -->

| Status | Issue | Domain | Files Modified (planned) | Collision Risk |
| ------ | ----- | ------ | ------------------------ | -------------- |
| [ ] | **#545** Pre-public-flip hardening checklist | CI/Infrastructure + GitHub Settings | `.github/CODEOWNERS` (already expanded via PR #546), workflow `permissions:` blocks (already added), repo-settings UI clicks (operator), `risk-sentinel/sparc-iac#281` (IaC repo) | **LOW** code-wise — most is operator clicks. Cross-repo coordination required for the OIDC trust policy. |
| [ ] | **#433** Content-style API tests | API (v1) + Shared (test fixtures) | `tests/api/schemas/` (new), `tests/api/test_*.py` extensions, `tests/api/fixtures/` additions | **LOW** — Python test suite is isolated from Ruby app code. Edits to `app/controllers/api/v1/*` controllers may surface if a contract diff is intentional vs accidental. |
| [ ] | **#498** CdefMutationService | CDEF | `app/services/cdef_mutation_service.rb` (new), `app/controllers/api/v1/cdef_documents_controller.rb`, `app/controllers/cdef_documents_controller.rb`, `app/models/cdef_document.rb` | **MEDIUM** — refactors mutation paths across both API and web controllers. Coordinate with anyone touching CDEF flows. |
| [ ] | **#499** Bulk Converter → CDEF + Rev 4↔Rev 5 helper | CDEF + Converters | `app/services/cdef_mutation_service.rb` (consumer), `converter.rb`, new Rev-mapping helper, `cdef_documents_controller.rb` (bulk action) | **MEDIUM** — depends on #498 landing first. Touches Converters domain which is currently quiet. |
| [ ] | **#528** Remove unsafe-inline from CSP | Transport/Session Hardening + Shared/UI | `config/initializers/content_security_policy.rb`, every inline `<script>` block across `app/views/` (refactor to nonce or Stimulus) | **HIGH** — view file changes will conflict with any feature work happening in those view trees. Recommend doing late in a sprint when other view work is done. |
| [ ] | **#531** GuardDuty S3 tag hook | Upload Security + ActiveStorage middleware | New middleware (e.g., `app/middleware/guardduty_blob_gate.rb`), `config/application.rb` middleware insert | **LOW** — new file, narrow insert. |
| [ ] | **#447** HDF Amendment umbrella (Plan B, deferred) | Evidence + new ScannerFinding domain | Substantial new domain — gated on customer demand | **HIGH** (when activated) — wholly new models + UI; needs its own domain lane |
| [ ] | **#341** XML upload fingerprinting | Upload Security | `file_uploadable.rb` (XML-specific path), `xml_security.rb` (deepen) | **LOW** — extends existing concern; coordinate with #511 author. |
| [ ] | **#246** Repo cleanup / OSCAL fixtures bloat | Shared/Cross-cutting + test fixtures | `spec/fixtures/files/**`, possibly `db/seeds/**` for the larger OSCAL samples | **LOW** — background lane; touches files no production code path uses. |
| [ ] | **#413** API docs + tests umbrella | (umbrella) | Closes when #433 merges | N/A |
| [ ] | **#422** POAM Scenario B federated visibility | (gated) | Stays parked | N/A |
| [x] | **#616** Emit CycloneDX SBOM to org SCA bucket | CI/Infrastructure | `.github/workflows/sbom-and-sca.yml` (NEW — calls org-shared `container-build-sign/sbom-source.yml`+`sca-scan.yml@v0.1.0`, emits to `s3://<security-artifacts-bucket>/sca/sparc/`), `.security/sca-allowlist.yaml` (NEW), `docs/compliance/nist-sp800-53-rev5-mapping.md` (SR-3, CM-8, RA-5), `docs/compliance/oscal/cdefs/component-definition-security-scanning.json` (SR-3, RA-5 remarks), `app/models/sparc_config.rb` (VERSION → 1.8.8) | **LOW** — new workflow file + compliance docs. Non-gating (not in `required-checks.json`). Cross-repo IAM dep: `SCA_EMIT_ROLE_ARN` provisioned in sparc-iac (umbrella container-build-sign#12). Validate with `actionlint`. |
| [x] | **#618** API-created docs stuck in pending — finalize + lifecycle logging + reaper | API + Jobs | `app/controllers/api/v1/base_controller.rb` (`finalize_unprocessed_create`), `document_base_controller.rb` / `cdef_documents_controller.rb` / `profile_documents_controller.rb` (create), `app/controllers/concerns/file_uploadable.rb` (enqueue log), `app/jobs/document_conversion_job.rb` (lifecycle log), `app/jobs/stuck_document_reaper_job.rb` (NEW), `config/recurring.yml`, `lib/tasks/documents.rake` (NEW backfill), `app/models/sparc_config.rb` (`SPARC_DOCUMENT_REAP_MINUTES`, VERSION → 1.8.9), mapping SI-11 | **MEDIUM** — touches the shared API create path + a new recurring job. Coordinate with anyone editing `file_uploadable.rb` or API document controllers. Email/in-app notification deferred to a follow-up. |
| [x] | **#627 + #628** (MERGED PR #637) Document content-completeness gate + empty-shell populate path | SSP + CDEF + Profile + API | `app/models/concerns/content_completeness.rb` (NEW), `ssp_document.rb` / `cdef_document.rb` / `profile_document.rb` (include + `requires_content`), `app/controllers/concerns/publishable.rb` (publish gate + readiness), `ssp_from_profile_service.rb` / `cdef_from_profile_service.rb` (`#populate`), `cdef_documents_controller.rb` / `ssp_documents_controller.rb` (`attach_profile`/`populate_from_profile`), `api/v1/cdef_documents_controller.rb` / `api/v1/ssp_documents_controller.rb` / `api/v1/profile_documents_controller.rb` (endpoint + serializer fields), `config/routes.rb`, show/index views (badge + populate card), `attach_profile.html.erb` (NEW ×2), mapping SI-10/SI-11 | **MEDIUM** — overlaps the #618 API create path and `Publishable` (used by all publishable doc types). Coordinate with #498/#499 (CDEF flows) and anyone editing `Publishable` or the from-profile services. |
| [x] | **#629** (MERGED PR #638) Bulk delete (multi-row) for CDEF + Authorization Boundary index (admin) | CDEF + Authorization Boundary + API + JS | `app/services/bulk_destroy_service.rb` (NEW), `app/controllers/concerns/bulk_destroyable.rb` (NEW), `app/models/authorization_boundary.rb` (SafeDestroyable + guard), `app/models/audit_event.rb` (new action), `cdef_documents_controller.rb` / `authorization_boundaries_controller.rb` (bulk_destroy + AB single-delete fix), `api/v1/cdef_documents_controller.rb` / `api/v1/authorization_boundaries_controller.rb` (bulk + AB destroy 422), `config/routes.rb`, `app/javascript/controllers/bulk_select_controller.js` (NEW), `app/helpers/authorization_helper.rb` (`can_bulk_delete?`), CDEF + AB index views, mapping AU-12 | **MEDIUM** — touches CDEF + AB controllers/models/views; coordinate with anyone editing those index pages or the AB destroy path. Held at v1.8.11. |
| [x] | **#630–634** Document review/approval workflow epic (Catalog/Profile/Baseline/CDEF) | Catalog + Profile + CDEF + API + JS-free UI | `db/migrate/20260614120000_*` (approval columns on control_catalogs/profile_documents/cdef_documents), `app/models/concerns/approvable.rb` (NEW), `app/services/document_approval_service.rb` (NEW), `app/services/baseline_review_service.rb` (NEW), `app/controllers/concerns/document_approval_actions.rb` + `document_approval_api.rb` (NEW), `app/controllers/review_queue_controller.rb` (NEW) + view, `control_catalog.rb`/`profile_document.rb`/`cdef_document.rb` (include Approvable), `audit_event.rb` (9 actions), `role.rb` (`*.approve` perms), `sparc_config.rb` (flag + VERSION 1.9.0), `publishable.rb` (approval gate), the 3 UI + 3 API controllers (submit/approve/reject), `config/routes.rb`, mapping CA-6 | **HIGH** — touches `Publishable` (shared by all publishable docs) and the catalog/profile/cdef controllers + models. Coordinate with anyone editing those controllers, `Publishable`, or running migrations. Flag-gated (default off) so publish behavior is unchanged until enabled. |

<!-- markdownlint-enable MD013 -->

> **Sequencing:** #545 + sparc-iac#281 first (public-flip blocker), then #433 (in-progress), then #498 → #499 chain. #528 last in any sprint because of view-conflict risk.

---

### Phase 15 -- Next-Version Deployment Model (post-v1.9.1)

The **18 issues open after v1.9.1** group into **four deployment-oriented lanes**. Each lane maps to a
domain, so the lanes are collision-safe to run **in parallel** (one owner per lane). Within a lane, items
are ordered by deployment priority. **Lane A gates the public flip and ships first**; Lanes B–D run alongside.
Two cross-cutting hazards: **#528** (CSP, touches every view) and **#672** (search, touches every index view +
API index endpoint) — schedule both **late** and serialize index-view edits to avoid conflicts with Lanes B/C.

<!-- markdownlint-disable MD013 -->

#### Lane A -- Pre-Public-Flip Hardening (deployment-gating) -- Owner: Dev E

| Status | Issue | Domain | Files Modified (planned) | Collision Risk |
| ------ | ----- | ------ | ------------------------ | -------------- |
| [ ] | **#545** Pre-public-flip hardening checklist | CI/Infra + GitHub Settings | `.github/CODEOWNERS`, workflow `permissions:`, repo-settings UI, `sparc-iac#281` (OIDC trust) | **LOW** code — mostly operator clicks + cross-repo coordination. **Public-flip blocker.** |
| [ ] | **#660** Enforce `strict` status checks on main | CI/Infra + GitHub Settings | `Merge_Main` ruleset (UI/API only — no repo files) | **LOW** — operator-side; recommendation + Option A/B already posted on the issue. |
| [ ] | **#639** Base-image CVE audit + hardened variants | CI/Infra + Container | `Dockerfile`, `bin/install-hdf.sh`, `docs/compliance/sparc-findings.yml` | **MEDIUM** — image build + CVE dispositions; serialize with any base-image bump. |
| [ ] | **#531** GuardDuty S3 tag hook on blob serving | Upload Security + ActiveStorage | new `app/middleware/guardduty_blob_gate.rb`, `config/application.rb` insert | **LOW** — new file, narrow insert. |
| [ ] | **#597** CI env-var rename (`AWS_ROLE_ARN`→`SPARC_AWS_ROLE_ARN`, `ECR_REGISTRY`→`SPARC_ECR_REGISTRY`) | CI/Infra | `.github/workflows/*`, coordinated secret rename in `sparc-iac` | **LOW** code — cross-repo secret rename; do atomically with sparc-iac. |
| [ ] | **#528** Remove `unsafe-inline` from CSP `style-src` | Transport/Session + Shared/UI | `config/initializers/content_security_policy.rb`, inline `style=` across `app/views/` | **HIGH** — view-wide; **do last in the sprint** after Lane B/C view work settles. |

#### Lane B -- Test & Validation Net (release confidence) -- Owner: Dev D + shared test infra

| Status | Issue | Domain | Files Modified (planned) | Collision Risk |
| ------ | ----- | ------ | ------------------------ | -------------- |
| [ ] | **#641** Run API + Playwright suites against a deployed instance | CI/Infra + tests | new deployed-smoke workflow, `tests/api/`, `tests/ui-smoke/`, deploy secrets | **LOW** — Python suites isolated; needs a deployed env + tokens (proven locally this cycle). |
| [ ] | **#642** Finish contract coverage for #628/#629/#630–634 endpoints | API tests | `tests/api/test_*.py`, `tests/api/schemas/` | **LOW** — Python only; isolated from Ruby. |
| [ ] | **#643** Extend Playwright ui-smoke (populate / bulk-delete / approval+review-queue) | UI tests | `tests/ui-smoke/*.py` | **LOW** — Python; **coordinate with #672** (both touch index-page expectations). |
| [ ] | **#635** Authorization-boundary orphan janitor + verify teardown deletes | API + Jobs/tests | session janitor (new), `tests/api/` teardown | **LOW–MEDIUM** — touches the AB create/teardown path. |
| [ ] | **#610** API docs + pytest tail (independent validation pass) | API docs/tests | `docs/api/`, `tests/api/` | **LOW** — sub-task of #413. |
| [ ] | **#413** Comprehensive API documentation review (umbrella) | (umbrella) | closes when #610 tail + the 30% independent-validation pass land | N/A |

#### Lane C -- Features & UX -- Owner: Dev B/C (doc domains) + shared

| Status | Issue | Domain | Files Modified (planned) | Collision Risk |
| ------ | ----- | ------ | ------------------------ | -------------- |
| [x] | **#672** Search field on all artifact index pages | API (v1) + Shared/UI | **SHIPPED (v1.10.0)** — one shared `Searchable.search_text` scope backs both web indexes and `Api::V1` `q`; ONE reusable `_index_search` partial + `index_search` Stimulus controller across all 8 indexes; per-index Playwright ui-smoke. | Resolved — built as a single reusable component as planned. |
| [x] | **#682** Configurable environment/rules header bar (all screens) | Shared/UI + Config | **SHIPPED (v1.10.0)** — `SparcConfig` header readers + color validator; `_environment_header` partial + `environment_header` Stimulus controller (CSSOM colors, CSP-safe); both layouts. | **LOW** — additive partial in layouts; AC-8. |
| [x] | **#680** Durable UUID-addressed artifact resolver (Phase 1) | API (v1) + Evidence/OSCAL | **SHIPPED (v1.10.0)** — `/artifacts/:uuid` web + API resolver; back-matter href emission switched to the immutable resolver URL. Touches `back_matter_resource.rb`, `evidence.rb`, `routes.rb`. Phases 2–3 open. | **MEDIUM** — touches hot files `routes.rb` + `back_matter_resource.rb`; coordinate with OSCAL-export work. |
| [ ] | **#623** Notify uploading user on parse failure (email + in-app) | Jobs + API + UI | `app/jobs/document_conversion_job.rb`, new mailer, in-app notification UI | **LOW–MEDIUM** — follow-up to #618; coordinate on the conversion-job path. |
| [ ] | **#341** XML document fingerprinting for upload validation | Upload Security | `app/controllers/concerns/file_uploadable.rb` (XML path), `lib/xml_security.rb` | **LOW** — extends existing concern; coordinate with #531 (same upload lane). |

#### Lane D -- Translation / Evidence / Federation (gated / owner-blocked) -- Owner: Dev D (Evidence/API)

| Status | Issue | Domain | Files Modified (planned) | Collision Risk |
| ------ | ----- | ------ | ------------------------ | -------------- |
| [ ] | **#636** SonarQube → HDF evidence (`saf sonarqube2hdf` / `hdf fetch sonarqube`) | Evidence + CI | new OHDF producer, security-artifact bake-in | **MEDIUM** — **owner-blocked** on the SonarCloud org LOC quota; CI-side. |
| [ ] | **#447** HDF Amendment translation/UI layer (umbrella) | Evidence + new ScannerFinding domain | wholly new models + UI — gated on customer demand | **HIGH** when activated — needs its own domain lane. Now partially enabled by `poam_from_amendments` (#663). |
| [ ] | **#422** POAM Scenario B — cross-instance federated POAM visibility | POAM + Federation | gated — stays parked | N/A |

<!-- markdownlint-enable MD013 -->

> **Recommended order:** Lane A first / in parallel (public-flip gate) — start with #545 + #660 + #597 (operator/CI),
> then #639/#531, and **#528 last**. Lanes B–D run concurrently with one owner each. The two highest-risk
> cross-cutting items (#528, #672) land at the **end** of the sprint after sibling view/test work is merged.

---

## 3. Branching Strategy

### Branch Naming Convention

```text
feature/{issue_number}_{short_description}
```

Examples:

- `feature/142_background_upload_ux`
- `feature/178_safe_delete_confirmation`
- `feature/163_catalog_format_interop`
- `feature/185_stig_xccdf_parser`
- `feature/186_hybrid_security_scanning`

### Rules

1. **One branch per issue.** Never combine issues on one branch.
2. **Branch from `main`** (or `develop` if you use Git Flow).
3. **Rebase before PR.** Before opening a PR, rebase onto latest
   `main` to catch conflicts early:

   ```bash
   git fetch origin && git rebase origin/main
   ```

4. **Short-lived branches.** Target less than 1 week per branch.
   If an issue takes 2+ weeks, split into sub-issues.
5. **Feature flags for in-progress work.** If a feature ships
   incrementally, gate it behind an ENV var:

   ```ruby
   # config/features.rb
   FEATURE_BACKGROUND_UPLOAD = \
     ENV.fetch("FEATURE_BACKGROUND_UPLOAD", "false") == "true"
   ```

---

## 4. Migration Coordination Protocol

Database migrations are the **#1 collision source** in
multi-developer Rails projects.

### Issues That Need Migrations

<!-- markdownlint-disable MD013 -->

| Issue | Migration Description | Tables Affected |
| ----- | -------------------- | --------------- |
| ~~#142~~ | ~~Add `processed_count`, `total_count` to `conversion_jobs`~~ -- **COMPLETED** (no migration needed; uses existing `metadata_extra` JSONB) | ~~`conversion_jobs`~~ |
| #177 | Add `file_digest` to `control_catalogs`; possibly `locked` to `catalog_controls` | `control_catalogs`, `catalog_controls` |
| #149 | Standardize `status` enum across all 6 document tables; add `published_at` | `ssp_documents`, `sar_documents`, `cdef_documents`, `profile_documents`, `sap_documents`, `poam_documents` |
| #148 | Add `published_version` columns (or use existing `metadata_extra` jsonb) | Possibly all document tables |
| #175 | Add `source_catalog_id`/`source_profile_id` to `profile_documents` | `profile_documents` |
| #172 | Add `source_profile_id` to `cdef_documents` | `cdef_documents` |
| #173 | Add `source_profile_id` to `ssp_documents` | `ssp_documents` |
| #174 | Add `source_profile_id`/`source_ssp_id` to `sar_documents` | `sar_documents` |
| #185 | Possibly new `stig_benchmarks` table or extend `converters` with XCCDF metadata | `converters`, possibly new table |
| #125 | Possibly new `ato_packages` table | New table |
| #107 | Possibly new `ksi_indicators` table | New table |
| #183 | Squash all existing migrations into single consolidated file | All tables (schema-only, no data change) |
| #283 | Pre-release squash: consolidate 9 post-v1.0.0 migrations into `20260323120000_squash_to_v110.rb` | All tables (schema-only, no data change) -- **COMPLETED 2026-03-23** |

<!-- markdownlint-enable MD013 -->

### Migration Rules

1. **Timestamp coordination.** If two developers create migrations
   on the same day, the one merged second may collide. Fix: always
   run `bin/rails db:migrate:status` before creating a new one.
2. **One table per migration.** Never alter multiple unrelated
   tables in one migration file.
3. **Additive only in parallel phases.** `add_column` is safe.
   `rename_column`, `remove_column`, and `change_column` require
   coordination.
4. **Announce migrations in Slack/Discord.** Post: "I'm adding
   `file_digest` to `control_catalogs` in #177" so no one else
   touches that table.
5. **Run `bin/rails db:migrate` after every pull from main.** Add
   to `.git/hooks/post-merge`:

   ```bash
   #!/bin/bash
   changed_migrations=$(git diff HEAD@{1} --name-only -- db/migrate)
   if [ -n "$changed_migrations" ]; then
     echo "New migrations detected. Running db:migrate..."
     bin/rails db:migrate
   fi
   ```

6. **Migration squash (#183) is a gate.** All issues with pending
   migrations must merge before #183 begins. After squash, new
   migrations start from a clean baseline.

---

## 5. Shared File Conflict Zones (Hot Files)

These files are touched by multiple issues. Extra care required.

<!-- markdownlint-disable MD013 -->

| File | Issues That Touch It | Mitigation |
| ---- | -------------------- | ---------- |
| `config/routes.rb` | #95, #125, #171, #167, #185 | Each adds routes in different blocks. Use section comments: `# === ATO Wizard ===`. Merge conflicts are trivial (additive lines). |
| `app/views/layouts/application.html.erb` | #171 (nav link), #167 (rename), #142 (progress bar) | Each touches different parts of the layout. Use partials to isolate: `render "shared/progress_bar"`, `render "shared/nav_links"`. |
| `Gemfile` | #100 (test gems), #171 (mermaid?), #95 (serializer gem) | Additive only. Merge conflicts are trivial. Run `bundle install` after merge. |
| `app/models/concerns/oscal_metadata.rb` | #148, #149, #177 | **HIGH RISK.** Assign one developer to this concern per sprint. Others wait for merge. |
| `app/services/oscal_schema_validation_service.rb` | #148, #125, #107 | Additive methods. Each adds a new validation method. Low conflict if methods are namespaced. #107 runs last (Phase 6), so no conflict with #148/#125. |
| `app/services/document_duplication_service.rb` | #176, #172, #173, #174 | Each document type adds its own `dup_*` method. Low conflict if well-separated. |
| `.github/workflows/` | #100 (CI test), #186 (security scanning), #543/#547/#553 (secrets rotation chain) | Different workflow files mostly. **MEDIUM** risk for `build-sign-publish.yml` + `security.yml` — they share secret references and validator rules. Always validate edits with `actionlint` before push (see #553 incident — phantom failure runs from invalid expressions). |
| `db/seeds.rb` | #108 (dual mode), #107 (FedRAMP seeds) | Both in Phase 6 (sequential: #107 then #108). Use separate seed files: `db/seeds/nist_traditional.rb`, `db/seeds/fedramp_20x.rb`. Main `seeds.rb` just dispatches. |
| `db/migrate/` | All migration issues + #183 (squash) + #283 (v1.1.0 squash) + #470 (v1.6.1 squash) | **HIGH RISK for squash PRs.** Squash migration's idempotent guard (`return if table_exists?(:ssp_documents)`) skips on existing DBs and DOES NOT add individual columns added between squashes — caused #537 prod schema drift. Squashes must capture every column added since the previous squash. |
| `app/models/sparc_config.rb` | Every new `SPARC_*` env var lands here | **MEDIUM** risk. Additive method blocks. Coordinate the section a new env var belongs in (organization metadata, rate limiting, upload caps, etc.) and add to `docs/ENVIRONMENT_VARIABLES.md` in the same PR. |
| `app/views/shared/_processing_banner.html.erb` | Every document show view renders it (#142, #549, #548) | **LOW** but critical UX — changes affect every document type at once. The Tier 1 stuck-bailout fix landed in v1.7.2; Tier 2/3 still tracked under #548. |
| `lib/xml_security.rb` | #511, future XML-related upload work, #341 (XML fingerprinting) | **LOW** — single funnel by design. Extend with new methods rather than modifying existing call paths. |
| `app/controllers/concerns/file_uploadable.rb` | #509, #510, #511, #341 | **MEDIUM** — every upload entrypoint depends on it. Test changes through `tests/api/` + parser specs together. |
| `app/controllers/api/v1/base_controller.rb` | Every paginated index (#549, future API work) | **LOW** — additive helpers. Pagination override clamp at `MAX_PAGINATION_LIMIT = 200` (#549). |
| `.github/CODEOWNERS` | Phase 13/14 hardening (#545/#546) | **LOW** — meta-rule changes go through `sparc-admin` team review per the file's own rule. |

<!-- markdownlint-enable MD013 -->

---

## 6. PR Review and Merge Protocol

### Required Reviews

| Change Type | Min Reviewers | Who |
| ----------- | ------------- | --- |
| Single-domain (e.g., SSP-only) | 1 reviewer | Any other dev |
| Cross-cutting (shared concerns) | 2 reviewers | Domain owners |
| Migration | 2 reviewers | Any two devs |
| Migration squash (#183) | 3 reviewers | All active devs |
| New model or controller | 2 reviewers | Tech lead + 1 |
| CI/workflow change | 1 reviewer | DevOps dev |

### Merge Checklist

```markdown
- [ ] All specs pass (`bundle exec rspec`)
- [ ] RuboCop clean (`bundle exec rubocop`)
- [ ] Brakeman clean (`bundle exec brakeman`)
- [ ] Migration tested up and down
- [ ] No unintended changes to shared files
- [ ] Rebased on latest main (no merge commits)
- [ ] OSCAL schema validation passes (if export changed)
```

---

## 7. Optimal Developer Assignment (4 Developers)

Assuming 4 developers (A, B, C, D) across all 6 phases:

### Phase 1 (Weeks 1-3) -- Full Parallel

| Dev | Issue | Domain |
| --- | ----- | ------ |
| A | #142 Background upload UX | Jobs/Shared |
| B | #178 Safe delete confirmation | Models/Shared |
| C | #100 Regression test suite | Testing |
| D | #134 HTTPS dev environment | Infrastructure |

### Phase 2 (Weeks 4-9) -- Staggered

<!-- markdownlint-disable MD013 -->

| Dev | Sprint 2a (Wk 4-6) | Sprint 2b (Wk 7-9) |
| --- | ------------------- | ------------------- |
| A | #163 Catalog format interop | #177 Catalog locking/SHA |
| B | #149 Status tracking | #176 Profile/CDEF publish |
| C | Expand test coverage from #100 | #148 Publication metadata |
| D | #167 Enterprise nav (early win) | #171 OSCAL diagram (early win) |

<!-- markdownlint-enable MD013 -->

### Phase 3 (Weeks 10-15) -- Entity Creation + STIG Parser

<!-- markdownlint-disable MD013 -->

| Dev | Sprint 3a (Wk 10-12) | Sprint 3b (Wk 13-15) |
| --- | --------------------- | --------------------- |
| A | #175 Profile from baseline | #172 CDEF from Profile (uses #185 for validation) |
| B | #185 STIG XCCDF SV/V to CCI parser | #125 ATO Wizard |
| C | #173 SSP from Profile | #174 SAR from Profile/SSP (uses #185 CDEF validations) |
| D | #95 CRUD API (start early) | #95 CRUD API (finish) |

<!-- markdownlint-enable MD013 -->

### Phase 4 (Weeks 16-18) -- Docs & UX Polish

<!-- markdownlint-disable MD013 -->

| Dev | Issues |
| --- | ------ |
| A | #133 Mapping docs |
| B | #167 Enterprise nav (if not done in Phase 2) |
| C | #171 OSCAL diagram |
| D | overflow / integration testing |

<!-- markdownlint-enable MD013 -->

### Phase 5 (Weeks 19-22) -- API, CI & DB Cleanup

<!-- markdownlint-disable MD013 -->

| Dev | Issues |
| --- | ------ |
| A | #95 CRUD API (if not done in Phase 3) |
| B | #186 Hybrid security scanning CI |
| C | #183 Migration squash (AFTER all migration PRs merged) |
| D | overflow / integration testing |

<!-- markdownlint-enable MD013 -->

### Phase 6 (Weeks 23-26) -- FedRAMP 20x

| Dev | Issues |
| --- | ------ |
| A | #107 FedRAMP 20x extensions |
| B | #108 Sample data (after #107 merges) |
| C | overflow / integration testing |
| D | overflow / integration testing |

### Phase 12 (Upcoming Release) -- OSCAL Foundations & Boundary Sync

Stacked into a single release per dependency order. See § 12 below for full
collision-risk analysis and per-issue file lists.

| Dev | Issues | Lane |
| --- | ------ | ---- |
| A | #397 OSCAL UUID stability (foundational, lightweight) | All export services |
| C | #395 Phase 1 boundary picker + FK inheritance (after #397 merges) | SAP/SAR/SSP/POAM/CDEF/Profile upload paths + boundary model |
| B | #393 sub-part hierarchy tables (after #395 Phase 1; unblocks #396 + #398) | Catalogs / Profiles / SSPs / CDEFs |
| E | #392 Active Storage read for parsers (independent infra fix; can land any time) | DocumentConversionJob + FileUploadable |
| C/B | #395 Phase 2-3 metadata sync + #396 leveraged auth + #398 CDEF→SSP (parallel after #397+#395 P1+#393 land) | Cross-domain |

**STATUS: Phase 12 closed 2026-04-20** (v1.3.0 milestone fully closed: 5/5
issues shipped). Final PR was #408 bundling #396 + #398. The next phase
is gated on local functional testing of the cumulative refactor —
boundary metadata sync, statement-level OSCAL UUIDs, leveraged
authorizations, and CDEF→SSP inheritance all touch the same code paths
and want a real-data shakedown before more product work layers on.

### Post-Phase 12 backlog (no milestone yet)

Pulled from open GitHub issues (9 total, as of 2026-04-20). Grouped by
collision lane so the next batch can be parallelized once functional
testing of #408's bundle clears.

| Lane | Issues | Notes |
| ---- | ------ | ----- |
| **CI / infra (CI-approval-gated)** | #386 SAF CLI EISDIR, #367 SimpleCov threshold, #244 Security gate | All touch `.github/workflows/*` — require explicit user approval. #386 is shipping standalone (small, unblocks security.yml). #367 + #244 should bundle (the gate consumes the threshold). |
| **POAM product surface** | ~~#389 POAM wizard missing OSCAL fields~~ — **COMPLETED 2026-04-26** | Shipped on `feature/389_poam_wizard_and_item_oscal_fields`. Wizard form gains `poam_version` / `oscal_version` defaults + boundary-grouped Source SSP dropdown; show view gets a publish-readiness warning when items are empty. POAM item form gains UI for `props_data` (name/value/class) and `links_data` (href/rel/media-type/text) via a reusable `oscal-repeater` Stimulus controller; controller normalizes `media_type` → `media-type` for OSCAL compliance. Export round-trip validated. **Origins UI deferred to #416** (needs party UUID picker that doesn't exist yet). New related issues filed: **#415** (leveraged-system POAM read-only visibility for leveraging systems), **#416** (POAM item origins UI). |
| **Upload pipeline hardening** | #341 XML document type fingerprinting | Defensive, post-#392. Touches `FileUploadable` and parser entry-points; coordinate with anything else editing those concerns. |
| **Admin / infra** | ~~#402 + #403 AWS Secrets Manager admin credential rotation pair~~ — **COMPLETED 2026-04-26** | Shipped as paired commits on `feature/402_403_admin_credential_rotation`. Adds: `app/services/admin_credential_rotation_service.rb`, `app/controllers/api/v1/admin/credentials_controller.rb`, three new `AuditEvent::ACTIONS` (incl. fix for latent silent-failure of `admin_password_reset`), one new `Role::PERMISSION_KEYS` (`admin.rotate_credentials`), `bootstrap_admin` reconciliation against `SPARC_ADMIN_PASSWORD` env. New env vars: `SPARC_ADMIN_PASSWORD` (ECS-injected), `SPARC_ADMIN_REFRESH_ENABLED` (off by default), `SPARC_ALLOW_CRED_ROTATION` (non-prod gate), `SPARC_PRINT_ROTATED_PASSWORD` (break-glass only). Sparc-iac counterpart: risk-sentinel/sparc-iac#197 (task-def secrets injection + IAM `PutSecretValue` + rotation Lambda). Runbook: `docs/dev/admin_credential_rotation.md`. |
| **OSCAL feature** | ~~#372 Import Authoritative Sources for global/org OSCAL docs~~ — **COMPLETED 2026-04-26** | Shipped on `feature/372_authoritative_sources_import` (8 commits): schema + models + RBAC, promotion workflow + API, federation export/import (HMAC-signed bundles + SPARC_HASH master KDF), bulk import + URL fetch, archive/changelog, NC/LC UI for library + queue + peers, CDEF + Rev 5 mapping updates. Adds: `app/models/back_matter_resource_change.rb`, `app/models/federation_peer.rb`, `app/lib/sparc_key_derivation.rb`, `app/services/{back_matter_resource_promotion,federation_bundle_signing,authoritative_source_federation,back_matter_bulk_import,authoritative_source_fetch}_service.rb`, `app/controllers/{authoritative_sources,promotion_queue,federation_peers}_controller.rb` (UI) + matching `Api::V1::*` API controllers + views. Touches `BackMatterResource` model + `BackMatterBuilder` (now scoped through `.active`) + `Role::PERMISSION_KEYS` (7 new keys, including a backfill of `back_matter.read`/`.write` that #375 was checking but had not registered). New env vars: `SPARC_HASH` (provisioning tracked by sparc-iac issue #195), `SPARC_AUTHORITATIVE_FETCH_ENABLED` (off by default). |
| **Repo cleanup** | #246 Repository Cleanup | Scope-define needed. Best treated as a background lane while a main feature ships. |
| **Crypto / federation hardening** | ~~#419 SPARC_HASH master-key rotation rake + runbook~~ — **COMPLETED 2026-04-25** | Shipped on `feature/419_sparc_hash_rotation_rake` as the v1.4.1 patch. Adds: `app/services/federation_peer_reencryption_service.rb` (idempotent, per-field, decrypt-with-current-first then decrypt-with-old, transactional), `lib/tasks/reencrypt.rake` (`sparc:reencrypt:rotate_master_key`), `docs/SPARC_HASH_ROTATION.md` (runbook). Extends `SparcKeyDerivation` with `derive_from(master, purpose)` and `master_matches_current?(candidate)`. Adds `FederationPeer.build_encryptor_with_master`. Registers `sparc_hash_rotated` AuditEvent action. Production invocation uses `aws ecs run-task` with `containerOverrides` on the existing app task definition — no IaC change required (ECS Exec is blocked in prod). Sparc-iac coordination on risk-sentinel/sparc-iac#200. |
| **Org migration** | ~~#430 GitHub org migration: Rebel-Raiders → risk-sentinel pre-cutover sweep~~ — **COMPLETED 2026-05-01** | Shipped on `feature/430_github_org_migration` ahead of the 5/2-5/3 transfer weekend. String-only sweep across `.github/workflows/{build-sign-publish,security}.yml` (cosign `--certificate-identity-regexp` retargeted at all 3 call sites; `org.opencontainers.image.source`/`vendor` labels updated; cross-repo `repository_dispatch` target + payload `source_repo` retargeted to `risk-sentinel/sparc-iac`), 4 app/view files (admin credentials controller comment + 3 ERBs), 12 public docs (README, ENVIRONMENT_VARIABLES, SPARC_HASH_ROTATION, ADMIN_CREDENTIAL_ROTATION, troubleshooting, api/INVENTORY, api procedure, 3 endpoint docs, 2 dev docs), 6 wiki files (incl. PUSH_TO_WIKI.sh clone URL), 4 compliance artifacts (compliance README, NIST mapping, 2 CDEF `remarks` fields), and 2 missed-glob files (`.env.production.example`, `lib/tasks/admin.rake`). OSCAL prop namespace `https://rebel-raiders.io/sparc-validate/v1` confirmed absent from repo (no preservation work needed). No control-status changes. Coordinated with `risk-sentinel/sparc-iac#204` (lead) and `risk-sentinel/sparc-validate#45`. Post-cutover: re-push `wiki/` to new wiki repo; verify `sparc-compliance-latest` artifact upload from new org. |
| **POAM completion** | ~~#415 Scenario A + #416 + #423 POA&M complete-feature bundle~~ — **COMPLETED 2026-04-27** | Shipped on `feature/415_416_423_poam_complete` (9 commits). Slice 0 extracts shared OSCAL extensibility-array partials (`shared/_oscal_props_array`, `_oscal_links_array`, `_oscal_origins_array`) and a `OscalExtensibilityParams` concern; party picker reads `metadata_extra["parties"]` via new `OscalMetadata#oscal_parties` helper. Slice 1 wires the items form to the shared partials and adds origins UI (closes #416). Slices 2-6 add full admin UI for `PoamRisks`, `PoamRemediations` + nested `PoamMilestones`, `PoamObservations`, `PoamFindings`, `PoamLocalComponents` — same pattern repeated, all consume the shared partials. Slice 7 adds `LeveragedPoamDocumentsController` (read-only) for #415 Scenario A with `poam_document_viewed_by_leveraging_user` audit. Slice 8 round-trip spec asserts items + risks + remediations + milestones + components survive export → re-parse with schema validation. **Carved out**: #422 (cross-instance federated POAM Scenario B — pairs with first federation-with-real-peers deployment). #424 (observation `methods` + finding `target.status` schema-required nested structures) was added back into this PR as slices 10 + 11; closed by this PR alongside #415A, #416, and #423. |

#### Sequencing principles for the next phase

1. **Test the merged Phase 12 bundle first.** #395 (boundary metadata
   sync), #393 (statement hierarchy), #396 (leveraged auth), #398
   (CDEF→SSP), and #408 (the joint #396+#398 PR) all manipulate the
   same models/services. A functional shakedown on real data unblocks
   any product work that touches SSP statements, CDEFs, or boundary
   relationships — i.e. nearly everything in the backlog above except
   the CI/infra items.
2. **CI items (#386, #367, #244)** can ship in parallel with functional
   testing because they don't touch product code paths. **They require
   explicit per-PR user approval per project policy.**
3. **#389 POAM wizard** is the safest first product PR after testing
   clears because POAM doesn't share files with the leveraged-auth /
   CDEF inheritance work that just landed.
4. **#341 XML fingerprinting** lands cleanly only after we know the
   #392 Active Storage path is stable in production — defer until
   testing confirms parser changes hold up.
5. **Admin pair (#402 + #403)** is independent of the product domain
   and can run in a separate lane any time.

---

## 8. File Lock Conventions

When a developer is actively working on a high-collision file,
they "soft lock" it:

### Method: GitHub Issue Comment

Post a comment on your issue:

```text
LOCK: I am actively modifying the following shared files:
- app/models/concerns/oscal_metadata.rb
- app/services/catalog_import_service.rb

Expected unlock: [date or PR merge]
```

### Method: CODEOWNERS (Recommended)

Add `.github/CODEOWNERS` to enforce review requirements:

```text
# Shared concerns -- require 2 reviewers
app/models/concerns/oscal_metadata.rb  @tech-lead @senior-dev
app/services/oscal_schema_validation_service.rb  @tech-lead

# Domain ownership
app/models/ssp_*.rb  @ssp-dev
app/models/sar_*.rb  @sar-dev
app/models/cdef_*.rb  @cdef-dev
app/models/profile_*.rb  @profile-dev
app/models/converter*.rb  @converter-dev
app/controllers/api/  @api-dev
.github/workflows/  @devops-dev
```

---

## 9. Dependency Graph (Visual)

```text
Phase 1 (all parallel):
  #142 -----+
  #178 -----+
  #100 -----+-- all merge to main
  #134 -----+

Phase 2:
  #163 --------------> #177
  #149 ------+-------> #148
             +-------> #176

Phase 3:
  #175 ------+-------> #172 (CDEF, validated by #185) --+
             +-------> #173 --> #174 (SAR, uses #185) --+--> #125
  #185 (STIG parser, parallel with #175) ------+--------+

Phase 4 (all parallel):
  #133 (independent)
  #167 (independent)
  #171 (independent)

Phase 5 (staggered):
  #95  (independent -- API)
  #186 (independent -- CI workflows)
  #183 (GATE: waits for all migration PRs) -----> squash

Phase 6 (FedRAMP 20x -- final):
  #107 --> #108
```

---

## 10. Quick Reference: Can These Issues Run In Parallel?

<!-- markdownlint-disable MD013 -->

| Issue Pair | Parallel? | Risk | Notes |
| ---------- | --------- | ---- | ----- |
| #142 + #178 | YES | Low | Different model layers |
| #142 + #100 | YES | None | Different directories |
| #163 + #149 | YES | Low | Catalog vs cross-cutting status |
| #163 + #177 | **NO** | High | Same catalog service files |
| #149 + #148 | **NO** | Medium | #148 depends on #149 status lifecycle |
| #149 + #176 | **NO** | Medium | #176 depends on #149 status enum |
| #175 + #172 | YES | Low | Different domains (needs #175 concept) |
| #175 + #173 | YES | Low | Different domains (same caveat) |
| #172 + #173 | YES | None | CDEF vs SSP -- zero file overlap |
| #172 + #174 | YES | None | CDEF vs SAR -- zero file overlap |
| #173 + #174 | **NO** | Medium | #174 can source from SSP, needs #173 |
| #185 + #175 | YES | None | STIG parser (Converters) vs Profile -- different domains |
| #185 + #173 | YES | None | STIG parser vs SSP -- different domains |
| #172 + #185 | YES (linked) | Low | CDEF uses #185 STIG/CCI data for validation |
| #174 + #185 | YES (linked) | Low | SAR uses #185 CDEF validations for evidence |
| #186 + #100 | YES | Low | Different workflow files in `.github/` |
| #186 + any app | YES | None | CI pipeline is fully isolated |
| #183 + any migration | **NO** | High | Squash must wait for all migrations |
| #107 + #108 | **NO** | Low | #108 needs #107 schema definitions |
| #95 + any app | YES | None | API namespace is isolated |
| #167 + #171 | YES | None | Different views, 1-line route max |

<!-- markdownlint-enable MD013 -->

---

## 12. Phase 12 -- Upcoming Release: OSCAL Foundations & Boundary Sync

Stacked release covering the architectural rework discovered while testing #390 in production. Issues #397, #395, #393, #392, #396, #398 ship together because each builds on the foundations that the previous one establishes -- splitting them across multiple releases would force repeated reworking of the same files.

### Dependency order (the stack)

```text
                       #397 (UUID stability)
                              |
                              v
                    #395 Phase 1 (boundary picker + FK inheritance)
                              |
                              v
                       #393 (sub-part hierarchy tables)
                              |
                +-------------+-------------+
                v             v             v
   #395 Phase 2-3   #396 (leveraged auth)  #398 (CDEF -> SSP)
   (metadata sync)
```

`#392` (Active Storage read for parsers) is an independent infrastructure fix. It can land at any point in the stack; recommend pairing with `#395 Phase 1` since both touch `FileUploadable`.

### Per-issue collision-risk matrix

<!-- markdownlint-disable MD013 -->

| Order | Issue | Primary Owner | Touched Files | Collision Risk | Notes |
| ----- | ----- | ------------- | ------------- | -------------- | ----- |
| 1 | **#397** OSCAL UUID stability | Dev A (or whoever owns export services) | All 7 `oscal_*_export_service.rb`, `app/models/sap_control.rb`, `sar_*` models, `ssp_control.rb`, `cdef_control.rb`, `profile_control.rb`, schema migration adding `uuid` columns + backfill, round-trip specs | **HIGH** -- touches every export service, but the change is purely "replace `SecureRandom.uuid` with `record.uuid`". Mechanical. | Ship first because every downstream issue depends on stable UUIDs for cross-document linkage |
| 2 | **#395 Phase 1** Boundary picker + FK inheritance + CDEF scope -- **COMPLETED 2026-04-18** | Dev C (SAP/SAR/SSP/POAM owner) | `app/controllers/concerns/file_uploadable.rb`, 5 document upload views (boundary picker partial), `app/views/cdef_documents/_scope_picker.html.erb` (CDEF scope radio + conditional boundary picker), `app/models/concerns/boundary_link_inheritance.rb` (NEW), `cdef_document.rb` (`globally_available` + `organization_id`), `sap_document.rb` + `sar_document.rb` (`include BoundaryLinkInheritance`), migration `20260418085606_add_global_scope_to_cdef_documents.rb` | **HIGH** -- cross-cutting. Same files as #355 (multi-file upload) -- coordinate review. | Smallest #395 phase; biggest immediate UX win (replaces most manual `associate_source` use). CDEF scope ships here too (boundary-specific via `boundary_cdef_documents` OR globally available within org, mirroring `back_matter_resources` pattern). |
| 3 | **#393** Sub-part hierarchy tables -- **COMPLETED 2026-04-18** | Dev B (Profile/CDEF) for Catalog+Profile side, Dev C for SSP side | `db/migrate/20260418155235_create_statement_and_part_tables.rb` (3 tables: `ssp_control_statements`, `cdef_control_statements`, `catalog_control_parts`; FKs `sar_findings.ssp_control_statement_id` + `poam_items.ssp_control_statement_id`), new models, `CatalogPartExtractorService` (generalizes `ControlObjectiveExtractorService`), SSP/CDEF JSON parsers, SAR parser (best-effort statement linkage), Catalog import service, OSCAL SSP/CDEF/SAR/POAM exporters (statement-driven), SSP/CDEF show views with `_statements_table` partial + edit modals (`?statement_id=N`), POAM item form picker, SAR enrich finding badge, control family `_parts_tree` partial, routes `update_statement` | **VERY HIGH** -- mirrored the #390 (objectives) pattern for SSP/CDEF/Catalog. Unblocks #396 + #398. | UUID stability invariant: backfilled rows use `OscalUuidService.derived(parent.uuid, "ssp-statement"|"cdef-statement"|"catalog-part:<name>", part_id)` so already-exported documents round-trip with byte-identical statement UUIDs (#397 contract honored) |
| 4 | **#392** Active Storage read for parsers -- **COMPLETED 2026-04-19** | Dev E (Infrastructure) | `app/jobs/document_conversion_job.rb` (blob.open + retry_on Aws/Net errors + conditional purge_later), `app/controllers/concerns/file_uploadable.rb` (drop tmp write + SAFE_* constants + file_path arg from perform_later), `spec/jobs/document_conversion_job_spec.rb` (10 examples), `spec/services/profile_resolved_catalog_parser_spec.rb` (attach-based fixtures) | **MEDIUM** -- one-line job switch + caller cleanup; eliminated tmp-path Brakeman taint comments | Eliminates ECS web/Sidekiq race ("Errno::ENOENT" failures). New env var `SPARC_PERSIST_S3_BLOB` (default false → purge after success; true → keep for audit/re-parse). Failed parses always retain blob. |
| 5 | **#395 Phase 2-3** Boundary metadata sync + OSCAL `import-*.href` resolution -- **COMPLETED 2026-04-20** | Dev C | `BoundaryMetadataSyncService`, `BoundaryMetadataSyncJob`, `lib/tasks/boundary.rake`, `OscalMetadata.resolve_import_href`/`import_href_for`, `AuthorizationBoundary` (boundary_metadata + profile_document_id + uuid), SSP/POAM added to `BoundaryLinkInheritance`, 4 parsers resolve `uuid:<...>` to FKs, 5 exporters emit `uuid:<sibling.uuid>`, `authorization_boundaries/show.html.erb` sync card + shared boundary_header on 4 document shows | **HIGH** -- cross-domain | Closes #395 entirely. Round-trip: a re-imported OSCAL document now re-binds its cross-document FKs via UUID. |
| 6+7 | **#396 + #398** Leveraged Authorizations + CDEF→SSP auto-population -- **COMPLETED 2026-04-20** | Dev C + Dev B (cross-cutting) | `db/migrate/20260420180000_create_leveraged_auth_and_inheritance_tables.rb` (4 tables/columns: `ssp_control_statement_inheritances` polymorphic, `leveraged_authorizations` boundary pair + crm_type, `leveraged_authorization_components`, `back_matter_resources.crm_type`), new models, `CdefToSspInheritanceService`, `LeveragedAuthorizationService` (populate + responsibility_gaps + cycle detection), `SspJsonParserService` (resolves statements[].links[rel=implements\|inherited] + upserts boundary-level LA from leveraged-authorizations[]), `OscalSspExportService` (emits per-statement `link[rel=implements\|inherited]` + merges legacy+boundary LAs), `LeveragedAuthorizationsController` wizard, `ssp_documents_controller` `refresh_inherited_statements` + `reset_inherited_statement`, `_leveraged_authorizations_card.html.erb`, `_statements_table.html.erb` badges + Reset button, `SspComponent#after_create_commit` auto-populate | **HIGH** -- single polymorphic inheritance table powers both issues | Bundled per user direction. Phase 4 legacy CRM deferred until NIST publishes CRM model. Cycle detection via seen-set walk (64-hop cap). Overridden prose protected from refresh — edits to inherited statements auto-flip `overridden: true` in `update_statement`. |

<!-- markdownlint-enable MD013 -->

### Sequencing rules

1. **#397 must merge before any other Phase 12 issue.** Every downstream issue depends on stable UUIDs -- if they don't merge first, downstream work has to be reworked when UUID-touching exporter code changes.
2. **#395 Phase 1 must merge before #395 Phase 2-3, #396, #398.** Boundary FK inheritance is the foundation for boundary-driven metadata sync and leveraged-authorization linking.
3. **#393 must merge before #396 + #398.** Both depend on statement-level granularity that #393 introduces.
4. **#392 can ship at any time.** No upstream or downstream dependency in this stack.
5. **#394 (current PR for #390) must merge before #393.** #393 generalizes the pattern that #394 establishes.

### Hot files for Phase 12 (lock conventions apply)

| File | Touched by |
| ---- | ---------- |
| `app/controllers/concerns/file_uploadable.rb` | #392, #395 P1 |
| `app/models/authorization_boundary.rb` | #395 P1, #395 P2-3, #396 |
| All 7 `oscal_*_export_service.rb` | #397, #393, #396 (SSP), #398 (SSP+CDEF) |
| All 6 OSCAL parser services | #393 |
| All 6 document show views (control card structure) | #393, #395 P2-3 |
| `app/jobs/document_conversion_job.rb` | #392 |

Devs working on multiple Phase 12 issues should rebase frequently and use `gh pr comment` to coordinate hot-file edits per § 8.

### Cross-cutting concerns

- **OSCAL schema validation**: All Phase 12 issues add new emitted fields (`statement-ids`, `leveraged-authorization`, `link[rel="implements"]`, statement-level UUIDs). Each PR's test plan must include `OscalSchemaValidationService.validate(...)` round-trip checks.
- **Migration safety**: Each issue ships ≥ 1 migration. Per `docs/dev/issue_rules.md` Migration Safety Rules: idempotent guards (`if_not_exists`, `column_exists?`), nullable FKs on existing tables, batched backfills with per-row rescue.
- **Compliance artifacts**: None of these issues are security-critical (data-model + UI). Per `docs/dev/issue_rules.md` step 9, no CDEF or `nist-sp800-53-rev5-mapping.md` updates required.
- **Release notes**: Each issue's GitHub release notes (per `feedback_release_pattern.md`) should call out the OSCAL-spec compliance milestone -- this stack moves SPARC from "OSCAL-import-aware" to "OSCAL-spec-native."

### Reference

NIST OSCAL Catalog, Profile, and Implementation Layers deck (`Day1.2-Dave-OSCAL_Control-inplementation.pdf`) drove most of the Phase 12 issue scoping. Specifically:

- Slide 3: Inheritance chain (Catalog → Profile → CDEF → SSP → SAP → SAR → POA&M) -- justifies #395 boundary-driven FK inheritance
- Slide 4: Common metadata across all 7 models -- justifies #395 Phase 2-3 metadata sync
- Slide 13: CDEF → SSP statement population -- #398
- Slides 14-21: Leveraged authorizations -- #396
- Slide 19: UUID linkage between leveraging/leveraged statements -- #397 prerequisite

---

## 11. Closed / Removed Issues

The following issues from the original plan have been resolved or
removed and are no longer tracked:

<!-- markdownlint-disable MD013 -->

| Issue | Status | Notes |
| ----- | ------ | ----- |
| ~~#106~~ | CLOSED | HTTPS-only traffic with dev exceptions -- implemented |
| ~~#109~~ | REMOVED | ECS Fargate Terraform -- deleted from repository |
| ~~#110~~ | REMOVED | EC2 standalone Terraform -- deleted from repository |
| ~~#111~~ | REMOVED | Azure VM Terraform -- deleted from repository |
| ~~#150~~ | CLOSED | Status tracking -- duplicate of #149, consolidated |
| ~~#162~~ | CLOSED | OSCAL XML catalog import with adjustable parameters -- implemented |

<!-- markdownlint-enable MD013 -->

---

## Summary

- **Total issues tracked:** 64 (23 original + 41 ad-hoc/new)
- **Completed:** 64 issues (Phases 1-10 + #361 + #372 + #389 + #402 + #403 + #415A + #416 + #419 + #423 + #424)
- **Remaining:** 5 issues (Phase 10: #244, #246; Phase 11: #341, #344, #367); follow-ups filed: #422 (POAM Scenario B cross-instance federated visibility)
- **Removed issues:** #109, #110, #111 (Terraform infra -- deleted)
- **Maximum parallel developers:** 4-5 in most phases
- **Phases 1-9:** COMPLETE (2026-03-14 through 2026-03-21)
- **Phase 10:** Nearly complete (2 remaining: #244, #246)
- **Phase 11:** Planned -- OSCAL integrity, enterprise features, infrastructure
