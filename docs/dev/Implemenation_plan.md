# SPARC Open GitHub Issues -- Implementation Strategy

Structured, prioritized roadmap for the open issues in the SPARC
GitHub repository.

**Last updated:** 2026-08-19

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

- [x] #142 -- Large uploads block UI (background + progress UX) -- **COMPLETED 2026-03-14**
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
- [x] #456 -- Remove redundant `db:prepare:all` invocation from `bin/docker-entrypoint` (eliminates `Rails::Command::UnrecognizedCommandError` noise in production logs) -- **COMPLETED 2026-05-14** (PR #467)
- [x] #466 -- AWS Labs CDEF runtime ingestion (opt-in via `SPARC_AWS_LABS_CDEF_ENABLED`); Solid Queue recurring refresh; read-only AWS rows with copy-to-amend; full Apache 2.0 attribution (NOTICE + LICENSES/ + THIRD_PARTY_NOTICES.md) -- **COMPLETED 2026-05-17** (PR #469)
- [x] #470 -- Squash 29 accumulated migrations (since 2026-03-19 squash) into single consolidated file + v1.6.1 patch bump -- **COMPLETED 2026-05-17** (PR #471, released as v1.6.1)
- [x] #472 -- SBOM license tracking + policy gate: Trivy `--scanners license`, consolidated `license-inventory.{json,md}` artifact, merged `sparc-combined-sbom.cdx.json`, `license-policy.yml` + `license-dispositions.yml` (warn-only) -- **COMPLETED 2026-05-17** (PR #474)
- [x] #636 -- SonarCloud → OHDF evidence: fetch SonarCloud findings post-analysis (`hdf fetch sonarqube` strategic / SAF `sonarqube2hdf` bridge), validate, bake HDF into the security-artifacts stream so SAST joins the Heimdall rollup. **Vendored** in-repo (`sonarqube-hdf.yml` + `sonarqube-hdf-emit.yml`) — public repo can't call the internal container-build-sign reusable. -- **IMPLEMENTED (PR pending)**
- [x] #473 -- Aggregator hardening -- **COMPLETED 2026-05-17** (PR #476)
- [x] #475 -- Triage outstanding license action items + LICENSES/ population + baseline dispositions -- **COMPLETED 2026-05-17 / 18** (PRs #477, #478)
- [x] #479 -- Drop roo-xls (GPL-3.0 transitive); scrub legacy UI references; flip license-policy enforce to true; v1.6.2 bump -- **COMPLETED 2026-05-18** (PR #480)
- [x] #481 -- Close out 120 unmapped license-inventory components (5-category triage) -- **COMPLETED 2026-05-18** (PR #482)
- [x] #483 -- Harmonize top-level license to Apache-2.0; v1.6.3 bump -- **COMPLETED 2026-05-18** (PR #484)
- [ ] #487 -- AWS Labs CDEF bootstrap-on-boot initializer (no shell access required); closes the "fresh deploy waits a week" gap
- [ ] #488 -- AWS Labs CDEF "Refresh from AWS Labs" admin button on CDEF index (mirrors DISA CCI Refresh Now); same `converters.write` RBAC bucket

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
| [x] | #142 | Background jobs + Turbo Streams/polling for large uploads | **HIGH** |
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

### Phase 13: v1.7.x Pre-Pen-Test Hardening + Patch Fixes (COMPLETE)

**Goal:** Harden the upload + transport + auth surface ahead of a planned penetration test, then ship the prod bugs surfaced during baseline API test runs against `sparc.risk-sentinel.org`.

<!-- markdownlint-disable MD013 -->

| Priority | Status | Issue | Description | Notes |
| -------- | ------ | ----- | ----------- | ----- |
| **P0** | [x] | ~~#509~~ | ~~Magic-byte / content-type cross-check + structural parse validation~~ — **COMPLETED 2026-05-22** | Marcel-driven content-type validation (defeats rename-only `foo.exe → foo.json` attacks) + 5s structural parse timeout. Shipped on `feature/509_magic_byte_validation` (PR #523) + executable-signature deny-list follow-up on `feature/509_followup_executable_signatures` (PR #526). |
| **P0** | [x] | ~~#510~~ | ~~File size limits + zip-bomb defense~~ — **COMPLETED 2026-05-22** | `SPARC_MAX_UPLOAD_MB` / `SPARC_MAX_AVATAR_MB` env-var caps + uncompressed-total check for zip-based formats. Shipped on `feature/510_upload_size_limits` (PR #522). |
| **P0** | [x] | ~~#511~~ | ~~Nokogiri XXE hardening via XmlSecurity helper~~ — **COMPLETED 2026-05-22** | Single `lib/xml_security.rb` funnel applied across 11 call-sites — `NONET`, no `NOENT/DTDLOAD/HUGE`. Defeats XXE + billion-laughs. Shipped on `feature/511_nokogiri_xxe_hardening` (PR #517). |
| **P0** | [x] | ~~#513~~ | ~~Rate limiting via Rack::Attack~~ — **COMPLETED 2026-05-23** | Five throttle buckets (auth + API write + uploads + login failures + global) keyed off Rails.cache (solid_cache prod). Safelist CIDRs via `SPARC_RATE_LIMIT_SAFELIST_CIDRS`. Shipped on `feature/513_rate_limiting` (PR #527). |
| **P0** | [x] | ~~#514~~ | ~~CSP enforce mode + per-request nonces~~ — **COMPLETED 2026-05-23** | Promoted from `report_only=true` to enforce. Nonce generator switched from `request.session.id` to `SecureRandom.base64(16)`. Shipped on `feature/514_csp_enforce` (PR #529). |
| **P0** | [x] | ~~#515~~ | ~~Cookieless userdata subdomain for blob downloads~~ — **COMPLETED 2026-05-23** | Session cookie scoped host-only (no `Domain=` attribute per RFC 6265); blob serving routed through `userdata.<host>` so session token is never exposed to user-uploaded content. Shipped on `feature/515_cookieless_userdata` (PR #530). |
| **P0** | [x] | ~~#524~~ | ~~Production security operator guide~~ — **COMPLETED 2026-05-23** | 16-section operator hardening guide at `docs/PRODUCTION_SECURITY.md` (388 lines): threat model, auth + MFA, segmentation, malware scanning patterns, CSP, rate limiting, audit/compliance, image hygiene, DR, sparc-validate, v1.7.0 checklist. Shipped on `feature/524_prod_security_doc` (PR #533). |
| **P0** | [x] | ~~#525~~ | ~~Scanner findings audit + suppression inventory~~ — **COMPLETED 2026-05-23** | `docs/security/SCANNER_FINDINGS_AUDIT.md` consolidates `.trivyignore` (9 entries) + confirms zero app-code suppressions across Brakeman / CodeQL / Rubocop / Bundler-audit / Trivy / Grype. Shipped on `feature/525_scanner_findings_audit` (PR #532). |
| **P0** | [x] | ~~#535~~ | ~~Admin navigation: surface Service Accounts in User dropdown~~ — **COMPLETED 2026-05-24** | One-line view fix in `app/views/layouts/application.html.erb` + spec coverage. Shipped on `fix/535_admin_nav_service_accounts` (PR #540) as part of v1.7.1. |
| **P0** | [x] | ~~#536~~ | ~~Hybrid mode: allow admin-owned SAs to hold admin~~ — **COMPLETED 2026-05-24** | Drop the `service_account_cannot_be_admin` validation in `app/models/user.rb`; expose admin checkbox on `/admin/service_accounts/new` + edit. AC-6 satisfied by explicit per-SA opt-in. Shipped on `fix/536_allow_admin_service_accounts` as part of v1.7.1 bundle (PR #539). |
| **P0** | [x] | ~~#537~~ | ~~Restore `cloned_from_id` column on `cdef_documents` (schema drift)~~ — **COMPLETED 2026-05-24** | Idempotent migration recovering the column + FK + partial unique index that #466 originally added; lost on prod DBs that crossed the #470 squash without running #466 first. Shipped in v1.7.1 bundle (PR #539). |
| **P0** | [x] | ~~#541~~ | ~~Document 10 SPARC_* env vars missing from operator catalog~~ — **COMPLETED 2026-05-24** | Added Login Consent Banner / Dynamic Roles / Organization Metadata / DISA CCI sections to `docs/ENVIRONMENT_VARIABLES.md`. Drift audit (`grep -oE 'SPARC_[A-Z_]+'`) now clean modulo intentionally-omitted internal feature flags. Shipped on `docs/541_env_var_doc_gap` (PR #542). |
| **P0** | [x] | ~~#543~~ | ~~Rotate all GitHub Actions vars to secrets (pre-public-flip)~~ — **COMPLETED 2026-05-24** | 22 references across `build-sign-publish.yml` + `security.yml` rewritten from `vars.X` → `secrets.X`. Fork-PR safety verified — every AWS-touching step already gated by `HAS_DISPATCH_TOKEN` or main-only conditions. Shipped on `security/543_vars_to_secrets` (PR #544). |
| **P0** | [x] | ~~#547~~ | ~~Declare AWS secrets in build-sign-publish workflow_call block~~ — **COMPLETED 2026-05-24** | Added `AWS_ROLE_ARN` / `AWS_REGION` / `ECR_REGISTRY` to `on.workflow_call.secrets` (regression from #543). Necessary but not sufficient — see #553. Shipped on `fix/build_workflow_secrets_declaration` (PR #547). |
| **P0** | [x] | ~~#548~~ | ~~Processing-banner meta-refresh trap bailout (Tier 1)~~ — **COMPLETED 2026-05-24** | `_processing_banner.html.erb` no longer emits `<meta refresh>` for documents stuck past `SparcConfig.processing_stuck_minutes` (default 5, override `SPARC_PROCESSING_STUCK_MINUTES`). Renders "Processing Stuck" message + Back button. Shipped in v1.7.2 bundle (PR #552). Tier 2/3 (API status=complete + sweeper) tracked in #548. |
| **P0** | [x] | ~~#549~~ | ~~paginate() honors ?items / ?per_page query params~~ — **COMPLETED 2026-05-24** | `Api::V1::BaseController#paginate` now reads `params[:items] || params[:per_page]` with `MAX_PAGINATION_LIMIT = 200` clamp guard. Cleared 6 `test_pagination_query_params_respected` failures across document types in `tests/api/`. Shipped in v1.7.2 bundle (PR #552). |
| **P0** | [x] | ~~#553~~ | ~~Move secrets.ECR_REGISTRY out of step-level if conditionals~~ — **COMPLETED 2026-05-24** | The real fix for the #547 follow-on: GitHub does NOT allow `secrets` context in step-level `if:` despite docs claiming otherwise (caught by actionlint). Hoisted to job-level `env: HAS_ECR` mirroring security.yml's `HAS_DISPATCH_TOKEN` pattern. Unblocked v1.7.2 image build (the first v1.7.2 tag silently failed to fire the workflow). Shipped on `fix/build_workflow_secrets_in_if` (PR #553). |

<!-- markdownlint-enable MD013 -->

**Deliverables:** OWASP-aligned upload defense, transport hardening (CSP, cookie scoping, rate limiting), CI secret hygiene, operator-facing security documentation, and three patch releases (v1.7.0, v1.7.1, v1.7.2) closing every prod bug surfaced during baseline pen-test prep.

---

### Phase 14: Pre-Public-Flip + API Test Validation + CDEF Mutations (CURRENT)

**Goal:** Land the remaining pre-public-flip hardening (operator UI clicks + IaC trust-policy work), close the content-style API test gap (#433), then build OSCAL-correct CDEF mutation primitives (#498, #499) so the AWS Labs ingest flow has a first-class authoring layer.

<!-- markdownlint-disable MD013 -->

| Priority | Status | Issue | Description | Notes |
| -------- | ------ | ----- | ----------- | ----- |
| **P0** | [ ] | #545 | Pre-public-flip hardening checklist | Operator UI clicks (branch protection, env-scoped secrets, outside-contributor approval, tag protection, default GITHUB_TOKEN perms, org Actions allowlist) + pre-flip log audit. Code-side (CODEOWNERS + workflow `permissions:` blocks) already shipped via PR #546. Companion `risk-sentinel/sparc-iac#281` tightens the OIDC trust policy. Blocks: public repo flip. |
| **P0** | [ ] | #433 | Test suite — content-style validation | In progress. Slice 1 (pydantic response schemas) ready to start once v1.7.2 deploys on prod and an admin-flagged SA exists. Baseline run shows 151 of ~205 tests pass; pagination drift (now fixed via #549) and SA-admin gate (now fixed via #536) cleared. Remaining failures will be the actual schema/content drift work. |
| **P0** | [x] | #593 | CSP `form-action 'self'` blocks OAuth/OIDC login in Chromium (GitHub/Okta buttons dead in Chrome/Edge, work in Firefox) | **Shipping (v1.8.5)** on `bug/593_csp_form_action_oauth_login`. Login page POSTs to `/auth/:provider` → OmniAuth 302 to the IdP; Chromium enforces `form-action` against every redirect hop, so the external IdP origin was blocked (Firefox doesn't re-check redirects, which masked it). Fix: per-controller CSP on `SessionsController#new` relaxes `form-action` to `SparcConfig.oauth_form_action_origins` (enabled IdPs only); strict `'self'` everywhere else. Bundled hardening: DB-enforced case-insensitive email uniqueness (functional index on `LOWER(email)`) to close the local-vs-OIDC email-casing workaround. Sibling to #528 (CSP unsafe-inline removal). |
| **P1** | [ ] | #498 | CdefMutationService — single discipline for OSCAL-compliant CDEF mutations + first-class back-matter | Foundational for #499. Currently CDEF mutations are scattered across controllers + services; this consolidates and enforces OSCAL invariants at the mutation boundary. |
| **P1** | [ ] | #499 | Bulk-apply Converter output to CDEF clone + NIST Rev 4 ↔ Rev 5 helper | Depends on #498. Lets operators take Converter results (AWS Security Hub → NIST) and apply them en masse to a cloned CDEF, with mapping help between Rev 4 ↔ Rev 5 framework versions. |
| **P1** | [x] | #627 | ~~API-created document marked `completed` with no required content — no gate~~ — **MERGED (PR #637, v1.8.11)** | `ContentCompleteness` concern; `Publishable#publish` gated on per-type required content; Incomplete badge + API `content_complete`/`content_completeness_gaps`. |
| **P1** | [x] | #628 | ~~API-created CDEF/SSP empty shell — control basis + post-create populate path~~ — **MERGED (PR #637, v1.8.11)** | populate-from-profile for an existing empty CDEF/SSP (UI + API). Profile enforced as a content-completeness prerequisite. PR #637 also bundled the hdf-libs v3.2.0 pin + the Required-Checks advisory-checks fix (SonarCloud org-LOC-quota unblock, #636). |
| **P1** | [x] | #629 | ~~Bulk delete (multi-row) for CDEF + Authorization Boundary index (admin)~~ — **MERGED (PR #638, held at v1.8.11)** | `BulkDestroyService` + `bulk-select` Stimulus controller; AB referential guard + single-delete fix. |
| **P1** | [ ] | #630–634 | Document review/approval workflow epic (Catalog/Profile/Baseline/CDEF) | On `feature/630_document_approval_workflow` (one stacked PR closing #630–634). `Approvable` concern + `DocumentApprovalService` (draft→pending_review→approved/rejected; approver = admin / `*.approve` / policy_manager, self-approval blocked); `BaselineReviewService` (#633 selected-vs-expected + ODP diff); flag-gated publish (`SPARC_REQUIRE_DOCUMENT_APPROVAL`, default off); per-type UI + API submit/approve/reject; review queue. **VERSION → 1.9.0** (covers #629 + this epic). |
| **P2** | [ ] | #528 | CSP follow-up — remove unsafe-inline, refactor inline scripts, add reporting | Post-v1.7.0 follow-up. Track-down all inline `<script>` blocks across `app/views/`, refactor to per-request nonces or Stimulus controllers. Required to remove `'unsafe-inline'` from the active CSP policy. |
| **P2** | [ ] | #531 | Optional GuardDuty S3 tag check hook on blob serving | Post-v1.7.0 follow-up. ActiveStorage middleware that reads GuardDuty's `GuardDuty-Malware-Protection-Status` S3 object tag and refuses to serve infected blobs. Defense-in-depth beside container-side scanning. |
| **P2** | [ ] | #447 | Umbrella: HDF Amendment translation/UI layer for tenant CI/CD finding triage | Plan B (deferred 2026-05-06). Hosted multi-reviewer disposition workflow with full UI. Stays parked unless customer demand justifies the scope (~4k LOC + UI). #449 shipped the lean stateless API instead. |
| **P1** | [x] | #682 | ~~Configurable environment/rules header bar on every screen~~ — **SHIPPING (v1.10.0)** | `feature/v1.10.0_header_resolver_search`. `SparcConfig` `header_text`/`header_text_color`/`header_highlight_color` + strict color validator; colors applied via CSSOM (CSP-safe vs #528); rendered in both layouts; defaults `#ffffff` on `#1f6fa5` = 5.42:1 (WCAG AA); contrast not enforced on operator values. NIST AC-8 mapping + authentication CDEF updated. |
| **P1** | [x] | #680 | ~~Durable, version-aware artifact references + version history~~ — **SHIPPING (v1.10.0)** | Stable `/artifacts/:uuid` resolver (→ current content) + **content-version UUID** in back-matter `resource.uuid` (fingerprint over file + attestations + status) for drift detection; permanent `artifact_versions` history with **full per-version blob retention** (reference-based) + `versions/:uuid` lookup; parse-blob purge **default off**. NIST AU-10/SI-12/CA-7. Folded into v1.10.0 (no bump) before the tag. Copy-per-version → #686; ODP cadence validator → #685; orphan reaper (Phase 3) still open. |
| **P1** | [x] | #672 | ~~Search field on every artifact index~~ — **SHIPPING (v1.10.0)** | Shared `Searchable.search_text` scope (name+description, LIKE-wildcard-escaped) backing the 8 web indexes + `Api::V1` `q` param; reusable Turbo/Stimulus search partial; per-index Playwright ui-smoke; endpoint docs updated. |
| **P3** | [x] | #681 | ~~Bump rubyzip 3.4.0 → 3.4.1 (patch-updates group)~~ — **SHIPPING (v1.10.0)** | Folded the Dependabot patch bump into the release branch. |
| **P3** | [ ] | #341 | Add XML document type fingerprinting for upload validation | Defensive, post-#392. Touches `FileUploadable` and parser entry-points. Coordinate with anything else editing those concerns. |
| **P3** | [ ] | #246 | Repository cleanup & OSCAL fixtures bloat | Background lane. Scope-define needed; treat as parallelizable while a feature ships. |
| **P3** | [ ] | #413 | API documentation + automated testing — umbrella | Close on #433 merge (Phase 2 of the umbrella). |
| **P3** | [ ] | #422 | POAM Scenario B — cross-instance federated POAM visibility | Gated on first real federation deployment (peers configured + `SPARC_HASH` rotated in production). Stays parked until that exists. |

<!-- markdownlint-enable MD013 -->

**Deliverables:** Repo safe to flip public, type-safe API test suite catching schema drift before deploy, OSCAL-correct CDEF mutation API and bulk Converter application workflow, CSP without `unsafe-inline`.

**Sequencing:**

```text
Sprint 14a (PUBLIC-FLIP CRITICAL):
  Operator:   #545 settings clicks + sparc-iac#281 OIDC trust apply
  Dev A:      #433 slice 1 (pydantic schemas, read paths)  -- starts after v1.7.2 deploys

Sprint 14b (post-flip):
  Dev A:      #433 slices 2-5 (write paths, round-trip, audit, OSCAL)
  Dev B:      #498 CdefMutationService
  Dev C:      #341 XML fingerprinting (background)

Sprint 14c:
  Dev B:      #499 bulk Converter → CDEF (depends on #498)
  Dev A:      #528 CSP unsafe-inline removal (after #433 lands so test coverage is in place)
  Dev C:      #531 GuardDuty hook (if Prisma/GuardDuty decision lands)

Backlog / gated:
  #246  -- background lane any time
  #413  -- closes when #433 merges
  #422  -- gated on first federated deployment
  #447  -- gated on customer demand
```

> **Order rule:** #545 + sparc-iac#281 MUST land before any visibility flip on the repo. Everything else can run in parallel once those are done.

---

### Phase 16: v1.16.0 — Config Correctness, Authorization Sweep, UX Filters, Auth Entitlements (CURRENT)

**Goal:** Close the v1.16.0 milestone (**49 issues — 40 closed, 9 open, re-measured 2026-08-19 late**, after Bundles T and Q and the hdf-cli pin shipped; 15 originally scoped, plus #939, #941, #942 and #936 filed during Bundle F, #944, #946, #947 + #952 found in local review of Bundle E, #845 pulled in to make the test data real, #954, #955, #956, #958 filed and fixed inside Bundle M, #963 filed and fixed inside Bundle N, #935, #951, #959 added by the owner on 2026-08-15, **#981, #982, #984 filed from the Bundle P verification gate**, **#988, #989 filed and fixed inside Bundle T**, **#991 filed and fixed inside Bundle Q**, **#993 filed and fixed by the hdf-cli 3.5.1 pin**, and **#994, #995, #997, #998, #999 filed 2026-08-19**). The count has moved **eight** times; **measure it rather than carrying the last figure forward** — reconcile against `gh issue list --milestone v1.16.0 --state all`, which is how #945 and #948 were found after being missed by every prior pass.

**The last five were all found by USING the product, none by the suite.** #994, #997, #998 and #999 came out of exercising `/api/v1` against a live instance and reading SPARC's output against NIST's published OSCAL references; #995 is the epic that generalises them. Every underlying defect was green at the time it was found — which is the argument #995 makes and the reason it is a release gate rather than a nice-to-have.

The two structural security deliverables led: a spec that fails when a controller ships without authorization (#919) and one that pins `disposition: "attachment"` on user content (#894). What remains is the document model, the boundary-attachment family, and the IdP entitlement epic.

#### Bundles at a glance

Ordered by when the work happens. Bundle letters are historical — read the **order** column,
not the letter. Every milestone issue belongs to exactly one bundle.

| Order | Bundle | Issues | Status |
| --- | --- | --- | --- |
| 1 | A — Config correctness | #914 #909 | **Shipped** (PR #924) |
| 2 | B — Content security | #894 #897 | **Shipped** (PR #925) |
| 3 | C — Authorization sweep | #919 #707 | **Shipped** (PR #931) |
| 4 | D — Collection browsing & lineage | #908 #928 | **Shipped** (PR #933) |
| 5 | K — Evidence provenance | #934 | **Shipped** (PR #937) |
| 6 | F — CDEF coverage from Terraform | #904 | **Shipped** (PR #938) |
| 7 | E — In-product help | #880 #879 | **Shipped** (PR #943) |
| 8 | M — Reference authorization estate | #845 #954 #955 #956 #958 | **Shipped** (PR #960) |
| 9 | N — Document model — reachable references | #941 #942 #944 #945 #946 #957 **#963** | **Shipped** (PR #964) |
| 10 | #939 — pulled forward, on its own | #939 **#967** **#970** | **Shipped** (PR #969) |
| 11 | O — Boundary attachment | #929 #952 | **Shipped** (PR #975) |
| 12 | S — Controls layer: who can see it, and what it carries | #974 #959 #935 | **Shipped** (PR #976) |
| 13 | P — Evidence completeness | #947 #948 | **Shipped** (PR #983) |
| 14 | T — Bundle P follow-ups | #981 #982 #984 #988 #989 | **Shipped** (PR #986 → `28443b7c`) |
| 15 | Q — Polish | #936 #991 | **Shipped** (PR #992 → `6d39e089`) |
| 16 | **hdf-cli 3.5.1 — pulled forward, on its own** | **#993** | **Shipped** (PR #996 → `e0473814`) |
| 17 | U — Profile fidelity: what the baseline says, and what SPARC shows | #997 #999 #998 **#994** | **IN PR** (#1000) |
| 18 | V — The release gate, and the last unslotted screen | **#995** #951 | **Next** (owner-slotted 2026-08-19) |
| 19 | R — Auth entitlements — IdP as system of record | #860 #842 #822 | Queued |

**Nothing is unslotted.** #935 and #959 went into **Bundle S** on 2026-08-17, #997 #998 #999 #994
into **Bundle U**, and **#995 and #951 into Bundle V on 2026-08-19 at owner direction** — which
makes V the NEXT bundle and moves R behind it. That ordering is the right way round for a release
gate: #995 must be satisfied before the tag, and its findings generate work, so discovering them
after the largest bundle in the milestone would be discovering them too late. **Tracked separately, no milestone:** #953 (authenticated DAST — unblocked by Bundle
M's production posture), #966 (SonarCloud findings triage — owner directed that it be filed
and *not* worked; 281 open findings, 2 Blockers amounting to one defect), and **#968** (audit the
swallow-and-continue rescue patterns — raised out of #939, **due 2026-09-06**; 54 rescue sites,
11 log-and-continue in services/jobs, and 17 files combining a transaction with a rescue, which
is the candidate set for the #963 shape).

**Milestone re-measured 2026-08-19 late, after Bundles T and Q and the hdf pin: 49 issues,
40 closed / 9 open.** The 9 open: **#822 #842 #860 #951 #994 #995 #997 #998 #999**. Bundle S closed
#935, #959 and #974; Bundle P closed #947 and #948; Bundle T closed #981, #982, #984, #988 and
#989; Bundle Q closed #936 and #991; the hdf pin closed #993.

**The earlier figure in this section — 40 issues, 30 closed / 10 open — was measured during Bundle
P and is superseded.** It is left in the paragraphs below as the record of what was known then.

**#981 and #982 were filed on 2026-08-18 from the Bundle P verification gate** and added to the
milestone by the owner. Neither is worked in Bundle P's PR. They are the eighth and ninth
additions to a milestone that has now moved six times — which is the whole reason this section
says to measure rather than carry the figure forward.

**The milestone PAGE reads 38, and that is not a disagreement — it counts pull requests too.**
PR #933 is attached to the milestone, so the web figure is issues + that PR. Count issues with
`gh issue list --milestone v1.16.0 --state all`, which is what the numbers above are; never read
the count off this file, and never off the milestone page without checking for attached PRs.

**Dev/prod toolchain divergence — measured 2026-08-17. OWNER-DECIDED: this is done *with* #820,
in sequence, not as a separate track.** The toolchain rebuild is the prerequisite step of that
work item, so **#820 is no longer just a lockfile bump** — it is "rebuild the dev Ruby against
OpenSSL 3, prove it, then take the gem bump", and the order is a hard dependency rather than a
preference. Merging the bump first leaves a developer with a segfaulting bundler and no working
`bundle` to recover with. It stays in Bundle R; nothing here pulls it earlier.

**Ruby is identical on both sides — 3.4.4, pinned by `.ruby-version` and
`ARG RUBY_VERSION=3.4.4` in the Dockerfile — and so is the openssl gem (3.3.0).** The split is
the system library: local links **OpenSSL 1.1.1w** (the EOL 1.1.1 branch) while the prod UBI9
image runs **3.5.5**, so no OpenSSL-3
behaviour is exercised in the inner loop. The pre-push gate does cover it — the UBI9 prod image
is required for the smoke/API run — so this is feedback latency rather than a hole in the gate,
and the #750 pattern in a different layer. It does gate **#820** (openssl gem 3.3.0 → 4.0.2):
the 4.x line requires OpenSSL 3.x, and on a 1.1.1-linked Ruby it **segfaults inside bundler
itself**, so `bundle install`, `bundle exec` and `gem install` all stop working — a hostile
failure to meet cold, since the crash names bundler rather than the dependency. Findings are
recorded on PR #820.

---

#### Remaining work — in execution order

<!-- markdownlint-disable MD013 -->

##### 10. #939 — pulled forward, on its own

**Out of Q at owner direction (2026-08-15).** It is small, and its cost **grows rather than staying flat**: every cold pass leaks more permanent orphans. Sequenced after N so it does not block the document-model work, and before O.

**The filed cause did not survive measurement.** The issue suspected GitHub rate limiting. But
every blob is fetched in `build_candidates`, and the per-candidate loop that counts the errors
already holds `candidate[:content]` — `import_one` performs **no network I/O at all**, so a rate
limit cannot be what it was counting.

**And the symptom no longer reproduces.** A live cold pass on current `main`, against the UBI9
prod image with a GitHub token, reported `discovered=230 imported=230 skipped_unchanged=0
superseded=0 errors=0` in 136 seconds, with 230 `aws_labs_sourced` documents and **zero** rows
in the orphan shape. Most likely repaired as a side effect of Bundle N — #944 stopped the
exporter hardcoding component fields and #963 fixed a rescued `RecordNotUnique` poisoning the
transaction, both directly on the failing path — but **causation is not demonstrated** and is
not claimed.

**The structural defect is real and latent, which is what the fix addresses.** Nothing about a
clean run makes a future parse failure safe. That framing also collapsed the planned scope: the
owner's point that "the refresh button should be sufficient to fix failed loads" is correct once
a failed file leaves no residue, so the separately-planned re-pull endpoint, "Fetch AWS" control
and failure-record table were all dropped. The retry/backoff classification was dropped too — its
justification was a failure mode that no longer reproduces, and #584's intent is that a genuine
upstream schema gap should surface as an error rather than be retried into silence.

**Cold-pass runtime — owner-decided 2026-08-17, not an issue.** The 136 seconds measured locally is a laptop artifact. In a live deployment the corpus is already in the database, so reads happen at the DB layer rather than re-fetching through the application, and the AWS↔GitHub path is far faster than a home connection — observed during the sparc.risk-sentinel.org deployment. **No follow-up issue.**

| Issue | Description | Notes |
| --- | --- | --- |
| **#939** | ~~`AwsLabsCdefRefreshJob` reports 39–51 errors on a cold pass and still reports success~~ — **MERGED (PR #969)** | **Filed during Bundle F. Pulled out of Bundle Q and sequenced on its own** (owner, 2026-08-15). Each failed file leaked a **permanent orphaned `CdefDocument`** — `write_through_parser` created the row before parsing, so a parse failure left `status: "processing"`, zero controls and no `source_type`, putting it outside `aws_labs_sourced` and therefore invisible to both cleanup and the dedupe in `import_one`, so each retry leaked another. 82 measured after four passes; they sorted to the top of the CDEF index and broke OSCAL export. **Fixed by wrapping the create in the transaction**, which is what makes the existing "Refresh from AWS Labs" button sufficient to repair a partial run. Also: `reindex_components` takes a SAVEPOINT (it rescues `StandardError` and is now inside a transaction — the #963 shape), `build_candidates` rescues an explicit list of fetch failures so one rate-limited blob no longer discards all 230, a degraded run emits an `aws_labs_cdef_refresh_degraded` audit event with an error-class histogram, and a deferred idempotent migration removes pre-existing shells behind seven conjunctive conditions. |
| **#967** | ~~Index totals count soft-deleted documents' children — 1 CDEF reports 1290 controls~~ — **MERGED (PR #969)** | **Filed 2026-08-17, found while validating the #939 plan against the running image** — the owner could not confirm the plan's claims from the screen, which is what surfaced it. The document models are `SoftDeletable` (`default_scope { where(deleted_at: nil) }`); the child models are not, and five index controllers counted the child table directly. Measured: CDEF **+1280**, SSP +149, Profile +10 (SAR and POA&M read 0 only because their soft-deleted documents carried no children). Not orphaned rows — the FK is `ON DELETE CASCADE`, validated, and proven to fire; a soft delete triggers neither it nor `dependent: :delete_all`, by design. Counting through the parent also stops the four boundary-scoped tiles reporting a population their own list does not. **Bundled into the #939 PR at owner direction.** |

##### 11. Bundle O — Boundary attachment

**#929 first, #952 second — the order is a hard dependency, not a preference.** `document_metadata_params` permits only name/version/oscal_version/description, so a boundary can be set at upload and **never after**; requiring one before #929 lands leaves every orphaned document permanently invalid and unfixable. Bundle M built the groundwork — the reference estate attaches every document to its boundary explicitly and ships a spec pinning it, because the generators leave it nil.

**SHIPPED 2026-08-17, PR #975 merged as `d1abba57`**, 5 commits. Final gates on the rebuilt UBI9 prod image: rspec **5311 passed / 0 failed / 10 pending**, `tests/api` **464**, full ui-smoke **448 passed / 0 failed / 29 skipped** (all skips environment-gated and named), rubocop + brakeman (0 warnings) + zeitwerk + ruff clean, **17 mutations RED**. Wiki published `468bbc8`, which also cleared the publishes owed from Bundle N and #939.

**Four measured findings correct the issues as written. Read these before trusting the issue text:**

1. **The boundary picker rendered for NOBODY, including admin** — a stronger statement than #929's "the one chance may not offer the right boundary". Both `shared/_boundary_picker` and `cdef_documents/_scope_picker` joined the LEGACY roster (`authorization_boundary_memberships.user_id`) while scoping and permissions run off **UserRole** — the two-role-systems trap. That column is optional and nil for anyone added by name/email. Measured live: all 7 roster rows nil, admin holding 0 `user_roles`, so both paths returned 0 and `<% if boundaries.any? %>` removed the field from the page. **Every SSP/SAP/SAR/POA&M uploaded on that instance was necessarily an orphan** — which is where #952's population comes from. This makes #929 a hard prerequisite for #952 rather than a sequencing preference.
2. **CDEF has no `authorization_boundary_id` column at all**, so #929's "all five document types" table is wrong on that row. A CDEF reaches a boundary through `boundary_cdef_documents` rows against its environments, or via `globally_available` — applied only in `FileUploadable#apply_post_create_scope!` at create and changed by no route. Same defect, different mechanism; owner directed it be fixed in this bundle, and the logic moved to `CdefScopeService`.
3. **SAR orphans measured 2 of 2, not 1 of 2.** `db/seeds.rb` linked only `SspDocument.first` / `SarDocument.first`, and the section did not re-run after Bundle N rebuilt the demo estate. Live: SSP 1/2, SAR 2/2, SAP 0/1, POA&M 0/1, Evidence 6/6 (exempt).
4. **Both layers authorized re-association against the CURRENT boundary.** `BoundaryScopedDocument#authorize_document_write!` and its `Api::V1` twin both computed `record&.authorization_boundary_id || params[…]`, so write on boundary A was enough to move a document into boundary B.

**Owner decisions, 2026-08-17:** orphans get a hard presence validation **plus** the nil-visibility fallback turned off for these types **plus** a report — **no row is auto-assigned**; CDEF scope re-assignment ships in this bundle; the "Add…" tile leads to a screen offering both attach-existing and upload-new.

**Two traps worth carrying forward.** `AuditEvent.log` rescues `RecordInvalid`, so an action missing from the `ACTIONS` constant is recorded **nowhere, silently** — the `FLASH_CLASSES` shape again; the audit spec is what caught it. And the presence validation exposed that **the generators mint orphans**: 161 of the 188 initial failures were `SarFromSspService` / `SapGeneratorService` / `SspFromProfileService` / `SarFromProfileService` creating boundary-less documents. They now inherit from their source where one exists and take the boundary from the caller where it does not.

**A latent bug surfaced with it:** `SspJsonParserService#upsert_leveraged_authorization_record` opens with `return unless leveraging_boundary` and had therefore never run. Once documents always had a boundary, importing the same OSCAL SSP into two boundaries collided on the GLOBAL unique index over `leveraged_authorizations.uuid` and raised an unrescued `RecordNotUnique`, aborting the whole import — the #963 failure mode. Fixed in-branch.

**Fixture cost, measured:** SSP 214 call sites / 88 files, POA&M 71/35, SAP 54/27, SAR 51/27 (~390, not the 368 the issues estimated). Associating the boundary in the four factories covered nearly all of them; only four specs outside the new ones genuinely need a boundary-less row and use the `create_legacy_orphan` helper.

| Issue | Description | Notes |
| --- | --- | --- |
| **#929** | ~~A document cannot be attached to a boundary after upload — the "Add…" tile leads nowhere~~ — **MERGED (PR #975)** | **Bundle O, and #952 depends on it landing first.** Same inversion as #928 and affects **all five** document types: the boundary can be set at upload but never after (`document_metadata_params` omits `authorization_boundary_id`), while the API permits it. Aggravated by the upload picker listing only boundaries the user is a member of, so the one chance to set it may not include the right one. Re-association must authorize against the **target** boundary — coordinate with #919. |
| **#952** | ~~SSP/SAP/SAR/POA&M can exist with no boundary and are then visible to every signed-in user~~ — **MERGED (PR #975)** | **Bundle O, and it must follow #929 — tightly coupled.** A **data affiliation** problem, not a controller one: `boundary_scoped_relation` matches `boundary_ids + [nil]` and `authorize_document_read!` returns early on a nil boundary ("global -> open to all"), which is right for a genuinely instance-wide record and wrong for these four types. Measured on a demo instance at filing: 1 of 2 SSPs and 1 of 2 SARs. **Re-measured when the work started it was 1 of 2 SSPs and 2 of 2 SARs** — the seed links only `SspDocument.first`/`SarDocument.first` and had not re-run since Bundle N rebuilt the estate, so **the seed itself creates them**. **Evidence is deliberately exempt** — it can be leveraged/inherited across boundaries, so boundary-less evidence is legitimate. CDEFs are out of scope: a CDEF is generic, stating a control *can* be satisfied rather than how it is implemented here (provider capability, e.g. MFA → Okta, being the exception). #929 is the prerequisite: `document_metadata_params` permits only name/version/oscal_version/description, so the boundary can be set at upload and **never after** — requiring it without #929 leaves every orphan permanently invalid and unfixable. Cost is in the fixtures, not the validation: **no** SSP/SAP/SAR/POA&M factory set a boundary, across **~390 call sites in ~150 spec files** (368 was the estimate at filing); seeds fixed and `SeedRunner::CURRENT_VERSIONS` bumped. **What the estimate missed:** the presence validation exposed that four generator services minted boundary-less documents outright — 161 of the 188 initial failures, one cause. |

##### 12. Bundle S — Controls layer: who can see it, and what it carries  ·  **SHIPPED** (PR #976, merged `dc7c7dcf`, 2026-08-18)

Three issues that all land on the same controllers, views and export builder. Sequenced together at owner direction (2026-08-17) because **nothing releases until v1.16.0 is tagged**, so there is no incremental-delivery reason to split the security fix out, and one branch avoids three rounds of conflicts in the same files.

**Progress on `feature/974_controls_layer_access`** — one commit per phase, one PR.

| Phase | Scope | State |
| --- | --- | --- |
| 1 | #974 — `public_controls_read` declaration + structural spec + both-posture request specs | **Committed** `b5a48012` |
| 2 | #959 — export carries only referenced back-matter + reference-integrity invariant + advisory report | **Committed** `0772f826` |
| 3 | #974 — Converters index/show, Controls-layer downloads under the flag, nav consistency | **Committed** `f96d4bb7` |
| 3b | #974 — rate-limit the newly-anonymous Controls downloads | **Committed** `23a0b541` |
| 4 | #935 — `framework` derived at import + facet on catalogs and baselines | **Committed** `4db8948c` |
| 5 | Docs, compliance, wiki, both-posture Playwright | **Committed** |
| — | SonarCloud findings on the PR: `find` over `each`+`return`, and four `<a role="button">` nav toggles made real `<button>`s | **Committed** `9ba70a70` |

Final gates on the merged tree: **rspec 5372 / 0 failures / 10 pending**, `tests/api` **464**,
ui-smoke **453 / 0 / 29 in both postures**, brakeman 0, rubocop / zeitwerk / ruff clean, and
**29 mutations RED** across the bundle.

**SonarCloud's review caught a real accessibility defect, and the fix was already in the repo.**
Eleven findings on the PR. Three were `FrameworkDeriver` iterating with `each` and returning from
inside the block — a `find` wearing a disguise, since the documented rule was always
first-match-wins. The other eight were four header dropdown toggles still written as
`<a href="#" role="button">`, which announces itself to a screen reader as a button and then
ignores the Space key, because anchors have no native activation. `_controls_nav` had **already**
been converted to a real `<button>` and carries a comment explaining why — the lesson had reached
one dropdown out of five, which is the same partial-application shape as the #974 gate itself.
Sonar's suggested `onKeyDown` handler is the workaround; the right element is the fix.

**The gap that allowed it:** nothing asserted that the menus OPEN. The parity spec checks which
paths appear in the HTML, so four dead toggles behind a shared partial changed nothing it looked
at. `spec/system/main_nav_dropdowns_spec.rb` now opens each menu in real Chrome via
`click_button` — which will not match an anchor — and opens one with the Space key alone;
reverting a single toggle fails both. **Deferred at owner direction:** six more
`<a role="button">` survive in older views (`shared/_heatmap` x2, and the SSP / SAP / CDEF /
profile `show` pages), outside this PR's diff and therefore never flagged. Not an issue; do not
file one unprompted.

**Two findings from phase 1 worth carrying forward.** The structural spec immediately caught that `api/v1/sessions` needed an explicit allowlist entry and that one allowlist entry was stale. And two mutations did NOT bite on the first round: the flag-on helper broke out on a login redirect and reported "status < 400", passing against a gate that never opens, and the macro's write-refusal guard had no test at all. Both are fixed and all four now bite — the same vacuous-test shape the #919 spec hit, which is why that file's history is cited in the new one.

**A navigation defect was found during owner testing and fixed in-bundle.** With the flag on, the SIGN-IN page offered no route to component definitions or converters — and that is where an anonymous visitor lands, because `/` redirects there. The cause was not a missing entry: **the header banner was two hand-maintained copies**. Only `environment_header` and `controls_nav` had ever been extracted; the nav shell, brand, About, Resources and theme toggle were duplicated across `layouts/application` and `layouts/login`, and the Implementation/Assessment/Enterprise dropdowns existed in `application` alone. The copies had **already drifted** (the About link carried different classes in each), and `_controls_nav` even carries the comment "Shared by the application and login layouts so they can't drift" — the same lesson learned once and applied to one dropdown out of five.

Mirroring the entry would have made a third copy. Instead the banner is now ONE partial, `shared/_main_nav.html.erb`, rendered by both layouts (371→116 and 266→222 lines). Extracting it exposed two more entries advertised to people who cannot open them: **Home** and **OSCAL overview** both 302 anonymously and are now signed-in only. A spec pins parity, reachability, and the structural rule that any layout with a navbar must render the shared partial.

**OWNER HARD RULE, recorded 2026-08-17: NO NAVIGATION CHANGES WITHOUT APPROVAL.** SPARC's menus follow the NIST layers and a link must be findable in the same place every time. Placement never varies; only visibility does.

**Both postures were proven in a real browser, twice.** `tests/ui-smoke/test_public_controls_974.py` declares the posture via `SPARC_SMOKE_PUBLIC_CATALOGS` and independently confirms it against the app, failing loudly when the two disagree or nothing is declared — verified by running it with the wrong posture and with none, which produced errors rather than skips (#885's lesson). Full suite, same image, container recreated between runs: **flag OFF 452 passed / 1 failed / 29 skipped**, **flag ON 453 passed / 0 failed / 29 skipped**.

**The one failure was a HARNESS bug, not a product one, and it is worth remembering why.** `test_index_filters_908` asserted `"framework=FedRAMP 20x" in url` against a URL reading `framework=FedRAMP+20x`. The filter worked; the assertion compared a raw value against an encoded query. Every facet value that file had ever seen was single-token (`OSCAL`, `1.1.2`, `published`), so the encoding path was never exercised — **`framework` is the first facet value in the product containing a space**. Fixed by parsing the query rather than by reordering the facet to dodge the first-dropdown position, which would have been gaming the test.

**Phase 3 turned up a real availability gap, found by driving the app rather than reading the diff.** With the flag on, the catalog download that is now anonymous measured **24 seconds and 2.97 MB** (16s of it GC), and every existing Rack::Attack bucket covered writes, uploads or credentials — nothing throttled anonymous GETs. Owner directed the fix land in-bundle, so `controls/downloads/5min/ip` was added with a new documented env var, scoped to `download_*` only because throttling the screens would make a published catalog unbrowsable.

**#935's derivation was proven on real data, not fixtures.** After the backfill, the live estate reads: the two NIST catalogs → `NIST SP 800-53`, FedRAMP KSI → `FedRAMP 20x`, and `Demo LOW Baseline` → `NIST SP 800-53` **through catalog lineage**, which is exactly the case the owner described — a baseline whose own name says nothing still resolves through the catalog it descends from.

**Phase 2 was narrower than it looked.** Only the authoritative branch is scoped: evidence-derived back-matter is `source: "managed"` with `resourceable: doc` and flows through `managed_resources`, untouched. The #845 estate's thirteen policy resources per SSP are of that kind and are unaffected — verified against the committed artifacts rather than assumed.

**#974 is a live exposure**, filed 2026-08-17 while answering a question about CDEF default scope. `CdefDocumentsController` and `ControlFamiliesController` carry a bare `skip_before_action :require_authentication` with **no** `require_authentication_unless_public_controls` companion, unlike catalogs, catalog controls, mappings and profiles. The pairing is a two-line convention repeated per controller, so omitting the second line is silent — nothing fails, the screen simply becomes public.

Measured unauthenticated against a UBI9 prod-mode instance with `public_catalogs? == false`, sweeping all 100 collection GET routes plus the Controls-layer member routes. The unintended public surface is **exactly two controllers**:

| Path | Unauthenticated today | Expected |
| --- | --- | --- |
| `/cdef_documents` and `/cdef_documents/:slug` | **200** | 302 → /login |
| `/control_catalogs/:catalog/control_families/:code` | **200** | 302 → /login |
| catalogs · profiles · mappings · converters · SSP/SAP/SAR/POA&M | 302 → /login | unchanged |

24 CDEFs are linked to an anonymous caller on page 1 of a 231-document corpus, and a control-family page serves catalog content that `/control_catalogs` itself refuses anonymously — the same data answering differently depending on the URL used to reach it. **No configuration turns it off.**

**The owner-decided view/auth matrix lives on #974 and is authoritative.** In short: the flag opens the Controls layer for **read on the web only** — catalogs, catalog controls, families, profiles, mappings, CDEFs, and Converters **index + show only**. Writes, fetches and refreshes never become public in any posture; **`/api/v1` always requires a Bearer token**; and **boundary documents (SSP/SAP/SAR/POA&M/Evidence) are never public**, which is what #929/#952 just tightened. Controls-layer **downloads/exports follow the screens** and become public under the flag.

**That last decision makes #959 a hard prerequisite, not a companion.** `BackMatterBuilder#authoritative_resources` embeds **every** authoritative resource in the instance into **every** export, with no document, boundary or organization scoping — measured **12 today** on the dev estate, and 96 rows of UI-smoke residue that leaked into the #845 reference artifacts and once reached a public wiki screenshot. Publishing exports before that is scoped would publish unrelated instance state to anonymous callers.

**#935 joins because it is the same screens.** It adds a derived-at-import `framework` column to `control_catalogs` and `profile_documents` plus a facet on those indexes and their `Api::V1` endpoints. No conceptual coupling to the other two — the reason to bundle is that all three edit the catalog and baseline index paths, and #908 already shipped the facet mechanism (`CollectionBrowseQuery`), so only the column is missing.

| Issue | Description | Notes |
| --- | --- | --- |
| **#974** | CDEF and control-family screens are public regardless of `SPARC_PUBLIC_CATALOGS` | **Bundle S, security half.** Replace the two-line per-controller convention with one declarative helper so a controller cannot half-opt-in, then **make the gap fail a test** in the manner of #919's coverage spec — a convention that can be half-applied will be half-applied again. Assert **both** postures for every screen: a test that only runs with the flag off passes today for catalogs and never notices CDEFs. |
| **#959** | Every export embeds every authoritative back-matter resource in the instance | **Bundle S, and #974's export half depends on it.** Filed as a *question* with three items to settle — whether instance-wide back-matter belongs in every document, whether it should be scoped by organization or boundary, and whether an export should be reproducible independent of unrelated instance state (#845 assumes yes; today it is not). **Settle those before writing code.** |
| **#935** | Derive and persist `framework` at import, so catalogs and baselines can be filtered by it | **Bundle S, feature half.** Cut from #908 because framework is not a field — it exists only as prose and filename, and deriving it per request by regexing titles was rejected deliberately: confidently displaying a *wrong* framework is worse than offering no filter. Derive once at import, **leave null when nothing says clearly**, and make the rule a named, tested unit with a backfill through the same path. |

##### 13. Bundle P — Evidence completeness  ·  **Shipped** (PR #983 → `1589bbbf`)

Both are about evidence being trustworthy rather than merely present. Bundle M is the first fixture with evidence at more than one tier — 32 records across two boundaries in two organizations — so #948 finally has something real to render.

| Issue | Description | Notes |
| --- | --- | --- |
| **#947** | An attestation cannot be recorded without a file, the attester is unverifiable free text, and evidence can be saved with no controls | **Found in local review of PR #943.** Three defects on one screen. (1) The evidence form renders the dropzone with `required: !@evidence.file.attached?`, so a file is **always** mandatory on create — a UI-only constraint the model does not impose (`has_one_attached :file`, no presence validation). It also fails **silently**: the real input is `d-none`, and a browser cannot focus a hidden required field to report a message, so the form just refuses to submit. `EVIDENCE_TYPE_LABELS` already offers **Signed Statement**, so the vocabulary anticipates fileless evidence the form forbids. (2) `Attestation` stores `attester_name` / `attester_email` as **strings with no FK to users** and no tie to the boundary, while `ROLES` spans `system_owner`, `isso`, `ciso`, `authorizing_official` — so an attestation can claim the SO signed off when that person holds no such role. Same shape as #934, and the #919/#707 roster already knows who holds which role per boundary. (3) Nothing requires an `Evidence` to have any `EvidenceControlLink`, so evidence that supports no control can be saved. Owner: **collected evidence should require 1:n controls.** |
| **#948** | Tier the evidence index Instance → Organization → Boundary | **Was never in this plan** — on the milestone and missed by every previous currency pass, found only by reconciling the plan against the GitHub milestone rather than reading it. Bundle P with #947. #845 listed it among the issues the reference estate unblocks: the estate is the first fixture with evidence at more than one tier (32 records across two boundaries in two organizations), so the tiering has something real to render. |

**Owner decisions taken during the bundle** (recorded so they are not relitigated):
an attestation **is** evidence, so it is created with the record on one screen rather than at a
second screen afterwards; who may attest is expressed through a new **`evidence.attest`**
permission rather than a hardcoded role list, seeded to the seven accountable boundary roles with
`assessor_3pao` excluded on separation of duties; **instance-wide evidence is provider material**
from a leveraged SSP, so Policy reaches it without thereby gaining authority over any individual
boundary's evidence; zero-control-link rows are **reported and blocked on re-save**; tiering is
**automatic**, appearing only when more than one boundary is visible; and the tiering generalises
to five screens, not six — `cdef_documents` has no boundary column at all (**#980**).

**Three defects the rspec suite could not see** were found by driving the form in a browser, which
is the concrete case for the ui-smoke gate: removing the dropzone's `required:` local **re-armed**
the JavaScript guard it was meant to remove (the partial defaults it to true, and
`dropzone_controller` enforces it with a capture-phase `preventDefault`), the attester picker
offered an Instance Admin a role it then disabled, and a blank review frequency posted `""` which
`allow_nil` does not cover. Two further findings were filed rather than folded in: **#981** and
**#982**.

##### 14. Bundle T — Bundle P follow-ups  ·  **Shipped** (PR #986 → `28443b7c`)

All three came out of the Bundle P verification gate and are deliberately **not** in its PR. They
are sequenced **after P** because #981 is a direct follow-on to the attester picker #947
introduces — there is nothing to refresh until that picker exists.

**Two of the three are the same shape: a check that reported green while testing nothing.** Bundle
P fixed that twice inside its own PR (`test_evidence_boundary_scoping`, whose fixtures the demo
seed could no longer create; and `test_oscal_metadata_edit`, which picked a published record off
the index and skipped its own interaction assertions). #984 is the remaining instance. Worth
treating as one theme rather than three tickets.

| Issue | Description | Notes |
| --- | --- | --- |
| **#981** | ~~The attester role list goes stale when the boundary changes~~ — **FIXED** | **Depends on #947.** Resolved with the JSON-lookup option, not the Turbo Frame: the attestation fieldset also holds the statement, date, frequency and status, and re-rendering the frame would discard typed input — trading one silent data-loss defect for another. `AttesterEligibilityService` now backs the partial, a session endpoint and its `Api::V1` twin, so what is OFFERED and what is ACCEPTED cannot drift. Original note: The eligible attesters and roles are computed server-side for the boundary the form was *rendered* with, so changing the boundary select leaves them behind — the form can offer `policy_manager` (instance-scoped, valid only for instance-wide evidence) and the server correctly refuses it. The model is right; the form has not been told. Fix by re-rendering the fieldset in a Turbo Frame on boundary change, or by fetching the eligible set the way the control picker already does — **not** by embedding a map of the whole estate. |
| **#984** | ~~12 collection-view checks skip on four screens with no records~~ — **FIXED** | Seeded on the DEMO path (the estate builder's fixtures live behind `SPARC_SEED_REFERENCE`, a separate opt-in). `authoritative_sources` was seeded too — not one of the four, but empty on any fresh database for the same reason. **Running the seed end to end found a worse bug than the one filed:** on a fresh database `demo_ssp_sar` died on its first `SspDocument.create!` ("Authorization boundary can't be blank") because #929/#952 made the boundary mandatory and never updated the seed, so the section aborted and the second SSP and **both SARs** never ran — a new install had no SSP and no SAR. Fixed and the section bumped to 2.1.0. Original note: `test_collection_views` runs three checks across 16 screens; on `review_queue`, `promotion_queue`, `leveraged_poams` and `federation_peers` all three skip, because the screen is empty on a demo-seeded instance. Page load and console errors are still asserted — only the card-versus-table assertions never run, which is the file's actual subject and exactly what a change to the #888 shared component would break on all sixteen at once. Fix by SEEDING the four (the estate builder already produces review/promotion entries), not by creating records per test: view-mode persistence is across a visit and a torn-down fixture cannot exercise it. Keep the `_populated` guard — an empty collection is legitimate on a non-seeded deployment. |
| **#982** | ~~`cdef_document_populated_from_profile` is unregistered~~ — **FIXED, and it was 69 actions, not one** | **The sweep the issue asked for found 69 unregistered actions across 79 call sites in 29 files** — API token create/revoke, every finding disposition, every federation peer change, the whole back-matter promotion workflow, and the `converter_*` / `ksi_validation_*` families. None wrote a row in ANY environment: `.log` rescues `RecordInvalid` internally, so the API base controller's `raise unless Rails.env.production?` never fired and dev/test were as silent as prod. Four more were reachable only by resolving the call sites that build their action at runtime. Two further corrections rode along, see below. Original note: The action is emitted by both the web and API controllers and appears nowhere in `AuditEvent::ACTIONS`, so the write fails validation and `audit_log` rescues it — silently. Worth more than the one-line fix: add a guard that fails when any `audit_log("…")` call site names an unregistered action, which catches the class rather than the instance, then sweep the remaining call sites. NIST AU-2 / AU-12 claim coverage this path does not deliver. |

**#988 joined the bundle** — owner-directed, filed and fixed here. A boundary could be
recorded as leveraging a system that was **never authorized**:
`LeveragedAuthorization#date_authorized` was nullable with no presence validation and the form
offered it as optional. OSCAL requires `date-authorized` on every `leveraged-authorization`, so a
single dateless row made **every SSP on the leveraging boundary** fail export validation in all
three formats, bouncing the user to `?oscal_validation_failed=1` with nothing naming the row
responsible. The OSCAL round-trip sibling `SspLeveragedAuthorization` has **always** required it,
and both feed the same `leveraged-authorizations` array — one output contract, two different
rules. Fixed with a presence validation, a required form field, and a report-only data migration
for legacy rows (#952 precedent: report, and refuse on next save, rather than inventing a date
that belongs to someone else's ATO).

**Why no spec caught it, and the wider gap it exposes.** Every example in
`oscal_ssp_export_inheritance_spec.rb` called `export_unvalidated`, which checks the SHAPE of a
field and skips schema validation entirely. A validated-export example now covers it. **Eight
other spec files exercise an export path only through `export_unvalidated` and never once assert
schema validity** — `oscal_catalog_export_service` (9/0), `oscal_mapping_export_service` (9/0),
`oscal_assessment_plan_export_service` (7/0), `ato_package_export_service` (6/0),
`oscal_sar_export_service` (5/0), `hdf_aggregation_service` (2/0), `cdef_unmapped_stig_rules`
(2/0), `oscal_compliance_audit` (1/0). Same class as #984: green while proving less than it
appears. **Raised, not filed** — needs an owner call.

**#989 joined the bundle** — owner-directed after the #988 report. Eight OSCAL export services
define both `#export` (schema-validated) and `#export_unvalidated`; **four had specs that never
called the validated method once** (SAP, SAR, catalog, mapping), so schema validity was an
untested guarantee on those paths. Measured first: all four *succeed* today, so this was not a
live defect — it was a guarantee no test asserted, which is exactly how #988 shipped. A shared
example group now gives **all eight** the same contract: the validated path produces legal OSCAL,
it validates against the **right** schema, it **raises rather than returning a payload** when
validation fails (the alerting half, surfaced in the UI as `?oscal_validation_failed=1`), and
`export_unvalidated` **does not validate** — so neither method can drift into the other unnoticed.
Every existing `export_unvalidated` example is preserved: the four gap specs gained 38 lines and
lost none, and their unvalidated call counts are unchanged. Mutation-checked three ways — dropping
`validate!`, adding it to the unvalidated path, and validating against the wrong schema each turn
the contract red.

**Two corrections #982 pulled in, both owner-approved during planning.**

**The action was renamed, not just registered.** `cdef_document_populated_from_profile` became
`cdef_control_implementation_sourced_from_profile`, and the CDEF route/method
`populate_from_profile` / `attach_profile` became `source_from_profile` /
`select_profile_source`. An OSCAL SSP has `import-profile` as a first-class element, so
`populate_from_profile` is **correct for SSPs and was left alone**; a component-definition has no
such import — `import-component-definition` imports another CDEF — and reaches a profile only as
`control-implementation/@source`. The CDEF path had borrowed the SSP's vocabulary for a
relationship OSCAL does not give it. `POST /api/v1/cdef_documents/:id/populate_from_profile` is
published, so it still routes to the renamed action: **deprecated, undocumented, removal in
v1.18.0** alongside the `SPARC_BANNER_*` names (#909 precedent).

**A profile-sourced CDEF exported a fabricated `@source`.** #911 declared `profile_document` as
exactly that hop (`CdefDocument.lineage_via :profile_document`; `CatalogLineage` names the chain
`cdef -> @source`) and #944 gave authors a field to name it, but the export read neither — every
profile-sourced CDEF emitted `https://sparc.local/component-definitions/<primary key>`, a URI
resolving to nothing, on a document whose entire control basis came from a published,
UUID-bearing profile. Schema-valid the whole time, which is why validation never caught it:
OSCAL requires `source` to be present, not to be true. Resolution order is now authored value →
linked profile → `determine_source`, resolved live from the association so no backfill or
migration is needed.

##### 15. Bundle Q — Polish  ·  **Shipped** (PR #992 → `6d39e089`)

The cheapest item on the milestone — and the one that turned out to have a second defect inside it.

| Issue | Description | Notes |
| --- | --- | --- |
| **#936** | ~~Serve a real favicon and link-preview metadata~~ — **FIXED** | **Filed during Bundle F.** Both causes confirmed in the checkout: no icon `<link>` in any layout, so the browser fell back to `/favicon.ico`, which did not exist; and `public/icon.svg` was the stock Rails placeholder, 122 bytes containing one red circle. **The crop was the part worth getting right.** `sparc_logo.png` is a LOCKUP — a circular medallion above a "SPARC" wordmark, separated by a transparent band measured from the alpha channel at y759–793. Rendered and inspected at real sizes before choosing: at 16px the whole lockup turns the wordmark into an illegible smear, while the medallion alone still reads and at 32px the bolt is unmistakable. So icons are cut from the medallion and the full lockup is reserved for the 1200×630 preview. There is **no vector source anywhere in the repo**, so `icon.svg` embeds the raster rather than pretending to be drawn; a hand-made approximation would be a new mark, not the logo. `og:url`/`og:image` are absolute — every consumer fetches them from another host — which is safe behind the proxy only because `config.assume_ssl = true`. Branding comes from the existing `SparcConfig.app_name`, so **no new environment variables**. |
| **#991** | ~~Nine views set a page title the layout never yields~~ — **FIXED, found while investigating #936** | `content_for :title` was called in nine templates and no layout ever yielded it, so every browser tab read "SPARC" regardless of page. `content_for` writes to a buffer, and a buffer nobody reads is indistinguishable from one that does not exist — no error, no warning, no failing spec. **The same silent shape as #982's unregistered audit actions.** Also a rebranding leak: `SparcConfig.app_name` already existed and the LOGIN layout used it correctly while the application layout hardcoded the literal. Yielded as-is rather than suffixed, because two of the nine templates already append "— SPARC" and the layout would have produced "API Documentation — SPARC — SPARC". **Proven green and mutation-checked BEFORE the issue was filed** — the correction from Bundle T. |

##### 15a. hdf-cli 3.5.1 — pulled forward, on its own  ·  **Shipped** (PR #996 → `e0473814`)

**Not a routine version bump, and not scheduled work** — Heimdall and the CI runners cut over to
hdf-cli **3.5.1** on 2026-08-19, so SPARC had to meet it the same day. Sequenced on its own branch
at owner direction rather than folded into Bundle Q, because it changes the translation engine, a
pinned external binary and NIST-facing OSCAL output, none of which belong in a PR about favicons.

**It surfaced by accident and by good test design.** Two specs failed during Bundle Q's suite run on
a machine where a `go install` build of 3.5.1 in `~/go/bin` shadowed the pinned 3.4.1 (`~/go/bin` at
PATH position 6, `/usr/local/bin` at 19 — `hdf_runner_spec`'s own failure message predicts exactly
that shadowing). One was the version allowlist. The other was
`oscal_e2e_pipeline_spec.rb`, which asserted the SAR conversion was REFUSED for being
schema-invalid and carried this instruction:

> "This example pins the CURRENT upstream state. When #184 lands, the conversion starts succeeding
> and this fails — deliberately, so the improvement is noticed rather than sitting unclaimed. At
> that point swap it for the positive assertion below it."

It did exactly that, and this is that swap.

**The headline: `hdf → oscal-sar` is safe for the first time.** Under 3.5.1 the output SATISFIES the
OSCAL v1.1.2 Assessment Results schema — upstream **mitre/hdf-libs#184 is fixed**. That conversion
was unsafe on *every previously shipping version* ([[project_hdf_cli_version_matrix]] measured 3.2.0
through 3.4.1), so the long-standing "do not trust hdf→oscal-sar" conclusion is now version-specific
rather than universal, and the assertion pins the opposite guarantee: the translation succeeds and
what comes back is schema-valid in both JSON and YAML.

**Every other behaviour was re-verified rather than assumed**, because the surrounding code carries
comments asserting version-specific behaviour that would silently rot:

| behaviour | 3.5.1 |
| --- | --- |
| `hdf → oscal-sar` schema validity | **CHANGED** — now valid |
| `validate --type results` still demands top-level `baselines` while the converter does not | unchanged — the upstream disagreement persists |
| no direct `hdf → oscal-poam` (the 501 path, mitre/hdf-libs#104) | unchanged |
| `--from oscal-poam` refuses an item whose risks carry no deadline, with the exact string the 422 branch matches on | unchanged |

One documentation error was corrected while confirming the last row: `poam_risk.rb` described the
command as `hdf convert --from oscal-poam --to hdf-amendments`, a direction hdf-cli does not offer —
`oscal-poam` converts only to `hdf`, and POA&M flows the other way, from an amendments doc. The code
was always right (`from: OSCAL_POAM` with no `to:`); only the comment named a dead end.

**The bump is four pins, not one.** `HdfRunner::PINNED_VERSION`, `bin/install-hdf.sh`, and — easy to
miss — `ARG HDF_LIBS_VERSION` in **both** `Dockerfile` and `Dockerfile_debian`, which bake the
binary independently of the install script. Changing only the script would have left the container
running 3.4.1 while the app pinned 3.5.1, so translations would have been refused inside the image.
No checksum to update: `install-hdf.sh` fetches `checksums.txt` from the release itself.

**CI cannot verify any of this** — it does not install hdf-cli (open issue **#835**), so these specs
skip there and CI stayed green throughout while local runs failed. The same class as #984: a check
that passes because it never ran. Verification for this change is therefore local and explicit.

##### 16. Bundle U — Profile fidelity: what the baseline says, and what SPARC shows  ·  **In progress**

Branch `bug/997_999_998_994_profile_oscal_fidelity`, cut 2026-08-19 from `e0473814`. Chosen by the
owner as the bundle after T and Q.

**Four issues, one defect at four layers: SPARC holds the right answer and does not hand it over.**
#994 accepts a tailoring decision and reports nothing happened; #997 never shows what was changed;
#999 exports it in a shape a conformant consumer cannot read; #998 offers a component type that
cannot carry its own claim. This is the same silent-success class as #982 (69 audit actions that
recorded nothing), #991 (page titles that rendered nowhere) and #902 (flash keys that displayed
nowhere) — and it is the worked example behind **#995**, the release gate.

**Three findings from the checkout that correct the issues as written.** Recorded here because each
changes what the work is, not merely how it is done:

1. **The flattening #999 describes is already losing data today.** `ProfileJsonParserService`
   handles nested `control["controls"]` on import, so an imported NIST resolved catalog gives the
   profile all 370 controls. But **six** consumers of `resolved_catalog_json` read only
   `group["controls"]` — `SspFromProfileService`, `SarFromProfileService`, `CdefFromProfileService`,
   `CdefBaselineGapService`, `CdefBulkApplyService`, and `BaselineParameterService` (one level
   only). Generate an SSP from an imported HIGH resolved catalog and you get **188 controls, not
   370** — every enhancement silently dropped. To be proven by spec before it is fixed.
2. **Control-level `links` cannot survive resolution because they never survive import.**
   `CatalogImportService` reads the guidance part's links for `related_controls` and discards
   control-level `links` entirely; the catalog's own back-matter resources are stashed inert in
   `metadata_extra["back_matter_resources"]`. So #999's second half is a **catalog-import** defect
   wearing an exporter's clothes.
3. **A CDEF cannot express #998's component pair at all.**
   `OscalComponentDefinitionExportService` emits `"components" => [ build_component ]` — exactly
   ONE component, built from the `cdef_documents.component_type` / `component_title` /
   `component_description` columns. A validation pair needs two components joined by
   `rel="validation"`. `ssp_components` is a real table with `props_data` / `links_data` and many
   rows per document, and the SSP exporter already emits both. That asymmetry is what the scope
   decision turns on.

**Owner decisions — taken 2026-08-19, before any code.** All three were put as questions because
each changes the size of the work, and two of them touch shared infrastructure:

1. **#999 — the download IS a conformant OSCAL resolved catalog.** Enhancements nest inside their
   parent, and a **shared reader walks nested-or-flat** so the six consumers above see every
   control regardless of which shape the column holds. Explicitly approved as a shared-
   infrastructure change; it is also the fix for finding 1.
2. **#999 — links are preserved at import.** Control-level `links` are stored at catalog import
   AND the catalog's back-matter resources are promoted to real `BackMatterResource` rows, so an
   emitted `href` resolves to a resource the document actually carries. Costs a
   `SeedRunner::CURRENT_VERSIONS` bump, a re-import of the seeded catalogs, and a backfill for
   existing installs. The cheaper alternative — emit only the `related` links SPARC already holds —
   was offered and declined, because it leaves NIST's reference links absent while looking complete.
3. **#998 — SSP first, CDEF documented as partial.** First-class `validation-type` /
   `validation-reference` / `validation-details` on `SspComponent` plus the `rel="validation"`
   pairing, round-tripping through export and import. CDEF component export gains `props` / `links`
   so it can at least carry its own claim, and `validation` is documented as **partial** on CDEF
   with the single-component reason stated. Giving CDEF a real multi-component model was offered
   and declined as its own bundle: it is a document-model change well beyond #998.

**A fourth finding, from building it: SSP components had NO Api::V1 surface at all.** They
could be created, edited and deleted only through the enrichment screen, which makes the web UI
the only way to perform those mutations — the one thing the API-first guardrail exists to
prevent. It was invisible to every endpoint sweep, because **an endpoint that was never written
cannot appear in a list of endpoints that answer wrongly**; it surfaced only from the other
direction, while adding #998's validation fields and finding there was no way to set them except
by hand in a browser. Closed in this bundle with five endpoints nested under the SSP
(`/api/v1/ssp_documents/:slug/components`), boundary-scoped on `ssp.read`/`ssp.write`, plus
request specs and a `tests/api` contract module. **This is the shape #995 should hunt for** —
the epic is scoped to "do the 223 endpoints do what they claim", and this was a mutation with no
endpoint at all. The surface is now 229 route entries.

**Two holds — OWNER-DECIDED 2026-08-19, do not re-raise inside this bundle:**

1. **The UBI9 prod-image gate is deferred for this cycle.** `tests/api` and the full Playwright
   suite were **NOT** run against a built container, and no screenshots were captured. The guides
   updated here therefore describe three screens — the Baseline detail panel, the SSP read-only
   panel, the enrichment Validation block — that have **no current images in `wiki/images/`**.
   That debt is real and is carried, not discharged: say so on the PR rather than letting a green
   rspec read as a verified feature.
2. **`wiki/API-Reference.md` is knowingly stale and left alone.** It still documents hdf-cli 3.4.1
   and the `sar_from_hdf` 502, which PR #996 made false. It is held for the **#995** API overhaul,
   which is expected to find more of the same on that page — fixing one line now would just
   invite a second pass.

**Scope notes.** #997's parameter editing lands **inline on the existing Profile screen**, so
there is no navigation change — but it is a new clickable control, so it takes a Playwright
interaction test with a CSP assertion. One shared control-detail partial renders statement,
resolved parameters, priority, guidance and related controls, used by the Profile screen (editable,
gated on `profiles.write`) and the SSP screen (read-only), rather than growing a third copy of
`control_families/show.html.erb`. Substitution goes through `OscalParameterResolver` (#942) — raw
`{{ insert: param }}` must never reach the screen.

| Issue | Description | Notes |
| --- | --- | --- |
| **#994** | `PUT /api/v1/profile_documents/:id/parameters` returns 200 with `0/0` and no errors for payloads it never parsed | **Bundle U, and the smallest of the four.** `params.permit` silently discards any shape it does not recognise, so a root-wrapped body, an object map instead of an array, or a missing `Content-Type` all arrive as empty arrays; both loops iterate zero times, `validation_errors` stays empty, and the controller's `errors.any? ? :unprocessable_entity : :ok` therefore returns **200**. A caller cannot distinguish "nothing matched" from "I never parsed your request", and that difference is the entire question when tailoring a baseline an ATO rests on. Two more on the same endpoint: `selection_id` instead of `select_id` is swallowed and the error then names `null` rather than the id, and a non-array `selected` is **coerced and persisted** rather than refused. Export keeps emitting `select_id` — it is published and #697's import reads files already in the wild — so the alias is input-only. |
| **#997** | A profile's controls, parameters and guidance are invisible; parameter edits cannot be seen | **Bundle U, and the largest.** There is no web UI for baseline parameters at all — the only way to observe a tailoring decision is to call the API back. More broadly, nothing on the Profile or SSP screens says what is legitimately part of the profile: the Profile screen lists identifiers grouped by family with priority counts and stops. Mostly assembly rather than new capability — the rendering exists in `control_families/show.html.erb` (#881), the data is on `catalog_controls`, the substitution is `OscalParameterResolver` (#942), the values come from `BaselineParameterService#extract_schema`, and the write path is the endpoint #994 repairs. **The resolver is what makes it worth doing properly:** showing raw `{{ insert: param, ac-20_odp.01 }}` would be worse than showing nothing. |
| **#999** | The resolved-catalog download is not shaped like a conformant resolver's output | **Bundle U.** Measured against NIST's own published resolved profile catalog: same root keys, same 18 groups, same param keys — but **182 nested enhancements vs 0** (SPARC emits every control as a top-level sibling, so a consumer cannot tell an enhancement from a base control except by parsing the identifier) and **188/188 controls carrying `links` vs 0/287**. Findings 1 and 2 above are what the work actually is. Assert through the validated path, not `export_unvalidated` (#989), and pin SPARC's output against the **structure** of NIST's published catalog so drift is caught rather than discovered. |
| **API gap** | SSP components had no `Api::V1` surface at all — found while building #998 | **Bundle U, not on the milestone.** Five endpoints under `/api/v1/ssp_documents/:slug/components`, carrying the validation pair so a pipeline can record "FIPS 140-2, certificate #4282, validating this component". Two deliberate refusals: `this-system` cannot be deleted (OSCAL requires it and the enrichment screen already protects it), and a validation claim on a non-validation component, or a pairing into another SSP, answers 422. The three audit actions are **registered** in `AuditEvent::ACTIONS` — an unregistered action records nowhere, which is #982's shape. |
| **#998** | `validation` is an allowed component type but nothing can express what it validates | **Bundle U.** OSCAL models third-party product validation as a **component pair** — the product, and a `validation` component carrying `validation-type` / `validation-reference` props and a `validation-details` link — joined by `rel="validation"`. SPARC has the enum value and none of the rest: the props appear nowhere in `app/`, and per finding 3 a CDEF cannot carry a second component at all. An enum value with no supporting fields reads as support without being it, which is worse than not offering the type — "this module is FIPS 140-2 validated, certificate #4282" is exactly the assertion an assessor checks. |

##### 18. Bundle V — The release gate, and the last unslotted screen  ·  **Next**

Slotted by the owner on 2026-08-19, which makes V the next bundle and moves R behind it. That is
the right way round: **#995 is a release gate**, its findings generate work, and discovering them
after the largest bundle in the milestone would be discovering them too late.

**#995 needs its framing corrected before it starts, and its baseline is stale.** Measured
2026-08-19 while closing Bundle U:

1. **The title counts endpoints that exist.** "Validate all 223 `/api/v1` endpoints actually do
   what they claim" cannot find a mutation with **no endpoint at all** — and that is exactly what
   Bundle U hit: SSP components were create/edit/delete-able only through the enrichment screen,
   invisible to any route-list sweep, found only by coming at it from the model. **Add a second
   axis: walk the WEB controllers and ask, for every mutation a user can perform, whether an
   `Api::V1` endpoint exists at all.** There is no reason to think components were the only one.
2. **The coverage columns measure presence, not teeth.** `docs/api/INVENTORY.md` reports
   167/168 documented and 167/168 pytest-covered, which reads as done. But **four `tests/api`
   modules never read a response body at all** — `test_admin_credentials.py`,
   `test_artifacts.py`, `test_authoritative_sources.py`, `test_sessions.py` — and
   `test_admin_credentials.py` performs **4 writes and 0 reads**, so nothing it does is ever read
   back. A test that exists is not evidence, for the same reason a 200 is not.
3. **The suite is weighted 4:1 toward happy paths** — 167 `2xx` assertions against 39 `4xx`.
   #994 was a *wrong status on a request that was never parsed*; every defect in Bundle U was a
   wrong answer carrying a right status. A suite shaped like this cannot find that class, which is
   the class the epic exists for.
4. **The inventory's own summary is 26 endpoints stale.** It states "142 logical endpoints
   (as of 2026-07-18)" while its table carries **168 rows** (229 route entries after Bundle U).
   The 99% / 93% coverage figures are therefore computed against the wrong denominator. **Fix the
   baseline first** — a screening pass measured against a stale inventory reports progress it has
   not made.

**#951** is the last UX item on the milestone and is unrelated to #995; it rides along because it
is small and because leaving one issue in no bundle is the scheduling gap this section exists to
close.

| Issue | Description | Notes |
| --- | --- | --- |
| **#995** | Epic: validate all `/api/v1` endpoints actually do what they claim — a 200 is not evidence | **Bundle V, release gate for v1.16.0.** Four corrections above, all measured. Order: fix the inventory baseline, then the missing-endpoint axis, then strengthen negative coverage, then the per-endpoint semantic sweep. The four body-blind modules are the cheapest first win. **Expect this to generate issues rather than close cleanly** — decide explicitly whether the gate is "the sweep ran and its findings are triaged" or "every finding is fixed", because those are different release dates. |
| **#951** | Sidebar independent scroll, re-organization, and a responsive breakpoint audit | **Bundle V.** Owner-added 2026-08-15, unslotted until now. **Re-organization is a NAVIGATION change and needs explicit approval** — nav follows the NIST layers and links must be findable in the same place every time; visibility may differ, placement may not. Any new or moved control also takes a Playwright interaction check with a CSP assertion. |

##### 19. Bundle R — Auth entitlements — IdP as system of record

Last by owner direction. **This moves #820 (openssl 3.3.0 → 4.0.2) to the end of the release**, since it is paired with #822 so one two-ceremony TLS verification round covers both. `bundle-audit` reports no vulnerabilities against the current lock, so the deferral is schedulable rather than reactive — **if that changes, decouple #820 from #822 and take it on its own.**

**#820 gained a prerequisite on 2026-08-17 (owner-decided): rebuild the dev Ruby against OpenSSL 3 FIRST, as part of the same work item.** Local Ruby links the EOL OpenSSL 1.1.1 branch while the prod image runs 3.5.5, and the openssl 4.x gem requires 3.x — so on an unmodified dev box the bump produces a **segmentation fault inside bundler itself**, leaving no working `bundle` to diagnose it with. Measurements and recovery steps are on PR #820. Recommended shape: install the OpenSSL-3-linked Ruby **alongside** rather than replacing, prove it with a full suite run, then switch — the rvm Ruby is shared with other work on the machine (InSpec profiles among it), so an in-place relink has a blast radius beyond this repo. Expect some specs to legitimately go red on OpenSSL 3 (legacy provider, stricter security level, PKCS#12 defaults); those are real differences prod already has and dev cannot currently see. Within the bundle: #860 answers the design questions, #842 needs a written answer for which of the two role systems a claim binds to, and #822 carries the PIV ceremony.

| Issue | Description | Notes |
| --- | --- | --- |
| **#860** | Epic: IdP as system of record for entitlements | Bundle I with #842. Five design questions answered in a memo commit before code. Dry-run built first, not last. |
| **#842** | Map OIDC claims to organization, boundary and role | Bundle I. A **missing** claim is an error, never "revoke everything" — that failure mode is what the blast-radius guard exists for. |
| **#822** | IdP-mediated PIV via OIDC `acr`/`amr` | Bundle G. Both auth paths stay configurable; two-ceremony verification required. |

<!-- markdownlint-enable MD013 -->

---

#### Shipped

<!-- markdownlint-disable MD013 -->

##### 1. Bundle A — Config correctness  ·  PR #924

| Issue | Description | Notes |
| --- | --- | --- |
| **#914** | ~~`SPARC_RESOURCES` replaced the shipped list wholesale~~ — **MERGED (PR #924)** | Bundle A. Extends by default; `SPARC_RESOURCES_REPLACE=true` opts back in. De-dupes on `href`, logs malformed JSON instead of swallowing it. **Behaviour change on upgrade — must lead the release notes:** deployments setting `SPARC_RESOURCES` get the 9 shipped links back unless they opt out. |
| **#909** | ~~Single `SPARC_BANNER` accepting inline HTML or a `file:` path~~ — **MERGED (PR #924)** | Bundle A. `file:` prefix is explicit and never rendered literally, so a typo'd path cannot become the AC-8 notice. `SPARC_BANNER_HTML`/`SPARC_BANNER_MESSAGE` deprecated but **honoured** (they carry the notice text). Cleared four doc surfaces stale since #867, incl. AC-8/PL-4/PS-6/PT-4 citing the retired flag. **All three legacy names scheduled for removal in v1.18.0** — release notes must say so and why. |

##### 2. Bundle B — Content security  ·  PR #925

| Issue | Description | Notes |
| --- | --- | --- |
| **#894** | ~~Regression test pinning `disposition: "attachment"`~~ — **MERGED (PR #925)** | Bundle B. All 48 `send_data` sites were already correct; the fragile seam was the keyword default in `artifact_resolvable.rb` that no caller passes. Specs assert the **emitted signed URL**, not the default; flipping it turns 5 of 9 red. Adds an inline-disposition source scan (help_controller allowlisted by name) and pins the host-only session cookie (#515). |
| **#897** | ~~Audit stored-value render sites for XSS~~ — **MERGED (PR #925)** | Bundle B. `BackMatterResource#href` had no scheme validation where `FederationPeer` does; `href: "javascript:alert(1)"` was a **valid record** on both surfaces, reaching **4** anchor render sites (not 6 — two of the originally-surveyed sites are different shapes and still need judging). Validates the **scheme, not the shape**: mirroring `FederationPeer`'s absolute-URL rule would have rejected ~97% of real OSCAL hrefs (25,485 fragment refs + 38 relative paths vs 872 http(s)) and broken catalog import. Adds `safe_external_url` at the render sites and an `html_safe`-on-literals guard. |

##### 3. Bundle C — Authorization sweep  ·  PR #931

| Issue | Description | Notes |
| --- | --- | --- |
| **#919** | ~~Sweep every controller for missing authorization, make the gap fail a test~~ — **MERGED (PR #931)** | Bundle C. Triage found **14** unguarded controllers (not 12 — the structural spec caught a 14th in `Api::V1::BaselineParameters` that the web-only survey missed) and a **37%-anomalous** permission vocabulary: 11 keys enforced but granted to no role, so back-matter authoring and approval were silently admin-only. Ships three structural specs, one of which was vacuous on first writing and only caught by mutation-checking the spec itself. Also fixed the v1.15.5 roster guard, which was unscoped and would have refused the very delegates it was meant to admit. |
| **#707** | ~~Reconcile membership role enums vs canonical Role catalog~~ — **MERGED (PR #931)** — NOT closed as a docs decision. The roster granted NOTHING (measured: 1 membership row, 0 user_roles), and #919's guards would have turned that into a lockout, so membership now provisions a boundary-scoped UserRole | Shipped inside #919 rather than as the docs-only decision originally planned. Measured before the fix: a member added as `isso` had 1 membership row, **0** user_role rows, and `has_permission?` returned false. Roster membership now provisions a **boundary-scoped** UserRole (`source: membership`), so AO/SO/ISSO stay per-boundary and a user can be R/W on one boundary and view-only on another. A `source` column keeps roster-derived grants from ever revoking an admin's manual assignment. |

##### 4. Bundle D — Collection browsing & lineage  ·  PR #933

| Issue | Description | Notes |
| --- | --- | --- |
| **#908** | ~~Filter controls on index screens~~ — **MERGED (PR #933)** | Bundle D. Ships `CollectionBrowseQuery`, a shared query object both the screen and its Api::V1 sibling narrow through, with facets declared per screen. Choices come from the loaded data (a hardcoded enum drifts as new OSCAL versions arrive) and a facet with one distinct value is hidden rather than offered. Replaced the hand-written evidence form, which re-emitted `q` and `view` but **dropped `per_page`** — filtering silently reset the page size. Framework filter **cut**: it is not a field anywhere, only prose in the title and the filename. Evidence "added by" also cut — `collected_by` is free text, not an FK. Both need a migration; raised, not filed. |
| **#928** | ~~An imported profile cannot be linked to a catalog — and is then permanently unpublishable~~ — **MERGED (PR #933)** | Bundle D. Narrower than filed but real: #911 already shipped a picker, inside the reconciliation banner, which renders only while the document BLOCKS updates. Measured against the running app, two states fall outside it — a profile referencing no controls (nothing to reconcile, so no banner) and a profile linked to the WRONG catalog (reconciled, banner gone). The picker moved to `shared/_baseline_picker`, rendered outside the blocked state too. Surfaced a genuine drift: repointing a **published** document's baseline was unguarded on BOTH surfaces, and `profile_params` has always permitted `control_catalog_id`. The rule now lives on `CatalogLineage`, narrow by design — blocks CHANGING a set baseline, never SETTING a missing one, or documents published before #911 become permanently unreconcilable. |

##### 5. Bundle K — Evidence provenance  ·  PR #937

| Issue | Description | Notes |
| --- | --- | --- |
| **#934** | ~~Auto-fetched evidence records no collector, and provenance has no link to the account~~ — **MERGED (PR #937)** | Bundle K — **SHIPPED**. Stamping consolidated into `Evidence#stamp_collection!(actor:, label:)`, the single writer all three creation paths call, so a fourth path cannot repeat the omission. New `collected_by_user_id` FK (nullify on delete) recorded alongside the unchanged `collected_by` snapshot; a deferred, idempotent backfill resolves the historical name to an account only where exactly one matches on email / display name / first+last, leaving ambiguous and unmatched rows null and **never** writing `collected_by`. "Added by" ships as an `EvidenceBrowseQuery` facet, so it reaches the screen and `GET /api/v1/evidences` from one definition. A `sparc_sa_…` token resolves to its own account, so pipeline submissions are attributed to the service account rather than its human owner — proven by request spec, not assumed. `au-10` was **absent from every CDEF** despite the mapping claiming it; added to `component-definition-audit.json` (49 → 50 controls). Original filing follows. Found auditing #908's "added by" filter. `AuthoritativeSourceFetchService#build_evidence` sets **neither** `collected_by` nor `collected_at`, while the only caller already passes `actor: current_user` — so the actor is known and discarded. Those rows show "Collected By: N/A" and, because `collected_at` is nil, **can never match the collected-between filter #908 just shipped**. Both controllers are symmetric and correct; this third path is the gap. Separately `collected_by` is a display-name string with no FK, so "added by" cannot be a facet. NOT a data-loss bug — users are deactivated, not deleted, so the recorded name stays true-as-of-collection and passes audit. |

##### 6. Bundle F — CDEF coverage from Terraform  ·  PR #938

| Issue | Description | Notes |
| --- | --- | --- |
| **#904** | ~~Terraform state/plan → CDEF coverage wizard~~ — **MERGED (PR #938, `56079c4a`)** | Bundle F — **SHIPPED** 2026-08-13. Classification model ported from `sparc-iac` `state_cdef_coverage.py`; the CLI plumbing stayed there. Two parsers (state vs plan) because the schemas differ in meaning: a plan's `change.actions` must count a REPLACEMENT (`["delete","create"]`) as present or every replaced resource vanishes. **The upload is never stored** — a `.tfstate` holds plaintext secrets, so files are parsed in-request and dropped; only the derived census plus filename + SHA-256 persists, asserted by spec (zero `ActiveStorage::Blob` rows) and mutation-checked. AWS Labs keys off `import_metadata["source_path"]`, NOT `cdef_components.service_id` — measured against the real corpus, one file declares many `type: service` components and `arnNamespace` agrees with the filename only 18/44 times. Custom CDEFs match on a declared prop or an explicit `CdefServiceAlias`, never on their name. Per the owner's issue comment, unmapped resources are reported as coverage gaps under an inferred namespaced key so a non-AWS boundary cannot read as fully covered. Wizard lives on the boundary screen; saving round-trips a signed token so the state is never needed twice. |

##### 7. Bundle E — In-product help  ·  PR #943

| Issue | Description | Notes |
| --- | --- | --- |
| **#880** | ~~In-page help drawer (Bootstrap offcanvas)~~ — **MERGED (PR #943, `7a491df3`)** | Bundle E — **SHIPPED** 2026-08-14. The navbar `?` opens the contextual guide in an offcanvas over the current screen; the anchor keeps its `href`/`target=_blank` deliberately, so a controller that never connects degrades to #870's new tab instead of a dead control. Content is a same-origin Turbo Frame (`/help/:slug?drawer=1`, layout-less), so **no CSP change** — no `frame-src`, no `connect-src`. The a11y baseline regeneration budgeted here **was not needed**: the panel is hidden on every page and axe skips hidden content, which is also why the open drawer is now audited explicitly under its own `help_drawer_open` key (recorded at **zero** violations, which it enforces). Three findings worth carrying: Bootstrap arms its focus trap when `!scroll \ |
| **#879** | ~~Extend `field_help` to remaining edit screens~~ — **MERGED (PR #943, `7a491df3`)** | Bundle E — **SHIPPED** 2026-08-14. Narrower than the ~90-100 fields originally scoped, deliberately: #879's own rule is that filler is worse than nothing, so this covers the screen groups where the copy could state a real consequence — evidence, admin users (new + edit), the POA&M and assessment-plan wizards, control catalogs — and **records a decision** for the rest rather than padding them. Two strings carry behaviour that is not guessable from the form: a blank Authorization Boundary makes the record visible to **every signed-in user** (`boundary_scoped_document.rb` treats nil as instance-wide), and instance roles vs the per-boundary roster is the #707 two-vocabulary split. Not covered, with reasons asserted in spec so adding help later fails loudly: organizations (contact details with example placeholders), the upload wizards (dropzones, not field forms), and — **held at owner request** — converters, plus SAP assessment type and catalog starting template, all pending the meaning of their option values. The spec enforces the issue's own copy rules and caught two of my own strings breaking them. |

##### 8. Bundle M — Reference authorization estate  ·  PR #960

| Issue | Description | Notes |
| --- | --- | --- |
| **#845** | ~~Reusable two-boundary leveraged reference authorization (golden E2E fixture)~~ — **MERGED (PR #960, `f656b0b9`)** | Bundle M — **SHIPPED** 2026-08-15, 16 commits. Two organizations in a real leveraging relationship, each with the full chain (Catalog → Profile → SSP → SAP → SAR → 3 POA&Ms → Evidence) plus live inheritance links; two tiers, one code path (`lean` = 40 curated controls, `full` = real NIST baselines). The **provider gets the HIGHER baseline** — MODERATE is a strict superset of LOW, and the reverse leaves 138 consumer controls with nothing to inherit from; a spec pins consumer ⊆ provider. Satisfaction is **derived from evidence**, not assigned: three simulated scanners own disjoint families, policy documents cover the management families and every `-1`, and a control with no covering evidence is never satisfied (an earlier `passed = technical − failed` quietly satisfied everything no scanner touched). 12 OSCAL artifacts committed under `db/fixtures/reference/lean/`, all schema-valid and **byte-identical on regeneration**, which required pinning `last-modified`, `SarResult#start_time`, SLA-derived deadlines, `sparc_resource_uuid`, the SSP `system_id` (it leaked the DB primary key) and five unordered queries. **The production ban was redesigned mid-PR at owner direction:** `Rails.env.production?` is the wrong discriminator — every container image runs in production mode, including the disposable target DAST is pointed at — so it is now `SPARC_ALLOW_REFERENCE_ESTATE=true` **plus an emptiness gate** that refuses if the instance holds any non-estate boundary/SSP/SAP/SAR/POA&M and names them. Measured on the UBI9 prod image: collection-view and index-filter skips **16 → 3** with the estate loaded (the 3 are `federation_peers`, a different subsystem). The original filing's "18 of 32 skips are data thinness" is **superseded by that measurement**. Exposed and fixed four product bugs — #954, #955, #956, #958, rows below. **DAST split out to #953, now unblocked by the production posture.** |
| **#954** | ~~A SAR generated from an SSP produces an empty POA&M~~ — **MERGED (PR #960)** | Bundle M. Found building #845. `SarFromSspService` created findings but no `SarRisk`, and `PoamGeneratorService` derives items from risks — so every generated POA&M was empty while an *imported* one was complete. First of three instances of the same shape: **building an authorization inside SPARC was hollow where importing one was complete.** Risks are now created per not-satisfied finding, gated so satisfied controls never become risks. |
| **#955** | ~~An SSP generated from a profile has no control statements~~ — **MERGED (PR #960)** | Bundle M. `SspFromProfileService` created no `SspControlStatement` rows, so there was nowhere to write an implementation and nothing for a leveraging system to inherit. My first cause analysis was **wrong** — I claimed the catalog collapsed `(a)/(b)/(c)` parts; measurement showed 867/897 base controls DO carry `guidance_data["statement"]` and paren rows are siblings on enhancements only. Corrected in the issue rather than quietly re-scoped. |
| **#956** | ~~A customer responsibility is auto-marked addressed~~ — **MERGED (PR #960)** | Bundle M. The filing understated it: `responsibility_gaps` was inverted in **both** directions. "Addressed" meant *an active inheritance link exists*, but `populate_from_leveraged!` creates that link for every responsibility — so doing **nothing** cleared the gap — and editing the statement flips the link to `overridden`, dropping it from `.active`, so doing the **right thing** re-opened it. A customer who correctly implemented a responsibility was told they had not. Also stopped copying the provider's "you must do this" text in as the customer's own implementation, which asserted the opposite of an implementation and was visible on screen. |
| **#958** | ~~An SSP with provided/responsibility statements cannot be exported~~ — **MERGED (PR #960)** | Bundle M. Third instance of the #954/#955 shape. Also made exports **reproducible** — `set-parameters` misuse replaced with `by-component.export.provided` / `.responsibilities`, plus the ordering and identifier pinning the drift gate depends on. |

##### 9. Bundle N — Document model — reachable references  ·  PR #964

**SHIPPED 2026-08-17**, PR #964 squash-merged as `fcb5bb67`, 20 commits, all seven issues
auto-closed. Final gates: `rspec` **5217 / 0 failures / 24 pending**, `tests/api` **464 / 0**
and `tests/ui-smoke` **442 passed / 28 skipped / 0 failed** against the UBI9 production image
over TLS, rubocop / brakeman / zeitwerk clean, 25+ mutations RED.

Five open issues here were **one failure wearing different clothes**: *a record that cannot reach the thing it is based on.* #928 (profile → catalog) already shipped in Bundle D and #911 established the lineage rule, so this is the fourth and fifth time the same problem is being solved. **Design the linkage rule once here and apply it in Bundle O** rather than a sixth time. #957 joins the bundle because it is the same layer, and because Bundle M gave it a free regression target — the 12 committed artifacts under `db/fixtures/reference/lean/` regenerate byte-identically, so any UUID instability now shows up as drift in a tracked file.

**What the bundle actually found.** The "design the linkage rule once" framing needed
correcting: `CatalogLineage` already exists and six models declare `lineage_via`, but its own
header says it *"reports. It does not block, rewrite, or **infer**."* The missing half was the
**resolver**, not the reporting — `OscalMetadata.resolve_import_href` matched only the
`uuid:<…>` spelling SPARC itself writes, so every other producer's href silently resolved to
nil. That is the piece Bundle O inherits for #929.

Two defects were found from inside the bundle and fixed in it, both on owner direction:
**#963** (a colliding statement UUID discarded an entire OSCAL import, because a rescued
`RecordNotUnique` without a SAVEPOINT poisons the Postgres transaction), and a lossy
export/import round trip that only a *screen* would reveal — the narrative survived in the
database while the edit form, which renders the field, showed every control blank.

**#944 was found CLOSED with no implementing PR** — closed one second after the docs-only
PR #961 merged, with no closing keyword anywhere — and was reopened after verifying against
the code that none of it existed.

**The demo estate was rebuilt mid-PR at owner direction, and that is where most of the bundle's
value came from.** A Rev 4 system cannot inherit from a Rev 5 one, and matching control *ids*
is not the same as matching control *language*, so both boundaries are now Rev 5 — ACME Cloud
Platform on MODERATE (288 controls, 95.8% compliant) and ACME HR Portal on LOW (150 controls,
96.6%) — generated from **real NIST baselines** vendored at
`db/seeds/oscal/nist_rev5_{low,moderate}_baseline_profile.json`. The previous "Demo LOW
Baseline" was a `limit(10)` slice being called a baseline. Compliance is **derived**, not
asserted: Implemented → passes, Deferred → fails → risk → POA&M, through the #845 mechanism.

Rebuilding it exposed seven defects, all fixed in the PR, none of which a green suite had
caught: `update_all(guidance_data:)` **replaced** the JSONB column at two seed call sites and
deleted the statement text of 187 Rev 5 controls (both now merge); `build_statements` returned
table statements **or** field-synthesized ones and never both, so an export kept the catalog's
words and dropped the organization's narrative; the OSCAL status token had no inverse, so a
screen showed **0.0% compliant beside 21 implemented controls**; `creation_method` defaulted to
`'excel'` **at the column**, so every path that forgot to set it claimed a spreadsheet import;
SARs named no SSP; `assessment_depth` was `%w[…].sample`; and #963 above.

| Issue | Description | Notes |
| --- | --- | --- |
| **#941** | ~~Catalog statement sub-parts sort after the last control instead of under their parent~~ — **MERGED (PR #964)** | **Filed during Bundle F.** `ac-2.7.(a)` sorts after `AC-25`, because `default_scope order(COALESCE(sort_id, control_id))` mixes a padded `sort_id` ("ac-02.07") with an unpadded `control_id` ("ac-2.7.(a)") — OSCAL parts carry no `sort-id` at all. 31 of 60 `ac-2%` rows have a NULL `sort_id`.  **SHIPPED in Bundle N.** The stated cause was wrong: `sort-id` IS imported, for all 1196 controls. NIST emits none on `part` elements — but SPARC MINTS the sub-part rows itself (`"ac-2.7"` + `".(a)"`) and then called `upsert_catalog_control` with no `sort_id:`. Fixed in all three import paths by deriving from the parent, plus a deferred backfill. Real scale was **1882 of 4054 rows**, not 31 of 60. |
| **#942** | ~~Selection choices that reference other ODPs export as opaque text~~ — **MERGED (PR #964)** | **Filed during Bundle F.** A `select` whose choices are `{{ insert: param, <id> }}` references (AC-20 odp.01 → odp.02/odp.03) is exported as flat text, so the dependency is lost and the choices render as raw markup. Lives in `BaselineParameterService#extract_schema`.  **SHIPPED in Bundle N.** Larger than stated. Owner set the construction rule: resolution is RECURSIVE (AC-20 nests two levels), a `select` resolves to its SELECTED branches assembled, and a value ODP falls back to `guidelines[].prose`. Also fixed: the resolved profile was not resolved at all (statement prose copied verbatim), export split a chosen branch into two garbage `set-parameters` values on `", "`, and the importer wrote a select's CHOICES into the field read as its chosen VALUE. |
| **#944** | ~~A component definition cannot be authored from scratch, and cannot be edited at all~~ — **MERGED (PR #964)** | **Bundle N.** Found in local review of Bundle E. `CdefDocumentsController` has `new`/`create` but **no `edit` and no `update`**: `create` is `handle_multi_file_upload`, so the only way a CDEF enters SPARC is as a file someone else authored, and afterwards the only mutators are the three inline fragment paths (`update_field`, `update_metadata`, `update_statement`). There are **no routes and no views for authoring components at all**. So every field NIST's simple-component-definition tutorial calls required — component `type`/`title`/`description`, `control-implementations[].source`/`.description`, `implemented-requirements[].control-id` — has nowhere to be entered. `create_from_profile` gives a control basis but never describes the component. Same create/edit inversion as #928 and #929, on the document type where authoring matters most. Must not weaken `refuse_if_aws_labs!` or `ensure_editable!`.  **SHIPPED in Bundle N — and was found CLOSED with no implementing PR, then reopened.** The OSCAL fields had nowhere to be entered because the exporter HARDCODED them (`"type" => "software"` for every component ever exported). Five nullable columns, authoring + edit on the web, the same fields on `Api::V1`, exporter falls back to the previous values so unedited documents export byte-identically. `refuse_if_aws_labs!` and `ensure_editable!` untouched and mutation-proven. |
| **#945** | ~~Mapping entries are typed as free text instead of picked from the source and target catalogs~~ — **MERGED (PR #964)** | **Was never in this plan** — on the milestone since before Bundle F and missed by every previous currency pass. Same family as #928/#929/#944/#946: a record that cannot reach the thing it refers to.  **SHIPPED in Bundle N.** Validated on the MODEL so `Api::V1` is guarded by the same rule. Two further gaps closed: `Api::V1::ControlMappingEntries` did not exist at all (the web form was the only way to mutate an entry), and neither surface had `update`, so an entry could be created and deleted but never corrected. |
| **#946** | ~~The assessment baseline is not derived from the selected SSP — and the SSP does not record what it is based on~~ — **MERGED (PR #964)** | **Found in local review of PR #943.** The sync is not broken: `sap_documents/new` already builds an `ssp → profile` map for `ssp_profile_sync_controller`, and `SapDocument` already inherits `profile_document_id: ->(b) { b.ssp_document&.profile_document_id }`. It has **nothing to derive from** — measured on a demo-seeded instance, both SSPs have `profile_document_id` nil, `import_profile_href` nil and no boundary profile, so the map serialises to `{}`. The demo seed creates SSPs and a "Demo LOW Baseline" and never links them, so a fresh instance shows the bug immediately. **Owner-DECIDED: derive and lock**, with an explicit override, which means fixing the upstream gap — link `profile_document_id` at import when the OSCAL `import-profile` href resolves, keep the href when it does not, idempotent `IS NULL`-predicated backfill, and fix the seed (bump `SeedRunner::CURRENT_VERSIONS`). Also populate on **render**, not only on `change`: a form returning with a preselected SSP leaves Baseline blank today even when the SSP has one. Fourth instance of the #928/#929/#944 family — a document that cannot reach the baseline it is based on.  **SHIPPED in Bundle N.** Three upstream causes, not one: the demo SSPs claimed a `demo_acme_*.xlsx` that does not exist in the repo (now imported from committed schema-valid OSCAL under `db/seeds/oscal/`), the profile was seeded AFTER the documents meant to reference it (now first, with a pinned UUID), and the resolver understood one href spelling. The seed was also not idempotent — `SafeDestroyable` refuses to delete an SSP an Assessment Plan points at. |
| **#957** | ~~Generated documents mint random UUIDs, so regenerating produces a different document~~ — **MERGED (PR #964)** | **Filed during Bundle M, open.** The general form of a problem #845 solved fixture-locally by pinning identifiers. OSCAL's own rule is explicit — a UUID "should be assigned per-subject … consistently used to identify the same subject across revisions" — and an export must never mint one. **The committed reference artifacts are now a ready-made regression target:** any UUID instability shows up as drift in a committed file, so this is cheaper to fix now than when it was filed.  **SHIPPED in Bundle N.** `batch_insert_records` takes a caller-supplied `uuid_for`; the four generators derive, the six importers deliberately do not. `SarFromSspService` was additionally taking the `gen_random_uuid()` column default. Existing rows not rewritten. The #845 artifacts still regenerate byte-identically against a clean database. |
| **#963** | ~~Re-importing an SSP that already exists rolls back the entire import, and the error is unrelated to the cause~~ — **MERGED (PR #964)** | **Filed from inside Bundle N and fixed in it, on owner direction.** A single colliding statement UUID discarded the whole OSCAL import: the `RecordNotUnique` was rescued, but a rescue with no SAVEPOINT leaves the Postgres transaction poisoned, so every subsequent statement in the same import failed with an error naming neither the colliding record nor the real cause. |

<!-- markdownlint-enable MD013 -->

**Deliverables:** Config that extends instead of silently replacing; a build that fails when a
mutating controller ships unguarded; filterable collections; in-product guidance; CDEF coverage
from real infrastructure; and entitlements sourced from the IdP without the power to de-provision
a customer.

---

---

#### Dependency lane (open Dependabot PRs)

Judged by **running `bundle-audit`, not by reading diffs** — it reports **no vulnerabilities**
against the current lock (advisory DB `6bda08e`, 2026-08-11). **None of these closes a CVE**, which
is what makes them schedulable around the feature work rather than reactive to it.

| PR | Bump | Slot | Why there |
|---|---|---|---|
| **#923** | `actions-updates` — `github/codeql-action` (init/analyze/upload-sarif), `dorny/paths-filter` | **BEFORE #919** | The one that impacts the sweep. #919's premise is that CodeQL/Brakeman/Semgrep **cannot** detect missing authorization, and it touches 16 controllers while adding a structural spec. If the CodeQL engine changes mid-sweep, a new alert is ambiguous — engine or our change? Fix the scanner baseline first. CI-only; its own run is the gate. |
| **#922** | `minor-updates` — `aws-sdk-s3` 1.228.2→1.229.0, aws-sdk-core/rds/partitions, io-console, rbs, reline | **AFTER #925** | `aws-sdk-s3` sits directly under ActiveStorage presigned-URL generation, which is exactly what #894's new spec pins (`disposition=attachment` on the emitted URL). Good interaction — the pin catches a regression — but the pin must land first. **Specific check: re-run `spec/security/user_content_disposition_spec.rb`.** |
| **#921** | `erb` 6.0.6→6.0.7 (patch) | **AFTER #925**, batch with #922 | Low risk. `erb` is one of the default-gem shadows showing as a residual UBI9 High, so it may reduce scanner-audit noise at release time. |
| **#820** | `openssl` 3.3.0→**4.0.2** (major) | **WITH Bundle G (#822)** — and **gated on the dev-toolchain rebuild** (owner-decided 2026-08-17: same work item, toolchain first) | Blast radius is 8 files: `piv_auth_service`, `federation_bundle_signing_service`, `sparc_http`, `sparc_key_derivation`, `ldap_auth_service`, `authoritative_source_fetch_service`, `cdef_bulk_apply_service`, `hdf_package_service` — PIV cert parsing, federation HMAC, outbound TLS, LDAP. #822 already requires the **two-ceremony** TLS proof, so pairing them means one verification round covers both. Also needs the Gemfile constraint change `~> 3.3` → `~> 4.0`; `~> 3.3` forbids 4.x today. |

**Closed 2026-08-11:** ~~#886 `activestorage` 8.1.3→8.1.3.1~~ — already in the image on `main`.
Worth recording *why it lingered*, because the same shape will recur: `activestorage` is **not a
direct Gemfile entry** (transitive via `rails`), so when #889 cherry-picked the Rails 8.1.3.1 bump
+ `image_processing` removal, the branch diff became empty but Dependabot had **no manifest line to
reconcile against** and left the orphan open. Auto-close is reliable for direct dependencies, not
for a transitive security PR whose requirement is satisfied by a different gem's bump. **Check
transitive security PRs by hand after any framework bump.**

> **#820 is not stale, it is pending a decision.** `dependabot.yml` deliberately keeps majors as
> individual PRs ("higher review needed", no major group), so an unmerged major sitting alone is
> the config working as intended — not neglect.

**Owner decisions still owed:**

1. **#919 roster posture** — admin-only vs delegable to ISSM/ISSO/SO, and whether to delete or
   seed `authorization_boundaries.manage_members` (defined, documented in `wiki/RBAC.md`, granted
   to 0 of 29 roles, enforced by 0 code). Triage memo lands first; build waits on the ruling.
2. **#860 × 5 open questions** — claim name, grant string format, slug canonicalization, session-
   revocation timing, whether `bootstrap` mode earns its keep.
3. **14-day fallback** — a coherent hardening-only v1.16.0 (A+B+C = 6 issues) was available around
   2026-08-21. Not taken; recorded because the option recurs if the date starts to bind.

**Release-notes obligations accumulated so far** (the release PR must carry these):

- #914 extend-by-default is a **behaviour change on upgrade** — leads the notes.
- #909 legacy banner variables **scheduled for removal in v1.18.0**, with the reasoning.
- If **#820** lands, `openssl` moves **3.x → 4.x** (a major, with the Gemfile constraint widened).
  Call it out explicitly — it sits under PIV, federation signing, outbound TLS and LDAP.
- **#919/#707 — the backfill grants permissions to every existing boundary roster member the
  moment it runs.** The intended repair for a roster that granted nothing, but a live
  authorization change across every boundary at once, not gradual. This should lead the notes.
- **#919 — `PUT /api/v1/profile_documents/:id/parameters` now 403s** without `profiles.write`.
  Its spec previously asserted "allows write access (all authenticated)".
- **#919 — `federation_peers` changed twice over:** widened from admin-only to admin + policy
  team, and no longer specially gated when no authentication is configured (the old hand-rolled
  guard ignored `any_auth_enabled?`; the canonical one honours it).
- **#919 — `attestations` is deliberately stricter than its Api::V1 sibling** (boundary-scoped vs
  unscoped). Flagged for reconciliation rather than quietly loosening the web side.
- **#934 — the evidence backfill runs post-boot on upgrade** and attributes existing evidence to
  accounts where the recorded name is unambiguous, so previously unattributable evidence becomes
  filterable by account. It never guesses and never rewrites `collected_by`; unresolvable rows stay
  unattributed and appear under no account in the new filter.
- **#880 — the navbar `?` no longer opens a new tab.** It opens an in-page drawer over the current
  screen. This is a visible change to a control every user already knows, so it belongs in the
  notes even though nothing breaks: the guide still opens, and the full guide is one click away in
  a new tab from inside the drawer. The sidebar Help & Guides links and the Resources page are
  unchanged and still open a tab.
### Wiki mirror — DONE 2026-08-12 (was owed on Bundle D merge)

- **Wiki mirror PUBLISHED 2026-08-12** (`8501eca`), immediately after PR #933 merged, rather
  than waiting for the release. The published wiki was last pushed
  **2026-07-28** — three releases behind — because that push is a manual step
  nothing enforces, and every PR that edited `wiki/` looked correct while
  publishing nothing. `wiki/OSCAL-End-to-End.md` has **never** been published,
  and `docs/MAP.md` on main links to its wiki URL, which currently **404s**.
  20 of 21 pages carry unpublished changes. Verify by cloning the published
  wiki and reading it, not by re-reading the source.
- **OWED AGAIN on the Bundle E merge.** #880 changes what the navbar `?` does, and
  `wiki/User-Guides.md` + `wiki/User-Guide-Getting-Oriented.md` + the new
  `wiki/images/help-drawer.png` describe the new behaviour. Until
  `./wiki/PUSH_TO_WIKI.sh` runs from `main`, the published wiki tells readers the `?`
  opens a new tab, which will no longer be true of the shipped app. Editing `wiki/`
  publishes nothing — that is the whole trap this section exists to record.


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
| 12 | Complete | Active Backlog — Post-migration Test/CI Hardening + Federation Follow-ups | ~~#436~~, ~~#244~~, ~~#367~~, ~~#445~~, ~~#440~~, ~~#449~~, ~~#451~~, ~~#453~~ | **COMPLETE** (carried items #433, #341, #246, #422, #413, #447 moved to Phase 14) |
| 13 | Complete | v1.7.x Pre-Pen-Test Hardening + Patch Fixes | ~~#509~~, ~~#510~~, ~~#511~~, ~~#513~~, ~~#514~~, ~~#515~~, ~~#524~~, ~~#525~~, ~~#535~~, ~~#536~~, ~~#537~~, ~~#541~~, ~~#543~~, ~~#547~~, ~~#548~~, ~~#549~~, ~~#553~~ | **COMPLETE** — v1.7.0 / v1.7.1 / v1.7.2 shipped |
| 14 | Current | Pre-Public-Flip + API Test Validation + CDEF Mutations | #545, #433, #498, #499, #528, #531, #447, #341, #246, #413, #422, #616, #618 | In Progress |
| 15 | Complete | v1.15.4 / v1.15.5 patches — account-lifecycle and UX defects | ~~#868~~, ~~#869~~, ~~#870~~, ~~#867~~, ~~#878~~, ~~#877~~, ~~#875~~, ~~#881~~, ~~#887~~, ~~#888~~, ~~#902~~, ~~#903~~, ~~#911~~ | **COMPLETE** — v1.15.4 and v1.15.5 shipped. #879 (field-help copy) was not done here and is carried into Phase 16. #911 shipped in PR #916/#918; the boundary-roster authorization bug found during it became #919 |
| 16 | Current | v1.16.0 — config correctness, authorization sweep, UX filters, auth entitlements, OSCAL fidelity (milestone `v1.16.0`) | ~~#914~~, ~~#909~~, ~~#894~~, ~~#897~~, ~~#919~~, ~~#707~~, ~~#908~~, ~~#928~~, ~~#934~~, ~~#904~~, ~~#880~~, ~~#879~~, ~~#845~~, ~~#954~~, ~~#955~~, ~~#956~~, ~~#958~~, ~~#941~~, ~~#942~~, ~~#945~~, ~~#946~~, ~~#957~~, ~~#944~~, ~~#963~~, ~~#939~~, ~~#929~~, ~~#952~~, ~~#974~~, ~~#935~~, ~~#959~~, ~~#947~~, ~~#948~~, ~~#981~~, ~~#982~~, ~~#984~~, ~~#988~~, ~~#989~~, ~~#936~~, ~~#991~~, ~~#993~~, #994, #995, #997, #998, #999, #951, #860, #842, #822 | In Progress — **40 of 49 shipped** (PRs #924, #925, #931, #932, #933, #937, #938, #943, #960, #964, #969, #975, #976, #983, #986, #992, #996). Bundles **O** (#929 #952, PR #975), **S** (#974 #959 #935, PR #976), **P** (#947 #948, PR #983), **T** (#981 #982 #984 #988 #989, PR #986), **Q** (#936 #991, PR #992) and the **hdf-cli 3.5.1 pin** (#993, PR #996) have all shipped. **Bundle U** (#997 #999 #998 + #994) is in progress on `bug/997_999_998_994_profile_oscal_fidelity`. The count moved 16 → 24 → 25 → 32 → 36 → 37 → 39 → 40 → **49**: #939, #941, #942 and #936 were filed during Bundle F; #944, #946, #947 + #952 came out of local review of Bundle E; **#954, #955, #956, #958 were filed and fixed inside Bundle M**, where building a real authorization exposed that the generators produce hollow documents where the importers produce complete ones; **#963 was filed and fixed inside Bundle N**; the owner added #935, #951, #959 on 2026-08-15; **#981, #982 came from Bundle P's verification gate**; **#988, #989 from Bundle T**, **#991 from Bundle Q** and **#993 from the hdf pin**; and **#994, #995, #997, #998, #999 were filed on 2026-08-19 — every one of them found by USING the product rather than by the suite**, which is the argument #995 makes. **Count it, do not carry the last figure forward** — reconcile this row against `gh issue list --milestone v1.16.0 --state all`, which is how #945 and #948 were found after being missed by every prior pass. Order set by the owner: **#939 pulled forward** → **O** → **S** → **P** → **T** → **Q** → **hdf pin** → **U** (#997 #999 #998 #994, in PR #1000) → **V** (#995 #951) → **R** (#860 #842 #822 +#820). **#951 and #995 were slotted into Bundle V on 2026-08-19**, which makes V the next bundle and moves R behind it — the right order for a release gate whose findings generate work. Nothing on the milestone is now in no bundle. Target tag ~2026-09-21. Per-issue detail and bundle sequencing live in the Phase 16 section above; this row is the phase-level status |

<!-- markdownlint-enable MD013 -->

**Total issues tracked:** 88 (23 original + 65 ad-hoc/new — adds the v1.7.x hardening cluster #509–#553)
**Completed (Phases 1-13):** 92 issues including the full v1.7.x sprint (17 issues across hardening + patch releases). v1.7.2 shipped 2026-05-24 (image `risksentinel/sparc:1.7.2`).
**Remaining (Phase 14 active backlog):** 11 issues — P0: #545 (operator clicks pre-public-flip), #433 (in progress) / P1: #498, #499 (CDEF mutations chain) / P2: #528, #531, #447 (deferred) / P3: #341, #246, #413, #422 (gated)
**Phases 1-13 and 15 complete.** Phase 14 (pre-public-flip + API test validation + CDEF mutations)
and Phase 16 (v1.16.0) are both in progress — 14 is a carried backlog, 16 is the active milestone.

> **This document is stale between v1.9.1 and v1.15.3.** The release history from
> v1.9.2 onward was tracked on the GitHub Releases page and the wiki Changelog
> rather than here, so the version and issue counts below reflect v1.7.2 and have
> not been carried forward. Phase 15 is recorded above because it is in flight;
> backfilling the intervening releases is tracked separately. Treat
> [GitHub Releases](https://github.com/risk-sentinel/sparc/releases) as canonical
> for what shipped when.
**First public release: v1.0.0** (#271). **Current version: v1.7.2** (released 2026-05-24 — pagination fix + processing-banner trap + CI workflow validator fix). Org migration to `risk-sentinel/sparc` completed 2026-05-02 (#430). **Repo flipping to public** — gated on #545 completion + `risk-sentinel/sparc-iac#281`.
