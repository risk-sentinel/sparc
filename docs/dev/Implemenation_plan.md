# SPARC Open GitHub Issues -- Implementation Strategy

Structured, prioritized roadmap for the open issues in the SPARC
GitHub repository.

**Last updated:** 2026-03-21

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

See **[`docs/dev/issue_rules.md`](issue_rules.md)** for the complete mandatory
workflow, hard guardrails, compliance artifact update requirements, and
authentication mode coverage matrix.

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
- [x] #176 -- Unified publication process for Profiles and Component Definitions -- **COMPLETED 2026-03-15**

### 4. OSCAL Entity Creation & Workflows

- [x] #175 -- Build Published Profile creation from baseline -- **COMPLETED 2026-03-15**
- [x] #185 -- Automate extraction of SV/V to CCI mappings from DISA STIGs (XCCDF parser for CDEF validation) -- **COMPLETED 2026-03-15**
- [x] #172 -- Component Definition (CDEF) creation & import (incl. from Profile, validated via STIG/CCI) -- **COMPLETED 2026-03-16**
- [x] #173 -- System Security Plan (SSP) creation & import (incl. from Profile) -- **COMPLETED 2026-03-18**
- [x] #174 -- Security Assessment Report (SAR) creation & import (incl. from Profile/SSP, uses CDEF validations) -- **COMPLETED 2026-03-18**
- [x] #125 -- End-to-end wizard for complete ATO Authorization Package -- **COMPLETED 2026-03-19**

### 5. Advanced OSCAL & Compliance Extensions

- [x] #107 -- Expand to support FedRAMP 20x framework -- **COMPLETED 2026-03-21**
- [x] #108 -- Expand sample data for FedRAMP 20x + traditional NIST 800-53 -- **COMPLETED 2026-03-21**
- [x] #133 -- Documentation & guidance for building OSCAL data mapping files -- **COMPLETED 2026-03-19**

### 6. UI/UX & Navigation Improvements

- [x] #190 -- Login consent/warning banner modal (configurable via ENV) -- **COMPLETED 2026-03-15**
- [x] #167 -- Enterprise/Organization visibility & navigation for admins -- **COMPLETED 2026-03-19**
- [x] #171 -- Interactive OSCAL document relationship diagram (Mermaid) -- **COMPLETED 2026-03-19**
- [x] #253 -- Page header/tile sizing increase, SPARC logo replacement, "Systemized" text correction, easter egg -- **COMPLETED 2026-03-21**
- [x] #248 -- About page with OSCAL, FedRAMP 20x & API documentation -- **COMPLETED 2026-03-21**

### 7. API & Backend Enhancements

- [x] #95 -- Full CRUD API endpoints for Users and Projects (server mode only) -- **COMPLETED 2026-03-19**

### 8. DISA STIG & Framework Mapping

- [x] #185 -- (Moved to Theme 4 / Phase 3 -- prerequisite for CDEF validation and SAR evidence) -- **COMPLETED 2026-03-15**

### 9. CI/CD & Security Scanning

- [x] #186 -- Hybrid security scanning in GitHub Actions (Trivy + CodeQL/Semgrep + Brakeman + SAF CLI) -- **COMPLETED 2026-03-15**

### 10. Database Maintenance

- [x] #183 -- Squash accumulated migrations into a single consolidated migration file -- **COMPLETED 2026-03-19**

### 11. Security Remediation & Bug Fixes (New — discovered during Phases 1-5)

- [x] #210 -- Remediate container image security findings from hybrid scanning pipeline (339 CVEs, 1 suppressed SAST)
- [x] #203 -- Control Catalogs index: summary counts show totals instead of unique values (BUG) -- **COMPLETED 2026-03-19**
- [x] #205 -- Accept fully resolved OSCAL profiles from NIST without prioritization requirement (BUG) -- **COMPLETED 2026-03-19**

### 12. OSCAL Import Quality & Traceability (New — discovered during Phases 3-4)

- [x] #207 -- Enhance Catalog/Baseline import to detect & report missing required data, priorities, and subparts -- **COMPLETED 2026-03-20**
- [x] #213 -- Map XCCDF/InSpec SV/V IDs to NIST control IDs during CDEF import -- **COMPLETED 2026-03-20**
- [x] #217 -- Document NIST SP 800-53 Rev. 5 controls mapping and SPARC implementation details -- **COMPLETED 2026-03-20**

### 13. API Expansion (New — extends Phase 5 API work)

- [x] #229 -- REST API Phase 1: Full CRUD for SSP, SAR, SAP, POA&M with Bearer token auth + Okta JWT -- **COMPLETED 2026-03-20**
- [x] #240 -- Baseline Parameter and Enumeration Management API (GET/PUT/export under profile_documents) -- **COMPLETED 2026-03-21**
- [x] #242 -- REST API Phase 2: Full CRUD for Catalogs, Profiles, CDEFs, Control Mappings -- **COMPLETED 2026-03-21**

### 14. Platform Hardening & Polish (New — post-roadmap improvements)

- [ ] #234 -- Refactor avatar upload with crop/scale/center controls
- [ ] #237 -- Add persistent Data Quality card to catalog show page
- [ ] #244 -- Add security gate with threshold-based merge/deploy blocking
- [ ] #246 -- Repository cleanup & OSCAL schema validation overhaul
- [x] #249 -- Mutually exclusive API auth modes (SPARC_API_AUTH=local|oidc|hybrid) -- **COMPLETED 2026-03-21**
- [ ] #250 -- Add API discovery endpoint (GET /api/v1/available)

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
| [x] | #148 | Standardized publication metadata + validation -- **COMPLETED 2026-03-15** | MEDIUM | AFTER #149 merges |
| [x] | #176 | Unified publish/copy logic for Profiles & CDEFs -- **COMPLETED 2026-03-15** | MEDIUM | AFTER #149 merges |

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
| [x] | #175 | Profile creation from baseline + parameter validation -- **COMPLETED 2026-03-15** | **HIGH** | Phase 2 complete |
| [x] | #185 | STIG XCCDF parser: SV/V to CCI extraction for CDEF validation & evidence | **HIGH** | None (builds on Converters domain) |
| [x] | #172 | CDEF creation/import from Profile, validated via STIG/CCI mappings -- **COMPLETED 2026-03-16** | **HIGH** | AFTER #175 merges; #185 for validation |
| [x] | #173 | SSP creation/import from Profile -- **COMPLETED 2026-03-18** | **HIGH** | AFTER #175 merges |
| [x] | #174 | SAR creation/import from Profile or SSP (uses CDEF STIG validations) -- **COMPLETED 2026-03-18** | MEDIUM | AFTER #173 and #185 merge |
| [x] | #125 | Multi-step ATO wizard (all OSCAL layers) -- **COMPLETED 2026-03-19** | MEDIUM | AFTER #172, #173, #174 merge |

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
| [x] | #133 | OSCAL data mapping documentation & guidance -- **COMPLETED 2026-03-19** | MEDIUM | None |
| [x] | #167 | Enterprise/Organization visibility & navigation -- **COMPLETED 2026-03-19** | MEDIUM | None |
| [x] | #171 | Mermaid OSCAL relationship diagram -- **COMPLETED 2026-03-19** | MEDIUM | None |

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
| [x] | #95 | Versioned REST API for Users/Projects with RBAC -- **COMPLETED 2026-03-19** | MEDIUM | None |
| [x] | #186 | Hybrid security scanning CI (Trivy + SAST + SAF CLI + HDF output) -- **COMPLETED 2026-03-15** | MEDIUM | None |
| [x] | #183 | Squash all migrations into single consolidated file -- **COMPLETED 2026-03-19** | LOW | AFTER all migration PRs merge |

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

### Phase 6: Security Remediation & Bug Fixes (1-2 weeks)

**Goal:** Address security findings and data integrity bugs before new features

<!-- markdownlint-disable MD013 -->

| Status | Issue | Description | Priority | Dependencies |
| ------ | ----- | ----------- | -------- | ------------ |
| [x] | #210 | Remediate container image CVEs (339 findings from Trivy scan) | **HIGH** (security) | None |
| [x] | #203 | Catalog index summary counts show totals instead of unique values | **HIGH** (bug) | None |
| [x] | #205 | Accept fully resolved OSCAL profiles without prioritization requirement | **HIGH** (bug) | None |

<!-- markdownlint-enable MD013 -->

**Deliverables:** Clean container image scan, accurate catalog counts, flexible profile import

```text
Dev A: #210 (container CVE remediation) -- Dockerfile/Gemfile, isolated ✅ COMPLETE
Dev B: #203 (catalog count bug fix)     -- Single controller/view fix ✅ COMPLETE
Dev C: #205 (profile import fix)        -- Profile parser/service ✅ COMPLETE
```

> **Rationale:** Security and bug fixes before new features.
> #210 is security-critical. #203 and #205 are data integrity issues.

---

### Phase 7: OSCAL Import Quality & Traceability (2-3 weeks)

**Goal:** Improve import quality, traceability, and documentation

<!-- markdownlint-disable MD013 -->

| Status | Issue | Description | Priority | Dependencies |
| ------ | ----- | ----------- | -------- | ------------ |
| [x] | #207 | Catalog/Baseline import: detect & report missing data, priorities, subparts | MEDIUM | None |
| [x] | #213 | Map XCCDF/InSpec SV/V IDs to NIST control IDs during CDEF import -- **COMPLETED 2026-03-20** | MEDIUM | None |
| [x] | #217 | Document NIST SP 800-53 Rev. 5 controls mapping and SPARC implementation -- **COMPLETED 2026-03-20** | MEDIUM | None |

<!-- markdownlint-enable MD013 -->

**Deliverables:** Better import validation UX, correct STIG-to-NIST traceability, comprehensive mapping docs

```text
Dev A: #207 (import quality)     -- Catalog domain ✅ COMPLETE
Dev B: #213 (XCCDF ID mapping)   -- CDEF/Converter domain ✅ COMPLETE
Dev C: #217 (Rev 5 docs)         -- Documentation only ✅ COMPLETE
```

> All 3 can run in parallel (different domains).

---

### Phase 8: API Expansion (2-3 weeks)

**Goal:** Full programmatic access to all OSCAL resources

<!-- markdownlint-disable MD013 -->

| Status | Issue | Description | Priority | Dependencies |
| ------ | ----- | ----------- | -------- | ------------ |
| [x] | #229 | REST API Phase 1: Full CRUD for SSP, SAR, SAP, POA&M with Bearer token auth + Okta JWT -- **COMPLETED 2026-03-20** | MEDIUM | AFTER #95 (API foundation) |
| [x] | #240 | Baseline Parameter and Enumeration Management API (GET/PUT/export) -- **COMPLETED 2026-03-21** | MEDIUM | AFTER #229 |
| [x] | #242 | REST API Phase 2: Full CRUD for Catalogs, Profiles, CDEFs, Control Mappings -- **COMPLETED 2026-03-21** | MEDIUM | AFTER #229 |

<!-- markdownlint-enable MD013 -->

**Deliverables:** Complete REST API covering all OSCAL document types

```text
Dev A: #229 (API expansion) -- API namespace, builds on #95 foundation
```

> Depends on #95 API token infrastructure already merged.

---

### Phase 9: FedRAMP 20x (final phase -- 3-4 weeks)

**Goal:** FedRAMP 20x extensions + comprehensive sample data

<!-- markdownlint-disable MD013 -->

| Status | Issue | Description | Priority | Dependencies |
| ------ | ----- | ----------- | -------- | ------------ |
| [x] | #107 | FedRAMP 20x extensions (KSIs, automation, new models) -- **COMPLETED 2026-03-21** | **HIGH** | Phases 1-8 complete |
| [x] | #108 | Dual sample sets + seed script flags (FedRAMP 20x + traditional NIST) -- **COMPLETED 2026-03-21** | MEDIUM | AFTER #107 merges |

<!-- markdownlint-enable MD013 -->

**Deliverables:** FedRAMP 20x support, comprehensive sample/seed data

```text
Dev A: #107 (FedRAMP 20x)          -- Phase 9a ✅ COMPLETE
Dev B: #108 (sample data)          -- Phase 9b ✅ COMPLETE
```

> **Critical rule:** #107 must merge before #108 starts
> (#108 needs #107 schema definitions).
> #107 completed 2026-03-21. #108 completed 2026-03-21.

---

### Phase 10: Platform Hardening & Polish (ongoing)

**Goal:** Security hardening, UX refinements, developer experience, schema validation

<!-- markdownlint-disable MD013 -->

| Status | Issue | Description | Priority | Dependencies |
| ------ | ----- | ----------- | -------- | ------------ |
| [ ] | #234 | Refactor avatar upload with crop/scale/center controls | LOW | None |
| [ ] | #237 | Persistent Data Quality card on catalog show page | MEDIUM | None |
| [ ] | #244 | Security gate with threshold-based merge/deploy blocking in CI | **HIGH** | None |
| [ ] | #246 | Repository cleanup & OSCAL schema validation overhaul | MEDIUM | None |
| [x] | #249 | Mutually exclusive API auth modes (local/oidc/hybrid) + service accounts -- **COMPLETED 2026-03-21** | **HIGH** (security) | None |
| [x] | #250 | API discovery endpoint (GET /api/v1/available) -- **COMPLETED 2026-03-21** | LOW | None |

<!-- markdownlint-enable MD013 -->

**Deliverables:** Hardened API auth, CI security gates, cleaner repo, improved UX

**Parallelism: All 6 issues can run simultaneously (different domains).**

```text
Dev A: #249 (API auth modes)       -- API/Auth domain ✅ COMPLETE
Dev B: #244 (security gate)        -- CI/Infrastructure domain
Dev C: #246 (repo cleanup/schema)  -- Shared/Validation domain
Dev D: #237 (data quality card)    -- Catalog UI domain
Dev D: #234 (avatar upload)        -- User/UI domain
Dev D: #250 (API discovery)        -- API domain ✅ COMPLETE
```

> **Recommended order:** #249 and #244 first (security), then #246, #237, #250, #234.

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

| Phase | Duration | Key Focus | Issues | Status |
| ----- | -------- | --------- | ------ | ------ |
| 1 | 2-4 weeks | Bugs + Testing + Dev Env | #142, #178, #100, #134 | **COMPLETE** |
| 2 | 4-6 weeks | OSCAL Core (Import/Export/Publication) | #163, #149, #177, #148, #176 | **COMPLETE** |
| 3 | 4-6 weeks | Entity Creation + STIG Parser + ATO Wizard | #175, #185, #172, #173, #174, #125 | **COMPLETE** |
| 4 | 3-4 weeks | Docs + UX Polish | #133, #167, #171 | **COMPLETE** |
| 5 | 3-4 weeks | API + CI/CD + DB Cleanup | #95, #186, #183 | **COMPLETE** |
| 6 | 1-2 weeks | Security Remediation + Bug Fixes | #210, #203, #205 | **COMPLETE** |
| 7 | 2-3 weeks | OSCAL Import Quality + Traceability | #207, #213, #217 | **COMPLETE** |
| 8 | 2-3 weeks | API Expansion (all OSCAL resources) | #229, #240, #242 | **COMPLETE** |
| 9 | 3-4 weeks | FedRAMP 20x | #107, #108 | **COMPLETE** |
| 10 | Ongoing | Platform Hardening & Polish | #234, #237, #244, #246, #249, #250 | In Progress |

<!-- markdownlint-enable MD013 -->

**Total issues tracked:** 42 (23 original + 19 ad-hoc/new)
**Completed (Phases 1-9 + ad-hoc):** 38 issues
**Remaining:** 4 issues (Phase 10: #234, #237, #244, #246)
**Phases 1-9 complete.** Phase 10 (hardening/polish) in progress.
