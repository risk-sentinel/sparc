# Changelog

All notable changes to SPARC are documented here. Versions follow semantic versioning. Links reference the [risk-sentinel/sparc](https://github.com/risk-sentinel/sparc) repository. Full release notes (with verification evidence) live on each version's [GitHub release page](https://github.com/risk-sentinel/sparc/releases).

---

## v1.12.1 -- UBI9 UTF-8 Locale Hotfix (2026-07-18)

Production hotfix for the v1.12.0 UBI9 image. Fixes **HTTP 500 on all full-layout pages** (including `/login`) whenever `SPARC_HEADER_TEXT` (the rules-of-behavior header) — or any operator env var rendered into a page, including the consent banner — contained **non-ASCII characters**. Root cause: UBI9 minimal ships no UTF-8 locale, so Ruby tags `ENV[]` values as BINARY (ASCII-8BIT) and rendering them into the UTF-8 layout raised `Encoding::CompatibilityError`; the prior Debian base set `LANG=C.UTF-8` implicitly, masking it. Adds `LANG`/`LC_ALL=C.UTF-8` to both build stages plus a **build-time guard** asserting `Encoding.default_external == UTF-8` so it can't silently regress ([#750](https://github.com/risk-sentinel/sparc/issues/750)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.12.1).

## v1.12.0 -- UBI9 Production Base-Image Cutover (2026-07-17)

Migrates the production image from Debian `ruby:slim` to **Red Hat UBI9** (Iron Bank / DISA-aligned), compiling Ruby + jemalloc from source and retiring the recurring Debian `perl`/`glibc` CVE-disposition treadmill ([#742](https://github.com/risk-sentinel/sparc/issues/742)). Multi-arch (amd64 + arm64), signed and SBOM-attested. **Known issue** (fixed in v1.12.1): non-ASCII header/banner text returns HTTP 500 on this image. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.12.0).

## v1.11.1 -- Boundary-Scoped Document Access + Scan Tooling Hardening (2026-07-16)

Security release. Enforces **boundary-scoped access** across SSP, SAR, SAP, POA&M, Evidence, and CDEF — authenticated users only see and act on documents in the authorization boundaries they can access; global (nil-boundary) documents remain open. The web UI now enforces the same rules as the API via `BoundaryScopedDocument` (NIST AC-3) ([#738](https://github.com/risk-sentinel/sparc/issues/738), [#739](https://github.com/risk-sentinel/sparc/issues/739)). Adds evidence validity guards (system-recorded UTC provenance), SSP metadata enrichment sourced from canonical SPARC locations ([#737](https://github.com/risk-sentinel/sparc/issues/737)), and supply-chain/scan tooling hardening ([#743](https://github.com/risk-sentinel/sparc/issues/743)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.11.1).

## v1.10.2 -- ODP Tooling, Artifact Lifecycle & CSP Hardening (2026-07-11)

Feature + hardening release. Adds **bulk ODP (Organization-Defined Parameter) import** for baselines/profiles — upload values as JSON / YAML / XML and preview a non-destructive diff (changed / unchanged / unknown / invalid) before applying, via `POST /api/v1/profile_documents/:id/parameters/import/{preview,confirm}`. Includes artifact-lifecycle and CSP hardening. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.10.2).

## v1.10.1 -- OSCAL-Aligned Control-Field Naming (2026-07-02)

Maintenance release. Standardizes internal control-field naming to neutral, OSCAL-aligned identifiers for closer alignment with the OSCAL standard. A transparent data migration updates existing records automatically on deploy — **no operator action required**. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.10.1).

## v1.10.0 -- Environment Header, Durable Artifact References & Index Search (2026-06-30)

Minor release. Adds a configurable **site-wide environment header bar** to label a deployment and its rules-of-use, via `SPARC_HEADER_TEXT` / `SPARC_HEADER_TEXT_COLOR` / `SPARC_HEADER_HIGHLIGHT_COLOR` (WCAG-passing defaults; operator colors honored as-is) ([#682](https://github.com/risk-sentinel/sparc/issues/682)). Also adds durable artifact references and document index search. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.10.0).

## v1.9.1 -- POA&M-from-Amendments + Security Remediations (2026-06-28)

Cleanup on v1.9.0. Restores OSCAL POA&M generation under hdf-cli 3.2.0 via the new `POST /api/v1/oscal/poam_from_amendments` endpoint (`hdf convert --from hdf-amendments --to oscal-poam`) — the supported replacement for the removed direct `hdf → oscal-poam` converter ([#663](https://github.com/risk-sentinel/sparc/issues/663)). Ships as a full API-first surface (shared service + audit event + request/contract specs + INVENTORY/Postman entries), plus security remediations and an accessibility fix. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.9.1).

## v1.9.0 -- Document Review & Approval Workflow (2026-06-26)

Minor release. Adds a **document review & approval workflow** — a new `Approvable` model, review queue, and `BaselineReviewService` / `DocumentApprovalService`, gated by `SPARC_REQUIRE_DOCUMENT_APPROVAL` (default off, so existing publish flows are unchanged until an org opts in) ([#640](https://github.com/risk-sentinel/sparc/issues/640), #630–634). Also adds **authoritative sources & federation** — add/import an authoritative source, plus a release-validation gate (API-coverage + nav CSP sweep) ([#657](https://github.com/risk-sentinel/sparc/issues/657), [#646](https://github.com/risk-sentinel/sparc/issues/646)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.9.0).

## v1.8.6 -- UI Accessibility (WCAG 2.1 AA) + UI Test Net (2026-06-03)

Accessibility + test-infrastructure release. Ships the **Section 508 / WCAG 2.1 AA** burndown ([#599](https://github.com/risk-sentinel/sparc/issues/599), [#602](https://github.com/risk-sentinel/sparc/issues/602)): a WORM (Write-Once, Read-Many) color architecture where semantic helper keys and single-source `.sparc-status` / `.sparc-heading` components own all contrast — views carry no badge/heading hex. **0 axe color-contrast / select-name / label / meta-refresh violations** across the 20 core pages in both light and dark themes. Adds the **UI Test Net** ([#572](https://github.com/risk-sentinel/sparc/issues/572)): Layer 2 Playwright post-deploy smoke and Layer 3 axe-core accessibility ratchet. Dependency patches incl. **puma 8.0.1 → 8.0.2** (PROXY-protocol-v1 injection hardening, [#601](https://github.com/risk-sentinel/sparc/issues/601)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.6).

## v1.8.5 -- Chromium OAuth Login Fix + DB-Enforced Email Uniqueness (2026-05-29)

Patch release. Restores SSO login in Chromium browsers — the global CSP `form-action 'self'` was blocking the OmniAuth → IdP redirect (Chromium enforces `form-action` on every redirect hop; Firefox does not), so login now relaxes `form-action` to the **configured IdP origins only** ([#593](https://github.com/risk-sentinel/sparc/issues/593)). Adds **database-enforced case-insensitive email uniqueness** via a functional `UNIQUE` index on `LOWER(email)`, plus two base-image `perl` CVE dispositions. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.5).

## v1.8.4 -- API Session-from-Token Cookie Bridge (2026-05-27)

Closes [#573](https://github.com/risk-sentinel/sparc/issues/573) (Layer 2 prerequisite of the UI-testing umbrella [#572](https://github.com/risk-sentinel/sparc/issues/572)). Adds `POST /api/v1/sessions/from_token`, which exchanges a SPARC API Bearer token (or OIDC JWT) for a Rails session cookie so headless test runners (Playwright, Cypress, Chromium) can drive the UI as an authenticated user without scraping the login form. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.4).

## v1.8.3 -- Deferred Data Migrations (2026-05-27)

Architectural fix removing the deploy kill-loop class of bug. Any `ActiveRecord::Migration` marked `include DeferredDataMigration` registers at `db:migrate` time (fast — no data work) and runs its body post-boot via an in-Puma Solid Queue job. The container binds its port and passes ECS health checks within seconds even on multi-minute data migrations. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.3).

## v1.8.2 -- Critical: Back-Matter Promotion UUID Collision Fix (2026-05-27)

Production hotfix. `back_matter_resources.uuid` carries a **global** unique index, but v1.8.0's promotion stored the source OSCAL uuid directly as `BMR.uuid` — two documents legitimately referencing the same source uuid (common across SSP/SAR/SAP/CDEF for shared NIST 800-53 references) crashed the second INSERT mid-migration. Resolves the `Uuid has already been taken` deploy failure. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.2).

## v1.8.1 -- Login OIDC Tab CSP Regression Hotfix (2026-05-27)

Production hotfix. The v1.7.0 CSP ([#514](https://github.com/risk-sentinel/sparc/issues/514)) enforced `script-src` with no `'unsafe-inline'`; the login page's tab switching used inline `onclick=` handlers (not nonce-exempt), so users with both local + OIDC/LDAP enabled could not click the Okta/LDAP tabs. Tab handlers moved to nonce'd scripts. Also captures `login_failure` reason codes. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.1).

## v1.8.0 -- CdefMutationService + Back-Matter Promotion (2026-05-27)

Minor release. Every CDEF mutation now funnels through **`CdefMutationService`**, which validates the post-mutation OSCAL against the NIST component-definition v1.1.2 schema **before** the transaction commits — an invalid result is rejected pre-commit instead of silently persisting. OSCAL back-matter is **promoted** out of the legacy `import_metadata["back_matter"]` stash to first-class `BackMatterResource` rows across SSP / SAR / SAP / Profile / POA&M, with `BackMatterResourceChange` audit rows on mutation. Bundles [#498](https://github.com/risk-sentinel/sparc/issues/498), [#581](https://github.com/risk-sentinel/sparc/issues/581), [#582](https://github.com/risk-sentinel/sparc/issues/582), [#583](https://github.com/risk-sentinel/sparc/issues/583), [#584](https://github.com/risk-sentinel/sparc/issues/584). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.0).

## v1.7.4 -- Nested-Route id-or-slug + RBAC Permission Gating (2026-05-26)

Patch release closing the last two API contract-drift bugs from the [#433](https://github.com/risk-sentinel/sparc/issues/433) test suite. The `authorization_boundaries` controller and every nested controller under it now accept **either an id or a slug** in the URL ([#574](https://github.com/risk-sentinel/sparc/issues/574)), plus RBAC permission-gating fixes. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.7.4).

## v1.7.3 -- API Contract + Compliance Drift Bundle (2026-05-26)

Patch release fixing five prod drift bugs surfaced by the [#433](https://github.com/risk-sentinel/sparc/issues/433) content-style tests. Notably, five `#update` endpoints (cdef_documents, control_catalogs, control_mappings, profile_documents, and the SSP/SAR/SAP/POA&M document base) now return the **detailed** serialization so callers can read-after-write to confirm a change ([#555](https://github.com/risk-sentinel/sparc/issues/555)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.7.3).

## v1.7.2 -- Pagination + Processing-Banner Trap + CI Fix (2026-05-24)

Patch release. `Api::V1::BaseController#paginate` now reads `params[:items]` / `params[:per_page]` (previously ignored, so every index returned the default) with a clamp at `MAX_PAGINATION_LIMIT = 200` to block `?items=999999` DoS attempts ([#549](https://github.com/risk-sentinel/sparc/issues/549)). Includes a processing-banner fix and a critical CI workflow fix that unblocks image publication. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.7.2).

## v1.7.1 -- Prod Bug Fixes Unblocking API Test Suite (2026-05-24)

Patch release covering three prod issues surfaced during [#433](https://github.com/risk-sentinel/sparc/issues/433) API testing against `sparc.risk-sentinel.org`. Headline: recovers the `cloned_from_id` column on `cdef_documents` (lost on databases that crossed the [#470](https://github.com/risk-sentinel/sparc/issues/470) squash boundary), fixing a 500 on every `/api/v1/cdef_documents` verb ([#537](https://github.com/risk-sentinel/sparc/issues/537)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.7.1).

## v1.6.6 -- Hotfix: SeedRunner Converters Version Bump (2026-05-19)

Two-line deploy hotfix ([#495](https://github.com/risk-sentinel/sparc/pull/495)). v1.6.5 added new `converters` seed sections but did not bump `SeedRunner::CURRENT_VERSIONS["converters"]`, so production deploys skipped the section and the new `aws_config_to_nist` Converter never appeared. Bumps `converters` `1.2.0 → 1.3.0`. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.6).

## v1.6.5 -- Decoupled AWS Converters with Refresh UI (2026-05-19)

Cleans up the v1.6.4 AWS Labs bootstrap initializer (`ApplicationRecord` autoload `NameError` + 3×-per-boot firing, [#492](https://github.com/risk-sentinel/sparc/issues/492)) and splits the v1.6.4 composite AWS converter into two first-class converters (`aws_config_to_nist`, `aws_security_hub_to_nist`) that operators can **refresh independently** from the converter management page ([#494](https://github.com/risk-sentinel/sparc/issues/494)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.5).

## v1.6.4 -- AWS Labs CDEF Bootstrap + Admin Refresh Button (2026-05-18)

Patch release delivering the operator-facing half of AWS Labs CDEF runtime ingestion ([#466](https://github.com/risk-sentinel/sparc/issues/466)). A new initializer enqueues `AwsLabsCdefRefreshJob` on the first boot where `SPARC_AWS_LABS_CDEF_ENABLED=true` and no AWS-Labs rows exist, so tenants don't wait for the weekly tick ([#487](https://github.com/risk-sentinel/sparc/issues/487)). Bundles a `faraday` security bump and a `thruster` patch. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.4).

## v1.6.3 -- Apache-2.0 License Harmonization (2026-05-18)

Legal-terms harmonization. The top-level `LICENSE` is now **Apache License 2.0**, matching what `NOTICE`, `THIRD_PARTY_NOTICES.md`, the component dispositions, and the `LICENSES/` texts had assumed since v1.6.0 — chosen for its express patent grant and NOTICE provision ([#483](https://github.com/risk-sentinel/sparc/issues/483)). Ships alongside the [#481](https://github.com/risk-sentinel/sparc/issues/481) unmapped-component triage. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.3).

## v1.6.2 -- Open-Source Readiness: License Inventory + Policy (2026-05-18)

No new app features — the infrastructure of supply-chain transparency. Consolidates three CycloneDX SBOMs into a canonical license inventory (`license-inventory.json` / `.md`), adds declarative `license-policy.yml` + per-component `license-dispositions.yml` (policy-as-code), enables Trivy `--scanners license`, and removes the only GPL-3.0 runtime dependency ([#472](https://github.com/risk-sentinel/sparc/issues/472)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.2).

## v1.6.1 -- SBOM-Driven SCA, AWS Labs CDEFs, SAF CLI Hardening (2026-05-17)

Maintenance + capability release. Adds **Grype** SBOM vulnerability scanning consuming the CycloneDX SBOMs (SARIF + HDF, [#461](https://github.com/risk-sentinel/sparc/issues/461)), hardens HDF normalization (Node 22 pin + cdxgen JSON SBOM, [#463](https://github.com/risk-sentinel/sparc/issues/463)), and clears the dependency-bump backlog with the second migration squash. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.1).

## v1.6.0 -- HDF ↔ OSCAL Translation Bridge, CMS Attestation Export & OSCAL Export Hardening (2026-05-08)

Minor release. Ships the [#449](https://github.com/risk-sentinel/sparc/issues/449) **HDF ↔ OSCAL translation bridge** — three stateless API endpoints that let tenant compliance pipelines move scan data between the HDF and OSCAL ecosystems without managing the `hdf` CLI on their side. Bundled with [#440](https://github.com/risk-sentinel/sparc/issues/440) **CMS attestation export**, [#451](https://github.com/risk-sentinel/sparc/issues/451) **OSCAL export schema-validation hardening + uniform error UX**, and [#453](https://github.com/risk-sentinel/sparc/issues/453) **OSCAL schemas baked into the container** (decouples runtime validation from NIST GitHub availability — multi-version validation now works air-gapped). **No breaking changes**; existing deployments upgrade in place.

Full release notes (with verification evidence) live on the [v1.6.0 GitHub release page](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.0).

### Highlights

- **HDF ↔ OSCAL translation bridge ([#449](https://github.com/risk-sentinel/sparc/issues/449))** — three new authenticated endpoints under `/api/v1/`:
  - `POST oscal/sar_from_hdf` — HDF results → OSCAL Assessment Results
  - `POST oscal/poam_from_hdf` — HDF results → OSCAL Plan of Action and Milestones
  - `POST hdf/amendments_from_oscal_poam` — OSCAL POA&M → HDF Amendments JSON (round-tripped through `hdf amend verify` before serving)
- **Optional Evidence back-matter enrichment** — pass `?authorization_boundary_id=N` to either OSCAL emission endpoint and SPARC merges the boundary's Evidence + Attestation records into the OSCAL output as `back-matter.resources[]` (with control-id, attestation provenance, and rlinks). Requires `evidence.read` on the boundary.
- **`hdf` binary baked into the SPARC container** — `bin/install-hdf.sh` provisions MITRE hdf-libs v3.1.0 from GitHub releases, SHA-256 verified against `checksums.txt`. Same script used by the security_gate CI job; bumping `HDF_LIBS_VERSION` updates both surfaces.
- **CMS attestation JSON export ([#440](https://github.com/risk-sentinel/sparc/issues/440))** — `Api::V1::AttestationsController#export` emits SPARC attestations in the canonical CMS / SAF CLI 6-field schema, denormalized one record per linked control_id. New `frequency` + `status` columns on `attestations` align SPARC with the upstream pattern without forking the internal model.

### Added

- `app/services/hdf_runner.rb` — Ruby subprocess wrapper centralizing all `hdf` CLI invocations (convert / validate / info / stats / amend_verify / amend_apply / version) with structured error class
- `app/services/hdf_oscal_translation_service.rb` — three translation flows + back-matter enrichment helpers
- `app/controllers/api/v1/translations_controller.rb` — public REST surface for the translation bridge
- `app/services/cms_attestation_export_service.rb` — emits CMS attestation JSON (one record per linked control)
- `app/controllers/api/v1/attestations_controller.rb` — fills the existing UI-only API gap; CRUD + `:export`
- `bin/install-hdf.sh` — single source of truth for hdf-cli install (Dockerfile + CI + local dev)
- `docs/compliance/hdf-oscal-bridge-demo.md` — pipeline-only curl demo for the translation surface

### Changed

- `Dockerfile` bakes the verified `hdf` binary into `/usr/local/bin/` via the bootstrap stage (no curl/gnupg in the production image)
- `.github/workflows/security.yml` security_gate now uses `bin/install-hdf.sh` instead of an inline curl-tar block
- `app/models/attestation.rb` gains `frequency` + `status` columns and inclusion validators
- `attestations` UI form gains frequency + status selects
- NIST mapping (CA-2, CA-7, RA-3, SI-2) updated for the new translation surface and CMS export

### Fixed (#451)

- **OSCAL export schema-validation leak** — `OscalMetadata#build_oscal_metadata` was merging the entire `metadata_extra` blob into OSCAL output. ProgressTrackable's `processing_stage` / `processing_message` / `processing_*_at` keys leaked into metadata and tripped schema validation. Switched to `slice(*METADATA_EXTRA_KEYS)` allowlist — covers every document type that includes the concern. Version-agnostic.
- **YAML/XML download 500s** — `download_yaml` / `download_xml` across CDEF, SSP, SAR, POAM, Profile, SAP, and Catalog now rescue `OscalValidationError` and redirect with a flash message that includes the `?skip_validation=1` escape hatch, matching the existing `download_oscal` UX.
- **Inconsistent error UX across views** — six index views (CDEF, SSP, SAR, POAM, Profile, SAP) replaced their inline plain-link export dropdowns with the shared `_oscal_export_dropdown` partial. The Stimulus controller's new `connect()` hook reads `?oscal_validation_failed=1&oscal_format=…` from the redirected show page and auto-opens the validation modal so direct-URL hits land in the same modal as dropdown clicks. Every human-facing path → same modal, same specific errors.

### Schema infrastructure (#453)

- **OSCAL schemas baked into the container** — new `oscal:bundle_schemas` rake task downloads all 5 supported versions (1.1.1 / 1.1.2 / 1.1.3 / 1.2.0 / 1.2.1) × 8 document types from NIST GitHub release assets at Docker build time and writes them to `lib/oscal_schemas_bundle/v<version>/<file>` plus a `manifest.json` with SHA-256 checksums. `oscal:seed_schemas` extended with three-tier fallback: bundle (offline, checksum-verified) → NIST GitHub fetch → legacy disk fallback. Air-gapped deployments validate against all 5 versions without runtime network dependency.
- **Two pre-existing bugs fixed in passing**: `OscalSchema::NIST_SCHEMA_URL_TEMPLATE` was pointing at a `raw.githubusercontent.com/.../json/schema/...` path that NIST never published — every fetch was 404'ing and silently falling back to disk; only v1.1.2 was ever loaded into the DB. URL corrected to the GitHub release-asset path. `DOCUMENT_TYPE_MAP` had `oscal_component-definition_schema.json` for component-definition; NIST publishes it as `oscal_component_schema.json` — corrected to match the validator's `SCHEMA_MAP`.

### Migrations

- `add_frequency_and_status_to_attestations` — adds `frequency` (string, nullable) + `status` (string, default `"passed"`, NOT NULL) + index on `status`. Backwards-compatible; existing rows default to `passed`.

### Verified

- `bundle exec rspec` — 2150+ examples, 0 failures, 2 pending (real-binary integration specs gated on `hdf` being on PATH)
- `bundle exec rubocop` — clean on changed files
- `bundle exec brakeman` — clean (2 ignored, 0 active)
- HDF binary install script verified against MITRE release SHA-256
- OSCAL schema bundle verified end-to-end: 37 schemas downloaded, 37 SHA-256 verified at seed time, 37 loaded into the DB

---

## v1.5.0 -- API Test Suite, Org Migration & Dependency Hardening (2026-05-04)

Minor release. Ships the comprehensive Python pytest API test suite ([#413](https://github.com/risk-sentinel/sparc/issues/413), [PR #432](https://github.com/risk-sentinel/sparc/pull/432) — 247 tests across 18 modules covering every documented endpoint), completes the GitHub org migration to `risk-sentinel` ([#430](https://github.com/risk-sentinel/sparc/issues/430)), and absorbs a wave of dependency security patches and bumps. **No breaking changes** to SPARC user-visible behavior — existing deployments upgrade in place.

Full release notes (with verification evidence and audit context) on the [v1.5.0 GitHub release page](https://github.com/risk-sentinel/sparc/releases/tag/v1.5.0).

### Highlights

- **Python pytest API test suite** — 247 tests, 18 modules, all 95 endpoints covered. Lives at `tests/api/`. ([#413](https://github.com/risk-sentinel/sparc/issues/413), [PR #432](https://github.com/risk-sentinel/sparc/pull/432))
- **GitHub org migration** — `Rebel-Raiders/sparc` → `risk-sentinel/sparc`. Workflows, cosign identity regex, cross-repo dispatch, docs, wiki, compliance CDEFs all retargeted. ([#430](https://github.com/risk-sentinel/sparc/issues/430), [PR #434](https://github.com/risk-sentinel/sparc/pull/434))
- **Security patches** — `net-imap` STARTTLS-stripping (GHSA-vcgp-9326-pqcp) + CRLF injection (GHSA-75xq-5h9v-w6px, GHSA-hm49-wcqc-g2xg) ([PR #438](https://github.com/risk-sentinel/sparc/pull/438)); `erb` defense-in-depth against `Marshal.load` of attacker-controlled ERB instances ([PR #410](https://github.com/risk-sentinel/sparc/pull/410)).
- **`jwt` major bump** — 2.10.2 → 3.1.2. SPARC's JWT consumer surface verified compatible (only one file uses the gem); new regression spec covers happy + rejection paths. ([PR #289](https://github.com/risk-sentinel/sparc/pull/289))

### Added

- Python pytest suite at `tests/api/` — request-level contract coverage for every documented endpoint, parametrized for the three auth modes ([#413](https://github.com/risk-sentinel/sparc/issues/413))
- API documentation review — Phase 1 closed: 100% endpoint doc coverage, Postman collection now covers all 95 endpoints ([#413](https://github.com/risk-sentinel/sparc/issues/413), [PR #427](https://github.com/risk-sentinel/sparc/pull/427), [PR #428](https://github.com/risk-sentinel/sparc/pull/428), [PR #429](https://github.com/risk-sentinel/sparc/pull/429), [PR #431](https://github.com/risk-sentinel/sparc/pull/431))
- API procedure document — review-and-automated-testing workflow at `docs/api/SPARC-API-Review-and-Automated-Testing-Procedure.md`
- OIDC JWT decode regression spec — closes the test-coverage gap for the live JWT happy path ([PR #289](https://github.com/risk-sentinel/sparc/pull/289))
- `.github/CODEOWNERS` — admin review required for non-admin PRs ([#435](https://github.com/risk-sentinel/sparc/issues/435))

### Changed

- Repository now lives at `https://github.com/risk-sentinel/sparc`. All cross-repo references in workflows (cosign identity regex, `repository_dispatch` target), app code, docs, wiki, and OSCAL CDEF `remarks` retargeted ([#430](https://github.com/risk-sentinel/sparc/issues/430))
- Implementation plan reorganized — Phase 12 (post-migration test/CI hardening + federation follow-ups) added with priority-ordered backlog ([PR #439](https://github.com/risk-sentinel/sparc/pull/439))

### Security

- **`net-imap` 0.6.3 → 0.6.4** ([PR #438](https://github.com/risk-sentinel/sparc/pull/438))
  - GHSA-vcgp-9326-pqcp — STARTTLS stripping (MITM could silently prevent TLS upgrade)
  - GHSA-75xq-5h9v-w6px, GHSA-hm49-wcqc-g2xg — CRLF / command / argument injection
- **`erb` 6.0.2 → 6.0.4** ([PR #410](https://github.com/risk-sentinel/sparc/pull/410)) — defense-in-depth: prohibit `def_method` on marshal-loaded ERB instances; release-tooling and packaging fixes
- **`jwt` 2.10.2 → 3.1.2** ([PR #289](https://github.com/risk-sentinel/sparc/pull/289)) — major version bump; the v3 line requires explicit algorithm on JWK verify (SPARC already passes `algorithms: ["RS256"]`), enforces RSA ≥2048 bits (Okta JWKS already meets this), and stricter base64 (RFC 4648). Audit found one consumer (`app/controllers/concerns/api_authentication.rb`); new spec covers a real RS256 token through the full decode path

### Dependencies

- `aws-sdk-s3` 1.219.0 → 1.220.0
- `aws-sdk-rds` 1.310.0 → 1.311.0
- `bootsnap` 1.23.0 → 1.24.1
- `faker` 3.6.1 → 3.8.0
- `rubyzip` 3.2.2 → 3.3.0 (in-major; only behavioral change in 3.3.0 is `Zip::InputStream` IO-compat refactor — SPARC consumers unaffected)
- `aws-sdk-core` 3.244.0 → 3.246.0, `aws-sdk-kms` 1.123.0 → 1.124.0, `aws-partitions` 1.1237.0 → 1.1244.0 (transitive)

([PR #437](https://github.com/risk-sentinel/sparc/pull/437) bundled the application-direct deps in this group.)

### Verification

Full RSpec on the merged dependency state: **2076 examples, 0 failures**. `bundle exec rubocop` clean.

---

# Legacy history (pre-v1.x reset)

> The entries below predate SPARC's adoption of the public **v1.x** release
> line. The `(unreleased)` items (2026-03) and the `v2.x`–`v3.x` versions
> were the project's earlier internal numbering. They are retained verbatim
> for traceability; their functionality is present in the current v1.x
> releases above.

## (unreleased) -- OSCAL XML Catalog Parameters & Baseline Adjustments (2026-03-11)

### Added
- **OSCAL XML catalog import** — full support for OSCAL 1.x XML serialization format alongside existing JSON and legacy SCAP XML imports; correctly parses `<param>`, `<select>`, `<choice>`, `<label>`, and `<guideline>` elements into the same `params_data` structure as JSON imports ([Issue #162](https://github.com/risk-sentinel/sparc/issues/162))
- **Parameter suggestion badges** — profile control edit form now shows clickable catalog-defined choices as quick-pick badges above the text input for selection-type parameters; users can click to fill or type custom values ([Issue #162](https://github.com/risk-sentinel/sparc/issues/162))
- **Selection info in profile show view** — read-only parameter display now shows available catalog options for selection-type parameters
- **CatalogImportService specs** — 29 new tests covering OSCAL XML format detection, parameter extraction (label, select/choice, guideline, props), enhancement recursion, and JSON regression

---

## (unreleased) -- Home Screen OSCAL Layer Alignment (2026-03-11)

### Changed
- **Home screen cards grouped by OSCAL layers** — Controls (blue), Implementation (green), Assessment (orange), and Environments (purple) with section headers and colored accent bars ([Issue #164](https://github.com/risk-sentinel/sparc/issues/164))
- **Control Mapping card added** to home screen under Controls Layer
- **Stat tiles redesigned with horizontal OSCAL layer labels** — replaced vertical truncated text badges with full horizontal labels (CONTROLS, IMPLEMENTATION, ASSESSMENT, ENVIRONMENTS) above each metric group; each group wrapped in a color-coded container with accent border and tinted background ([Issue #164](https://github.com/risk-sentinel/sparc/issues/164))
- **Unique family & control counts** — Families and Controls tiles now show distinct counts across all catalogs instead of total rows
- **Login page OSCAL diagram** updated to include Mapping Model in the Controls Layer
- **Login page branding upsized** — SPARC logo enlarged from 72px/88px to 96px/120px (mobile/desktop), Welcome heading upgraded from h4 to h3, and description text set to standard body size

### Fixed
- **Heatmap card click filtering** — clicking anywhere on a heatmap family card body now filters by that family, not just badges/links ([Issue #159](https://github.com/risk-sentinel/sparc/issues/159))
- **Family group visibility** — empty family groups are hidden when heatmap filter is active
- **Profile show page** — controls grouped by collapsible NIST families with Expand/Collapse All buttons; catalog sub-parts shown as nested implementation statements

### Added
- **NIST catalog fixture files** — Rev 4 (XML, YAML) and Rev 5 (JSON, YAML) catalog fixtures for test coverage

---

## (unreleased) -- Control Family Selection/Deselection (2026-03-10)

### Added
- **Family-level control selection** — "Create Profile from Catalog" page now groups controls by family in collapsible accordions with family-level select/deselect checkboxes, tri-state indicators, and expand/collapse all ([Issue #151](https://github.com/risk-sentinel/sparc/issues/151))
- **Baseline auto-select** — choosing a baseline level (LOW, MODERATE, HIGH) auto-checks all controls matching that impact level via a dedicated server endpoint, keeping baseline logic server-side
- **Manage Controls page** — existing catalog-linked profiles now have a "Manage Controls" button to bulk add/remove controls with parameter inheritance from the source catalog
- **Stimulus controller** — `family_selector_controller.js` replaces inline vanilla JS with proper Hotwire architecture; supports both dynamic (create) and server-rendered (manage) modes
- `profile_controls_bulk_updated` audit event action for tracking bulk control changes

---

## (unreleased) -- OSCAL Document UUID & Back Matter (2026-03-10)

### Added
- **Stable document UUID** — dedicated `uuid` column on all six OSCAL document tables (SSP, SAR, CDEF, SAP, POAM, Profile), auto-generated by Postgres `gen_random_uuid()`. OSCAL imports preserve the source document UUID. Exports use the stable column value instead of generating a random UUID each time. ([Issue #147](https://github.com/risk-sentinel/sparc/issues/147))
- **OSCAL back-matter support** — every exported OSCAL document now includes a `back-matter` section with a SPARC-identifying resource (title, description, rlink to app URL) for auditor traceability
- **Centralized back-matter logic** — `OscalMetadata` concern provides `build_oscal_back_matter` and `sparc_back_matter_resource` methods, eliminating duplicate implementations across export services
- **Round-trip back-matter fidelity** — imported back-matter resources are fully preserved and merged with the SPARC resource on export; Profile parser no longer strips resource fields
- **Parser consistency** — all six JSON parsers now store both `uuid` and `back_matter` in `import_metadata` (SAP and CDEF parsers were previously missing these)
- Missing `cdef_document_imported`, `poam_document_imported`, and `profile_document_imported` audit event actions added to `AuditEvent` whitelist

---

## (unreleased) -- User Lifecycle Enhancements (2026-03-10)

### Added
- **User UUID** — immutable UUID column for audit traceability, auto-generated by Postgres `gen_random_uuid()` ([Issue #146](https://github.com/risk-sentinel/sparc/issues/146))
- **Soft-delete (deactivate)** — admin can deactivate users instead of hard-deleting; records `deleted_at` timestamp and `inactive_reason` for audit trails
- **Reactivate with force password reset** — admin checkbox to require password change on reactivation
- **Password expiration** — local-auth users are forced to change password after configurable `SPARC_PASSWORD_EXPIRY_DAYS` (default 30); OAuth/SSO users are exempt
- **Automatic inactivity deactivation** — `InactivityCheckJob` deactivates users who haven't signed in within `SPARC_INACTIVITY_DAYS` (default 30)
- `SPARC_INACTIVITY_DAYS` and `SPARC_PASSWORD_EXPIRY_DAYS` environment variables for user lifecycle configuration
- Admin user show page displays UUID, password changed date, deactivation details, and 3-way status badge (success/warning/danger)
- Deactivated users see a specific "account has been deactivated" message at login (not generic "invalid")
- Missing `organization_*` audit event actions added to `AuditEvent` whitelist

---

## (unreleased) -- Organization Management (2026-03-10)

### Added
- **Organization entity** with UUID-based audit traceability — organizations own authorization boundaries and serve as the parent grouping unit ([Issue #145](https://github.com/risk-sentinel/sparc/issues/145), [Issue #137](https://github.com/risk-sentinel/sparc/issues/137))
- Admin CRUD interface for organizations with search, status filtering, and pagination
- Organization membership management with senior-official-pattern roles (Org Admin, Head of Agency, CIO, CISO, Risk Executive, etc.)
- Soft-delete via deactivate/reactivate — organizations are never hard-deleted, preserving UUID for audit trails
- Authorization boundaries now link to a parent organization (`organization_id` foreign key)
- `SPARC_ORG_*` environment variables for configuring the default organization name, description, address, and contact info
- Default organization seeded with admin user as org_admin

---

## v3.4.8 -- Home Screen & Navigation UX (2026-03-09)

### Fixed
- Dashboard section cards now have consistent OSCAL-layer-colored borders — Controls (blue), Implementation (green), Assessment (orange), Boundaries (purple) — with uniform hover effect ([Issue #152](https://github.com/risk-sentinel/sparc/issues/152))
- "Auth Boundaries" navbar link upgraded to dropdown showing the user's assigned boundaries with status badges and quick navigation; admins see all boundaries ([Issue #153](https://github.com/risk-sentinel/sparc/issues/153))

---

## v3.4.7 -- Control Parameters & Profile Publish (2026-03-09)

### Added
- Catalog-level OSCAL parameter definitions (`params`) extracted and stored during catalog import as `params_data` JSONB column on `catalog_controls` ([Issue #143](https://github.com/risk-sentinel/sparc/issues/143))
- Control family show view displays parameter badges and expandable parameter details (ID, label, constraint/choices)
- Catalog control edit form with editable parameter labels for organization-specific customization
- OSCAL catalog export now emits `params` array on controls when present
- Profile "Create from Catalog" inherits parameter definitions from the catalog (not empty)
- Per-parameter value editing in profile control form with save-your-work support
- **Publish** action on profiles generates a fully-resolved OSCAL catalog merging catalog data with profile modifications (priority, parameter values)
- Resolved catalog download available after publish via Export dropdown
- `OscalResolvedProfileCatalogService` for building resolved profile catalogs

### Fixed
- Delete buttons across all index views now work with Turbo (changed `link_to method: :delete` to `button_to` with `turbo_confirm`)
- Profiles index table fits viewport without horizontal scrolling (fixed-layout table with truncated names)

### Note
- Re-seed catalogs (`bin/rails db:seed`) to populate `params_data` on existing catalog controls
- Run migration for new `resolved_catalog_json` column on `profile_documents`

---

## v3.4.6 -- Fix Docker Migration Failure (2026-03-09)

### Fixed
- Removed duplicate `error_message` column addition from `AddOscalSspEntities` migration that caused `docker compose up --build` to fail on existing Postgres volumes ([Issue #140](https://github.com/risk-sentinel/sparc/issues/140))

---

## v3.4.5 -- Heatmap Removal & Environment UX Fix (2026-03-09)

### Fixed
- Removed aggregate compliance heatmap from home page -- document-level heatmaps remain on individual SSP, SAR, CDEF, SAP, and Profile pages ([Issue #136](https://github.com/risk-sentinel/sparc/issues/136))
- Renamed "Boundaries & Components" section to "Environments & Components" on authorization boundary show page for clearer terminology ([Issue #136](https://github.com/risk-sentinel/sparc/issues/136))

---

## v3.4.4 -- Authorization Boundary Rebrand (2026-03-09)

### Changed
- Rebranded "Project" to "Authorization Boundary" throughout the application -- models, controllers, views, routes, database schema, and documentation now align with NIST RMF / FedRAMP terminology ([Issue #124](https://github.com/risk-sentinel/sparc/issues/124))
- Renamed database tables `projects` to `authorization_boundaries`, `project_memberships` to `authorization_boundary_memberships`
- Renamed all `project_id` foreign key columns to `authorization_boundary_id`
- Updated role scope from `project` to `authorization_boundary`
- Updated permission keys from `projects.*` to `authorization_boundaries.*`
- Added `docs/groups_users/mindmap.md` capturing Organization to Authorization Boundary to OSCAL Artifacts hierarchy

---

## v3.4.3 -- HTTPS Enforcement & Security Headers (2026-03-09)

- Enforce HTTPS-only traffic with HSTS preload, subdomains, and 1-year max-age ([Issue #106](https://github.com/risk-sentinel/sparc/issues/106))
- Health-check endpoint `/up` excluded from SSL redirect for container probes (ALB, Kubernetes)
- Security headers middleware: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`, `X-Permitted-Cross-Domain-Policies`
- Content Security Policy enabled in report-only mode (Bootstrap CDN allowlisted)
- Centralized version constant in `SparcConfig::VERSION` — no longer hardcoded in layouts
- HTTPS enforcement and security headers test coverage

## v3.4.2 -- Hide Expected Upload Fields from Upload UI (2026-03-09)

- Removed hardcoded "Expected Format" tables from SSP and SAR upload pages ([Issue #129](https://github.com/risk-sentinel/sparc/issues/129))
- Replaced with concise import notes referencing data mapping definitions (`lib/data_mappings/`)
- OSCAL files (JSON, XML, YAML) noted as auto-detected with no mapping required

## v3.4.1 -- Full Multi-Format Support (2026-03-09)

- Full OSCAL tri-format support: import and export JSON, YAML, and XML for all six document types ([Issue #120](https://github.com/risk-sentinel/sparc/issues/120))
- Six new YAML parser services (SSP, SAR, POAM, Profile, CDEF, SAP) using delegation pattern to avoid logic duplication
- New SAP XML parser service (`SapXmlParserService`) completing XML import coverage for all document types
- OSCAL export format conversion via `OscalExportFormatService` (JSON to YAML/XML)
- OSCAL JSON-to-XML converter (`OscalJsonToXmlConverter`) with Nokogiri XML::Builder and OSCAL namespace
- XSD schema validation for XML exports via `Nokogiri::XML::Schema` with 7 OSCAL XSD schemas
- Format auto-detection service (`OscalFormatDetectionService`) with extension and content sniffing
- Bootstrap 5 split-button dropdown for OSCAL export format selection across all document views
- Upload forms updated to accept `.yaml` and `.yml` extensions
- Fixed pre-existing bug in `CdefJsonParserService#parse_oscal_cdef` (wrong method call for batch insert)

## v3.4.0 -- Robust Audit Logging (2026-03-09)

- Comprehensive audit logging with approximately 80 tracked actions across 16 categories ([PR #121](https://github.com/risk-sentinel/sparc/pull/121), [Issue #101](https://github.com/risk-sentinel/sparc/issues/101))
- Polymorphic subject tracking (`subject_type`/`subject_id`) for resource-level traceability
- Admin audit log UI at `/admin/audit_logs` with filtering, detail views, and CSV export
- `Auditable` controller concern providing a DRY `audit_log` helper method
- Structured JSON logging to `Rails.logger.info` for integration with CloudWatch/Datadog ([PR #122](https://github.com/risk-sentinel/sparc/pull/122))
- Fixed silent audit failures in `ControlMappingsController`
- Authorization failure logging for security monitoring

## v3.3.0 -- Navbar Redesign (2026-03-09)

- Redesigned navbar with OSCAL layer dropdowns organized by function:
  - **Controls** (blue) -- Catalogs, Baselines, Control Mappings
  - **Implementation** (green) -- SSP, CDEF
  - **Assessment** (orange) -- SAP, SAR, POA&M
- User avatar system with upload and remove functionality
- Version badge displayed in the navbar
- [PR #118](https://github.com/risk-sentinel/sparc/pull/118) -- Control Mapping Models

## v3.2.1 -- Bug Fix (2026-03-09)

- Fixed user dropdown menu not opening after Turbo navigation ([PR #117](https://github.com/risk-sentinel/sparc/pull/117), [Issue #116](https://github.com/risk-sentinel/sparc/issues/116))

## v3.2.0 -- RBAC Enforcement & Summary Tiles (2026-03-08)

- Full OSCAL/RMF/FedRAMP role coverage with 29 roles ([PR #115](https://github.com/risk-sentinel/sparc/pull/115))
- Restricted catalog and baseline editing to Policy Manager and Instance Admin ([Issue #99](https://github.com/risk-sentinel/sparc/issues/99))
- Summary tiles across all main sections for at-a-glance status ([Issue #103](https://github.com/risk-sentinel/sparc/issues/103))
- Added SPARC SME and Evidence Integration Engineer roles ([Issue #96](https://github.com/risk-sentinel/sparc/issues/96))

## v3.1.1 -- SSP Rebrand (2026-03-08)

- Rebranded "Controls Implementation" to "System Security Plan" throughout the application ([PR #113](https://github.com/risk-sentinel/sparc/pull/113), [Issue #97](https://github.com/risk-sentinel/sparc/issues/97))

## v3.1.0 -- RBAC Admin Screens (2026-03-08)

- User administration screen with search, suspend, and reactivate capabilities ([Issue #93](https://github.com/risk-sentinel/sparc/issues/93))
- Role administration with permission matrix editing ([Issue #94](https://github.com/risk-sentinel/sparc/issues/94))
- Authorization boundary administration with member and role management ([Issue #92](https://github.com/risk-sentinel/sparc/issues/92))
- [PR #112](https://github.com/risk-sentinel/sparc/pull/112)

## v3.0.0 -- Authentication & RBAC Foundation (2026-03-08)

- Local email/password authentication conforming to NIST SP 800-63B ([Issue #70](https://github.com/risk-sentinel/sparc/issues/70))
- OAuth support for GitHub and GitLab ([Issue #34](https://github.com/risk-sentinel/sparc/issues/34))
- OIDC support for Okta, Keycloak, and generic providers ([Issue #33](https://github.com/risk-sentinel/sparc/issues/33), [Issue #35](https://github.com/risk-sentinel/sparc/issues/35))
- LDAP authentication with bind-and-search pattern
- RBAC system with 29 seeded roles and 20 permission keys
- Login page restructure with OSCAL overview ([Issue #90](https://github.com/risk-sentinel/sparc/issues/90), [Issue #102](https://github.com/risk-sentinel/sparc/issues/102))
- Fixed local login and admin password reset flow ([Issue #91](https://github.com/risk-sentinel/sparc/issues/91))
- [PR #73](https://github.com/risk-sentinel/sparc/pull/73), [PR #104](https://github.com/risk-sentinel/sparc/pull/104), [PR #105](https://github.com/risk-sentinel/sparc/pull/105)

## v2.0.1 (2026-03-06)

- Dark mode fixes for consistent theming ([Issue #47](https://github.com/risk-sentinel/sparc/issues/47))
- Bug fixes for SSP viewing and inline editing ([Issue #41](https://github.com/risk-sentinel/sparc/issues/41), [Issue #42](https://github.com/risk-sentinel/sparc/issues/42))

## v2.0.0 -- OSCAL Full Schema (2026-03-06)

### UI & Framework
- Bootstrap 5.3 adoption for modern responsive layout ([Issue #51](https://github.com/risk-sentinel/sparc/issues/51))
- Interactive heat maps for control status visualization ([Issue #81](https://github.com/risk-sentinel/sparc/issues/81))
- Dashboard aggregate heatmap across all documents ([Issue #83](https://github.com/risk-sentinel/sparc/issues/83))

### OSCAL Compliance
- Full OSCAL schema uplift for all artifact types ([Issue #58](https://github.com/risk-sentinel/sparc/issues/58))
- OSCAL schema validation against official NIST schemas ([Issue #45](https://github.com/risk-sentinel/sparc/issues/45))
- OSCAL metadata management and inheritance ([Issue #52](https://github.com/risk-sentinel/sparc/issues/52))
- Vendor-neutral data mapping schema ([Issue #54](https://github.com/risk-sentinel/sparc/issues/54))

### Document Types
- SSP wizard, enrichment, and enhanced export ([Issue #30](https://github.com/risk-sentinel/sparc/issues/30))
- SAR creation, enrichment, and wizard ([Issue #32](https://github.com/risk-sentinel/sparc/issues/32))
- SAP creation ([Issue #28](https://github.com/risk-sentinel/sparc/issues/28))
- POA&M import and management ([Issue #27](https://github.com/risk-sentinel/sparc/issues/27), [Issue #29](https://github.com/risk-sentinel/sparc/issues/29))
- Component Definition (CDEF) support

### Other
- Evidence and attestation collection ([Issue #31](https://github.com/risk-sentinel/sparc/issues/31))
- Authorization boundary orchestration with RMF roles ([Issue #46](https://github.com/risk-sentinel/sparc/issues/46))
- Document duplication ([Issue #56](https://github.com/risk-sentinel/sparc/issues/56))
- Control catalog and family CRUD ([Issue #48](https://github.com/risk-sentinel/sparc/issues/48), [Issue #49](https://github.com/risk-sentinel/sparc/issues/49))
