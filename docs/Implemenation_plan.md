# SPARC Open GitHub Issues -- Implementation Strategy

Structured, prioritized roadmap for the open issues in the SPARC
GitHub repository.

**Last updated:** 2026-03-15

---

## Guiding Principles

<!-- markdownlint-disable MD013 -->

- **Prioritization** -- High-priority bugs and foundational items first
- **Phased delivery** -- Stability -> core OSCAL -> advanced features -> deployment polish
- **Dependencies respected** -- Prerequisites completed before dependent work
- **Testing-first mindset** -- Regression suite (#100) early
- **Compliance focus** -- NIST OSCAL schema validation on all related changes
- **Team size** -- 3-5 developers (adjustable)
- **Sprint length** -- 2-4 weeks
- **Total estimated duration** -- 16-24 weeks (~4-6 months) with overlap

<!-- markdownlint-enable MD013 -->

---

## Issue Process

Standard workflow for every issue in the SPARC phased roadmap:

1. Pull from Main unless otherwise noted
2. Assign the issue to me
3. Review the issue and updated notes
4. Start a fresh branch `feature/` or `bug/` based on the issue
   with the issue number in the branch name
5. Create a plan
6. Implement the approved plan
7. Troubleshoot any issues
8. Appropriately update:
   - `docs/Implemenation_plan.md`
   - `docs/Developer_Collision_Avoidance_Plan.md`
   - Release notes so they are all stacked
   - Regression testing
9. Commit / push changes
    - Reference the issue in any commit messages
10. Wait for user testing
    - Functional testing
    - Review regression report(s)
11. Create a PR
    - Reference the Issue so it will close on merge
    - Wait for the PR to be merged by the user before moving forward

---

## Grouped Issues by Theme

### 1. Bugs & Quick Wins (High priority -- Fix first)

<!-- markdownlint-disable MD013 -->

- [x] #142 -- Large Excel uploads block UI (background + progress UX) -- **COMPLETED 2026-03-14**
- [x] #178 -- Safe delete confirmation with dependency checks -- **COMPLETED 2026-03-14**

### 2. Testing & Developer Experience (Foundation)

- [x] #100 -- Comprehensive automated regression testing suite -- **COMPLETED 2026-03-14**

- [x] #134 -- Enable HTTPS in development environment (mkcert + Rails config) -- **COMPLETED 2026-03-14**

### 3. OSCAL Core (Import/Export, Publication, Status)

- [x] #163 -- Unified catalog import/export (JSON/YAML/XML interoperability) -- **COMPLETED 2026-03-15**
- [x] #177 -- Extend Catalog import & management (locking, SHA digest, baseline impacts) -- **COMPLETED 2026-03-15**
- [x] #148 -- OSCAL-compliant publication process for key document types -- **COMPLETED 2026-03-15**
- [x] #149 -- Status tracking for Baselines/Profiles, Components, Documents -- **COMPLETED 2026-03-15**
- [ ] #176 -- Unified publication process for Profiles and Component Definitions

### 4. OSCAL Entity Creation & Workflows

- [ ] #175 -- Build Published Profile creation from baseline
- [ ] #185 -- Automate extraction of SV/V to CCI mappings from DISA STIGs (XCCDF parser for CDEF validation)
- [ ] #172 -- Component Definition (CDEF) creation & import (incl. from Profile, validated via STIG/CCI)
- [ ] #173 -- System Security Plan (SSP) creation & import (incl. from Profile)
- [ ] #174 -- Security Assessment Report (SAR) creation & import (incl. from Profile/SSP, uses CDEF validations)
- [ ] #125 -- End-to-end wizard for complete ATO Authorization Package

### 5. Advanced OSCAL & Compliance Extensions

- [ ] #107 -- Expand to support FedRAMP 20x framework
- [ ] #108 -- Expand sample data for FedRAMP 20x + traditional NIST 800-53
- [ ] #133 -- Documentation & guidance for building OSCAL data mapping files

### 6. UI/UX & Navigation Improvements

- [ ] #167 -- Enterprise/Organization visibility & navigation for admins
- [ ] #171 -- Interactive OSCAL document relationship diagram (Mermaid)

### 7. API & Backend Enhancements

- [ ] #95 -- Full CRUD API endpoints for Users and Projects (server mode only)

### 8. DISA STIG & Framework Mapping

- [ ] #185 -- (Moved to Theme 4 / Phase 3 -- prerequisite for CDEF validation and SAR evidence)

### 9. CI/CD & Security Scanning

- [ ] #186 -- Hybrid security scanning in GitHub Actions (Trivy + CodeQL/Semgrep + Brakeman + SAF CLI)

### 10. Database Maintenance

- [ ] #183 -- Squash accumulated migrations into a single consolidated migration file

<!-- markdownlint-enable MD013 -->

---

## Phased Roadmap

### Phase 1: Stabilization & Foundations (2-4 weeks)

**Goal:** Prevent data loss, improve dev experience, establish testing safety net

<!-- markdownlint-disable MD013 -->

| Status | Issue | Description | Priority |
| ------ | ----- | ----------- | -------- |
| [x] | #142 | Background jobs + Turbo Streams/polling for large Excel uploads | **HIGH** |
| [x] | #178 | Dependency-aware delete modal across all OSCAL entities | **HIGH** |
| [x] | #100 | RSpec/Capybara + RuboCop/Brakeman in CI pipeline -- **COMPLETED 2026-03-14** | **HIGH** |
| [x] | #134 | HTTPS localhost via mkcert for dev environment -- **COMPLETED 2026-03-14** | MEDIUM |

<!-- markdownlint-enable MD013 -->

**Deliverables:** Stable dev env, >70-80% regression coverage, safe deletes

**Parallelism:** All 4 issues can run simultaneously with 4 developers.

```text
Dev A: #142 (background upload UX)
Dev B: #178 (safe delete confirmations)
Dev C: #100 (regression test suite)
Dev D: #134 (HTTPS dev environment)
```

> **Merge order:** #134 first (config only), then #100
> (test infra), then #142 and #178 (no conflict).

---

### Phase 2: OSCAL Import/Export & Publication Core (4-6 weeks)

**Goal:** Solid, interoperable, publishable OSCAL foundation

<!-- markdownlint-disable MD013 -->

| Status | Issue | Description | Priority | Dependencies |
| ------ | ----- | ----------- | -------- | ------------ |
| [x] | #163 | YAML + full XML enhancement support, round-trip tests -- **COMPLETED 2026-03-15** | **HIGH** | None |
| [x] | #149 | Status enum + lifecycle rules across all document types -- **COMPLETED 2026-03-15** | **HIGH** | None |
| [x] | #177 | Catalog locking, universal SHA digest, baseline impact multi-select -- **COMPLETED 2026-03-15** | **HIGH** | AFTER #163 merges |
| [ ] | #148 | Standardized publication metadata + validation | MEDIUM | AFTER #149 merges |
| [ ] | #176 | Unified publish/copy logic for Profiles & CDEFs | MEDIUM | AFTER #149 merges |

<!-- markdownlint-enable MD013 -->

**Deliverables:** All-format import/export, immutable published artifacts

**Parallelism Strategy:**

```text
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

### Phase 3: OSCAL Entity Creation, STIG Parsing & ATO Wizard (4-6 weeks)

**Goal:** Full artifact lifecycle + STIG-based CDEF
validation + guided ATO package generation

<!-- markdownlint-disable MD013 -->

| Status | Issue | Description | Priority | Dependencies |
| ------ | ----- | ----------- | -------- | ------------ |
| [ ] | #175 | Profile creation from baseline + parameter validation | **HIGH** | Phase 2 complete |
| [x] | #185 | STIG XCCDF parser: SV/V to CCI extraction for CDEF validation & evidence | **HIGH** | None (builds on Converters domain) |
| [ ] | #172 | CDEF creation/import from Profile, validated via STIG/CCI mappings | **HIGH** | AFTER #175 merges; #185 for validation |
| [ ] | #173 | SSP creation/import from Profile | **HIGH** | AFTER #175 merges |
| [ ] | #174 | SAR creation/import from Profile or SSP (uses CDEF STIG validations) | MEDIUM | AFTER #173 and #185 merge |
| [ ] | #125 | Multi-step ATO wizard (all OSCAL layers) | MEDIUM | AFTER #172, #173, #174 merge |

<!-- markdownlint-enable MD013 -->

**Deliverables:** End-to-end traceable ATO package ZIP
export, automated STIG-to-CCI-to-NIST traceability

**Parallelism Strategy:**

```text
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
> parallel with #175 (different domain). #172 benefits from
> #185 (STIG/CCI data for CDEF validation). #174 needs #173
> and #185 (CDEF validation for SAR evidence). #125 needs all.

---

### Phase 4: Documentation & UX Polish (3-4 weeks)

**Goal:** Better navigation, documentation, interactive diagrams

<!-- markdownlint-disable MD013 -->

| Status | Issue | Description | Priority | Dependencies |
| ------ | ----- | ----------- | -------- | ------------ |
| [ ] | #133 | OSCAL data mapping documentation & guidance | MEDIUM | None |
| [ ] | #167 | Enterprise/Organization visibility & navigation | MEDIUM | None |
| [ ] | #171 | Mermaid OSCAL relationship diagram | MEDIUM | None |

<!-- markdownlint-enable MD013 -->

**Deliverables:** Improved admin UX, interactive OSCAL
diagram, comprehensive mapping docs

**Parallelism: All 3 issues can run simultaneously.**

```text
Dev A: #133 (mapping docs)
Dev B: #167 (enterprise nav)
Dev C: #171 (OSCAL diagram)
```

---

### Phase 5: API, CI/CD & Database Cleanup (3-4 weeks)

**Goal:** Programmatic access, security scanning, clean migration history

<!-- markdownlint-disable MD013 -->

| Status | Issue | Description | Priority | Dependencies |
| ------ | ----- | ----------- | -------- | ------------ |
| [ ] | #95 | Versioned REST API for Users/Projects with RBAC | MEDIUM | None |
| [ ] | #186 | Hybrid security scanning CI (Trivy + SAST + SAF CLI + HDF output) | MEDIUM | None |
| [ ] | #183 | Squash all migrations into single consolidated file | LOW | AFTER all migration PRs merge |

<!-- markdownlint-enable MD013 -->

**Deliverables:** OpenAPI docs, multi-tool security CI pipeline, clean `db/migrate/`

**Parallelism Strategy:**

```text
Dev A: #95  (CRUD API)          -- API namespace, isolated
Dev B: #186 (security scanning) -- CI workflows only
Dev C: #183 (migration squash)  -- AFTER all migration PRs merge
```

> **Critical rule:** #183 (migration squash) is a gate -- it must
> wait until every issue with pending migrations has merged. This
> includes #142, #149, #148, #177, #175, #172, #173, #174, #125.
> After squash, new migrations start from a clean baseline.

---

### Phase 6: FedRAMP 20x (final phase -- 3-4 weeks)

**Goal:** FedRAMP 20x extensions + comprehensive sample data

<!-- markdownlint-disable MD013 -->

| Status | Issue | Description | Priority | Dependencies |
| ------ | ----- | ----------- | -------- | ------------ |
| [ ] | #107 | FedRAMP 20x extensions (KSIs, automation, new models) | **HIGH** | Phases 1-5 complete |
| [ ] | #108 | Dual sample sets + seed script flags (FedRAMP 20x + traditional NIST) | MEDIUM | AFTER #107 merges |

<!-- markdownlint-enable MD013 -->

**Deliverables:** FedRAMP 20x support, comprehensive sample/seed data

```text
Dev A: #107 (FedRAMP 20x)          -- Phase 6a
Dev B: #108 (sample data)          -- Phase 6b, AFTER #107 merges
```

> **Critical rule:** #107 must merge before #108 starts
> (#108 needs #107 schema definitions).

---

## Closed / Removed Issues

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

## Summary Timeline

<!-- markdownlint-disable MD013 -->

| Phase | Duration | Key Focus | Issues | Parallelizable? |
| ----- | -------- | --------- | ------ | --------------- |
| 1 | 2-4 weeks | Bugs + Testing + Dev Env | #142, #178, #100, #134 | Yes (all 4) |
| 2 | 4-6 weeks | OSCAL Core (Import/Export/Publication) | #163, #149, #177, #148, #176 | Staggered (2a/2b) |
| 3 | 4-6 weeks | Entity Creation + STIG Parser + ATO Wizard | #175, #185, #172, #173, #174, #125 | Staggered (3a/3b) |
| 4 | 3-4 weeks | Docs + UX Polish | #133, #167, #171 | Yes (all 3) |
| 5 | 3-4 weeks | API + CI/CD + DB Cleanup | #95, #186, #183 | Yes (with #183 gate) |
| 6 | 3-4 weeks | FedRAMP 20x | #107, #108 | Sequential |

<!-- markdownlint-enable MD013 -->

**Total open issues:** 23 (20 original + 3 new: #183, #185, #186)
**Estimated duration:** 18-24 weeks with 4 developers working in parallel
