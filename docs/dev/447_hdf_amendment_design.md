# #447 — HDF Amendment translation/UI layer — Design Pass

**Status:** DRAFT for review (satisfies the umbrella's "design doc reviewed and approved before implementation begins" gate).
**Author:** design pass, 2026-07-25.

## 1. Goal (unchanged from umbrella)

Make SPARC the **translation engine + human-in-the-loop UI** for HDF Amendment
dispositions on tenant CI/CD scanner findings. Tenant uploads HDF scanner output →
triages failed controls in SPARC's UI → SPARC emits per-boundary HDF Amendments
JSON their pipeline consumes via `hdf amend apply`. **SPARC is a translation
artefact store, not the system of record** — dispositions are re-derivable from
tenant inputs; nothing SPARC-only gets trapped.

## 2. What already exists (reconciliation — the umbrella predates this)

The umbrella lists the primitives as "already have," but the picture is richer:

| Primitive | State | Relevance |
|---|---|---|
| `HdfOscalTranslationService` + `Api::V1::TranslationsController` (#449/#663) | **Exists, STATELESS** | Already does HDF→SAR, HDF→POAM, **OSCAL POAM ↔ HDF Amendments** as `hdf convert` pass-through, with Evidence back-matter enrichment. |
| `HdfRunner` | Exists | Wraps the pinned `hdf-cli` binary (currently 3.4.1). Reuse for ingest parsing/validation. |
| `bin/sparc_findings_to_hdf_amendments.rb` | Exists, proven in CI (#244) | The export contract + severity-cadence policy, already targeting **Amendments schema v3.4.0**. Database-back it as `HdfAmendmentExportService`. |
| `Attestation` | Exists w/ `role`, `frequency`, `signature_hash`, `status` (#440 CLOSED) | Provenance for `falsePositive`/`waiver`. Dependency is RESOLVED. |
| `Evidence` | Exists (boundary-scoped, `file_hash`, `evidence_type`, `status`) | Justification artefact for FP/waiver. |
| `PoamFinding` / `PoamDocument` | Exists | Link target for the `poam` override. |
| `AuthorizationBoundary` | Exists (org + profile scoped, slug, uuid, status) | The scoping unit. |
| `RiskAssessment` | **MISSING → build in v1** (D1 resolved) | link target for `riskAdjustment`. |

**Framing takeaway:** #447 is NOT re-implementing translation. It adds a
**persistent triage layer** on top of the existing stateless translator:
*ingest → persist findings → human disposition → export DB-backed dispositions.*
The stateless `TranslationsController` stays; the new layer is where a human
decision and its provenance live between a scan and its amendment.

## 2b. hdf-cli / schema reconciliation (verified against upstream 2026-07-25)

Checked mitre/hdf-libs `hdf-schema` + `hdf-cli` READMEs against our pins.

**Version: NO drift.** Upstream schema is **v3.4.0**; we pin **hdf-cli 3.4.1**
(`install-hdf.sh` + `HdfRunner::PINNED_VERSION`) and our translator targets v3.4.0.
`SPARC_HDF_ALLOWED_VERSIONS` allowlist already guards forward-compat.

**Drift is in FEATURE AWARENESS, not version.** The `amend` workflow grew well
beyond the static YAML→JSON pattern `bin/sparc_findings_to_hdf_amendments.rb` proved:

| `hdf amend` subcommand | What it does | `HdfRunner`? | Use in #447 |
|---|---|---|---|
| `amend apply` | merge amendments into results, sets **`effectiveStatus`** | ✅ `amend_apply` | roundtrip demo |
| `amend verify` | schema + expiration + **chain-integrity** check | ✅ `amend_verify` | **validate our export** (don't hand-roll) |
| `amend create` | generate waiver/attestation/POA&M docs | ❌ | see D5 (build-vs-delegate) |
| `amend draft` | **scaffold amendment from a results file** | ❌ | optional ingest accelerator (seed triage list) |
| `amend list` | list amendments w/ status/expiration | ❌ | optional (parity view) |
| `amend set` | modify top-level amendment fields | ❌ | not needed |

**Schema deltas to absorb:**
- **7th override type `vendorDependency`** (POAM family, added v3.1.0) — our design
  and the CI script both miss it. Add to the kind enum.
- `exception` was **removed** upstream → use `waiver` + `status: notApplicable`
  (we never emitted `exception`, so no migration needed).
- v3.4.0 **breaking**: `sbom`/`sbomRef`/`sbomFormat` → generalized **`boms[]`**.
  Affects HDF *results* shape; our `ScannerFinding.raw_hdf` stores the control
  slice verbatim, so impact is limited to any code that reads SBOM refs — we're
  already on the `boms[]` world via the 3.4.1 pin.
- `amend apply` writes **`effectiveStatus`** (not `status`) on the amended result
  — the field the tenant's threshold gate reads. Name it correctly in the demo.

**New CLI adjacencies (out of scope, noted):** `hdf system` (manages
authorization boundaries/components — potential future overlap with SPARC's
`AuthorizationBoundary`), `hdf fetch` (pulls aws-securityhub/gitlab/sonarqube/
splunk — adjacent to #491 Security Hub→NIST), `hdf evidence` (bundle for audit).

## 3. Data model (net-new)

Grounded in existing SPARC conventions (`uuid` via `gen_random_uuid()`, `slug`
FriendlyId, `status` string enums, `*_data` jsonb, boundary FK scoping).

### `ScanRun` — one ingest event
```
scanner            :string  null:false   # "trivy", "brakeman", "gitleaks", ...
scanner_version    :string
authorization_boundary_id :bigint null:false  # scope
ingested_at        :datetime null:false
finding_count      :integer default:0
passed_count / failed_count / skipped_count :integer
source_filename    :string
raw_hdf_digest     :string               # sha256 of uploaded bundle (idempotency)
uuid / slug        :string (unique)
created_by         :string
```

### `ScannerFinding` — one control result (translation state, re-uploadable)
```
scan_run_id        :bigint null:false
authorization_boundary_id :bigint null:false   # denormalized for scoping queries
control_id         :string null:false    # HDF control id (e.g. CVE-…, rule id)
status             :string null:false     # passed|failed|skipped|error|notApplicable
severity           :string                # CRITICAL|HIGH|MEDIUM|LOW|INFORMATIONAL
title / desc       :text
scanner            :string
raw_hdf            :jsonb default:{}       # the control's HDF slice (translation cache)
uuid               :string (unique)
index: [authorization_boundary_id, control_id]  # idempotent re-ingest key
index: [scan_run_id]
```
Idempotency: re-ingest of the same `(boundary, control_id)` UPDATES the current
finding + repoints to the latest `scan_run`; it does not duplicate. Dispositions
attach to `(boundary, control_id)`, not to a specific scan_run, so they survive
re-scans (and naturally drop from export when the control_id stops appearing).

### `FindingDisposition` — the human decision SPARC translates
```
authorization_boundary_id :bigint null:false
control_id         :string null:false    # binds to the finding by (boundary, control_id)
kind               :string null:false     # falsePositive|waiver|poam|inherited|riskAdjustment|operationalRequirement
reason             :text   null:false
expiration         :datetime              # required for waiver/operationalRequirement
linked_subject     :polymorphic (type,id) # Evidence | PoamFinding | AuthorizationBoundary | (RiskAssessment?)
signature_hash     :string                # provenance over tenant-supplied inputs
decided_by         :string null:false
decided_at         :datetime null:false
uuid               :string (unique)
index: [authorization_boundary_id, control_id] unique  # one active disposition per finding
```

### `RiskAssessment` — link target for `riskAdjustment` (new in v1, D1)
```
authorization_boundary_id :bigint null:false   # scope
title              :string null:false
original_severity  :string null:false    # CRITICAL|HIGH|MEDIUM|LOW|INFORMATIONAL
adjusted_severity  :string null:false     # must be strictly lower than original
rationale          :text   null:false
methodology        :string                # e.g. "CVSS environmental", "NIST 800-30"
assessed_by        :string null:false
assessed_at        :datetime null:false
expiration         :datetime              # re-assessment cadence
evidence_id        :bigint                # optional supporting Evidence
uuid / slug        :string (unique)
```
Deliberately lightweight — a downgrade record with provenance, not a full RA-3
assessment engine. Validation: `adjusted_severity` must rank below
`original_severity` (reuse the severity ordering from the #244 policy).

## 4. Override-type rules (the triage contract)

Reuse the #244 policy (CRITICAL bans waiver/FP; per-severity review windows) —
now enforced in the model/service, not just the CI script.

| kind | Required linkage | Extra validation | HDF status |
|---|---|---|---|
| `falsePositive` | Evidence (+ Attestation) | not on CRITICAL unless documented | notApplicable |
| `waiver` | Attestation role=`authorizing_official` + `expiration` | banned on CRITICAL | notApplicable |
| `poam` | existing `PoamFinding` (link, don't create) | — | failed |
| `vendorDependency` | existing `PoamFinding` (POAM family) | — | failed |
| `inherited` | upstream `AuthorizationBoundary` | — | notApplicable |
| `riskAdjustment` | `RiskAssessment` (new model, D1) | severity downgrade rationale | failed (adjusted) |
| `operationalRequirement` | Attestation role=`authorizing_official` | `expiration` | failed |

The complete v3.4.0 override enum is these 7 (`exception` removed upstream).

## 5. Services

- **`HdfIngestService`** (translation IN): parse uploaded HDF JSON (single or
  `saf convert` bundle) via `HdfRunner`/direct JSON, upsert `ScanRun` +
  `ScannerFinding` records idempotently, scoped to a boundary. Reject non-HDF /
  malformed via existing `XmlSecurity`-style guardrails (JSON here, so schema-shape
  guard + size cap).
- **`HdfAmendmentExportService`** (translation OUT): database-backed port of
  `bin/sparc_findings_to_hdf_amendments.rb`. **Hybrid (D5):** hand-emit the
  Amendments JSON from DB dispositions — deterministic (stable ordering, uuid
  seeded from disposition content so re-export is cache-pinnable) — then run it
  through `HdfRunner#amend_verify` before returning. We own determinism; upstream
  owns schema + chain-integrity + expiration validation, so schema drift surfaces
  as a failing verify rather than a silently-malformed artefact.
- **Reuse, don't rebuild:** `amend_verify` and `amend_apply` already exist on
  `HdfRunner`. The end-to-end demo (§8 slice 6) is achievable with current
  plumbing. `amend draft`/`amend create`/`amend list` are NOT yet wrapped — add
  only if a slice needs them (draft as an optional ingest accelerator).

## 6. API surface (API-first, per project convention)

All under `Api::V1::`, auth-token scoped per `AuthorizationBoundary`:
- `POST /api/v1/authorization_boundaries/:id/scan_runs` — ingest HDF (multipart)
- `GET  /api/v1/authorization_boundaries/:id/scanner_findings?status=failed` — list
- `POST /api/v1/scanner_findings/:id/disposition` — create/update disposition
- `DELETE /api/v1/finding_dispositions/:id`
- `GET  /api/v1/authorization_boundaries/:id/hdf_amendments` — export (the artefact tenant CI pulls)

UI is a thin client over these (triage list → disposition form → linkage picker →
export button). New routes/pages get Playwright ui-smoke coverage per convention.

## 7. Decisions (RESOLVED)

- **D1 — `riskAdjustment` link target.** RESOLVED: **v1 ships all 7 override types
  + a new lightweight `RiskAssessment` model** (§3). No generic-Evidence stopgap.
- **D2 — Schema version.** RESOLVED (§2b): **v3.4.0 / hdf-cli 3.4.1** (no drift).
  Add `vendorDependency`; note `boms[]` / `effectiveStatus`.
- **D3 — Delivery shape.** RESOLVED: **one branch, one PR** closing #447. Design
  doc = first commit; each slice = its own stacked commit in the same PR
  (stack-commits-one-PR pattern). Full rspec + rubocop green per commit.
- **D4 — Sub-issues.** RESOLVED: no separate GitHub sub-issues — the umbrella
  #447 is the tracking unit; slices are commits.
- **D5 — Export build-vs-delegate.** RESOLVED: **hybrid** — hand-emit deterministic
  JSON, validate via `HdfRunner#amend_verify`.

## 8. Slice plan (commits in one PR closing #447)

- **C0 — Design pass** (this doc → `docs/dev/`).
- **C1 — Models + migrations** — `ScanRun`, `ScannerFinding`, `FindingDisposition`,
  `RiskAssessment` + indexes + factories + model specs.
- **C2 — Ingest service + API** — `HdfIngestService`, ingest + list endpoints,
  idempotency, request specs.
- **C3 — Disposition service + API** — validation rules table (§4) incl. all 7
  kinds + severity policy, linkage, provenance hash; request specs.
- **C4 — Export service + API** — `HdfAmendmentExportService` (hybrid hand-emit +
  `amend_verify`), deterministic; request specs + roundtrip test.
- **C5 — Triage UI** — list/disposition/linkage/export; Playwright ui-smoke + a11y.
- **C6 — Compliance docs** — NIST CA-7/RA-3/RA-5/SI-2/SA-11 mapping, CDEF entry,
  end-to-end demo (upload → triage → export → `hdf amend apply` → `saf validate
  threshold`). VERSION bump in this same PR.

## 9b. Successor epic — #809 (v1.14.0)

#447 is the **export** direction (tenant triages → SPARC emits Amendments for
their CI). The reverse direction — consumers **send** SPARC HDF evidence *with*
amendments and SPARC **aggregates** it into their SSP / SAP / SAR / POA&M at the
appropriate function, plus packaging the aggregated result back to the customer —
is tracked separately in **#809**, targeted at **v1.14.0**. Out of scope here, but
the persistence layer in this PR (`ScanRun` / `ScannerFinding` / `FindingDisposition`
/ `RiskAssessment`, boundary-scoped) is designed so #809 can consume it without a
schema rewrite.

## 9. NIST controls touched
CA-7 (continuous monitoring), RA-3 (risk assessment), RA-5 (vuln scanning),
SI-2 (flaw remediation), SA-11 (developer testing), AU-12 (audit on disposition),
AC-3 (boundary-scoped authz). CDEF + inline control comments per issue_rules.
