# SPARC Open GitHub Issues -- Implementation Strategy

Structured, prioritized roadmap for the open issues in the SPARC
GitHub repository.

**Last updated:** 2026-05-13

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
- [ ] #461 -- SBOM-driven vulnerability scanning (Grype) — consume CycloneDX SBOMs from sbom_generation + Trivy, SARIF to Code Scanning, HDF via SAF CLI
- [x] #463 -- Fix SAF CLI MODULE_NOT_FOUND: pin Node 22 + @mitre/saf@1.6.0 so `cyclonedx_sbom2hdf` and `anchoregrype2hdf` converters work; harden parallel-script error capture -- **COMPLETED 2026-05-14** (PR #464)
- [ ] #456 -- Remove redundant `db:prepare:all` invocation from `bin/docker-entrypoint` (eliminates `Rails::Command::UnrecognizedCommandError` noise in production logs)

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
- [x] #390 -- SAP/SAR objective-level assessment tracking (NIST 800-53A determination statements + SAR finding→objective FK) -- **COMPLETED 2026-04-16**
- [x] #393 -- Catalogs/Profiles/SSPs/CDEFs: surface enhancement/sub-part hierarchy (apply #390 pattern) -- **COMPLETED 2026-04-18**
- [x] #392 -- Parsers read from local tmp; multi-task ECS race fix (Active Storage source of bytes + SPARC_PERSIST_S3_BLOB) -- **COMPLETED 2026-04-19**
- [x] #397 -- OSCAL UUID stability across exports (foundational for #393/#396/#398 cross-document linkage) -- **COMPLETED 2026-04-18**
- [x] #395 -- Boundary as canonical association + metadata sync -- **COMPLETED 2026-04-20** (P1 PR #400, P2-3 close out OSCAL `import-*.href` `uuid:<...>` resolution + boundary metadata source-of-truth + sync service + rake task)
- [x] #396 -- Leveraged Authorizations: boundary-to-boundary inheritance graph + OSCAL `leveraged-authorizations[]` assembly + CRM/SSRM back-matter (Phases 1-3; Phase 4 legacy CRM deferred until NIST 1.x publishes CRM model) -- **COMPLETED 2026-04-20**
- [x] #398 -- CDEF → SSP control statement auto-population (component-driven SSP authoring) via polymorphic `SspControlStatementInheritance` shared with #396 -- **COMPLETED 2026-04-20**

### 13. API Expansion (New — extends Phase 5 API work)

- [x] #229 -- REST API Phase 1: Full CRUD for SSP, SAR, SAP, POA&M with Bearer token auth + Okta JWT -- **COMPLETED 2026-03-20**
- [x] #240 -- Baseline Parameter and Enumeration Management API (GET/PUT/export under profile_documents) -- **COMPLETED 2026-03-21**
- [x] #242 -- REST API Phase 2: Full CRUD for Catalogs, Profiles, CDEFs, Control Mappings -- **COMPLETED 2026-03-21**

### 14. Platform Hardening & Polish (New — post-roadmap improvements)

- [x] #234 -- Refactor avatar upload with crop/scale/center controls -- **COMPLETED 2026-03-21**
- [x] #237 -- Add persistent Data Quality card to catalog show page -- **COMPLETED 2026-03-21**
- [ ] #244 -- Add security gate with threshold-based merge/deploy blocking
- [ ] #246 -- Repository cleanup & OSCAL schema validation overhaul
- [x] #249 -- Mutually exclusive API auth modes (SPARC_API_AUTH=local|oidc|hybrid) -- **COMPLETED 2026-03-21**
- [x] #250 -- Add API discovery endpoint (GET /api/v1/available) -- **COMPLETED 2026-03-21**
- [x] #257 -- Service Account Management for API Access -- **COMPLETED 2026-03-21**
- [x] #259 -- AWS Secrets Manager integration for ECS deployments -- **COMPLETED 2026-03-21**
- [x] #264 -- Gitleaks pattern for SPARC service account tokens (`.gitleaks.toml`) -- **COMPLETED 2026-03-21**
- [x] #263 -- Auto-disable service accounts on token expiry and inactivity -- **COMPLETED 2026-03-21**
- [x] #262 -- Service account token expiry email notifications -- **COMPLETED 2026-03-22**
- [x] #269 -- Configurable Resources page + support email links -- **COMPLETED 2026-03-22**
- [x] #274 -- Rebrand SPARC acronym to "Systematic Policy and Regulatory Compliance" -- **COMPLETED 2026-03-22**
- [x] #272 -- Collapsible left sidebar navigation for Organizations, Boundaries, and Resources -- **COMPLETED 2026-03-22**
- [x] #276 -- Bundle converter mapping data as seed fixtures for Docker deployments -- **COMPLETED 2026-03-22**
- [x] #271 -- Consolidate all releases into v1.0.0 (first public release) -- **COMPLETED 2026-03-22**
- [x] #282 -- Fix incomplete data seeding on startup (SeedRunner, version-tracked sections, demo gate) -- **COMPLETED 2026-03-23**
- [x] #281 -- Update login page features list + version bump to v1.1.0 -- **COMPLETED 2026-03-23**
- [x] #283 -- Pre-release squash all pending migrations (9 files into single squash, 73 archived) -- **COMPLETED 2026-03-23**
- [x] #291 -- Create Postman collection and environment for SPARC API (59 endpoints, 12 folders, prod + local envs) -- **COMPLETED 2026-03-23**
- [x] #296 -- Downsize hero card size by ~20% (CSS padding, font sizes, mobile breakpoints) -- **COMPLETED 2026-03-25**
- [x] #300 -- Add compliance artifact pipeline with S3 upload on PRs (OIDC + S3 + CDEF validation workflow) -- **COMPLETED 2026-03-25**
- [x] #314 -- Optimize CI pipeline: dependency caching, parallel scans, Docker layer caching, pipeline metrics job -- **COMPLETED 2026-03-26**
- [x] #430 -- GitHub org migration: Rebel-Raiders → risk-sentinel (pre-cutover sweep PR #434 landed 2026-05-01; transfer + verification + wiki re-push completed 2026-05-02) -- **COMPLETED 2026-05-02**

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
| [x] | #316 | Signed Docker image build pipeline with Docker Hub + ECR publishing -- **COMPLETED 2026-03-31** | MEDIUM | None |
| [x] | #335 | Paths filters on CI workflows -- reduce unnecessary dependabot runs -- **COMPLETED 2026-04-02** | LOW | None |
| [x] | #340 | Container vulnerability baseline for ATO readiness -- **COMPLETED 2026-04-04** | HIGH | None |
| [x] | #342 | Harden Dockerfile -- remove unused packages, reduce image size -- **COMPLETED 2026-04-05** | MEDIUM | #340 |
| [x] | #349 | OSCAL schema database with version-aware validation -- **COMPLETED 2026-04-06** | HIGH | None |
| [x] | #355 | Multi-file drag/drop upload + SPARC branding update -- **COMPLETED 2026-04-08** | MEDIUM | None |
| [x] | #356 | Baseline-driven CDEF prioritization and enhanced editable fields -- **COMPLETED 2026-04-12** | HIGH | None |
| [x] | #370 | OSCAL metadata compliance -- all spec fields in exports -- **COMPLETED 2026-04-13** | HIGH | #349 |

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
| [x] | #234 | Refactor avatar upload with crop/scale/center controls -- **COMPLETED 2026-03-21** | LOW | None |
| [x] | #237 | Persistent Data Quality card on catalog show page -- **COMPLETED 2026-03-21** | MEDIUM | None |
| [x] | #249 | Mutually exclusive API auth modes (local/oidc/hybrid) + service accounts -- **COMPLETED 2026-03-21** | **HIGH** (security) | None |
| [x] | #250 | API discovery endpoint (GET /api/v1/available) -- **COMPLETED 2026-03-21** | LOW | None |
| [x] | #257 | Service Account Management for API Access -- **COMPLETED 2026-03-21** | **HIGH** (security) | AFTER #249 |
| [x] | #259 | AWS Secrets Manager integration for ECS deployments -- **COMPLETED 2026-03-21** | **HIGH** (security) | None |
| [x] | #264 | Gitleaks pattern for SPARC service account tokens -- **COMPLETED 2026-03-21** | MEDIUM (security) | AFTER #257 |
| [x] | #263 | Auto-disable service accounts on token expiry and inactivity -- **COMPLETED 2026-03-21** | **HIGH** (security) | AFTER #257 |
| [x] | #262 | Service account token expiry email notifications -- **COMPLETED 2026-03-22** | **HIGH** (security) | AFTER #257 |
| [x] | #271 | Consolidate all releases into v1.0.0 (first public release) -- **COMPLETED 2026-03-22** | **HIGH** | All phases complete |
| [x] | #300 | Compliance artifact pipeline with S3 upload on PRs (OIDC + CDEF validation) -- **COMPLETED 2026-03-25** | **HIGH** (security) | None |
| [x] | #316 | Signed Docker image build pipeline -- **COMPLETED 2026-03-31** | MEDIUM | None |
| [x] | #335 | Paths filters on CI workflows -- **COMPLETED 2026-04-02** | LOW | None |
| [x] | #340 | Container vulnerability baseline -- **COMPLETED 2026-04-04** | HIGH | None |
| [x] | #342 | Harden Dockerfile -- **COMPLETED 2026-04-05** | MEDIUM | #340 |
| [x] | #349 | OSCAL schema database with version-aware validation -- **COMPLETED 2026-04-06** | **HIGH** | None |
| [x] | #355 | Multi-file drag/drop upload + branding -- **COMPLETED 2026-04-08** | MEDIUM | None |
| [x] | #356 | CDEF prioritization and enhanced editable fields -- **COMPLETED 2026-04-12** | **HIGH** | None |
| [x] | #370 | OSCAL metadata compliance -- all spec fields in exports -- **COMPLETED 2026-04-13** | **HIGH** | #349 |
| [x] | #371 | Back-matter resource management with control-level linking -- **COMPLETED 2026-04-14** | **HIGH** | #370 |
| [x] | #375 | Back-matter resource API with authoritative layer -- **COMPLETED 2026-04-14** | **HIGH** (enterprise) | #371 |

<!-- markdownlint-enable MD013 -->

**Deliverables:** Hardened API auth, CI security gates, cleaner repo, OSCAL-compliant back-matter, enterprise API

> **Status:** All Phase 10 issues are complete. #244 and #246 carried
> forward to Phase 12 (post-migration active backlog) for prioritized
> execution alongside the new test/CI hardening work.

---

### Phase 11: OSCAL Integrity, Enterprise API & Infrastructure (complete)

**Goal:** UUID integrity, authoritative resource API, import quality, CI optimization, container hardening

<!-- markdownlint-disable MD013 -->

| Status | Issue | Description | Priority | Dependencies |
| ------ | ----- | ----------- | -------- | ------------ |
| [x] | #344 | Upgrade Docker base image to Debian Trixie -- remediate OS-level CVEs -- **COMPLETED 2026-04-15** | **HIGH** (security) | None |
| [x] | #346 | Optimize CodeQL scan -- scope to Ruby, reduce analysis time -- **COMPLETED 2026-04-15** | LOW | None |
| [x] | #358 | Configure Dependabot grouping -- batch low-risk updates -- **COMPLETED 2026-04-15** | LOW | None |
| [x] | #361 | UUID collision handling on OSCAL import + replace placeholder UUIDs -- **COMPLETED 2026-04-14** | **HIGH** (compliance) | #371 |
| [x] | #372 | Import Authoritative Sources for Global and Organizational Use -- **COMPLETED 2026-04-26** | **HIGH** (enterprise) | #375 |

<!-- markdownlint-enable MD013 -->

**Deliverables:** UUID integrity, optimized CI/CD, hardened container images, authoritative source import

> **Status:** Phase 11 complete. #244, #246, #341, #367 carried forward
> to Phase 12 alongside the post-migration test/CI hardening backlog.

---

### Phase 12: Active Backlog — Post-migration Test/CI Hardening + Federation Follow-ups (current)

**Goal:** Unblock developer velocity (CI gate hygiene), close the contract→content gap in the API test suite, hold federation follow-on for first real federated deployment, and finish the carried-over Platform Hardening / Phase 11 items.

<!-- markdownlint-disable MD013 -->

| Priority | Status | Issue | Description | Notes |
| -------- | ------ | ----- | ----------- | ----- |
| **P0** | [x] | ~~#436~~ | ~~CI: path-filtered required checks block config/docs PRs — adopt consolidating-gate pattern~~ — **COMPLETED 2026-05-05** | Shipped on `bug/436_ci_consolidating_gate` (PR #442). Adds `.github/required-checks.json` (single source of truth), `.github/workflows/required-passed.yml` (aggregator with path-aware sanity rules — catches misconfigured-skip bugs by demanding `success` when changed paths match a rule's `filterPathSpec`), and `.github/workflows/validate-required-checks-sync.yml` (drift validator — fails CI if rule's `filterPathSpec` is not a subset of the workflow's actual path filter). Branch protection cutover: `gh api PUT /repos/.../branches/main/protection` and `gh api PUT /repos/.../rulesets/13385940` updated to require only `Required Checks Passed`. |
| **P1** | [x] | ~~#244~~ | ~~Security gate with threshold-based merge/deploy blocking in CI~~ — **COMPLETED 2026-05-06** | Shipped on `feature/244_367_security_gate_coverage`. Pivots to MITRE hdf-libs as the manipulation engine. New artifacts: `bin/sparc_findings_to_hdf_amendments.rb` (converts `docs/compliance/sparc-findings.yml` dispositions to HDF Amendments JSON; validates severity-based review cadence + freshness), `docs/compliance/threshold.yml` (SAF CLI strict policy on amended residual: critical=0, high≤5), new `security_gate` job in `.github/workflows/security.yml` (applies amendments via `hdf-cli amend`, then `saf validate threshold`), `security_gate` rule in `.github/required-checks.json`. CRITICAL findings cannot use disposition `accepted` (only `false_positive`, `deferred`, or `remediated`). Refactored `Api::V1::UsersController` to set `:admin`/`:status` outside mass-assignment (BRAKE0105 remediation); added `validates :role, inclusion:` on `Attestation` (defense-in-depth for residual BRAKE0105 FP). Added 10 new container findings + DS-0002 trivy-fs FP to `.trivyignore`. NIST: CA-7, CA-7(4), RA-3, SI-2 mappings updated. |
| **P1** | [x] | ~~#367~~ | ~~Code coverage threshold and tracking — SimpleCov integration~~ — **COMPLETED 2026-05-06** | Shipped on the same branch as #244. SimpleCov `minimum_coverage 70` (gated on `ENV['CI']` so single-spec local runs aren't tripped). Today's measured baseline 71.17% line coverage (9875/13876 LOC); 70% floor gives small buffer for run-to-run variance. Per-file coverage gate and branch coverage deferred to follow-up issues (15 existing files at 0% line need fix-or-exclude before per-file enforcement; branch coverage needs measurement first). NIST: SA-11 mapping updated. |
| **P1** | [ ] | #433 | Test suite — content-style validation (response schemas, fixtures, round-trip, audit, OSCAL) | Large multi-slice (~2.5-3.5k LOC, similar to #432). Closes the type/field-drift gap left open by #432's contract-style suite (pydantic schemas, realistic fixtures, round-trip + audit-log + OSCAL schema assertions). Independent of #436/#244/#367 — can run in parallel. |
| **P2** | [ ] | #341 | Add XML document type fingerprinting for upload validation | Defensive, post-#392; touches `FileUploadable` and parser entry-points. Coordinate with anything else editing those concerns. |
| **P2** | [ ] | #246 | Repository cleanup & OSCAL schema validation overhaul | Background lane. Scope-define needed; treat as parallelizable while a feature ships. |
| **P2** | [x] | ~~#445~~ | ~~PR checklist hygiene: PR template + skip-marker for CI/post-merge boxes~~ — **COMPLETED 2026-05-06** | Shipped on `feature/445_pr_checklist_hygiene`. Tier 1: `.github/PULL_REQUEST_TEMPLATE.md` (five-section shape: Summary / Changes / Test plan / Verified by CI / Post-merge verification — checkboxes only in Test plan, plain bullets elsewhere) + `CONTRIBUTING.md` documenting the convention. Tier 2: `.github/workflows/pr-checklist.yml` strips `<!-- pr-checklist:skip --> ... <!-- /pr-checklist:skip -->` blocks before counting `- [ ]` so contributors have a machine-enforced escape hatch for CI-verified or post-merge items. Triggered by mid-PR body restructures on PR #441 (release) and PR #444 (security gate). Tier 3 (re-trigger aggregator on `pull_request: edited`) deferred. |
| **P3** | [x] | ~~#440~~ | ~~Adopt SAF CLI / CMS-style attestation JSON schema (Option B — export only)~~ — **COMPLETED 2026-05-06** | Shipped on `feature/440_attestation_cms_export`. Migration adds `frequency` + `status` to `attestations` (CMS schema parity). New `CmsAttestationExportService` denormalizes one record per (attestation × linked control_id) in the canonical 6-field shape. New `Api::V1::AttestationsController` (index/show/create/destroy + collection `:export`) — fills the existing UI-only gap per the SPARC api-first rule. UI form gains `frequency` + `status` selects. Internal SPARC attestation model stays as-is (richer than CMS — adds `attester_email`, `signature_hash`, polymorphic `evidence` link); export endpoint is the convergence point. NIST: CA-2 + CA-7 mappings updated. |
| **P3** | [x] | ~~#449~~ | ~~HDF ↔ OSCAL translation bridge for tenant compliance pipelines (#447 lean spinout)~~ — **COMPLETED 2026-05-07** | Shipped on `feature/449_hdf_oscal_translation_bridge` (PR #450). HdfRunner Ruby wrapper + `bin/install-hdf.sh` + Dockerfile bake; three stateless API endpoints (`oscal/sar_from_hdf`, `oscal/poam_from_hdf`, `hdf/amendments_from_oscal_poam`); optional Evidence back-matter enrichment via `?authorization_boundary_id=N`. SparcConfig::VERSION 1.5.0 → 1.6.0. NIST: CA-7, RA-3, SI-2 mappings updated. |
| **P3** | [x] | ~~#451~~ | ~~OSCAL export schema-validation fixes (metadata leak + YAML/XML 500s + UX uniformity)~~ — **COMPLETED 2026-05-07** | Shipped on `fix/451_oscal_export_metadata_leak` (PR #454). Three slices: (1) `OscalMetadata#build_oscal_metadata` switched from un-filtered merge to `slice(*METADATA_EXTRA_KEYS)` allowlist — closes the leak across every doc type that includes the concern. (2) Rescue `OscalValidationError` on `download_yaml` / `download_xml` across 7 controllers — graceful redirect with flash instead of 500. (3) UX uniformity (A1+A2): 6 list views switched to shared `_oscal_export_dropdown` partial + Stimulus `connect()` hook reads `?oscal_validation_failed=1&oscal_format=…` to auto-open the validation modal on direct-URL hits. Every human path → same modal showing same specific errors. 81 specs added across 8 files; full suite 2152/0. |
| **P3** | [ ] | #453 | Bake OSCAL schemas into the container at build time (decouple runtime from NIST GitHub) | Filed 2026-05-07. Active. New `oscal:bundle_schemas` rake task downloads all 5 supported versions × 8 doc types from NIST GitHub release assets at Docker build time, writes to `lib/oscal_schemas_bundle/v<version>/<file>` + `manifest.json` with SHA-256 checksums. `oscal:seed_schemas` extended with three-tier fallback: bundle (offline, checksum-verified) → NIST GitHub fetch → legacy disk fallback. Discovered + fixed two pre-existing bugs while doing this: (a) `OscalSchema::NIST_SCHEMA_URL_TEMPLATE` pointed at a non-existent `raw.githubusercontent.com/.../json/schema/...` path (every NIST fetch was 404'ing and silently falling back to disk; only v1.1.2 was ever loaded). (b) `OscalSchema::DOCUMENT_TYPE_MAP` had `oscal_component-definition_schema.json` for component-definition; NIST publishes it as `oscal_component_schema.json`. Both fixed. Targets v1.6.0 — must merge before prod deploy. |
| **P3** | [ ] | #447 | umbrella: hosted multi-reviewer disposition workflow + UI (Plan B / future expansion) | Filed 2026-05-06; **demoted to Plan B** 2026-05-06 in favor of #449's lean implementation. Captures the full hosted-disposition product: ScannerFinding/FindingDisposition/ScanRun domain models, triage UI, multi-reviewer approval flows, lifecycle reconciliation engine, discrepancy queue, auto-disposition heuristics, cross-scanner correlation. Stays parked unless customer demand justifies the scope (~4k LOC + UI). |
| **P3** | [ ] | #422 | POAM Scenario B — cross-instance federated POAM visibility (carved from #415) | Gated on first real federation deployment (peers configured + `SPARC_HASH` rotated in production). Stays parked until that exists. |
| **P3** | [ ] | #413 | Comprehensive SPARC API Documentation Review and Automated Testing — umbrella | Phase 1 + Phase 2 acceptance criteria shipped (PR #432 — 247 tests covering all 95 endpoints). Stays open as the umbrella reference for the API testing program; close once #433 lands and the content-style layer is in place. |

<!-- markdownlint-enable MD013 -->

**Deliverables:** CI gate hygiene that doesn't block config/docs PRs; threshold-blocking security + coverage gates; type-safe API test suite; XML upload defense; cleaner repo. Federation follow-up parked for production deployment.

**Sequencing:**

```text
Sprint 12a (P1 launch — P0 #436 shipped 2026-05-05):
  Dev B: #244 + #367 bundle                 -- consolidating-gate pattern available; build security threshold check on top
  Dev C: #433 slice 1                        -- pydantic schemas + fixtures (independent)

Sprint 12b (P1 finish + P2):
  Dev A: #341 (XML fingerprinting)
  Dev C: #433 slices 2-6                     -- continues
  Dev B: #246 (repo cleanup)                 -- background lane

Out (gated): #422 — first federation deployment
Umbrella: #413 — close on #433 merge
```

> **Order rule:** #436 has shipped — every subsequent CI work (#244,
> #367) benefits from the consolidating-gate pattern. Single required
> status check on `main` is now `Required Checks Passed`. #433 is
> independent — it can run in parallel from sprint 12a.

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
| 10 | Ongoing | Platform Hardening & Polish | #234-#375 (25 issues) | **COMPLETE** |
| 11 | 4-6 weeks | OSCAL Integrity, Enterprise & Infrastructure | #344, #346, #358, #361, #372 | **COMPLETE** |
| 12 | Current | Active Backlog — Post-migration Test/CI Hardening + Federation Follow-ups | ~~#436~~, ~~#244~~, ~~#367~~, ~~#445~~, ~~#440~~, ~~#449~~, ~~#451~~, #453, #447 (Plan B), #433, #341, #246, #422, #413 | In Progress |

<!-- markdownlint-enable MD013 -->

**Total issues tracked:** 71 (23 original + 48 ad-hoc/new — adds #436, #445, #440, #447, #449, #451, #453)
**Completed (Phases 1-11 + ad-hoc):** 75 issues (incl. #415 Scenario A + #416 + #423 + #424 POAM completion — completed 2026-04-27; #419 SPARC_HASH master-key rotation rake — completed 2026-04-25; #430 GitHub org migration completed 2026-05-02; #436 CI consolidating-gate pattern completed 2026-05-05; #244 security gate + #367 coverage threshold completed 2026-05-06; #445 PR checklist hygiene completed 2026-05-06; #440 CMS attestation export completed 2026-05-06; #449 HDF↔OSCAL translation bridge completed 2026-05-07; #451 OSCAL export schema-validation fixes + UX uniformity completed 2026-05-07)
**Remaining (Phase 12 active backlog):** 6 issues — P1: #433 / P2: #341, #246 / P3: #453 (OSCAL schema bake — active, must land before v1.6.0 prod deploy), #447 (Plan B / hosted-disposition workflow with UI — deferred), #422 (gated on first federation deployment), #413 (umbrella; closes on #433 merge)
**Phases 1-11 complete.** Phase 12 (post-migration active backlog) in progress.
**First public release: v1.0.0** (#271). **Current version: v1.5.0** (released 2026-05-05 — API test suite, org migration, security patches). Org migration to `risk-sentinel/sparc` completed 2026-05-02 (#430).
