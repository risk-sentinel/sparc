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

**Goal:** Close the v1.16.0 milestone (**86 issues — 83 closed, 3 open, re-measured 2026-08-23; Bundle X closes the last 3**, after Bundle R merged; 15 originally scoped, and the rest filed as the work found them — #939, #941, #942, #936 during Bundle F; #944, #946, #947, #952 in local review of Bundle E; #845 to make the test data real; #954–#958 inside Bundle M; #963 inside Bundle N; #935, #951, #959 added by the owner on 2026-08-15; #981, #982, #984 from the Bundle P verification gate; #988, #989 inside Bundle T; #991 inside Bundle Q; #993 by the hdf-cli 3.5.1 pin; #994, #995, #997, #998, #999 on 2026-08-19; #1001–#1003 from scanning the shipping image; **#1004 from the owner reading a live OSCAL export**; and **twenty more filed and fixed inside Bundle V's own sweep**). The count has moved **ten** times; **measure it rather than carrying the last figure forward** — reconcile against `gh issue list --milestone v1.16.0 --state all`, which is how #945 and #948 were found after being missed by every prior pass.

**Open (0) — the milestone is complete.** The last three, #1042 #950 #1039, are **Bundle X** and
close on its PR. #1039 was slotted into it by the owner on 2026-08-23. Bundle R shipped
2026-08-23 (PR #1045 → `a41764a7`), closing #860, #842, #822 and #1043.

**VERSION is 1.16.0** (`app/models/sparc_config.rb`), bumped on the Bundle X PR together with the
`wiki/Home.md` version rows and the `wiki/Changelog.md` entry — `spec/docs/wiki_currency_spec.rb`
asserts all four and fails if any one is left behind. **Editing `wiki/` publishes nothing:** the
wiki is mirrored by `wiki/PUSH_TO_WIKI.sh`, which is a manual step at release time.

**The release gate was Bundle V, and it is MET** (PR #1009 → `fda3413d`, merged 2026-08-22).
Every `/api/v1` endpoint was swept against its published contract — send a payload, parse the
response, and prove with an INDEPENDENT read that the endpoint did what `docs/api/endpoints/*.md`
says it does, not "it returned 200." All three gate axes are **0**: no endpoint without a
`tests/api` module (was 42), none documented nowhere (was 19), none missing from Postman (was 6),
and both `bin/api_inventory_check.rb` and `bin/api_postman_check.rb` exit 0 across 285 endpoints.
The matrix and the per-group tracker are in the **Bundle V** section below.

**The last five were all found by USING the product, none by the suite.** #994, #997, #998 and #999 came out of exercising `/api/v1` against a live instance and reading SPARC's output against NIST's published OSCAL references; #995 is the epic that generalises them. Every underlying defect was green at the time it was found — which is the argument #995 makes and the reason it is a release gate rather than a nice-to-have. **That has now held all the way through:** #1001 came from scanning the shipping image, #1002 and #1003 from running the UBI9 gate Bundle U had held, and #1004 from the owner reading a live OSCAL export. Bundle V then made the point at scale — **twenty issues found by exercising a live instance**, every one of them green in rspec at the moment it was found. Not one was found by the suite.

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
| 17 | U — Profile fidelity: what the baseline says, and what SPARC shows | #997 #999 #998 **#994** | **Shipped** (PR #1000 → `27aea200`) |
| 18 | **W — The CVEs the UBI9 migration hid, + Bundle U's carried debt** | **#1001** **#1002** **#1003** | **Shipped** (PR [#1005](https://github.com/risk-sentinel/sparc/pull/1005) → `ab2dbd1a`, 15 commits). Image CVEs 132 → 80, undispositioned HIGHs 19 → 0; rspec 5669/0/10, tests/api 473, ui-smoke 496 passed / 9 skipped / 0 failed. **#1002 and #1003 were filed and fixed inside it**, both surfaced by running the gate U had held |
| 19 | **V — SWEEP every API endpoint against its published contract** | **#995** #951 **#1004** + 20 filed and fixed inside it | **Shipped — RELEASE GATE MET** (PR [#1009](https://github.com/risk-sentinel/sparc/pull/1009) → `fda3413d`, **72 commits, 32 `Closes`**, merged 2026-08-22). All three gate axes 0 (pytest 42→0, docs 19→0, Postman 6→0); both gate scripts exit 0 on 285 endpoints. Final gates: rspec **6049/0/10**, tests/api **2668 with zero skips**, ui-smoke **497 passed / 18 skipped / 0 failed**, brakeman 0. Per-group tracker in the Bundle V section |
| 20 | R — Auth entitlements — IdP as system of record | **#860** **#842** **#822** **#1043** | **Shipped** (PR [#1045](https://github.com/risk-sentinel/sparc/pull/1045) → `a41764a7`, **25 commits**, merged 2026-08-23). Design memo settled both open questions before code; dry-run built first, not last. Grant parsing → resolution → sync → login wiring → unmatched queue (API, screen, daily digest) → preview endpoint, plus the absolute session cap and IdP-mediated PIV. Final gates: rspec **6187/0/10**, tests/api **2704 passed / 2 skipped**, ui-smoke **508 passed / 0 failed / 15 skipped**, both API gates 0 at **288 endpoints** |
| 21 | **X — UI consistency, authoritative-source CRUD, and the dependency lane** | **#1042** **#950** **#1039** | **THE LAST BUNDLE — in progress.** #1042 is what the #951 responsive sweep found — 62 pages × 5 breakpoints, and the functional categories came back EMPTY: **layout, not function**. #950 is buttons + the missing shared page-header, scoped by the owner 2026-08-23. **#1039 was slotted here** the same day (owner: *"mostly UI … a true gap in managing the required data. APIs are unknown and must ride the bundle X"*). Carries the **VERSION bump to 1.16.0** and the **dependency lane**, including a live `mail` advisory no Dependabot PR covers |

**#1039 is no longer unslotted — it rides Bundle X** (owner, 2026-08-23). The reasoning is that
the gap is a management gap rather than a modelling one: *"1039 is mostly UI as the fields should
all exist but have no way of being updated in the UI in CRUD and a true gap in managing the
required data. APIs are unknown and must ride the bundle X."* That is measurably right for three
of its four asks and **wrong for one** — see the Bundle X section, where the surface is measured.
Everything is now slotted. #935 and #959 went into **Bundle S** on
2026-08-17, #997 #998 #999 #994 into **Bundle U**, and **#995 and #951 into Bundle V on 2026-08-19
at owner direction**; **#1004 was slotted into Bundle V on 2026-08-21** rather than waiting, because
the back-matter work it needed was already open in that branch. **W was then moved from LAST to FIRST on 2026-08-20**, combined with Bundle
U's carried debt, to land the milestone — so the order is now **W → V → R**, not V → R → W. V
before R remains the right way round for a release gate: #995 must be satisfied before the tag, and
its findings generate work, so discovering them after the largest bundle in the milestone would be
discovering them too late. **Tracked separately, no milestone:** #953 (authenticated DAST — unblocked by Bundle
M's production posture), #966 (SonarCloud findings triage — owner directed that it be filed
and *not* worked; 281 open findings, 2 Blockers amounting to one defect), and **#968** (audit the
swallow-and-continue rescue patterns — raised out of #939, **due 2026-09-06**; 54 rescue sites,
11 log-and-continue in services/jobs, and 17 files combining a transaction with a rescue, which
is the candidate set for the #963 shape).

**Milestone re-measured 2026-08-23, with Bundle X in flight: 86 issues, 83 closed / 3 open**
(`gh issue list --milestone v1.16.0 --state all --limit 300` → 83 CLOSED, 3 OPEN). The 3 open:
**#1042 #950 #1039**, all Bundle X, all closed by its PR — which takes the milestone to **86/86**. #1043 was filed from Bundle R's own
verification work — the eleventh time the count has moved, and the reason it is measured. Bundle R closed #860, #842, #822 and #1043; Bundle S closed #935, #959 and #974; Bundle P closed #947 and #948;
Bundle T closed #981, #982, #984, #988 and #989; Bundle Q closed #936 and #991; the hdf pin closed
#993; Bundle U closed #994, #997, #998 and #999; Bundle W closed #1001, #1002 and #1003; and
**Bundle V closed 32 — #995, #951, #1004, #1036 and the twenty-odd its own sweep filed.**

**The jump from 53 to 85 is not drift.** Bundle V's sweep filed and fixed its findings inside the
same bundle, so the milestone grew by exactly what the sweep found. That is the epic working as
intended, not a scope leak — and it is why the count is measured, never carried forward.

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

##### 16. hdf-cli 3.5.1 — pulled forward, on its own  ·  **Shipped** (PR #996 → `e0473814`)

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

**The bump is five pins, not one.** `HdfRunner::PINNED_VERSION`, `script/dev/install-hdf.sh`
(moved from `bin/` in #1001), `ARG HDF_LIBS_VERSION` in **both** `Dockerfile` and
`Dockerfile_debian`, and the `HDF_LIBS_VERSION` in the `security_gate` job of
`.github/workflows/security.yml`. Changing only the script would have left the container running
3.4.1 while the app pinned 3.5.1, so translations would have been refused inside the image. No
checksum to update: `install-hdf.sh` fetches `checksums.txt` from the release itself.

**And that drift really happened.** #1001 found `security_gate` still pinned at 3.4.1 after
#993/#996 moved everything else to 3.5.1 — the gate validated amendments with a different binary
than the product shipped. `sonarqube-hdf.yml` still carries the same stale `HDF_CLI_VERSION:
v3.4.1`; it is a separate workflow and was left alone deliberately, pending its own approval.

**CI cannot verify any of this** — it does not install hdf-cli (open issue **#835**), so these specs
skip there and CI stayed green throughout while local runs failed. The same class as #984: a check
that passes because it never ran. Verification for this change is therefore local and explicit.

##### 17. Bundle U — Profile fidelity: what the baseline says, and what SPARC shows  ·  **Shipped** (PR #1000 → `27aea200`)

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

**OWED — the a11y sweep cannot see the new panel.** `tests/ui-smoke/test_accessibility.py`
audits `profile_show`, but axe **skips hidden content** and the entire
`shared/_baseline_control_detail` panel — including its parameter form — sits inside a collapsed
`<details>`. So the sweep audits that page and never looks at the new controls, reporting clean
either way. This is the same structural gap #880 hit, which is why `help_drawer_open` exists as its
own baseline key recorded at zero violations. **Bundle U's panel needs the equivalent** — an
expanded-state audit key — and it cannot be added here because a new baseline entry has to be
recorded from a real run, which the deferred UBI9 gate did not do. **Sonar caught two a11y defects
in this partial that axe would never have reported** (a label associated only by wrapping, and a
text input with no accessible name at all); both are fixed, but the gap that hid them is not.

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

##### 18. Bundle W — The remediation claims the UBI9 migration invalidated, + Bundle U's carried debt  ·  **Shipped** (PR #1005 → `ab2dbd1a`)

**MOVED TO THE FRONT and combined with Bundle U's carried debt, by owner direction 2026-08-20**
(superseding the same day's "placed at the END, after Bundle R"). The order ran
**W + U-debt -> V -> R -> X**, chosen to land the milestone; W and V have both shipped. The letter
is not alphabetical sequencing; the POSITION is what matters, and it changed.

**The two halves share one image build.** U's debt needs a built UBI9 prod image to run its gate
and capture screenshots; W needs one to prove the CVE fixes. The Dockerfile fixes therefore land
FIRST, and everything downstream runs against the image that will actually ship — one build, one
arch, one code state.

**STATUS: MERGED** — [PR #1005](https://github.com/risk-sentinel/sparc/pull/1005) → `ab2dbd1a`, 15 commits.
`Closes #1001 #1002 #1003`, all three now closed. The milestone count recorded here at the time
(53 issues, 44 closed) is superseded — see the re-measure at the top of this phase. **#1004 was a
follow-up NOT in this bundle**; it went into Bundle V and closed with it.

**What the bundle actually did, measured against the image it produces:**

| | before | after |
| --- | --- | --- |
| distinct CVEs in the image | 132 | **80** |
| grype matches | 177 | 103 |
| undispositioned HIGHs | 19 | **0** |
| curl-attributed findings | 16+ | **0** |
| register | 28 live / 69 retired | **16 live / 85 retired** |
| enumerable packages | 112 | 107 (rpm KEPT) |

**Gates, all against the final built image** — rspec **5669 / 0 failed / 10 pending** (every pending
one environment-gated and named), rubocop clean on changed files, `tests/api` **473 passed / 0
skipped**, `tests/ui-smoke` **496 passed / 9 skipped / 0 failed**, `test_authenticated_nav.py`
**71/71** with the screenshots in place, grype **103 matches / 80 distinct**, findings converter
**16 overrides, exit 0**. Eight mutations (four on `BaselineControlDetail`, four on the importer
specs) each go RED and restore green.

**#1001 — 20 of 89 findings marked `remediated` are still in the shipping image.** The claims were
true for the **Debian** image and were carried across the **Debian → UBI9 migration without
re-verification**; the same CVEs are present under the RHEL equivalent packages. Same class as the
v1.12.2 audit (#770), which found eleven of these — recurring because nothing re-checked a
remediation claim once it was made.

**Found by scanning, not by reading.** Implementing the owner's retire-with-proof ruling meant
cross-checking every `remediated` entry against `grype 0.114.0` on `sparc-ubi9-web:latest`
(RHEL 9.8, confirmed from `/etc/os-release`): 177 matches, 132 distinct ids. **69 confirmed absent
→ retired to `sparc-findings.retired.yml` with `verified_absent_on` + `verified_by`. 20 still
reported → not remediated.** Had `remediated` simply been exempted from the review cadence — the
other option on the table — all 20 would have been exempted permanently, across 92% of the file.

**`GO-2026-5026` is the sharp one.** The file records it against `golang.org/x/net 0.48.0`; the
image attributes it to **`stdlib go1.26.5`**, a different artifact entirely, so remediating x/net
never touched it. A fix exists (Go 1.26.6).

**The "two blocked by the #865 deviation policy" state is GONE — and the issue text describing it
is stale.** The severity re-grading that shipped inside PR #1000 (`GO-2026-5026` CRITICAL->HIGH,
`CVE-2026-41989` HIGH->MEDIUM, each re-graded to the artifact actually in the image) together with
the re-based `discovery_date` puts both inside their caps at a 14-day window. Measured 2026-08-20:
`ruby bin/sparc_findings_to_hdf_amendments.rb --input docs/compliance/sparc-findings.yml` writes 28
overrides and exits 0, with no policy errors. **No deviation was needed and none was written.**
Note the script has no `--validate` flag, which #1001's acceptance criteria assume — use
`--input`/`--output`.

**Owner decisions 2026-08-20 — DECIDED, do not re-ask:**

1. **`GO-2026-5026`: compile hdf-cli from source.** The artifact is not a base package — it is
   hdf-cli, the MITRE Go binary the image used to download. hdf 3.5.1 is the NEWEST published
   release and `go version -m` on the shipped binary confirms go1.26.5 against a go1.26.6 fix line,
   so no version bump reaches it. `risk-sentinel/container-build-sign` hit this on the same tool
   (#234, #246) and fixed it the same way; SPARC was the last consumer still on the tarball. The
   `hdf-builder` stage is a port of the one in its `containers/ci-runner/Dockerfile` and the two
   should be kept in step. Takes CVE-2026-56852 (HIGH, `golang.org/x/text` v0.27.0 -> v0.39.0) with it.
2. **`CVE-2026-41989`: refresh the public UBI digest.** Same mechanism and registry as the 9.7->9.8
   bump of 2026-08-04. A digest bump updates versions in place and removes nothing.
3. **Audit scope: the live entries plus the HIGH undispositioned orphans.** The MEDIUM and LOW
   orphans are a follow-up.
4. **CI stops downloading hdf too** — `security_gate` builds from source with the same pinned
   toolchain, and `install-hdf.sh` moves to `script/dev/` as a local-developer convenience.

**We are NOT on Iron Bank, and the file said otherwise by implication.** `Dockerfile`'s header
reads "Red Hat UBI9 (Iron Bank / DISA-aligned)", which describes the UBI9 LINEAGE — but the pin is
`registry.access.redhat.com`, Red Hat's PUBLIC registry. There is no `registry1.dso.mil` reference
and no Iron Bank pull credential in `sparc` or in `container-build-sign`. A comment now says so.
Moving to a genuine Iron Bank base would need credentials in CI and sparc-iac and belongs in
`container-build-sign`; it is explicitly out of scope here.

**What the rebuilt image measured (2026-08-20, grype 0.114.0 db v6.1.9 on `sparc-ubi9-web:latest`,
RHEL 9.8 confirmed from `/etc/os-release`):** distinct CVEs **132 -> 101**, matches 177 -> 145.
All four fixable findings in #1001's table cleared, plus five `sqlite-libs` CVEs the digest bump
took as a side effect and CVE-2026-56852 the toolchain change took. Undispositioned **HIGHs 19 -> 5**.

**Two of the eleven entries that vanished from the scan had NOT been fixed — the scanner renamed
them.** `CVE-2026-27820` (zlib) is now reported as `GHSA-g857-hhfv-j68w` and `CVE-2026-41316` (erb)
as `GHSA-q339-8rmv-2mhv`, each listing the old id as a related vulnerability. A retire-with-proof
pass keyed on "absent from the scan" would have marked both remediated — **the exact false
remediation claim this issue exists to stop, reproduced inside the fix for it.** Both were re-keyed
to the id the scanner reports, with `discovery_date` preserved because the exposure is continuous
and only the label moved; their severities were re-graded to the new ids as well (zlib
CRITICAL -> MEDIUM), because leaving a grading attached to an id that is no longer reported is the
same defect in miniature. **Check every "absent" entry against `relatedVulnerabilities` before
retiring it.**

**Also found, raised not acted on:** `/usr/bin/curl` IS in the runtime image, contradicting the
`Dockerfile` comment that says runtime "deliberately carries no curl". `rpm -q --whatrequires`
reports **nothing in the image requires `curl-minimal` or `libcurl-minimal`** — they are inherited
from ubi-minimal. Removing them would retire roughly sixteen findings including two HIGHs. That is
a deliberate image change and needs its own approval.

**Also stale, left alone deliberately:** `.github/workflows/sonarqube-hdf.yml` still pins
`HDF_CLI_VERSION: v3.4.1` for a reason (mitre/hdf-libs#184) that #993/#996 resolved. It is a
separate workflow and changing it needs its own approval; a comment now records the drift.

| Issue | Description | Notes |
| --- | --- | --- |
| **#1001** | 20 findings claim remediation the Debian→UBI9 migration invalidated | **Bundle W, in progress, moved to the front.** Register now **23 live / 78 retired**, validator green, **zero** live entries absent from the scan and **zero** undispositioned HIGHs. Acceptance box 2 is met by fixing rather than deviating; boxes 1, 3 and 4 by the audit above. The issue body still describes the superseded blocked-by-policy state and should be corrected on close. |
| **#1002** | Raw OSCAL `{{ insert: param }}` on the Profile screen, and NO implementation statements on the SSP screen | **Filed and fixed inside Bundle W**, at owner direction, after the held gate caught it. Four defects stacked: sub-parts rendered outside the shared partial (so raw on Profile, absent on SSP); sub-parts declaring parameters the parent's list does not carry; the SSP lookup unscoped, rendering Rev 4 sub-parts under Rev 5 controls; and unresolvable references printed as markup. `CatalogControl.sub_parts_by_parent` is now the one definition of the grouping rule — the Profile controller had the only copy, which is how the SSP screen came to have none. |
| **#1003** | `CatalogImportService` truncates statement prose to 200 chars | **Filed and fixed inside Bundle W**, at owner direction. `prose.truncate(200)` at three call sites, "for readability", with nothing forcing it — the column is an unbounded varchar. Three costs: every implementation statement on both screens was a fragment; **44 controls were severed mid `{{ insert: param, ...`**, leaving a reference nothing can resolve; and **`title` is emitted verbatim by `OscalCatalogExportService` and `OscalResolvedProfileCatalogService`, so the OSCAL export carried truncated control titles** — wrong OSCAL a consumer cannot detect. `SeedRunner` 3.0.0 → **3.1.0** re-imports both catalogs; the truncation is in stored rows and the source files are the only thing to re-read. |
| **curl removal** | `curl-minimal` / `libcurl-minimal` dropped from the runtime image | **Owner-directed 2026-08-20, on proof rather than assertion.** Every ELF linking libcurl was `/usr/bin/curl`, `microdnf`, `libdnf`, `librepo` — the CLI and the package manager. Ruby links it zero times, hdf-cli is static, no gem links it, and every outbound fetch (DISA CCI, AWS Labs CDEFs, federation, Security Hub) is `Net::HTTP`/`open-uri`. Removable only via `rpm -e --nodeps`, which takes the package manager with it — correct for an immutable runtime. **`rpm` is KEPT: scanners enumerate OS packages from its database, and removing it would make the image scan clean by making it unreadable — the same lie #1001 was filed about.** 112 → 107 packages, all enumerable. |
| **#1004** | An SSP's back-matter carries no resource or href for the CDEFs its components came from | **Filed 2026-08-20 from owner review of the live exports, NOT fixed here.** Measured on the seeded Moderate SSP: 3 components, 20 back-matter resources, **zero** referencing a CDEF; the only internal `#uuid` href points at a component, not a resource. `ssp_components` already carries `cdef_document_id`, so the provenance is stored and never emitted — the same gap #999 closed for catalogs, on the SSP side. **Scope owner-DECIDED 2026-08-20: ALL of the boundary's CDEFs**, referenced or not — back-matter is the evidence set, and an unreferenced resource is still a citation someone can follow. Also found while confirming it: the **profile exporter already does this correctly** (its `import` href uuid matches a back-matter resource carrying an rlink to the catalog file), while the **SSP's `import-profile` href resolves to nothing** — its 4 back-matter resources are all generic "SPARC Document Source". Same code path, same rule, and an in-repo reference implementation to copy. |
| **Bundle U debt** | The UBI9 gate and screenshots held on 2026-08-19 | Carried from PR #1000, cleared here. `tests/api` and `tests/ui-smoke` run against the built prod image, and the three screens documented without images get captured. **The held gate immediately earned its keep**: `test_translations.py::TestSarFromHdf::test_raw_body_returns_oscal_sar` is a deliberate tripwire for mitre/hdf-libs#184, and it fired — hdf-cli 3.5.1 emits schema-valid assessment-results, so the 502 assertion was swapped for the positive one. The rspec half was swapped when #996 shipped; **the Python half was not, because nothing ran it.** **DONE:** the three screenshots are captured (`tests/ui-smoke/capture_baseline_panels_997.py`, a new one-off runner — the panels are disclosures three `<details>` deep on the SSP screen and the flat `pages.py` inventory cannot reach them), the guides carry them plus the implementation-statements prose, and both suites are green against the final image. **The gate caught the guide edit too**: adding image references before capturing the files turned `/help/system-security-plans` red, because the in-app Help Center serves `wiki/images` at `/help/images/*` and one 404 is a console error. **Of the 6 failures and 5 errors the first full gate run produced: 5 errors were a harness omission** (`SPARC_SMOKE_PUBLIC_CATALOGS` must be 0 or 1 — the file refuses to guess or skip), **3 were flakes under sustained load** (pass isolated), **2 were test defects**, and **1 was the real product bug that became #1002**. Root-cause each against the running app before calling it either. |


<!-- markdownlint-enable MD013 -->

---

##### 19. Bundle V — Sweep every API endpoint against its published contract  ·  **SHIPPED — RELEASE GATE MET** (PR #1009 → `fda3413d`, 72 commits, merged 2026-08-22)

**This was the endpoint sweep, and the v1.16.0 release gate. The gate is MET — SWEPT + FIXED**
(owner-decided 2026-08-20): every endpoint verified, and every finding fixed inside this milestone.
Slotted by the owner on 2026-08-19, ahead of Bundle R, because #995's findings generate work and
finding them after the largest bundle in the milestone is finding them too late — which is exactly
how it went: **the sweep filed and fixed twenty issues of its own.**

**Outcome, as merged in PR #1009 → `fda3413d` (72 commits, 32 `Closes`):**

| Gate axis | Bundle open | Now |
|---|---|---|
| Endpoints with no `tests/api` module | 42 | **0** |
| Endpoints documented nowhere | 19 | **0** |
| Endpoints missing from Postman | 6 | **0** |

`bin/api_inventory_check.rb --check` and `bin/api_postman_check.rb --check` both
exit 0. rspec 6044 / 0 / 10 · tests/api 2668 passed, **zero skips** ·
ui-smoke 497 passed / 18 skipped / 0 failed · brakeman 0 warnings.

**Twenty issues were FOUND BY the sweep and fixed inside it** — #1017-#1026,
#1028, #1030-#1032, #1034-#1038, #1041 — on top of #1007, #1008 and #1010-#1016
which opened it. Two were the argument for the whole bundle in one endpoint:

- **#1037** — `hdf_amendments` returned 422 for EVERY boundary in its default
  mode. `HdfRunner` treats a String as a PATH, and the export service passed
  `JSON.generate(doc)`, so the document reached `hdf amend verify` as a
  filename. The unit spec asserted `with(kind_of(String))` — the defect written
  down as an expectation. Green suite, broken endpoint.
- **#1038** — a CDEF's scope could not be read back through the API at all, so
  check 3 of the matrix ("an INDEPENDENT read confirms the change persisted")
  was impossible to perform.

**What the bundle keeps teaching:** every one of these was invisible to a status
code. #1035 found five credential-redaction tests that would have passed with
redaction switched off; #1041 found `tests/api` silently emptying a screen
another suite asserts on; `fc45f216` found three smoke tests that had been
SKIPPING since a correctness fix in this very bundle changed an endpoint from
dropping unknown fields to refusing them. A green suite is not evidence, and a
count that hides skips is not a measurement.

---

#### What the sweep IS

For **every one of the 229 `/api/v1` route entries**: send a real payload, read the response,
parse it, and prove the endpoint **did what `docs/api/endpoints/*.md` publishes that it does** —
confirmed by an **independent read**, not by the write's own echo.

The standard is not "it returned 200." Every defect Bundle U found was **a wrong answer carrying a
right status**:

- **#994** — `PUT .../parameters` answered `200 {"status":"updated"}` with zero updates for a body
  it never parsed. **Reproduced live against the running instance on 2026-08-19**, twice, before
  the fix. Green test suite throughout.
- **#999** — the resolved-catalog download returned `200` with a document shaped wrongly:
  0 nested enhancements against NIST's 182, 0 of 287 controls carrying links against 188 of 188.
- **#982** (Bundle T) — 69 audit actions recorded nothing, in every environment.
- **The SSP components gap** — a whole CRUD surface with **no endpoint at all**, invisible to any
  route-list sweep.

A suite that asserts status codes cannot find any of those. That is the entire reason this bundle
exists.

#### The surface, measured 2026-08-19

**229 route entries / 168 logical endpoints** across 34 groups —
**80 GET, 74 POST, 27 DELETE, 25 PUT, 23 PATCH** (149 writes, 80 reads).

#### The per-endpoint check matrix — this is what makes it countable

**Every write endpoint (149) — 6 checks:**

| # | Check | Why |
|---|---|---|
| 1 | Returns the status its published doc claims | Documented status codes must be reachable |
| 2 | The response body carries the fields the doc names | A doc naming a field the endpoint never returns is a lie (`baseline-parameters.md` did exactly this) |
| 3 | **An INDEPENDENT read confirms the change persisted** | The write's own echo can be synthesised; #994 proves a write can report success and change nothing |
| 4 | A payload in the wrong shape is **refused with a named reason**, not silently discarded | `params.permit` drops what it does not recognise — the #994 mechanism, and it is in every controller |
| 5 | An unauthorized caller is refused, and **the record is unchanged afterwards** | Refusing the button is not refusing the write |
| 6 | DELETE additionally: gone from `show` **and** from its parent's index | A soft-delete that still lists is not deleted |

**Every read endpoint (80) — 5 checks:** documented envelope; content equals what was written;
filters and pagination narrow the set **truthfully** (a filter that returns everything is worse
than none); boundary/organization scoping shows only what the caller may see; unauthorized refused.

**Floor: 149 × 6 + 80 × 5 = 1,294 checks.** Today the `tests/api` estate holds **438 test
functions and 540 assertions, of which 103 compare a value to what was sent.** So against this
standard the estate is at roughly **103 of ~1,294 — about 8%** — while `docs/api/INVENTORY.md`
reports 99% documented and 167/168 pytest-covered. **Those columns count whether a module exists,
not whether it proves anything.**

#### A second axis — endpoints that do not exist

The sweep must also walk the **web controllers**, not the route list, and ask of every mutation a
user can perform: **is there an `Api::V1` endpoint at all?** SSP components had none — found only
because Bundle U needed to set a field and there was nowhere to set it from. A route-list sweep
cannot find this class, and there is no reason to think components were the only one.

#### Fix the baseline before measuring anything

`docs/api/INVENTORY.md`'s summary says **"142 logical endpoints (as of 2026-07-18)"** while its own
table carries **168 rows** — 26 stale. Its 99% / 93% percentages are computed against the wrong
denominator. A screening pass measured against that reports progress it has not made.

#### Named starting points — measured, not guessed

**Eight update tests assert a status code and never read the response body.** Each one would pass
if the endpoint discarded the payload entirely, which is precisely #994:

`test_authorization_boundaries.py::test_admin_updates_boundary` ·
`test_baseline_parameters.py::test_admin_updates_parameters` ·
`test_cdef_documents.py::test_admin_updates_via_patch` ·
`test_control_catalogs.py::test_admin_updates_catalog` ·
`test_poam_documents.py::test_admin_updates_via_patch` ·
`test_profile_documents.py::test_admin_updates_via_patch` ·
`test_sap_documents.py::test_admin_updates_via_patch` ·
`test_users.py::test_admin_updates_user`

**Four modules never read a response body at all:** `test_admin_credentials.py` (4 writes,
0 reads), `test_artifacts.py`, `test_authoritative_sources.py`, `test_sessions.py`.

**Hand-probed live 2026-08-19 (7 of 229 — 3%, not a sweep):** control_catalogs, authorization_
boundaries, poam_documents, profile_documents, sap_documents all genuinely persist a PATCH;
cdef_documents correctly refuses with 422 (#911 lineage gate, not a defect); baseline_parameters
reproduced #994. **No conclusion may be drawn from a 3% sample** — it is recorded so the next pass
does not repeat it.

#### Deliverables

1. **`assert_crud_round_trip` helper** in `tests/api/` — write → independent read → field equality
   → restore, so check 3 is one call and cannot be skipped by accident. An `assert_create_round_trip`
   already exists and is used by **10 of 30** modules; there is **no update equivalent at all**.
2. **Per-group progress table** (below) — the sweep is 34 groups; track it there so status is
   visible mid-flight rather than at the end.
3. **Negative-path coverage raised** from 39 `4xx` assertions against 167 `2xx`.
4. **Contract reconciliation** — each `docs/api/endpoints/*.md` checked against real responses.
   `baseline-parameters.md` documented four fields the endpoint has never returned; it was found by
   reading, and nothing else would have caught it.
5. **Findings filed as issues, not fixed inline** (per `issue_rules.md`).

#### Progress, measured 2026-08-20 — first pass on branch `feature/995_api_contract_sweep`

**Three of this section's own numbers were wrong, and the corrections matter more
than the progress.**

- **"229 route entries / 168 logical endpoints" — the second figure is 208.**
  Both denominators are real (229 counts PATCH and PUT separately; 208 collapses
  the aliases), but `docs/api/INVENTORY.md` published **142** and had done since
  2026-07-18, so every percentage it carried was computed against a denominator
  66 endpoints short. It read as 99% documented and 93% in Postman. Measured
  honestly: **165 of 208 listed in a doc page's own Endpoints table, 24 more
  mentioned only in prose, 19 documented nowhere.**
  The summary drifted because it was hand-written prose beside a generated
  table. It is generated now, between markers, along with the gaps list.
- **"Four modules never read a response body at all" is a measurement artefact**
  of grepping for `.json()`. `test_sessions.py` asserts a cookie, which is that
  endpoint's actual contract, and then uses it to fetch an authenticated page;
  `test_authoritative_sources.py` parses every body through
  `assert_error_envelope`; `test_admin_credentials.py` documents why it stops at
  the gate paths, and its published contract was checked against the controller
  and matches. **Only `test_artifacts.py` was a real gap** — it asserted 404 and
  401 and nothing else, so it would have passed against a resolver that 404'd
  for every artifact.
- **The Postman collection was worse than "63% covered".** It had **zero** saved
  response examples, 15 write requests with no body at all, and a Bulk Update
  Parameters body carrying the object map the API refuses — the published
  collection taught the payload that #994 answered `200 {"status":"updated"}` to.

**Landed on the branch:**

| | |
|---|---|
| `f82a1d67` | INVENTORY baseline generated, not asserted; the doc matcher now reads each page's own Endpoints table instead of grepping for an action name anywhere in a mapped file |
| `f383c57f` | `assert_update_round_trip` + `assert_unhandled_payload_is_not_reported_as_success`; `sparc-api doctor` fixed (it never passed `-k`, so it reported valid tokens as rejected against the local UBI9 target this document mandates) |
| `605e5dc3` | all 8 status-only update tests converted to real round trips, one committed RED |
| `b4d7f8c5` | **#1007** and **#1008** fixed |
| `8ea6821a` | unrecognised fields refused at all 25 permit sites |
| `0e1866b0` | Postman reconciled: 132 → **208 of 208**, 93 saved examples captured live |
| `34c06b03` | artifact resolver happy path; the "body-blind" count corrected |
| `487dac25` | plan updated for the first pass; three published figures corrected |
| `1ec6ee52`-`348ca39a` | **the missing-endpoint axis** — API tokens (#1016), leveraged authorizations (#1015), RBAC roles (#1014), service accounts (#1013), organizations + membership (#1012), converters (#1011), POA&M sub-objects (#1010) |
| `fc01a2a2`-`a539af13` | **#1017** OSCAL validated on all three translation paths, **#1018** bulk delete refused a body it never parsed, **#1019** one list envelope |
| `ced2f8bc`, `9bc72a7c` | the whole-surface contract sweep, enumerating its own subjects |
| `5a906b6d`, `b590918e` | **#1020** OSCAL 1.2.2, **#1021** two missed permit sites |
| `b37156df`, `6412a9c0`, `e2055950` | the per-payload matrix as a reusable contract, extended to nested groups and exports |
| `71079f66`, `f9eb40ec` | **#1023** invalid enum returned 500 + HTML, **#1024** KSI writes ungated |
| `655d068d`-`3d54d709` | **#1025**, **#1026**, **#1028**, **#1030**, **#1031**, **#1032**, **#1034** |
| `30aa7684`, `ac209d3a` | password-reset assertion finished; **#1035** a shared `SECRET` made five redaction tests vacuous, + a standing AST guard |
| `612d2530`-`3d35a03c` | scanner findings, dispositions, scan runs, control lookups, guides, federation, admin credentials — swept live |
| `247f0493` | **#1037** the amendments export passed its JSON to hdf-cli as a FILENAME — 422 for every boundary |
| `be2f42be` | **#1038** a CDEF's scope could not be read back through the API at all |
| `0f3a73f9` | **#1029** STIG ingested end to end; one export endpoint with `format` + `validate` |
| `080fbb03` | **#1004** an exported SSP carries the trail back to its component definitions |
| `c0ca8904` | the last six Postman entries — **all three gate axes now 0** |
| `775577fc`, `8936d800`, `5a8cfc68` | **#951** the boundary CDEF/evidence filters made real, the sidebar rebuilt, the boundary name linked |
| `c98ebb86` | **#951** warning badge contrast 2.19:1 -> 9.58:1 |
| `5ccc4570` | the leveraged POA&M fixture ships with an item, so it can be exported |
| `707aae7b` | Sonar + CodeQL findings this branch introduced |
| `fc45f216` | three password-recovery smoke tests were silently skipping |

**Findings, all filed:**

- **#1007** — a tailored ODP wrote, persisted, and read back as the old value.
  `load_current_values` keyed a flat map by `param_id` across every control, so
  a control and its statement sub-part fought over one logical parameter and
  iteration order decided the winner. `parameters_updated` counted attempts
  rather than writes, so it could not report the discrepancy in principle.
- **#1008** — a **published** profile's parameters could be rewritten, on the API
  and the web path alike. The `Lifecycle` concern has documented "Published
  documents are read-only" since it was written; nothing enforced it.
- **The refusal policy** (owner-decided): every write endpoint accepted and
  silently discarded unknown fields. Two cases were security-relevant — evidence
  provenance and an attestation's `attester_name` were accepted-and-ignored, so
  a caller backdating evidence or attesting under another name received 201 and
  a record they could reasonably believe carried what they sent.

**Yield so far: two filed defects plus a policy-level defect, from roughly four
groups.** Extrapolating 34 groups from that is not yet warranted — the groups
touched first were chosen because they were named as weak — but nothing so far
argues the ~2026-09-21 target is comfortable.

#### Progress by group — 34 groups, complete as of 2026-08-22

Every group is now exercised against a RUNNING INSTANCE. The two marks record
HOW, because they are not the same standard and collapsing them into one tick
would claim more than was done:

| Mark | Meaning |
|---|---|
| **M** | Covered by the shared matrix contract (`tests/api/_crud_contract.py`) — the per-payload checks, applied identically |
| **E** | Covered by a purpose-written module, because the group does not fit the CRUD shape |

**20 groups M, 14 groups E, 0 uncovered.** The E groups are the ones the mixin
cannot describe: a scanner finding cannot be POSTed (it exists only as the
product of an HDF ingest), a disposition is a singleton sub-resource with no
index and no PATCH, translations are stateless conversions, and discovery is a
single document. Each carries the matrix's substance — an independent read of
every write, a named refusal, both authorization directions — written out
rather than inherited.

**What a mark does NOT mean.** It means the endpoints in that group are
exercised against a live instance with their effects read back. It does not
certify that all six checks ran on all 285 endpoints. The distinction is the
reason #995 exists, and a tracker that blurred it would be the same defect this
bundle spent its length removing. The gate's own coverage column measures
module PRESENCE, and that is stated in `docs/api/INVENTORY.md` too.

The route surface grew from 229 entries to **316** during the bundle, because
the missing-endpoint axis added the surfaces that had no API at all (#1010-#1016,
#1031). The table below is the original 229-entry census; the current figures
live in `docs/api/INVENTORY.md`, which is generated.



| Group | Entries | Writes | Reads | Swept |
| --- | --- | --- | --- | --- |
| `cdef_documents` | 17 | 15 | 2 | **M** |
| `back_matter_resources` | 16 | 12 | 4 | **M** |
| `authorization_boundaries` | 15 | 8 | 7 | **M** |
| `evidences` | 14 | 8 | 6 | **M** |
| `ssp_documents` | 12 | 9 | 3 | **M** |
| `control_mappings` | 11 | 8 | 3 | **M** |
| `sar_documents` | 11 | 8 | 3 | **M** |
| `profile_documents` | 10 | 7 | 3 | **M** |
| `control_catalogs` | 9 | 7 | 2 | **M** |
| `poam_documents` | 9 | 6 | 3 | **M** |
| `sap_documents` | 9 | 7 | 2 | **M** |
| `authorization_boundaries/ksi_validations` | 8 | 4 | 4 | **M** |
| `control_catalogs/control_families` | 8 | 5 | 3 | **M** |
| `authorization_boundaries/memberships` | 7 | 4 | 3 | **M** |
| `federation_peers` | 7 | 5 | 2 | **M** |
| `users` | 7 | 5 | 2 | **M** |
| `scanner_findings` | 6 | 4 | 2 | **E** |
| `ssp_documents/components` | 6 | 4 | 2 | **M** |
| `profile_documents/parameters` | 6 | 4 | 2 | **E** |
| `cdef_coverage` | 5 | 3 | 2 | **E** |
| `control_catalogs/controls` | 5 | 3 | 2 | **M** |
| `poam_risks` | 4 | 3 | 1 | **M** |
| `admin` | 4 | 2 | 2 | **E** |
| `artifacts` | 4 | 0 | 4 | **E** |
| `ksi_catalog` | 4 | 0 | 4 | **E** |
| `authoritative_sources` | 3 | 2 | 1 | **E** |
| `oscal` | 3 | 3 | 0 | **E** |
| `controls` | 2 | 0 | 2 | **E** |
| `guides` | 2 | 0 | 2 | **E** |
| `attestations` | 1 | 0 | 1 | **E** |
| `available` | 1 | 0 | 1 | **E** |
| `hdf` | 1 | 1 | 0 | **E** |
| `sessions` | 1 | 1 | 0 | **E** |
| `profile_documents/controls` | 1 | 1 | 0 | **M** |

#### What satisfies the gate — **OWNER-DECIDED 2026-08-20: SWEPT + FIXED**

**The gate is "every endpoint swept AND every finding fixed."** Not "the sweep ran and its
findings are triaged." **DECIDED — do not re-open.**

What that commits us to:

- All **229 route entries** verified against their published contracts under the matrix above.
- **Every defect the sweep surfaces is fixed inside v1.16.0**, not deferred to v1.17.0 and not
  closed as "documented as known."
- A finding is only closed when the fix is proven the same way the sweep proves an endpoint:
  an independent read showing the corrected behaviour, and a mutation check showing the new
  assertion goes RED against the old code.

**Schedule consequence, stated once and not re-litigated.** The number of findings is unknown by
construction — that is what a sweep is for. Bundle U swept **zero** endpoints and produced four
issues plus a whole missing CRUD surface; the same yield across 34 groups is not a small number.
**The ~2026-09-21 target should be treated as provisional until the first few groups report**, at
which point the yield per group is measurable and the date can be set from evidence rather than
hope. Re-measure after the first three groups and say plainly what the run rate implies.

**Findings are still filed as issues** (per `issue_rules.md` — bugs found by a test program become
issues, they are not fixed silently inline). The difference the ruling makes is that those issues
are **in scope for this milestone**, not triage fodder for the next one.

---

**#951** is the last UX item on the milestone and is unrelated to the sweep; it rides along because
it is small and because leaving one issue in no bundle is the scheduling gap this section exists to
close.

| Issue | Description | Notes |
| --- | --- | --- |
| **#995** | Epic: validate every `/api/v1` endpoint actually does what the published docs say — a 200 is not evidence | **DONE in PR #1009 (2026-08-22).** All three gate axes are 0 — no endpoint without a `tests/api` module (was 42), none documented nowhere (was 19), none missing from Postman (was 6) — and both gate scripts exit 0. Twenty issues were found by the sweep and fixed inside it. A mark in the per-group tracker means the group is exercised against a live instance with its effects read back; it does NOT certify all six matrix checks on all 285 endpoints, and the tracker says so. Original plan below, kept for the record. **Bundle V, RELEASE GATE.** The sweep, the matrix, the floor of ~1,294 checks and the per-group tracker are above. Sequence: fix the inventory baseline → build `assert_crud_round_trip` → the 8 status-only update tests and 4 body-blind modules (cheapest first wins) → the per-group sweep → the missing-endpoint axis over the web controllers → contract reconciliation against `docs/api/endpoints/*.md`. |
| **#951** | Sidebar independent scroll, re-organization, and a responsive breakpoint audit | **DONE in PR #1009 (2026-08-22)**, layout approved by the owner. Root cause of the scroll was `min-height` on `.sparc-sidebar`: the box grew with its content, so `overflow-y: auto` never engaged and the DOCUMENT scrolled. Boundary documents reordered to the NIST layers (CDEFs, SSP, SAP, Evidence, SAR, Amendments, POA&Ms); Profiles removed as a baseline SELECTION rather than a per-boundary artefact; boundaries paginate at 10; Resources nest by HOST; the boundary name links to the boundary; width 220px -> 288px; dropdown bounded (was 800px tall, 87px unreachable at 777px); warning-badge contrast 2.19:1 -> 9.58:1. **The boundary CDEF and evidence filters were INERT and are now real** — the CDEF leaf listed every CDEF in the instance. 10 Playwright checks, CSP-clean, three breakpoints. **Caveat: the responsive breakpoint AUDIT was not performed systematically** — the one known finding was fixed and three breakpoints are covered. **Bundle V.** Owner-added 2026-08-15. **Re-organization is a NAVIGATION change and needs explicit approval** — nav follows the NIST layers and links must be findable in the same place every time; visibility may differ, placement may not. Any new or moved control also takes a Playwright interaction check with a CSP assertion. |

##### 20. Bundle R — Auth entitlements — IdP as system of record  ·  **SHIPPED 2026-08-23**

**SHIPPED** as PR [#1045](https://github.com/risk-sentinel/sparc/pull/1045) → `a41764a7`, 25
commits, merged 2026-08-23. #860, #842, #822 and #1043 closed. Bundle X (#1042 #950 #1039) is
what remains, and it is now in its own PR — the last three close on merge.

**#820 (openssl 3.3.0 → 4.0.2) did NOT ride this bundle, and has moved to v1.16.1** (owner-decided
2026-08-23). It was paired with #822 so one two-ceremony TLS round would cover both; #822 shipped
without it because its own gateway-mTLS proof was deferred to AWS anyway, so the pairing bought
nothing. The standing condition on the deferral was *"`bundle-audit` reports no vulnerabilities
against the current lock, so this is schedulable rather than reactive — if that changes, decouple
#820 and take it on its own."* **That condition has now failed, but not on `openssl`** — the live
advisory is `mail` 2.9.0, which is unrelated to the openssl gem and is taken in Bundle X's
dependency lane. So #820's deferral still stands on its own terms.

**#820's prerequisite, decided 2026-08-17 and unchanged: rebuild the dev Ruby against OpenSSL 3 FIRST, as part of the same work item.** Local Ruby links the EOL OpenSSL 1.1.1 branch while the prod image runs 3.5.5, and the openssl 4.x gem requires 3.x — so on an unmodified dev box the bump produces a **segmentation fault inside bundler itself**, leaving no working `bundle` to diagnose it with. Measurements and recovery steps are on PR #820. Recommended shape: install the OpenSSL-3-linked Ruby **alongside** rather than replacing, prove it with a full suite run, then switch — the rvm Ruby is shared with other work on the machine (InSpec profiles among it), so an in-place relink has a blast radius beyond this repo. Expect some specs to legitimately go red on OpenSSL 3 (legacy provider, stricter security level, PKCS#12 defaults); those are real differences prod already has and dev cannot currently see. Within the bundle: #860 answers the design questions, #842 needs a written answer for which of the two role systems a claim binds to, and #822 carries the PIV ceremony.

**The absolute session cap rides this bundle as [#1043](https://github.com/risk-sentinel/sparc/issues/1043)**
(owner, 2026-08-22: *"The working day needs to have a default max of 8 hours
(user provisionable?) in this PR"*, then *"file/fix and close in the PR"*). It
was found while verifying the offboarding ruling, and it belongs here because it
is a precondition for the entitlement model rather than a neighbour of it.

**Why it belongs to Bundle R and not to a later one.** The ruling is that a login
establishes a user's rights and the session timeout bounds how long they last.
That is only true if there is a bounded time until the *next* login, and there
was not: `SPARC_SESSION_TIMEOUT_MINUTES` is an IDLE timeout whose clock resets on
every request, and the codebase had no absolute limit anywhere. An active user
was never asked to re-authenticate, so entitlements resolved at one sign-in
stayed in force indefinitely — including after the IdP revoked them, since SPARC
learns of IdP-side changes only at the next sign-in. Shipping the entitlement
sync without the cap would have shipped a model whose central claim was false.

**Shipped** (`415b2e29`): `SPARC_SESSION_MAX_HOURS`, default **8** — a working
day, so a user who signs in at the start of one signs in again the next.
Provisionable per instance; `0` disables it and restores the previous behaviour.
Enforced in the same `before_action` as the idle check, so both limits are
evaluated on every authenticated request. AC-12 and IA-11 in
`component-definition-authentication.json` and the Rev 5 mapping row updated to
describe both limits and why the idle one is insufficient alone.

**Two things this cost, worth remembering rather than rediscovering:**

1. **The first implementation expired a session carrying no start stamp.** That
   logs every signed-in user out the moment the release lands, and it is not
   confined to real upgrades — nothing outside `start_session` stamps a session,
   so the entire request-spec suite was bounced immediately. Changed to adopt
   and stamp on next sight, which gives the same guarantee one sign-in later
   without the flag day.

2. **An 8-hour example written the obvious way proves nothing.** The session
   COOKIE carries its own `expire_after`, fixed at boot to 60 minutes; travel
   further than that between requests and the integration session drops the
   cookie, so the next request arrives with a brand new empty session — and
   because `sign_in_as` stubs `signed_in?`, the app answers 200. The test passes
   whether or not the cap exists, because what it expires is a session the test
   already threw away. The spec proves the mechanism at 1 hour with every jump
   inside the cookie's life, and asserts the default of 8 as its own fact.

Mutation-checked both ways; the one that matters is refreshing `started_at` like
`last_active_at`, which silently degrades the cap into a second idle timeout that
can never fire for the active user it exists for. Two tests catch it.

**Still open, and deliberately not decided here:** whether the cap should be
provisionable **per user** rather than only per instance. That needs a schema
change and a UI, so it is a separate issue if the owner wants it.

**Instance roles ARE grantable from the IdP, opt-in — owner-decided 2026-08-22**
(*"I'd like to see if we can include the instance roles in the IdP if at all
possible... a nice to have which makes it easier to manage IdP"*, then *"the
remaining instance makes sense and good framework that belongs in v1.16.0"*).
Tracked under #860 rather than a separate issue: the epic already contemplated
`instance-level? -> SKIP unless allowlisted`, and this is that, built.

`sparc:instance:{role}`, gated by **`SPARC_OIDC_INSTANCE_ROLES`, empty by
default** — an allowlist per role, not a blanket switch, so opting in to
`global_viewer` does not confer `head_of_agency`. A grant arriving at an
instance that has not opted in is refused **with a reason and surfaced**, not
dropped: someone created that directory group deliberately.

**What makes it safe is that `users.admin` is a boolean column, not a `Role`.**
The resolver only ever produces `user_roles` and `organization_memberships`
targets, so no claim can confer or revoke the break-glass account. Recovery from
a misconfigured IdP is always available through it, which means the epic's
"the last instance admin is never removable by any automated path" holds by
construction rather than by a guard that could later be relaxed.

**The natural follow-on is [#1044](https://github.com/risk-sentinel/sparc/issues/1044),
filed to v1.16.1** at owner direction so it gets deliberate attention. An
instance role today opens **no admin screen**: all five `authorize_admin!`
definitions and **77 direct `current_user.admin?` checks** test the boolean, and
none consults role permissions, so roles and instance-admin are disjoint
systems. Making a time-boxed IdP administrator real means consolidating that
gate first — four of the five definitions are private copies **shadowing** the
shared concern, in `organizations`, `service_accounts`, `roles` and `api_tokens`.
The owner's framing is the reason it is worth doing: Okta can expire a group
membership on a timer, so elevation becomes temporary by construction rather
than permanent `sudo` — and **#1043's absolute session cap is what makes that
expiry bite**, since an active administrator is never idle.

### What Bundle R actually built

| Piece | What it is |
|---|---|
| `IdpGrant` | Parse and canonicalise a grant string. No database — parsing asks "is this well formed?", resolution asks "does what it names exist?" |
| `IdpGrantResolver` | Resolve against real records, and **never create**. Every failing spec asserts the ABSENCE of a record as well as the error |
| `EntitlementSync` | The diff, then `dry_run` or `apply`. One code path, so a preview cannot disagree with the run |
| `IdpClaimReader` | Decides ABSENT vs EMPTY once, on the raw payload, rather than inferring it later from an empty array that has lost the difference |
| OIDC callback wiring | The login IS the sync. A failure there cannot deny the session |
| `UnmatchedGrantQuery` | One reading of "what is SPARC refusing?", shared by the API, the screen and the digest so they cannot disagree |
| Admin screen + digest | Administration → IdP Grants, with Create/Reject; daily email, no-op without SMTP |
| Preview API | `GET/POST /api/v1/entitlement_sync` — ask what `authoritative` would do while running `bootstrap` |
| `DeactivateInactiveUsersJob` | Offboarding. A disabled IdP account cannot sign in, so absence of sign-in is the signal |
| Session cap (#1043) | `SPARC_SESSION_MAX_HOURS`, default 8 |

**The design memo (`docs/dev/860_idp_entitlements_design.md`) was corrected twice
by the code**, and both corrections are worth carrying forward:

1. **There are THREE role representations, not the two #707 describes.**
   `user_roles` has no `organization_id` — its only scope is
   `authorization_boundary_id`. A boundary grant resolves to `user_roles`, an org
   grant to `organization_memberships` (a string vocabulary where `org_admin` is
   a real permission gate), and **nothing ever resolves to
   `authorization_boundary_memberships`**, which is documentary SSP content an
   assessor reads. Worth fixing on #707 itself.
2. **"No migration" was wrong.** `organization_memberships` had no `source`
   column, so "only rows the sync created are ever revoked" would have held for
   boundary grants and been silently false for org grants. A safety property true
   in one half of a feature is not a safety property.

**Two guards that hold by construction rather than by a check**, which is the
property to preserve if this is ever refactored:

- **`users.admin` is unreachable from any grant.** It is a boolean column, not a
  `Role`, and the resolver only produces `user_roles` and
  `organization_memberships` targets. Recovery from a misconfigured IdP is
  therefore always possible, and the epic's last-instance-admin constraint needs
  no guard.
- **Revocation is scoped to `source: "idp"`.** A hand-made grant survives any
  claim, any misconfiguration, any empty group. The percentage ceiling is a
  second line, and the owner has since turned it off by default.

**A blast-radius design error the specs caught.** The percentage guard was
per-user, so a user holding a single IdP role who legitimately left that group
was a 100% revocation — the default 25% limit blocked every ordinary offboarding.
The owner then ruled the ceiling off entirely: *"Each time a user logs in, we
should process the grants and anything not in the grant would be removed."*
The estate-wide version belongs to a bulk re-sync path that does not exist yet,
and the code says so rather than implying this covers it.

| Issue | Description | Notes |
| --- | --- | --- |
| **#860** | Epic: IdP as system of record for entitlements | Bundle I with #842. Five design questions answered in a memo commit before code. Dry-run built first, not last. |
| **#842** | Map OIDC claims to organization, boundary and role | Bundle I. A **missing** claim is an error, never "revoke everything" — that failure mode is what the blast-radius guard exists for. |
| **#822** | ~~IdP-mediated PIV via OIDC `acr`/`amr`~~ — **BUILT** (owner directed it into this PR) | `SPARC_PIV_OIDC_ACR_VALUES` / `SPARC_PIV_OIDC_AMR_VALUES`, both **empty by default, and empty accepts NOTHING** — the one property that matters, because every deployment that has not opted in has an empty allowlist and a wildcard there would silently downgrade PIV enforcement to nothing. The gateway-mTLS path is untouched and both stay configurable. `acr` is compared **exactly**, so `aal/2` cannot satisfy a deployment asking for `aal/3`; `amr` is a list and any accepted member is enough, but `swk` is not `x509` — accepting a soft key would reintroduce the very gap the feature closes. The session still records `oidc` as the provider so the audit trail says HOW someone signed in, with a separate `piv_asserted_by_idp` event recording WHY it counted as PIV. **The two-ceremony verification against real PIV hardware is still owed** and is the owner's to run. Paired with **#820** (openssl 3.3.0 → 4.0.2), which keeps its own prerequisite: rebuild the dev Ruby against OpenSSL 3 FIRST. |
| **#1043** | ~~A session has no absolute lifetime, so an active user's entitlements never expire~~ — **FIXED** (`415b2e29`) | **Filed from Bundle R's own verification work**, not from the suite. `SPARC_SESSION_MAX_HOURS`, default 8. It is a precondition for #860's model rather than a neighbour of it: the ruling that a login establishes rights holds only if there is a bounded time until the next login, and an idle-only timeout gives none. Closed by this bundle's PR. |

##### 21. Bundle X — UI consistency, authoritative-source CRUD, the dependency lane  ·  **THE LAST BUNDLE — in its PR, VERSION bumped to 1.16.0**

Branch `feature/1042_bundle_x_ui_consistency`, cut from `main` at `a41764a7`.
**After this the v1.16.0 milestone closes and the release is cut**, so this
bundle also carries the **VERSION bump** and the **dependency lane**.

| Issue | What |
|---|---|
| **#1042** | The main navbar overflows the viewport from 992px to ~1400px, on every page |
| **#950** | One button role, one class — and light/dark parity |
| **#1039** | Authoritative sources need control references, provenance, dates and full CRUD |
| — | **Dependency lane** — one live advisory, plus currency. See the Dependency lane section below |
| — | **VERSION 1.15.5 → 1.16.0** |

**Deliberately kept OUT of PR #1009** (owner, 2026-08-22: *"address 950 in
milestone v1.16.0. Not this pr though"*). Both #1042 and #950 touch shared
navigation and shared button styling, and a layout change dropped into a review
in progress is how a reviewer loses their place. #1009 and #1045 have both
merged; Bundle X lands in its own PR.

###### Owner decisions, 2026-08-23 — taken before scoping, not during

1. **#1039 rides Bundle X**, not v1.16.1: *"1039 is mostly UI as the fields
   should all exist but have no way of being updated in the UI in CRUD and a
   true gap in managing the required data. APIs are unknown and must ride the
   bundle X."* That is right for three of its four asks and **wrong for one** —
   measured below.
2. **#820 (openssl 3.3.0 → 4.0.2) slips to v1.16.1.** The dev-Ruby-against-
   OpenSSL-3 rebuild is unchanged as its prerequisite, and it is a multi-hour
   cross-repo toolchain job that does not belong bolted onto a CSS bundle days
   before a tag.
3. **PR #1006 folds in whole** — all five action bumps across the four workflow
   files, `astral-sh/setup-uv` 9.0.0 → **10.0.1** major included. Workflow edits
   were approved explicitly for this bundle; the branch's own CI run is the gate.
4. **#950 is scoped to buttons plus a shared page-header component.** NOT the
   full 1,399-site inline-style sweep — see the CSP finding below, which removes
   the deadline that scope rested on.

###### Landing order — slices, because there is no visual-regression harness

The one real risk restated: **#950 touches shared CSS that every screen depends
on, and there is no visual-regression harness.** PR #943 is the proof — a
completely green suite alongside a visibly broken drawer header. A sweep across
47 view files has that failure mode 47 times over, so it lands in slices, each
verified on the screen before the next starts.

| # | Slice | Why here |
|---|---|---|
| 1 | **Dependency lane** — `mail` 2.9.1 first, then currency, then #1006, plus `bundle-audit` in the **local** pre-PR gate | A live advisory leads. Doing it first also means the whole bundle is built and tested on the gems that will ship, rather than re-running the gates after a late bump. **No `security.yml` edit for the gate** — that is [#1048](https://github.com/risk-sentinel/sparc/issues/1048) on `ci.v0.0.1` |
| 2 | **#1042 navbar** | Self-contained, one partial, and it is the bundle's only NAVIGATION change — get the approved layout settled while there is time to iterate |
| 3 | **#950a** — the seven role classes in CSS, no view changes yet | Defines the vocabulary before anything consumes it. Contrast-probed before a single view is edited |
| 4 | **#950b** — sweep the 47 view files onto the role classes | Mechanical once 3 is proven. Removes the ~14 button-adjacent inline styles as it goes |
| 5 | **#950c** — `shared/_page_header` and the screens that adopt it | The largest reuse target after buttons; **zero views reference a page-header class today** |
| 6 | **#1039** — API first, then the screens | [[feedback_api_first]]. The API gap is smaller than the issue records; the UI gap is larger |
| 7 | **VERSION + wiki + release-notes obligations** | Last, so the number lands on a finished bundle |

###### #1042 — found by the #951 audit, which is the point of audits

`tests/ui-smoke/responsive_audit_951.py` sweeps **62 pages × 5 breakpoints, 310
page loads**, looking for findings rather than confirming the one already known.
It is committed and re-runnable, and it is the artefact #951's "responsive
breakpoint audit recorded" acceptance criterion asks for.

**The functional categories are EMPTY**: `PAGE_ERROR` 0, `UNBOUNDED_OVERLAY` 0,
`UNSCROLLABLE_TABLE` 0. No page fails to load at any breakpoint, no unreachable
overlay, no unscrollable table. `UNBOUNDED_OVERLAY` is the functional class — it
is what the nav dropdown was, 800px tall in a 777px viewport with 87px
unreachable — and it is empty because #951 fixed it. **This is layout, not
function**, and the owner asked directly: at 992px the rightmost nav control
sits at 1215px, fully off-screen, **and clicking it still works**; at 375px the
hamburger opens and reveals its links. The pages are ugly at these widths, not
broken.

What remains is layout. Measured:

```
992px  viewport -> document 1215px   (223px overflow, 61 of 62 pages)
1280px viewport -> document 1328px   (48px  overflow, 61 of 62 pages)
```

**138 horizontal-overflow occurrences and 1,431 off-screen elements come down to
one cause** — the navbar neither wraps nor collapses between 992px and roughly
1400px. Fix the navbar and almost all of both counts go.

**The mechanism, measured in `app/views/shared/_main_nav.html.erb` (291 lines):**
the bar is `navbar-expand-lg`, so it expands to its full horizontal form at
**≥992px**; **five `li.nav-item.d-none.d-lg-block` items appear at exactly the
same breakpoint**; `sparc-theme.css:2256` brings the sidebar back
(`.sparc-sidebar { display: none }` below `991.98px`); and
`sparc-theme.css:662` grows `.sparc-navbar-logo` from 44px to **52px** at
`min-width: 992px`. So 992px is where the navbar stops collapsing, five extra
items appear, the logo grows, and the sidebar reclaims width — **four things at
one breakpoint**. That is the 223px.

Note line 245 already carries `d-none d-xl-inline` on the user display label —
someone had already found 992px too tight for one element and moved it alone.
This fix generalises that judgement rather than introducing a new one.

**OWNER-DECIDED 2026-08-23 — `navbar-expand-xl` + `d-none d-xl-block`.** Move
the whole transition to 1200px, where there is room.

The five are **About, Resources, OSCAL, Help (`?`)** and a separator — so four
real controls. Between 992px and 1200px they move into the hamburger, which
already works and already holds them at 375px. **Nothing is lost and nothing
moves**: visibility differs between 992 and 1200, placement does not, so this
stays inside [[feedback_no_navigation_changes_without_approval]] rather than
needing a new approved layout.

It also resolves the `.d-none.d-lg-block`-appears-at-992 /
sidebar-hides-below-992 conflict **by construction** rather than by picking a
side — the nav items move to `-xl` and the sidebar keeps `-lg`, so they no
longer collide.

Rejected, with reasons recorded so they are not re-proposed: **wrap
(`flex-wrap`)** keeps everything visible but makes the `sticky-top` header two
rows tall on every laptop-width page, spending vertical space on every screen to
solve a horizontal problem; **demoting items into the overflow menu** changes
the placement of controls users already know and would need an approved layout.

###### #950 — measured 2026-08-23, and larger than the issue records

| | #950 records | Measured on `main` |
|---|---|---|
| Distinct `btn-*` classes in views | 19 | **34** |
| View files carrying a `btn` class | 46 | **47** |
| Inline `style=` (buttons only) | 13 | ~14 |
| Inline `style=` (app-wide) | not counted | **1,399 across 112 files** |
| Views referencing a page-header class | not counted | **0** |
| `[data-bs-theme="dark"]` rules in the theme CSS | 5 of 9 filled variants | **51 rules**, and **all 6 outline variants still carry none** |

The 34: `btn-action` `btn-action-row` `btn-cancel-dark` `btn-clear-filter`
`btn-close` `btn-close-sm` `btn-danger` `btn-dark` `btn-edit` `btn-enrich`
`btn-enrich-sm` `btn-ghost` `btn-ghost-muted` `btn-group` `btn-header-edit`
`btn-lg` `btn-link` `btn-oscal` `btn-outline-*` (6) `btn-primary` `btn-save`
`btn-secondary` `btn-sm` `btn-sparc-orange` `btn-sparc-purple` `btn-success`
`btn-warning`.

**OWNER DESIGN RULES, given 2026-08-22 — these are the specification:**

1. **One colour scheme per FUNCTION**, light and dark.
2. **Symmetrical text and height** — equal-height rows by construction.
3. **a11y / WCAG compliant**, verified by `tests/ui-smoke/_contrast_probe.py`
   and axe, **not by eye**.
4. **Dark mode carries NO fill — outline and text only.** This is the rule that
   settles the half-done dark palette rather than patching variant by variant.
   `btn-cancel-dark` already exists as a one-off in exactly this shape.
5. **Buttons, headers and the rest go in CSS and are REUSABLE wherever
   possible** — a shared class or partial, never repeated markup, never inline
   `style=`. This is what makes rule 1 hold: a scheme defined per function only
   stays consistent if there is exactly one place it is defined.

**The owner asked "might be missing one?" — measured, and two were missing.**
The owner's list is **seven** (Create, Edit, Export, Import, View, Update,
wizard/guide); with Cancel/Back and Destructive the roster is **NINE**:

| Role | Evidence |
|---|---|
| Create | `New …`, `Add …` — makes a new record from an empty form |
| Edit | `btn-edit`, `btn-header-edit` |
| Export | `Export CSV`, `Export JSON`, `Export OSCAL`, `Download ATO Package` |
| Import | `Upload File`, `Upload and Process`, `Import STIG` |
| View | `View` (the only action `_item_actions` currently offers) |
| Update | `btn-save` |
| Wizard / guide | `Create from Wizard`, the ATO wizard — a multi-step guided flow, distinct from Create because it is a *process* entry point, not a form |
| **Cancel / Back** *(added)* | **the most common button in the app** — **79** `Cancel` occurrences across the views, plus a **25**-strong `Back to …` family |
| **Destructive** *(added)* | **49 distinct** Delete/Remove/Archive confirm strings (`data-turbo-confirm=` / `confirm:`) |

**Approve / Reject is deliberately NOT folded into Update.** It is a workflow
DECISION pair — the two halves are meaningful only together, and giving them
Update's scheme loses the pairing. Left as an explicit owed decision below
rather than settled by default.

**The trap inside rule 4, to raise before implementing rather than after:**
outline-only dark mode strips the red fill from destructive buttons, so "this is
destructive" ends up carried by **colour alone** — a **WCAG 1.4.1** failure, and
rule 3 forbids it. Destructive therefore needs a non-colour cue — icon plus an
explicit verb in the label — in **both** modes. Rules 3 and 4 conflict on
exactly one role, and this is the resolution.

###### The CSP deadline behind the inline-style sweep does not exist — this changed the scope

The standing argument in this plan was that #950 must land before **#528**,
because #528 removes `unsafe_inline` from `style_src` and all 1,399 inline
styles would then lose their styling silently — no error, no failing spec, just
wrong pages.

**Measured 2026-08-23: #528 is CLOSED** (COMPLETED, 2026-07-09), and so is its
parent epic **#650**. #528's own closing comment records that it shipped items 2
and 3 (inline handlers → Stimulus, CSP report-uri) and left **item 1
(`style-src 'unsafe-inline'`) and item 4 (Trusted Types) open**, saying *"Keeping
this issue open to track those two."* It was then closed anyway.
`config/initializers/content_security_policy.rb:26` still reads
`policy.style_src :self, :unsafe_inline, "https://cdn.jsdelivr.net"`, and a
search of every issue, open or closed, finds **no successor tracking either
item**.

Two consequences, and they point in opposite directions:

- **For #950's scope, the pressure is off.** Nothing is about to break those
  1,399 inline styles, so sweeping them is tidiness on a release-week branch
  with no visual-regression harness. **Owner-decided: buttons + page-header
  only.** The remaining ~1,385 stay recorded here as measured backlog.
- **The CSP hardening tail was dropped silently, which is worth its own issue.**
  `style-src 'unsafe-inline'` and Trusted Types are real remaining hardening,
  and right now nothing tracks them. **Raised, not filed** — filing is the
  owner's call.

Worst offenders, kept for whoever picks that up:

| View | Inline styles |
|---|---|
| `sar_documents/enrich.html.erb` | 136 |
| `authorization_boundaries/ato_wizard.html.erb` | 99 |
| `ssp_documents/enrich.html.erb` | 97 |
| `ssp_documents/show.html.erb` | 90 |
| `poam_documents/show.html.erb` | 73 |
| `cdef_documents/show.html.erb` | 47 |
| `control_families/show.html.erb` | 43 |

###### #1039 — the surface measured, and one claim that did not survive it

There is **no `AuthoritativeSource` model**. An authoritative source *is* a
`BackMatterResource`; `authoritative_sources` is a filtered view over that table
plus its own create path. That is why the CRUD picture is asymmetric, and it is
the single most important thing to know before scoping this.

**Routes today:**

```
web  resources :authoritative_sources, only: %i[index show new create]
api  resource  :authoritative_sources, only: [:create]  + export/import   # SINGULAR `resource`
api  resources :back_matter_resources, only: [:index, :show, :create, :update, :destroy]
       member: link, unlink, promote, approve_promotion, reject_promotion, archive, restore, changes
```

The API path is a **singular `resource`**, which is the mechanical reason it has
no index and no show — not an omission in a list somewhere.

**The owner's read — "the fields should all exist" — is right for three of the
four asks and wrong for one:**

| #1039 asks for | Measured on `main` | Verdict |
|---|---|---|
| **Control references** | `control_back_matter_links` table + association exist, **and the API already sets them**: `POST/DELETE /api/v1/back_matter_resources/:id/link\|unlink`, accepting 6 linkable types (`CatalogControl` `CdefControl` `ProfileControl` `SspControl` `SarControl` `SapControl`) | **Exists in the API. Absent from the authoritative-sources path and from every screen.** UI + route exposure only |
| **Created / last-updated dates** | `created_at` / `updated_at` on the table, already emitted by `serialize_back_matter_resource` | **Exists.** Contract + screen exposure only |
| **Full CRUD** | Full CRUD exists at `/api/v1/back_matter_resources`. The web path has **no edit, no update, no destroy**; `_item_actions.html.erb` offers exactly one action, `View`. Web `resource_params` permits only `title description href rel media_type` — **`organization_id` is not even settable** | **Web CRUD genuinely missing.** API needs the authoritative-sources path widened, not new machinery |
| **"Provided by" — organization, team, person** | `organization_id` exists on `back_matter_resources`. `organizations` carries a single `contact_person` + `contact_email`. **There is no `teams` table anywhere in the schema, and no per-source person field** | **DOES NOT EXIST.** This one is a migration, not a UI gap |

So three quarters of #1039 is exposure work — routes and screens over machinery
that already exists — and one quarter is a schema decision. **OWNER-DECIDED 2026-08-23 — free-text on the resource.** Add
**`provided_by_team`** and **`provided_by_contact`** (strings) to
`back_matter_resources`, alongside the existing `organization_id`. One
migration, no new model, honest about the fact that the provider is often an
external body — NIST, a CSP, another agency — that SPARC does not otherwise
model and should not have to.

**`provided_by_contact` holds an email OR a phone number, and the form field
"ghosts" the recommended format as placeholder text in the cell that collects
it** (owner: *"contact is an email/phone and should 'ghost' the recommended
information in the cell collecting the data"*). So the input carries a
`placeholder` showing the expected shape rather than relying on a separate label
or help text to explain it; same treatment for `provided_by_team`. The field is
deliberately **not** validated as an email — a phone number is equally valid,
and an external provider's contact is often in neither form. Placeholder text is
a hint, not a constraint, and must not be mistaken for one: it disappears the
moment the user types, so it cannot carry information the reader needs after the
fact.

Rejected, recorded so they are not re-proposed: **a `teams` table** — a new
first-class domain concept with its own RBAC and API surface, far too much for
the last bundle of a release; **leaning on `organizations.contact_person`** — no
migration, but every source from one organization would share one contact, which
is not what an assessor asking *"who do I ask about THIS reference"* needs.

**OWNER-DECIDED 2026-08-23 — `destroy` maps to archive/supersede, never a hard
delete.** Back-matter resources participate in federation
(`federated_from_instance`, `original_uuid`) and promotion (`promotion_status`,
`approved_by_user_id`), so a hard delete strands a federated copy on a peer.
`superseded_by_id` and `archived_at` already exist on the table and
`archive`/`restore` are already API members, so this reuses the mechanism rather
than inventing one.

Consequences to build to, rather than discover later:

- The web action and its confirm string say **"Archive"**, not "Delete" — a
  label must not promise something the system deliberately does not do.
- `DELETE /api/v1/authoritative_sources/:id` soft-deletes and **returns the
  archived record** rather than 204-with-nothing, so a client can tell what
  happened. Document it on the endpoint page: **a DELETE that does not delete is
  exactly the kind of contract surprise the #995 sweep exists to catch.**
- A reference already cited by a document **stays citable**. That is the point —
  archiving removes it from the picker, not from history.
- **Restore must be reachable from the UI**, or archive is a one-way door with
  extra steps.
- `visible_resources` already scopes to `BackMatterResource.active`, so archived
  rows should drop out of the index for free — **verify that, do not assume it**,
  and confirm the archived record is still reachable at its `show` URL.

On whether control references are set inline on create or through a nested
route: **follow the `evidences` precedent and use the nested route.** The issue
raised it as an open choice, but it is not really one — `evidences` already does
this with `control_links`, and the API already has `link`/`unlink` members on
`back_matter_resources` doing exactly the same job. Inventing an inline-on-create
variant would give SPARC two ways to attach a control to a thing, which is the
divergence the scope note was worried about. **Recorded as settled by precedent
rather than left owed**; flag it if the precedent turns out not to fit.

`POST /api/v1/authoritative_sources` is already covered by `tests/api` from the
#995 sweep; **every new route takes the same treatment**, and
`docs/api/endpoints/authoritative-sources.md` needs its Endpoints table extended.


###### #950 IMPLEMENTATION PLAN — settled 2026-08-23

The schema is agreed and persisted at `docs/dev/design/button_schema.html`
(published copy: artifact `c3f0af3e`). **Ten roles from seven intents; light is
all pale tint, dark carries no fill.** This section is how it gets into the app.

**The governing lesson from the first attempt: a half-swept app is worse than
either end state.** 223 buttons were swept, 274 Bootstrap variants were left,
and one card row rendered `View` and `Delete` as outlines beside a filled
`Copy` and `Export OSCAL`. Before the sweep the app was consistently wrong;
during it, it was incoherent. **Every slice below therefore has to leave the app
in a self-consistent state**, which is the reason the order is what it is.

####### What the first attempt got wrong, so the transformer is not rebuilt the same way

| Gap | Size | Why it was missed |
|---|---|---|
| Raw HTML `<button>` / `<a class="btn">` | **123 in 42 files** | the transformer only matched `link_to` / `button_to` / `submit_tag` / `button_tag`. `Export OSCAL` is a raw `<button class="btn btn-success dropdown-toggle">`, which is exactly why it stayed green |
| Labels leading with a glyph | **30** | the role regexes were `^`-anchored, so `＋ New Catalog`, `↑ Import from File`, `+ Add Item` and `&#8592; Back` never matched |
| Labels outside the roster | ~115 | now covered by the ten roles; the residue is genuine and gets counted, not forced |
| A match spanning two calls | latent | `.{0,500}?` with `re.S` paired one label with a **later** call's class. Sweeping `wizard` would have written `sparc-action--wizard` onto a **Cancel** button. Fixed by forbidding a match to cross another call — keep that guard |

**20 `sparc-btn-ghost` buttons stay out of the sweep.** They are `color: white`
on a translucent fill, built for banner surfaces that are dark in *both* themes
(the #974 trap). A role class also sets `color` at equal specificity and
`sparc-theme.css` loads last, so a role class would win and paint a dark label
onto a dark banner. Ghost is a contextual variant, not a role.

####### SCOPE — owner-decided 2026-08-23, mid-implementation

*"Get the button colouring consistent, audit, decide on implementing any other
changes on this or move any other changes in buttons/layout to v1.16.1."*

So this bundle does **colour consistency and nothing else**, then an audit, then
a decision. Slices 1-3 below are in scope. **4-7 are candidates, not
commitments** — they get decided after the audit, and the default for anything
that is not colour is **v1.16.1**.

**Do NOT touch inline `style=` in this bundle.** Owner, same message: *"be
careful on css and inline as some of that was intentional before and we are
going to do an in-line audit in v1.16.1."* The sweep changes button CLASS
attributes only. Nothing in slices 1-3 removes an inline style, and the earlier
claim that this work reduces the `unsafe-inline` surface is **withdrawn for this
bundle** — it is true of the eventual inline audit, not of a class rename.

####### AA CORRECTION — found during slice 1, after the schema was approved

The pale-tint model puts the label on a 20% tint **of itself**, and that pair is
much tighter than the same colour on the page. `primary` is 5.42:1 on #f5f5f5
but only **4.09:1** on its own tint. **Six of the seven intents failed AA** that
way; `neutral` passed only because it is nearly black.

    primary 4.09 · positive 4.35 · info 4.40 · accent 4.39
    caution 4.13 · danger 4.00        (neutral 6.79 PASS)

Fixed by splitting the token in two: the **tint and border** keep the approved
value, and a separate **`-ink` token** carries the label 2-4% darker. Every
intent now clears 4.62-4.84 on the 20% tint and 5.17-5.45 on the 12% ghost
tint, and the thing that was approved by eye — the tint — is unchanged.

**The lesson worth keeping: approving a colour by eye approves the FILL, not
the pair.** Contrast is a property of two colours together, so a schema signed
off visually still has to be measured against every surface the label actually
lands on.

####### Slices, in landing order

Each is independently verifiable and leaves the app coherent.

| # | Slice | Scope | Done when |
|---|---|---|---|
| **1** | **Replace the CSS vocabulary** | rewrite the `.sparc-action` block: 7 intents, 3 emphasis, 10 roles, pale-tint light / no-fill dark. **Rewrite `spec/quality/button_role_contrast_spec.rb`** — it currently asserts *nine* roles and a *filled-light* model, so it WILL fail and must move in lockstep | spec green, mutation-proved RED, **zero view changes** |
| **2** | **Fix the transformer** | add raw-HTML `<button>`/`<a>` matching and glyph-tolerant label rules; keep the call-scoped guard and the ghost exclusion | dry run reports ≥95% of 455 buttons mapped, **0 mis-pairings** on a call-scoped audit |
| **3** | **Sweep, one role at a time** | order: `Cancel/Utility` (111) → `Create/Approve` (64) → `Destroy/Reject` (40) → `Edit` (32) → `Export/Run` (24) → `View` (20) → `Import` (15) → `Update/Save` (10) → `Overwrite` (6) → `Wizard` (2) | after each role: `docker cp` + restart, a11y suite green, and the role's own screens eyeballed at 1280 and 375 |
| **4** | **Dropdowns** | the 5 `dropdown-toggle` buttons → split-button treatment, intent inherited from the action | each renders correctly open and closed, in both themes |
| **5** | **The residue** | whatever the transformer could not classify, listed individually and either assigned or left with a written reason | the count is published, not rounded away |
| **6** | **The 62px row** | `d-flex gap-2 flex-shrink-0` in `home/index`, `profile_documents/show`, `cdef_documents/show` — the dashboard's 992px overflow | responsive audit reports 0 findings above 375px |
| **7** | **Style guide** | fold the schema into the wiki as the button reference, linking `docs/dev/design/button_schema.html` | wiki page published via `PUSH_TO_WIKI.sh` |

####### Gates

- **rspec full suite** after slice 1 and at the end. `spec/quality/button_role_contrast_spec.rb` is the standing AA check and must be mutation-proved again after the rewrite — green proves nothing until it has been seen RED.
- **`tests/ui-smoke` with `SPARC_SMOKE_PUBLIC_CATALOGS=0`.** Its absence produced 5 ERRORs I initially misread as regressions.
- **Never restart the container while a suite runs.** A mid-run `docker compose restart` produced 38 `HTTP 502` failures that had nothing to do with the change under test.
- **After any `app/assets/**` edit**: `docker cp`, then `rm -f public/assets/.manifest.json` and `assets:precompile` **as `-u root`** — without root the `rm` is denied, precompile fails, and the app serves the OLD stylesheet with no error. Confirm by fetching the fingerprinted asset and grepping for the new class, not by the restart succeeding.
- **Verify by rendering, not by reasoning.** Screenshot the section and read it back. Every design miss in this bundle survived a code-level check and died within a minute of being looked at.

####### Risk, stated plainly

There is **no visual-regression harness**, and PR #943 is the proof of what that
costs: a completely green suite beside a visibly broken drawer header. The
mitigations are the per-role slicing above, the a11y sweep after each, and
looking at the screens. That is weaker than a real harness and should be said
out loud rather than implied.

**Security posture is unchanged or improved.** Every role is a CLASS; the sweep
removes inline `style=` rather than adding it, which moves toward
[#1047](https://github.com/risk-sentinel/sparc/issues/1047) (dropping
`style-src 'unsafe-inline'`) instead of against it. No new inline handlers, no
CSP directive changes.

###### VERSION — 1.15.5 → 1.16.0, in THIS PR

Owner-decided 2026-08-22: *"v1.16.0 won't be done until the next bundle is
done."* It is `1.15.5` at **`app/models/sparc_config.rb:22`**, and
`spec/docs/wiki_currency_spec.rb` asserts the wiki's
`| Current Version | **v1.15.5** |` row matches — **so both move together or that
spec fails.**

###### Gates and traps this bundle must meet

- **This bundle is mostly CSS, so the Propshaft trap is the likeliest one to
  bite.** A CSS-only change still needs `docker compose restart web` (Propshaft
  caches at boot), and **in the UBI9 prod image a restart is NOT enough**: run
  `assets:precompile` after `docker cp` of JS/CSS, with
  `rm -f public/assets/.manifest.json` first or it silently no-ops.
- **Verify contrast with `tests/ui-smoke/_contrast_probe.py`, not by eye.**
- The audit script is #1042's acceptance instrument: it must report **zero**
  `HORIZONTAL_OVERFLOW` findings, with a standing assertion in
  `test_sidebar_951.py` to keep it there. Re-run with:
  `SPARC_SMOKE_BASE_URL=https://localhost:3443 SPARC_SMOKE_SA_TOKEN=<token> SPARC_SMOKE_INSECURE_TLS=1 uv run python responsive_audit_951.py`
- **The navbar is shared NAVIGATION.** Visibility may differ, placement may not,
  without an approved layout. Any new or moved control also takes a Playwright
  interaction check with a CSP assertion.
- **Any new page or nav entry** gets registered in `tests/ui-smoke/pages.py`
  **and needs an a11y baseline** captured with `UPDATE_A11Y_BASELINE=1` —
  otherwise the a11y check silently SKIPS for that page. #1039's edit screens
  are new pages.
- **`Test plan checklist` fails on ANY unchecked box**, and `Required Checks
  Passed` then fails solely because of it. Owner-run and post-merge items go in
  a `<!-- pr-checklist:skip -->` block.
- **ui-smoke DEFAULTS TO PRODUCTION** — always set `SPARC_SMOKE_BASE_URL`, and
  read the skip reasons rather than the pass count.
- Full suite always: rspec, `tests/api`, ui-smoke, rubocop, ruff, brakeman, both
  API gate scripts, and a browser pass at **:3443**.

###### Decisions still owed by the owner — **2 of 6 remain**

1. **Approve / Reject** — its own workflow-decision role pair, or folded into
   Update? Folding loses the pairing. **Not blocking**: it can be settled during
   slice 3, when the role classes are written.
2. **Two touch-target calls**, surfaced by the #951 audit and deliberately not
   taken unilaterally (WCAG 2.2 AA §2.5.8 wants 24×24): `button.sparc-field-help`
   renders **16×16**, and roughly **90 inline help-guide links** render 20px
   tall — which is ordinary body-text link behaviour and arguably outside the
   criterion. Both are density-vs-AA judgement calls, not bugs. **Not blocking**
   either; nothing in slices 1–7 depends on the answer.

**Settled 2026-08-23** — recorded in place above, not repeated here:
**#1042's fix shape** (`navbar-expand-xl` + `d-none d-xl-block`) ·
**#1039 "provided by"** (free-text `provided_by_team` / `provided_by_contact`,
placeholder-ghosted, no email validation) · **#1039 delete semantics**
(`destroy` → archive/supersede) · **the audit gate** — Bundle X fixes the
`mail` finding and adds `bundle-audit` to the LOCAL pre-PR gate only; the
systemic threshold-gate work is
**[#1048](https://github.com/risk-sentinel/sparc/issues/1048)** on `ci.v0.0.1`.

**The CSP tail is FILED as [#1047](https://github.com/risk-sentinel/sparc/issues/1047),
milestone v1.16.1** — `style-src 'unsafe-inline'` plus Trusted Types, the tail
#528 closed over on 2026-07-09. The owner's read: *"CSP tail is not going to be
easy and needs to be filed and will likely need to ride v1.16.1 milestone."*
That is the right size for it — the flip is one line, but surviving it is 1,399
edits with no visual-regression harness to catch a silent break.

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

#### Dependency lane (open Dependabot PRs) — **rides Bundle X**

Judged by **running `bundle-audit`, not by reading diffs**. Re-run 2026-08-23 against `main`
(`a41764a7`) with advisory DB `8cfcc07`, 2026-08-22:

```
Name: mail
Version: 2.9.0
GHSA: GHSA-mvxr-6m87-mv2q
Criticality: Medium
Title: Email address spoofing via malformed RFC 2047 encoded-words in mail
Solution: update to '>= 2.9.1'
Vulnerabilities found!            # exit 1
```

**This section's previous standing claim — "no vulnerabilities against the current lock" — is now
FALSE, and it went false without any Dependabot PR appearing.** `mail` is **transitive**
(`actionmailer`, `actionmailbox` and `omniauth_openid_connect` all require it, at `>= 2.8.0`), it
has **no line in the Gemfile**, and so Dependabot had nothing to open a PR against. This is the
**exact shape** the #886 note below already warned about — *"auto-close is reliable for direct
dependencies, not for a transitive security PR"* — recurring on the other side: not an orphan PR
left open, but a live advisory with **no PR at all**. `mail >= 2.8.0` already admits 2.9.1, so the
fix is `bundle update mail` and nothing else moves.

**The lesson to carry: `bundle-audit` is the gate, the Dependabot PR list is not.** An empty
dependency queue is not evidence of a clean lock.

##### Why nobody caught it — CI found it 85 times and reported success

The owner's question on 2026-08-23 was *"how do we build the audit into our
ceremony, since CI on the PR missed it as well as us during development."*
**Measured, and the premise needs correcting: CI did not miss it.**

| | |
|---|---|
| Advisory published | 2026-07-01 |
| Entered `ruby-advisory-db` (`cfa8518`) | 2026-08-18 ~00:24 UTC |
| **First CI run to report it** | **2026-08-18T21:42**, run `32189123058` |
| Green `security.yml` runs carrying it since | **85** |
| …of which push-to-`main` merges | **8** |
| Those merges include | **Bundle V (PR #1009)** and **Bundle R (PR #1045)** |

The `bundler-audit-json` artifact from the Bundle R merge run (`32611703559`,
`main`, conclusion **success**) contains exactly one result:

```json
{ "type": "unpatched_gem",
  "gem": { "name": "mail", "version": "2.9.0" },
  "advisory": { "id": "GHSA-mvxr-6m87-mv2q", "criticality": "medium",
                "patched_versions": [">= 2.9.1"] } }
```

**The scanner worked, the advisory DB refresh worked, the weekly cron worked.
The finding was written to a 90-day artifact on the merge commit and the
workflow reported success.**

**Why the job went green — one design working as intended, and one hole in it:**

1. **`security.yml:340` — `continue-on-error: true`** on the check step, so it
   cannot fail its job whatever it finds. **This is by design and is not the
   defect** — see below.
2. **Nothing ever assesses the JSON.** It is downloaded at line ~1022 only to be
   `cp`'d into the archive at line 1325. **This is the defect.**
3. A contributing detail: the `Evaluate severity threshold` step at line 1341 is
   `if: env.FAIL_ON_SEVERITY != 'none'`, and `FAIL_ON_SEVERITY` **defaults to
   `'none'`** (line 54) — so it is inert on every trigger except a manual
   dispatch that sets it. It also reads HDF results, not bundler-audit. **Two
   gates with different rules** is its own problem, carried into #1048.

**The posture is deliberate and CORRECT — do not "fix" it by making the step
fail.** `continue-on-error` at line 340 exists so scans run to completion and
produce artifacts; assessment happens **downstream**, in a threshold gate. That
architecture is already built and already merge-blocking: **`security_gate`
(#244)** amends each HDF from `docs/compliance/sparc-findings.yml` and runs
`saf validate threshold -T docs/compliance/threshold.yml`, failing the build on
violation. **This is exactly the scan → artifact → assess model, and it works.**

**The real defect is narrower and sharper: `bundler-audit-results.json` is the
ONE artifact that never enters it.** `normalize_hdf` runs **12
`saf convert … 2hdf` calls** — gitleaks, brakeman, codeql, semgrep, trivy-fs,
trivy-container, three SBOMs and three grype scans. bundler-audit is downloaded
at ~line 1022 **purely to be `cp`'d into the archive zip at line 1325.** It never
becomes HDF, so it never reaches `security_gate`, so no threshold is ever
applied to it.

**And plumbing it in would not have been sufficient**, which is the part worth
keeping: `threshold.yml` sets the global residual band at `medium: max: 20`, and
this finding is a **Medium**. It needs a per-scanner band of its own, as
`brakeman`, `gitleaks`, `codeql` and the trivy scanners already have.

Measured, not assumed: `@mitre/saf` **1.6.0** — the version the workflow pins —
offers `dependency_track2hdf`, `snyk2hdf` and `zap2hdf`, but **no bundler-audit
converter**. So closing this needs a converter written, not a line of YAML.

**And our own side of it, stated plainly:** the recorded practice was *run
`bundle-audit` when assessing a dependency PR*. No PR appeared for `mail` —
there could not be one, it has no manifest line — so the trigger never fired.
The practice was conditioned on the wrong event.

###### OWNER-DECIDED 2026-08-23 — fix the finding here, fix the GATE in its own issue

**Superseding an earlier recommendation in this plan to drop
`continue-on-error`.** The owner's correction, and it is right: *"we probably
need a different way so that the scans occur, generate artifacts, and then the
artifacts are 'assessed' for thresholding. This is exactly why HDF thresholding
and blocking occurs. Let's just fix the offending issue on this, file an issue
in the existing ci milestone to review generated artifacts in a threshold gate
so that this doesn't happen next time."*

Making the step fail would have traded a working evidence-collection design for
a blunt instrument — and it would have bypassed `sparc-findings.yml`, so an
accepted advisory would have had no way to be dispositioned except by turning
the check off. **Recorded because the wrong fix was plausible**: it closes the
observed symptom while removing the mechanism that makes dispositions auditable.

**So Bundle X does two things and no more:**

1. **Fix the finding** — `bundle update mail` → 2.9.1, in slice 1. No workflow
   edit for the gate.
2. **Add `bundle-audit` to the LOCAL pre-PR gate.** Cheap, no CI change, and it
   moves the signal to development time. Note the ruby-2.6 trap: `bundle-audit`
   on system ruby produces **no output at all**, which reads exactly like
   success ([[feedback_run_it_dont_reason_about_it]]).

**The systemic fix is [#1048](https://github.com/risk-sentinel/sparc/issues/1048),
milestone `ci.v0.0.1`** — convert bundler-audit to HDF so it reaches
`security_gate`, give it a per-scanner threshold band, resolve the second inert
gate (`FAIL_ON_SEVERITY` defaults to `'none'`), and — the deliverable that
actually stops recurrence — **audit every artifact `security.yml` produces
against what `security_gate` assesses.** That orphan was found by accident while
chasing one advisory; the systematic question has never been asked.

**#1048 must prove the gate RED before it is trusted green**
([[feedback_prove_tests_have_teeth]]): validate against the pre-bump lockfile,
confirm the build fails, then against the fixed one. **A gate only ever observed
green is not known to work** — which is the whole lesson here.

**`security.yml` is NOT edited by Bundle X for this.** The only workflow edits in
this bundle are PR #1006's five action bumps.

| Item | Bump | Slot | Why there |
|---|---|---|---|
| **(no PR)** | **`mail` 2.9.0 → 2.9.1** — transitive | **FIRST, ahead of everything** | The only live advisory. Medium, email-address spoofing via malformed RFC 2047 encoded-words. **Reachable, not theoretical: SPARC has 5 mailers** — `password_reset_mailer.reset_link`, `idp_grant_mailer.unmatched_grants_digest` (Bundle R), `service_account_mailer` (4 expiry/inactivity notices) and `document_parse_mailer`. An advisory about spoofing the apparent sender under a *password-reset* mailer is the combination worth taking first. `bundle update mail`; no Gemfile change |
| **#971** | `brakeman` 8.0.5 → 8.0.6 (patch group) | With the lane | Dev/CI only. Carries *"fix command injection false positives"*, so it may **reduce** brakeman noise at the release gate rather than add it. Take the bump directly; the PR is behind `main` |
| **#972** | `minor-updates` group — `solid_queue`, `bootsnap`, `selenium-webdriver`, `axe-core-rspec`, `simplecov` | With the lane, **but at LATEST, not at the PR's versions** | See the solid_queue note below — the PR is a week stale and offers 1.6.0 where 1.7.0 has since shipped |
| **#1006** | `actions-updates` group — `github/codeql-action` (init/analyze/upload-sarif) 4.37.6 → 4.37.7, `docker/setup-buildx-action` 4.2.0 → 4.3.0, **`astral-sh/setup-uv` 9.0.0 → 10.0.1 (MAJOR)** | With the lane, **whole** | **Workflow edits approved by the owner for this bundle specifically** (2026-08-23), all five, major included. **15 pin SITES across 4 files**, not 5 — `codeql-action` alone appears 12 times. Every SHA was verified against its claimed tag via the GitHub API before being trusted, and the `# v4` comments were sharpened to the real versions (`# v4.37.7`, `# v4.3.0`, `# v10.0.1`) so the next reader can check the pin without an API call. **The `setup-uv` major is a no-op for us, and that is measured rather than hoped:** v10's breaking change is that `enable-cache: **auto**` now DISABLES the cache for `pull_request_target`, `workflow_run` and `release`, to blunt cache poisoning. `ui-smoke.yml` sets `enable-cache: **true**` explicitly, so the new default does not apply. **But note what that means: `ui-smoke.yml` triggers on `workflow_run` and holds `SPARC_SMOKE_SA_TOKEN`, so we are explicitly opting out of the protection v10 added.** Whether that is exploitable here depends on GitHub's cache scoping, which has NOT been measured — flagged for the owner, deliberately not changed, since altering cache behaviour is beyond the approved bump |
| **#820** | `openssl` 3.3.0 → **4.0.2** (major) | **MOVED OUT — v1.16.1** | Owner-decided 2026-08-23. Unchanged prerequisite: rebuild the dev Ruby against OpenSSL 3 first, as one work item. On this box `openssl-4.0.2` **segfaults inside bundler itself**, leaving no working `bundle` to recover with. Details in the Bundle R section above |

##### Take the gems at LATEST, not at the Dependabot PRs' versions

The owner's direction is *"might as well fold them in for the most up-to-date gems if possible."*
The bundler PRs are 6 days stale and one of them is already behind:

| Gem | On `main` | PR #972 / #971 offers | **Latest on rubygems (2026-08-23)** |
|---|---|---|---|
| `solid_queue` | 1.5.1 | 1.6.0 | **1.7.0** |
| `bootsnap` | 1.24.6 | 1.25.0 | 1.25.0 |
| `selenium-webdriver` | 4.46.0 | 4.47.0 | 4.47.0 |
| `axe-core-rspec` | 4.12.0 | 4.13.0 | 4.13.0 |
| `simplecov` | 1.0.3 | 1.1.1 | 1.1.1 |
| `brakeman` | 8.0.5 | 8.0.6 | 8.0.6 |
| `mail` (transitive) | **2.9.0** | *(no PR)* | **2.9.1 — the advisory fix** |

So four of the six land at latest either way; **`solid_queue` is the one that does not**, and
PR #972 would additionally re-pin it to `~> 1.6.0`, which forbids 1.7.0.

**`solid_queue` needs a Gemfile decision, not just a lockfile bump.** The pin reads:

```ruby
gem "solid_queue", "~> 1.5.0"   # 1.6.0 is a minor bump on the prod job backend — review separately
```

The comment is a standing instruction to review rather than a pin to carry forward, and this is
that review. **1.6.0's headline is an opt-in fiber execution mode** — it requires `fibers:` in the
worker config *and* `config.active_support.isolation_level = :fiber`; SPARC sets neither, so the
new path is unreachable. The rest is bug fixes, including *"roll back transactions leaked by killed
job threads in tests."* **Recommended: `~> 1.7` (not `~> 1.7.0`)**, so patch *and* future minor
fixes arrive without another pin edit — the `~> 1.5.0` form is what let this one go stale in the
first place. `solid_queue` is the **production job backend** (`AwsLabsCdefRefreshJob`,
`DocumentConversionJob`, the unmatched-grant digest), so the proof is a **job actually running in
the UBI9 prod image**, not a green rspec.

##### Prove the audit has teeth — both directions

A "No vulnerabilities found" after the bump means nothing unless the same invocation reports the
known-bad lock. Run it both ways and record both:

```bash
export PATH="$HOME/.rvm/rubies/ruby-3.4.4/bin:$HOME/.rvm/gems/ruby-3.4.4/bin:$PATH"
export GEM_HOME="$HOME/.rvm/gems/ruby-3.4.4"
export GEM_PATH="$HOME/.rvm/gems/ruby-3.4.4:$HOME/.rvm/gems/ruby-3.4.4@global"
(cd ~/.local/share/ruby-advisory-db && git pull)
bundle-audit check --database ~/.local/share/ruby-advisory-db   # --database every run, NOT --update
```

RED leg: the `a41764a7` lockfile reports GHSA-mvxr-6m87-mv2q, exit 1. GREEN leg: the post-bump
lockfile reports none, exit 0. **Both legs go in the PR body.** Note `rvm use` needs
`unset -f rvm` first or the shell silently stays on system ruby 2.6 — and a `bundle-audit` run on
2.6 produces no output at all, which reads exactly like success.

##### Closed 2026-08-11 — kept because the shape recurs

~~#886 `activestorage` 8.1.3 → 8.1.3.1~~ — already in the image on `main`. Worth recording *why it
lingered*: `activestorage` is **not a direct Gemfile entry** (transitive via `rails`), so when #889
cherry-picked the Rails 8.1.3.1 bump + `image_processing` removal, the branch diff became empty but
Dependabot had **no manifest line to reconcile against** and left the orphan open. Auto-close is
reliable for direct dependencies, not for a transitive security PR whose requirement is satisfied
by a different gem's bump. **Check transitive security PRs by hand after any framework bump** — and,
as `mail` now shows, check for transitive advisories that never got a PR at all.

> **#820 is not stale, it is pending a decision.** `dependabot.yml` deliberately keeps majors as
> individual PRs ("higher review needed", no major group), so an unmerged major sitting alone is
> the config working as intended — not neglect.

**Owner decisions still owed — 2 of 6 remain, neither blocking.** Full context in the
Bundle X section above; summarised here so the release PR has one place to check:

1. **#950 — Approve / Reject**: its own workflow-decision role pair, or folded into Update?
   Settle it during slice 3, when the role classes are written.
2. **Two touch-target calls** — `button.sparc-field-help` at 16×16 and ~90 help-guide links at
   20px, against WCAG 2.2 AA §2.5.8's 24×24. Density-vs-AA judgement calls, not bugs.

**Settled 2026-08-23:** #1042's fix shape (`navbar-expand-xl` + `d-none d-xl-block`) · #1039's
"provided by" (free-text on the resource, placeholder-ghosted, not email-validated) · #1039's
delete semantics (`destroy` → archive/supersede) · **the audit gate — fix the `mail` finding in
Bundle X, add `bundle-audit` to the LOCAL pre-PR gate, and track the systemic threshold-gate work
as [#1048](https://github.com/risk-sentinel/sparc/issues/1048) on `ci.v0.0.1`. `security.yml` is
NOT edited by Bundle X for this.**

**The CSP tail is FILED as [#1047](https://github.com/risk-sentinel/sparc/issues/1047) on
milestone v1.16.1** — so **v1.16.1 now holds 5 issues**: #1022, #1033, #1040, #1044, #1047.
**#820 is a PR, not an issue, and is deliberately left OFF the milestone** — attaching a PR to a
milestone pollutes every count read off the milestone page, which is a trap this plan has already
been caught by. It is deferred to the v1.16.1 *timeframe*, tracked here and on the PR itself.

**Decided and closed out, kept for the record:** #919's roster posture and #860's five open
questions were both settled and shipped (Bundles C and R). The **14-day fallback** — a coherent
hardening-only v1.16.0 of A+B+C — was available around 2026-08-21 and not taken; recorded because
the option recurs if the date starts to bind. It no longer binds: 83 of 86 are closed.

**Release-notes obligations accumulated so far** (the release PR must carry these):

- #914 extend-by-default is a **behaviour change on upgrade** — leads the notes.
- #909 legacy banner variables **scheduled for removal in v1.18.0**, with the reasoning.
- **#820 does NOT land in v1.16.0** — `openssl` stays on the 3.x line, deferred to v1.16.1 with
  its dev-toolchain prerequisite. Say so plainly rather than leaving readers to infer it from
  silence; it sits under PIV, federation signing, outbound TLS and LDAP.
- **A transitive security fix ships with no Dependabot PR behind it**: `mail` 2.9.0 → 2.9.1,
  GHSA-mvxr-6m87-mv2q (Medium, email-address spoofing via malformed RFC 2047 encoded-words).
- **`solid_queue` moves 1.5.1 → 1.7.0 on the production job backend**, and its Gemfile pin widens
  from `~> 1.5.0` to `~> 1.7`. The new fiber execution mode is opt-in and SPARC does not enable it.
- **`astral-sh/setup-uv` takes a major** (9 → 10) in CI. No runtime effect; it changes how the
  ui-smoke and API suites bootstrap their toolchain.
- **Button styling changes app-wide** (#950) — seven roles, one class each, and dark mode goes
  outline-only with no fill. Every screen looks slightly different; nothing moves.
- **The main navbar's breakpoint changes** (#1042). Visibility differs between 992px and ~1400px;
  placement does not.
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
| 16 | Current | v1.16.0 — config correctness, authorization sweep, UX filters, auth entitlements, OSCAL fidelity (milestone `v1.16.0`) | **86 issues — 83 closed, 3 open, measured 2026-08-23; Bundle X's PR closes the last 3, taking it to 86/86.** Open: **#1042 #950 #1039**, all in **Bundle X, the LAST bundle**. The full closed list is the milestone itself — do not maintain a second copy here | In Progress — **the release gate is MET, and Bundle X is in its PR carrying the VERSION bump to 1.16.0.** Bundle R merged 2026-08-23 as [PR #1045](https://github.com/risk-sentinel/sparc/pull/1045) → `a41764a7` (25 commits), closing #860, #842, #822 and #1043. Bundle V merged 2026-08-22 as [PR #1009](https://github.com/risk-sentinel/sparc/pull/1009) → `fda3413d` (72 commits, 32 `Closes`). Bundle W merged as [PR #1005](https://github.com/risk-sentinel/sparc/pull/1005) → `ab2dbd1a`. **Remaining: Bundle X only** — #1042 navbar overflow, #950 button roles + a shared page-header, and **#1039**, which the owner slotted into Bundle X on 2026-08-23 rather than deferring it. Bundle X also carries the **VERSION bump 1.15.5 → 1.16.0** and the **dependency lane**, which is no longer routine: `bundle-audit` on `a41764a7` is **RED** — `mail` 2.9.0, GHSA-mvxr-6m87-mv2q — a **transitive** advisory with **no Dependabot PR behind it**, so an empty dependency queue was not evidence of a clean lock. **#820 (openssl 4.x) moved OUT to v1.16.1**, its dev-toolchain prerequisite unchanged. **#950 had sat OPEN with NO MILESTONE** since it was split from #949, which is why it never appeared in a bundle — it was invisible to every milestone count; the owner put it on v1.16.0 on 2026-08-22. **The milestone grew 53 → 86 because the sweep FOUND things**, not through scope creep: every one was a defect already shipped and previously invisible. **Count it, do not carry the last figure forward** — reconcile against `gh issue list --milestone v1.16.0 --state all --limit 300` (the default 30-row limit under-reports it, and the milestone page counts PRs too). That is how #945 and #948 were found after being missed by every prior pass. Order set by the owner: **#939 pulled forward** → **O** → **S** → **P** → **T** → **Q** → **hdf pin** → **U** → **W** → **V** → **R** → **X**. Target tag ~2026-09-21, provisional. Per-issue detail and bundle sequencing live in the Phase 16 section above; this row is the phase-level status |

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
