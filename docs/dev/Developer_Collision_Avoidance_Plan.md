# SPARC Developer Collision Avoidance Plan

Companion to `Implemenation_plan.md`. Maps every issue to exact
files/domains, assigns developer lanes, and defines branching rules
so 3-5 developers can work in parallel without stepping on each
other.

**Last updated:** 2026-03-21

---

## 1. Domain Ownership Map

The codebase divides into **13 isolated domains**. Each issue is
assigned to exactly one primary domain. A developer "owns" a domain
lane for a sprint.

<!-- markdownlint-disable MD013 -->

| Domain | Key Files | Primary Owner |
| ------ | --------- | ------------- |
| **Catalog** | `catalog_import_service`, `catalog_builder_service`, `control_catalog.rb`, `catalog_control.rb`, `control_family.rb`, `control_catalogs_controller`, `catalog_controls_controller`, views under `control_catalogs/`, `catalog_controls/` | Dev A |
| **Profile** | `profile_document.rb`, `profile_control.rb`, `profile_documents_controller`, `oscal_profile_export_service`, `oscal_resolved_profile_catalog_service`, views under `profile_documents/`, `profile_controls/` | Dev B |
| **SSP** | `ssp_document.rb`, `ssp_control.rb`, `ssp_documents_controller`, `ssp_wizard_service`, `ssp_*_parser_service`, `oscal_ssp_export_service`, views under `ssp_documents/` | Dev C |
| **SAR** | `sar_document.rb`, `sar_control.rb`, `sar_documents_controller`, `sar_wizard_service`, `sar_*_parser_service`, `oscal_sar_export_service`, views under `sar_documents/` | Dev C |
| **CDEF** | `cdef_document.rb`, `cdef_control.rb`, `cdef_documents_controller`, `cdef_*_parser_service`, `oscal_component_definition_export_service`, views under `cdef_documents/` | Dev B |
| **Converters** | `converter.rb`, `converter_entry.rb`, `converters_controller.rb`, `cci_refresh_service.rb`, `framework_mapping_generator_service.rb`, views under `converters/` | Dev A |
| **POAM/SAP** | `poam_document.rb`, `sap_document.rb`, related controllers/services | Dev C |
| **Auth/Users** | `user.rb`, `role.rb`, `identity.rb`, sessions, registrations, `admin/*` controllers | Dev D |
| **Boundary/Org** | `authorization_boundary.rb`, `organization.rb`, boundary controllers, admin org views | Dev D |
| **Evidence** | `evidence.rb`, `attestation.rb`, `evidences_controller` | Dev D |
| **API (v1)** | `api/v1/*_controller.rb`, API serializers, API auth middleware | Dev D |
| **CI/Infrastructure** | `.github/workflows/`, `docker-compose.yml`, `Dockerfile`, CI pipelines | Dev E |
| **Shared/Cross-cutting** | `OscalMetadata` concern, `oscal_schema_validation_service`, `document_duplication_service`, `application.html.erb` layout, shared partials, routes, Stimulus controllers, `db/migrate/` | Requires PR review from 2 devs |

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
| [ ] | **#234** Avatar upload crop/scale/center | User/UI | `app/models/user.rb`, `app/controllers/registrations_controller.rb`, `app/views/registrations/`, new Stimulus crop controller, `app/assets/stylesheets/` | **NONE** -- isolated to user profile |
| [ ] | **#237** Data Quality card on catalog show | Catalog UI | `app/views/control_catalogs/show.html.erb`, `control_catalogs_controller.rb` (new helper), possibly new partial `_data_quality_card.html.erb` | **NONE** -- Catalog domain only |
| [ ] | **#244** Security gate (threshold merge/deploy blocking) | CI/Infrastructure | `.github/workflows/security.yml` (new gate job), possibly new `.github/security-thresholds.yml` config | **NONE** -- CI files only |
| [ ] | **#246** Repository cleanup & OSCAL schema validation overhaul | Shared/Validation | `app/services/oscal_schema_validation_service.rb`, schema fixtures in `spec/fixtures/`, `docs/` cleanup, stale file removal | **LOW** -- validation service shared |
| [ ] | **#249** Mutually exclusive API auth modes (local/oidc/hybrid) | API/Auth | `app/controllers/concerns/api_authentication.rb` (REWRITE to strategy pattern), new `app/auth_strategies/`, `config/initializers/api_auth.rb` (NEW), `user.rb` (add `service_account` column), migration, spec files | **LOW** -- API auth is isolated |
| [ ] | **#250** API discovery endpoint (GET /api/v1/available) | API | `app/controllers/api/v1/base_controller.rb` or new `api/v1/discovery_controller.rb`, `config/routes.rb` | **NONE** -- additive API endpoint |

<!-- markdownlint-enable MD013 -->

**Phase 10 Parallelism: All 6 issues can run simultaneously (different domains).**

```text
Dev A: #249 (API auth modes)       -- API/Auth domain
Dev B: #244 (security gate)        -- CI/Infrastructure domain
Dev C: #246 (repo cleanup/schema)  -- Shared/Validation domain
Dev D: #237 (data quality card)    -- Catalog UI domain
      #234 (avatar upload)        -- User/UI domain
      #250 (API discovery)        -- API domain (after #249)
```

> **Recommended order:** #249 and #244 first (security-critical),
> then #246 (tech debt), #237, #250, #234 (UX improvements).

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
| `.github/workflows/` | #100 (CI test), #186 (security scanning) | Different workflow files. #100 adds test runner; #186 adds security pipeline. **LOW** risk. |
| `db/seeds.rb` | #108 (dual mode), #107 (FedRAMP seeds) | Both in Phase 6 (sequential: #107 then #108). Use separate seed files: `db/seeds/nist_traditional.rb`, `db/seeds/fedramp_20x.rb`. Main `seeds.rb` just dispatches. |
| `db/migrate/` | All migration issues + #183 (squash) | **HIGH RISK for #183.** Squash must be the last migration-related PR to merge. See Section 4 rule 6. |

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

- **Total issues tracked:** 42 (23 original + 19 ad-hoc/new)
- **Completed:** 36 issues (Phases 1-9 + ad-hoc)
- **Remaining:** 6 issues (Phase 10: #234, #237, #244, #246, #249, #250)
- **Removed issues:** #109, #110, #111 (Terraform infra -- deleted)
- **Maximum parallel developers:** 4-5 in most phases
- **Zero-conflict pairs in Phase 10:** 100% (all different domains)
- **Highest-priority Phase 10 issues:** #249 (API auth modes -- security),
  #244 (security gate -- CI hardening)
- **Key Phase 10 sequencing:** #250 (API discovery) recommended after
  #249 (auth modes) since discovery should reflect the active auth mode.
  All other Phase 10 issues are fully independent.
- **Phases 1-9:** COMPLETE (2026-03-14 through 2026-03-21)
- **Phase 10:** In progress (ongoing platform hardening and polish)
