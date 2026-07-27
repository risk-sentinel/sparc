# #809 + #811 — HDF aggregation + scan/CDEF association + re-occurrence lifecycle — Design Pass

**Status:** DRAFT for review (satisfies the "design doc reviewed and approved before implementation" gate on BOTH #809 and #811).
**Author:** design pass, 2026-07-26. One branch / one PR / stacked commits (per #447).

## 1. Why these two together

#811 is the **foundation** for #809. #447 shipped: ingest scanner findings per boundary → triage → export HDF Amendments. To make that production-real and reverse it into the document set:

- **#811 Part 1** binds a scan (and its findings) to the **target/CDEF + component** it came from — the missing key that lets everything aggregate *by CDEF/target, not by document type* (maintainer note).
- **#811 Part 2** adds the **re-occurrence lifecycle** — carry-forward, re-failed-after-mitigation, expiry→re-approval, drift — which needs **scan history** (today we keep only the current finding per `(boundary, control_id)`).
- **#809** consumes all of that: aggregate into **SSP / SAP / SAR / POA&M**, with an **amendment approval flow** (creator + approver, RBAC-configurable) and an **ODP-timeline/active-POA&M validity rule**, then **package** a signed bundle back to the consumer.

## 2. Current foundation (on main, from #447)

- `ScanRun` (boundary-scoped; `raw_hdf_digest` only — **no file persisted, no CDEF/target link**).
- `ScannerFinding` — **unique per `(boundary, control_id)` = current only, no history**, no component link, no lifecycle status.
- `FindingDisposition` — `decided_by` (creator), `signature_hash`; **no approver / approval state**; 7 override kinds; `hdf_status` mapping.
- Services: `HdfIngestService`, `FindingDispositionService`, `HdfAmendmentExportService`. Triage UI + API (`scan_runs`, `scanner_findings`, `finding_dispositions`, `hdf_amendments`).
- Reusable: `HdfOscalTranslationService` (HDF→OSCAL SAR/POAM), `SparcKeyDerivation` + `FederationBundleSigningService` (#372 signing), `#680` durable artifact resolver, CDEF document = the component-definition unit (`ssp_components.cdef_document_id`).

## 3. Schema changes

### `ScanRun`
- `+ cdef_document_id :bigint` (nullable FK) — the target/CDEF the scan ran against. Boundary-wide scanners (AWS Config) leave it null; their findings tie to components at triage.
- `+ has_one_attached :file` (ActiveStorage) — persist the **original scan file** as a durable artefact (#680/#811 Part 1), not just parsed `raw_hdf`. Optionally mirror to an `Evidence` record for back-matter.
- `+ scanner_scope :string` — `"target"` (CDEF/target-specific: trivy, secrets) vs `"boundary"` (AWS Config); drives finding→component mapping.

### `ScannerFinding`
- `+ component_ref :string` — component identity (purl / image digest / hostname) the finding affects (D4).
- `+ source_location :string` — the source file / location the finding points at (D4).
- `+ cdef_document_id :bigint` (nullable) — resolved impacted CDEF/component.
- `+ lifecycle_status :string` — `new | carried_forward | re_failed | expired | superseded` (distinct from raw HDF `status`).
- **History (D1 — per-scan rows + current flag):** relax the `(boundary, control_id)` unique index; findings become per-`scan_run` rows, each with `current :boolean`. "Current" = the latest scan_run's finding per `(boundary, control_id)` (partial unique index on `current=true`). Full history retained → N-vs-N-1 diff for the lifecycle.

### New: `RemediationTimeline` (admin SLA table, D3)
- `baseline_level :string` (Low/Moderate/High), `criticality :string` (NIST 6), `days :integer`, uniqueness on `(baseline_level, criticality)`. Admin-managed (screen + API); seeded defaults.

### `FindingDisposition`
- `+ approval_status :string` — `draft | approved | rejected` (default draft).
- `+ approved_by :string`, `+ approved_at :datetime` — the approver (creator = existing `decided_by`); signature covers both.
- `+ valid_until :datetime` / validity metadata — ODP-timeline result (D3).

### New: aggregation link
- `DocumentFindingAggregation` (or reuse Evidence/back-matter) — records which finding/disposition informed which control field in which target document (SSP/SAR/POA&M), for idempotent re-aggregation + audit + roundtrip.

## 4. Re-occurrence lifecycle (on re-ingest)

For each `(boundary, control_id)` in a new scan, compared to the prior current finding + its disposition:
- **carried_forward** — still-failing, a valid non-expired disposition exists → carry it, mark finding `carried_forward`, **audit** (not silent).
- **re_failed** — was dispositioned `poam`/mitigated (or passing) and now fails / worsens severity → `re_failed`, surfaced as a regression signal; disposition validity reconsidered.
- **expired** — disposition `expiration`/`valid_until` passed → `expired`; routes to **re-approval** (AO re-attestation) instead of suppressing.
- **drift** — severity or `component_ref` changed → flag for re-triage.
- **superseded** — control no longer in the latest scan → drops from export (as today).

## 5. Amendment validity (ODP timeline / active POA&M) — #809 persistence rule

An amendment (disposition) is **persisted/applied only if**:
1. it remediates within the **ODP timeline of impact**, **or**
2. an **active POA&M** addressing the control part / CDEF is still active (sufficient evidence). Lookup: `PoamFinding`/`PoamItem` linked to the boundary+control that is open/active.

Otherwise the disposition is flagged invalid (needs POA&M or re-mediation) and excluded from the applied amendment.

### ODP timeline source (D3, resolved)
The remediation window comes from **the profile the boundary uses** (its ODP values for the control). **Absent an ODP value**, fall back to an **admin-provisioned remediation-timeline (SLA) table** — a new `RemediationTimeline` model + admin screen + API controllers:
- Keyed by **profile baseline_level** ∈ `Low | Moderate | High` × **criticality** ∈ NIST `Critical | High | Moderate | Low | Informational | Unknown` → **days**.
- The Instance Admin provisions/edits the table (seeded with sensible defaults). `RemediationTimelineService.window_for(boundary:, control_id:, severity:)` resolves: profile ODP first, else the SLA table by `(profile.baseline_level, criticality)`.

## 6. Approval flow (#809; RBAC per maintainer clarification)

- Disposition carries **creator + approver**, both bound in `signature_hash`.
- Approve/reject is a new action gated by an **`amendment.approve` permission** the **Instance Admin assigns to roles** via existing RBAC (the Role catalog + permission map). The full RBAC role-wiring UI can be a **follow-up issue** (D5); this PR ships the approval *state*, the permission check, and the signing.

## 7. Aggregation into SSP / SAP / SAR / POA&M — #809 core

**Trigger ("appropriate function") — D2.** Recommend a **background aggregation job** (per boundary, keyed by CDEF/target) **plus** an explicit "Aggregate now" action; on-upload aggregation is viable now that the scan records its CDEF/target.

Per target type (idempotent, mirroring the `(boundary, control_id)` upsert into the document layer):
- **SAR** — assessment results: persisted, document-linked `HdfOscalTranslationService` output (HDF→OSCAL SAR).
- **POA&M** — failed/deferred findings + `poam`/`vendorDependency` dispositions → tracked `PoamFinding`/`PoamItem`.
- **SSP** — implementation-status / control-satisfaction signals from passing controls + dispositions.
- **SAP** — planned assessment coverage informed by the scan surface.

## 8. Packaging back to the consumer — #809 goal 2 (D6)

Signed **evidence + amendments** bundle (reuse `FederationBundleSigningService` / `SparcKeyDerivation` #372 + #680 durable artifact) the consumer can archive / feed downstream. **Candidate to defer to a follow-up** if the PR gets too large.

## 9. API / UI / User Guides / Playwright (explicit ask)

- **API:** ingest accepts `cdef_document_id` + persists the file; endpoints for aggregate-now + status, disposition approve/reject, component-filtered findings, (packaging export).
- **UI (triage screen):** target/CDEF selector at ingest; **component column + filter/group**; **lifecycle badges** (`re_failed` regression alert); **approve/reject** disposition actions; **Aggregate** action + per-target status.
- **User Guides:** extend `wiki/User-Guide-HDF-Amendment-Triage.md` (target selection, components, lifecycle, approval, aggregation) + **refreshed Chrome screenshots**; verify in-app Help Center.
- **Playwright:** extend `tests/ui-smoke/test_hdf_triage.py` (target selector, component filter, lifecycle badge, approve, aggregate; zero CSP).

## 10. Slice plan (commits in one PR)

- **C0** design pass (this doc).
- **C1** schema + models: scan→CDEF + file persistence + finding component/lifecycle + **history** + disposition approval/validity (migrations, factories, model specs).
- **C2** ingest: record CDEF/target, persist file, compute lifecycle on re-ingest (carry-forward / re_failed / expired / drift) + service specs.
- **C3** disposition approval + ODP-timeline/active-POA&M validity + API + request specs.
- **C4** aggregation service + job (SAR/POA&M first, then SSP/SAP) + API + specs.
- **C5** packaging bundle + API + specs *(defer per D6 if needed)*.
- **C6** UI (target selector, component filter, lifecycle badges, approval, aggregate) + Playwright + a11y.
- **C7** docs + guides + Chrome screenshots + NIST mapping (CA-7/RA-5/SI-2/CA-5-POA&M/AU-10/AU-12) + VERSION.

## 11. Decisions (RESOLVED)

- **D1 — scan history:** per-`scan_run` finding rows + a `current` boolean (full history; N-vs-N-1 diff).
- **D2 — aggregation trigger:** background job (per boundary/CDEF) + explicit "Aggregate now" action.
- **D3 — ODP timeline:** the boundary's profile ODP first; **absent it, an admin-provisioned `RemediationTimeline` SLA table** (baseline_level × NIST criticality → days) with a new admin screen + API.
- **D4 — component identity:** CDEF link + `component_ref` + `source_location` (framework, no first-class Component model).
- **D5 — approval RBAC:** ship approval state + `amendment.approve` permission now; defer the Role-assignment UI to a follow-up.
- **D6 — PR scope:** include the signed packaging bundle in this PR.

Slice plan updated: **C1** adds `RemediationTimeline`; a new **C-admin** slice adds the SLA admin screen + API; **C5** (packaging) is IN.

## 12. NIST controls
CA-7 (continuous monitoring), RA-5 (vuln scanning), SI-2 (flaw remediation), CA-5 (POA&M), RA-3 (risk), AU-10 (creator+approver signatures), AU-12 (lifecycle/aggregation audit), AC-3 (boundary/RBAC).
