# SPARC Developer Collision Avoidance Plan

Companion to `Implementation_plan.md`. Maps every issue to exact
files/domains, assigns developer lanes, and defines branching rules
so 3-5 developers can work in parallel without stepping on each
other.

---

## 1. Domain Ownership Map

The codebase divides into **12 isolated domains**. Each issue is
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
| **POAM/SAP** | `poam_document.rb`, `sap_document.rb`, related controllers/services | Dev C |
| **Auth/Users** | `user.rb`, `role.rb`, `identity.rb`, sessions, registrations, `admin/*` controllers | Dev D |
| **Boundary/Org** | `authorization_boundary.rb`, `organization.rb`, boundary controllers, admin org views | Dev D |
| **Evidence** | `evidence.rb`, `attestation.rb`, `evidences_controller` | Dev D |
| **API (v1)** | `api/v1/*_controller.rb`, API serializers, API auth middleware | Dev D |
| **Infrastructure** | `terraform/`, `docker-compose.yml`, `Dockerfile`, CI workflows | Dev E |
| **Shared/Cross-cutting** | `OscalMetadata` concern, `oscal_schema_validation_service`, `document_duplication_service`, `application.html.erb` layout, shared partials, routes, Stimulus controllers | Requires PR review from 2 devs |

<!-- markdownlint-enable MD013 -->

---

## 2. Issue-to-Domain Assignment with File Collision Risk

### Phase 1 -- All issues are collision-safe (different domains)

<!-- markdownlint-disable MD013 -->

| Issue | Domain | Files Modified | Collision Risk |
| ----- | ------ | -------------- | -------------- |
| **#142** Background upload UX | Shared (Jobs) | `document_conversion_job.rb`, `conversion_job.rb` model, new Stimulus controller, document controller upload actions | **LOW** -- touches job infra, not domain logic |
| **#178** Safe delete | Shared (Models) | `before_destroy` callbacks across all document models, new shared modal partial, new Stimulus controller | **LOW** -- adds callbacks, doesn't change business logic |
| **#100** Regression testing | Testing | `spec/` directory (new files), `Gemfile`, `.github/workflows/`, `spec_helper.rb` | **NONE** -- additive only, own directory |
| **#134** HTTPS dev | Infrastructure | `config/puma.rb`, `config/environments/development.rb`, `docker-compose.yml` | **NONE** -- config files only |

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

| Issue | Domain | Files Modified | Collision Risk |
| ----- | ------ | -------------- | -------------- |
| **#163** Format interop | Catalog | `catalog_import_service.rb`, `oscal_catalog_export_service.rb`, `oscal_format_detection_service.rb`, `control_catalog.rb` | **NONE** with non-Catalog work |
| **#177** Catalog locking/SHA | Catalog | `catalog_import_service.rb`, `control_catalog.rb`, `catalog_control.rb`, catalog views | **HIGH with #163** -- same files |
| **#149** Status tracking | Shared (Models) | All 6 document models (status enum), all 6 document controllers (publish/copy guards), all document views (badges) | **MEDIUM** -- touches many models but only adds `status` enum + callbacks |
| **#148** Publication metadata | Shared (Services) | All document controllers (publish action), export services, new `PublicationService`, schema validation | **MEDIUM with #149** -- both touch controllers |
| **#176** Profile/CDEF publish | Profile + CDEF | `profile_document.rb`, `cdef_document.rb`, their controllers, `document_duplication_service.rb` | **MEDIUM with #149** -- both touch profile/cdef models |

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

### Phase 3 -- Sequential chain but different document domains

<!-- markdownlint-disable MD013 -->

| Issue | Domain | Files Modified | Collision Risk |
| ----- | ------ | -------------- | -------------- |
| **#175** Profile from baseline | Profile | `profile_documents_controller.rb`, `profile_document.rb`, profile views, `oscal_profile_export_service.rb` | **NONE** with SSP/SAR/CDEF work |
| **#172** CDEF from Profile | CDEF | `cdef_documents_controller.rb`, `cdef_document.rb`, new `CdefFromProfileService`, CDEF views | **NONE** with SSP/SAR work |
| **#173** SSP from Profile | SSP | `ssp_documents_controller.rb`, `ssp_document.rb`, `ssp_wizard_service.rb`, SSP views | **NONE** with CDEF/SAR work |
| **#174** SAR from Profile/SSP | SAR | `sar_documents_controller.rb`, `sar_document.rb`, `sar_wizard_service.rb`, SAR views | **NONE** with SSP/CDEF work |
| **#125** ATO Wizard | NEW domain | New `AtoWizardController`, new `AtoPackageService`, new views, new model | **LOW** -- mostly new files |

<!-- markdownlint-enable MD013 -->

**Phase 3 Parallelism Strategy:**

```bash
Sprint 3a (weeks 1-3):
  Dev A: #175 (Profile from baseline)  -- Profile domain
  Dev B: #172 (CDEF from Profile)      -- CDEF domain
  Dev C: #173 (SSP from Profile)       -- SSP domain

Sprint 3b (weeks 3-6):
  Dev A: #125 (ATO Wizard)             -- New domain
  Dev C: #174 (SAR from Profile/SSP)   -- SAR domain
  Dev B: overflow / integration testing
```

> **Critical rule:** #175 must merge first (creates Published
> Profiles that #172, #173, #174 consume). #172/#173 can run in
> parallel. #174 needs #173. #125 needs all four.

---

### Phase 4 -- Highly parallelizable (different domains)

<!-- markdownlint-disable MD013 -->

| Issue | Domain | Files Modified | Collision Risk |
| ----- | ------ | -------------- | -------------- |
| **#107** FedRAMP 20x | New (FedRAMP) | New models/services, extends export services, dashboard | **LOW** -- mostly new code |
| **#108** Sample data | Seeds/Samples | `db/seeds.rb`, new `samples/` directory | **NONE** -- own directory |
| **#133** Mapping docs | Documentation | `docs/` directory, minor service annotations | **NONE** -- documentation |
| **#167** Enterprise nav | UI/Navigation | `home/index.html.erb`, layout partials, `home_controller.rb` | **NONE** with other Phase 4 work |
| **#171** OSCAL diagram | UI (new page) | New view file, `config/routes.rb` (1 line), layout nav link | **NONE** -- new page |

<!-- markdownlint-enable MD013 -->

**Phase 4 Parallelism: All 5 issues can run simultaneously.**

```text
Dev A: #107 (FedRAMP 20x)
Dev B: #108 (sample data)     -- waits for #107 schema
Dev C: #133 (mapping docs)
Dev D: #167 (enterprise nav)
Dev E: #171 (OSCAL diagram)
```

---

### Phase 5 -- Fully parallelizable (zero overlap)

<!-- markdownlint-disable MD013 -->

| Issue | Domain | Files Modified | Collision Risk |
| ----- | ------ | -------------- | -------------- |
| **#95** CRUD API | API | New `api/v1/users_controller.rb`, `api/v1/projects_controller.rb`, routes | **NONE** -- new files in API namespace |
| **#109** ECS Fargate | Infrastructure | New `terraform/aws-ecs-fargate/` directory | **NONE** -- own directory |
| **#110** EC2 standalone | Infrastructure | New `terraform/aws-ec2/` directory | **LOW with #109** -- shared Terraform modules |
| **#111** Azure VM | Infrastructure | New `terraform/azure-vm/` directory | **NONE** -- different cloud provider |

<!-- markdownlint-enable MD013 -->

**Phase 5 Parallelism: All 4 issues can run simultaneously.**

```text
Dev A: #95  (CRUD API)
Dev B: #109 (ECS Fargate)
Dev C: #110 (EC2)         -- coordinate shared modules
Dev D: #111 (Azure VM)
```

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
| #142 | Add `processed_count`, `total_count` to `conversion_jobs` | `conversion_jobs` |
| #177 | Add `file_digest` to `control_catalogs`; possibly `locked` to `catalog_controls` | `control_catalogs`, `catalog_controls` |
| #149 | Standardize `status` enum across all 6 document tables; add `published_at` | `ssp_documents`, `sar_documents`, `cdef_documents`, `profile_documents`, `sap_documents`, `poam_documents` |
| #148 | Add `published_version` columns (or use existing `metadata_extra` jsonb) | Possibly all document tables |
| #175 | Add `source_catalog_id`/`source_profile_id` to `profile_documents` | `profile_documents` |
| #172 | Add `source_profile_id` to `cdef_documents` | `cdef_documents` |
| #173 | Add `source_profile_id` to `ssp_documents` | `ssp_documents` |
| #174 | Add `source_profile_id`/`source_ssp_id` to `sar_documents` | `sar_documents` |
| #125 | Possibly new `ato_packages` table | New table |
| #107 | Possibly new `ksi_indicators` table | New table |

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

---

## 5. Shared File Conflict Zones (Hot Files)

These files are touched by multiple issues. Extra care required.

<!-- markdownlint-disable MD013 -->

| File | Issues That Touch It | Mitigation |
| ---- | -------------------- | ---------- |
| `config/routes.rb` | #95, #125, #171, #167 | Each adds routes in different blocks. Use section comments: `# === ATO Wizard ===`. Merge conflicts are trivial (additive lines). |
| `app/views/layouts/application.html.erb` | #171 (nav link), #167 (rename), #142 (progress bar) | Each touches different parts of the layout. Use partials to isolate: `render "shared/progress_bar"`, `render "shared/nav_links"`. |
| `Gemfile` | #100 (test gems), #171 (mermaid?), #95 (serializer gem) | Additive only. Merge conflicts are trivial. Run `bundle install` after merge. |
| `app/models/concerns/oscal_metadata.rb` | #148, #149, #177 | **HIGH RISK.** Assign one developer to this concern per sprint. Others wait for merge. |
| `app/services/oscal_schema_validation_service.rb` | #148, #125, #107 | Additive methods. Each adds a new validation method. Low conflict if methods are namespaced. |
| `app/services/document_duplication_service.rb` | #176, #172, #173, #174 | Each document type adds its own `dup_*` method. Low conflict if well-separated. |
| `db/seeds.rb` | #108 (dual mode), #107 (FedRAMP seeds) | Use separate seed files: `db/seeds/nist_traditional.rb`, `db/seeds/fedramp_20x.rb`. Main `seeds.rb` just dispatches. |

<!-- markdownlint-enable MD013 -->

---

## 6. PR Review and Merge Protocol

### Required Reviews

| Change Type | Min Reviewers | Who |
| ----------- | ------------- | --- |
| Single-domain (e.g., SSP-only) | 1 reviewer | Any other dev |
| Cross-cutting (shared concerns) | 2 reviewers | Domain owners |
| Migration | 2 reviewers | Any two devs |
| New model or controller | 2 reviewers | Tech lead + 1 |
| CI/workflow change | 1 reviewer | DevOps dev |
| Terraform (IaC) | 1 reviewer | Infra dev |

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

Assuming 4 developers (A, B, C, D) across all 5 phases:

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

### Phase 3 (Weeks 10-15) -- Domain Isolation

<!-- markdownlint-disable MD013 -->

| Dev | Sprint 3a (Wk 10-12) | Sprint 3b (Wk 13-15) |
| --- | --------------------- | --------------------- |
| A | #175 Profile from baseline | #125 ATO Wizard (start) |
| B | #172 CDEF from Profile | #125 ATO Wizard (finish) |
| C | #173 SSP from Profile | #174 SAR from Profile/SSP |
| D | #95 CRUD API (start early) | #95 CRUD API (finish) |

<!-- markdownlint-enable MD013 -->

### Phase 4+5 (Weeks 16-20) -- Full Parallel

| Dev | Issues |
| --- | ------ |
| A | #107 FedRAMP 20x extensions |
| B | #108 Sample data + #133 Mapping docs |
| C | #109 ECS Fargate + #110 EC2 (shared TF) |
| D | #111 Azure VM |

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
app/controllers/api/  @api-dev
terraform/  @infra-dev
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
  #175 ------+-------> #172  ------+
             +-------> #173 --> #174 --> #125
             +--------------------------> #125

Phase 4 (all parallel):
  #107 --> #108
  #133 (independent)
  #167 (independent)
  #171 (independent)

Phase 5 (all parallel):
  #95  (independent)
  #109 (independent, share TF modules with #110)
  #110 (independent)
  #111 (independent)
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
| #107 + #108 | **NO** | Low | #108 needs #107 schema definitions |
| #109 + #110 | YES | Low | Shared TF modules, different dirs |
| #109 + #111 | YES | None | Different cloud providers |
| #95 + any app | YES | None | API namespace is isolated |
| #167 + #171 | YES | None | Different views, 1-line route max |

<!-- markdownlint-enable MD013 -->

---

## Summary

- **Maximum parallel developers:** 4-5 in most phases
- **Zero-conflict pairs:** 70% of issue combinations
- **Highest-risk shared files:** `oscal_metadata.rb`,
  `catalog_import_service.rb`, `routes.rb`
- **Key sequencing constraints:** #163 before #177,
  #149 before #148/#176, #175 before #172/#173/#174,
  all entity creation before #125
- **Estimated time savings from parallelism:** about 40%
  (from 24 weeks sequential to 14-16 weeks with 4 devs)
