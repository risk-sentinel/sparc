# SPARC Open GitHub Issues -- Implementation Strategy

Structured, prioritized roadmap for the open issues in the SPARC
GitHub repository.

**Last updated:** 2026-10-17 — **v1.17.2 planned in bundles AP–AT, tag by 2026-10-24** (owner); #1223 moved to v1.17.2; OIDC sign-in in Chrome joins the local gate (PR #1225); #1224 (publish gate) on v1.17.2, worked last; #1223 filed. Before that, 2026-10-16 — **v1.17.1 shipped 2026-10-16** (tag on `cfa7935f`, PR #1219): OIDC sign-in on json 3 (#1217), Rev 5 parameter ids and worksheets (#1218), image findings and hdf-libs 3.7.2; the planned v1.17.1 wave moved to **v1.17.2** (owner); milestone counts re-measured after the tag

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


## Phased Roadmap

> **Phases 1–18 have shipped and are archived in
> [`implemented.md`](implemented.md)**, together with the per-bundle detail and
> the original theme checklist. They were moved on 2026-08-24 because the great
> majority of what this file referenced was already closed, so most of it was
> history and the live work was buried inside it. Nothing was deleted — look
> there for why a decision was made. (The "248 of 282" figures this note used to
> quote were stale; see *Open work* below for the measured counts.)
>
> **The most recent shipped phase is 18 — v1.16.1, tagged 2026-09-17**, followed by
> the v1.16.2 / v1.16.3 hotfix pair on 2026-09-18. Phase 19 shipped as **v1.17.0**
> on 2026-10-02; v1.17.1 (hotfix) on 2026-10-16; v1.17.2–v1.17.4 on 2026-10-26/27.
> **The current work is the v1.17.5 patch**, below.
> Phases 17 and 18 moved there on **2026-09-27**, with a record of that hotfix
> pair; their bundle detail, the Bundle Z sweep record and the cadence
> re-measures are there, unedited.


---

### Patch: `v1.17.5` — SSP items answered in full, ATO wizard defaults, CDEFs under many baselines

Plan approved by the owner on 2026-10-27; one branch (`feature/v1175_bundle`), one PR.
v1.17.2–v1.17.4 shipped 2026-10-26/27. The navigation refactor moved from
`1.17.5-rf` to `1.18.0-rf` the same day (owner).

| Issue | What | Decisions (owner, 2026-10-27) |
|---|---|---|
| **#1312** | Every SSP item that takes a response (no item below it, at any depth) sets its own answer, implementation status, control origination, responsible roles, expected completion and remarks in the control's Edit form; lead-ins are headings; SP 800-53A objectives under each item with the SAR's determination read-only. SAR known findings per Planned/Partial item; SAP, SAR context, HDF designations and dashboard read the items. Deferred data migration copies the control-level values down. | OSCAL's five statuses, `partial` kept; Will Not Implement → Alternative, which is not a known finding; drop control application and coverage level; responsible entities → responsible roles; expected completion in remarks; no author status on objectives; control-level rows kept until v1.18.0 |
| **#1101** | ATO wizard starts from the boundary: settled baseline as context (a chosen one becomes the boundary's), linked CDEFs listed, each document step on the boundary's one current document. Fixed while there: the create-new fields never reached the server, and the wizard's new SSP/SAR failed (boundary required at create since #952). | The wizard saves a chosen baseline to a boundary that has none |
| **#1089** | CDEF ↔ baselines join table; `profile_document_id` kept as a mirror until v1.18.0; controls built from a baseline name it as their source (backfilled), so the export does not change; membership against all linked baselines; add/remove on the web and API. | Resolved when ≥1 baseline is linked or every control names its source |
| **#1206** | `docs/c4/components.yml` in sparc-iac's descriptor schema, checked against `SparcConfig::VERSION` and the code it names. | — |

**Owed to v1.18.0:** drop `ssp_control_fields` rows for the retired fields, and `cdef_documents.profile_document_id`.

---

### Hotfix: `v1.17.1` ✅ SHIPPED 2026-10-16 — OIDC sign-in (#1217), Rev 5 parameter worksheets (#1218)

PR #1219, merged and tagged on `cfa7935f`; both issues closed. Gated locally on the prod
UBI image for arm64 and amd64 (API, Chrome, Okta in a real browser), CI green on the
merge commit before the tag.

**OIDC sign-in fails on v1.17.0** (reported against Okta, 2026-10-16). v1.17.0
took json 3.0.2 (#1210); faraday 2.14.3's JSON response middleware passes
`JSON.parse` a positional options hash, which json 3 rejects, so every IdP
response read by `openid_connect` / `swd` / `rack-oauth2` raised — discovery
first. Fix: faraday 2.14.4 (floor in the Gemfile) and
`spec/initializers/omniauth_oidc_json_parsing_spec.rb`, which runs the IdP's
discovery, JWKS and token responses through the gems' real HTTP stack (red on
2.14.3). No migrations. sparc-iac deploys and tests it in the deployment.

**Folded in (owner, 2026-10-16): Rev 5 parameter worksheets and ids (#1218).** A
Postman user bulk-updating a Rev 5 profile sent `ac-1_prm_2`, the Rev 4-style id
NIST kept as an `alt-identifier` on `ac-01_odp.03`, and got "Unknown parameter
ID"; the API docs and Postman examples taught exactly those Rev 4 ids. The API
now resolves an `alt-identifier` to the parameter that declares it
(`resolved_aliases`), shows `alt_identifier` in the schema, and treats `null` as
"not provided" (skipped, not cleared — a behaviour change). `docs/api/samples/`
gains worksheets for the Rev 5 catalog and the LOW / MODERATE / HIGH baselines,
generated by `bin/rails samples:odp_worksheets` (`OdpWorksheetBuilder`) and
proven against profiles built the way the seeds build them. The user's second
report, a "published" refusal on an `in_progress` profile, reproduced as a
request sent to a published NIST baseline (profiles 1/2), not the draft in their
list: the 422 is correct, and the docs now say to check `lifecycle_status`
rather than `status`. **Left for v1.17.2:** a guard on aggregate parameters
(`ac-1_prm_1`), and a 422 that today also means "the valid entries were stored".

**Folded in (owner, 2026-10-16): image findings and hdf-libs 3.7.2.** The
release rescan (grype DB built 2026-10-16) found 3 Critical / 25 High on v1.17.0
and v1.17.1 alike, which the live grype-container gate (High, max 0) would fail
on: Go stdlib in the `hdf` binary (go1.26.6), x/text GO-2026-6629, and pcre2.
Taken: UBI 10 digest 552f8cc1, hdf builder on golang 1.26.9 with an x/text
floor of v0.41.0 (the owner approved the matching `security.yml` values), and
hdf-libs 3.7.2 (owner, for its upstream fixes; schema unchanged; its Go
workspace resolves x/text to v0.42.0, which clears GO-2026-6629). One High
remains, gnutls CVE-2026-88647 (not-fixed, nothing loads it), registered as
deferred; the owner approved its deviation on the PR. See
`docs/security/SCANNER_FINDINGS_AUDIT.md`.

> **Milestones moved 2026-10-16 (owner):** the 13 issues planned for `v1.17.1`
> moved to a new **`v1.17.2`** milestone, so `v1.17.1` holds only #1217. The
> v1.17.1 wave keeps its scope under the new name; where this file or the
> collision plan says "v1.17.1" about that work, read v1.17.2.

---

### Phase 20: `v1.17.2` — the deferred wave, in bundles (target: tag by 2026-10-24)

**Owner, 2026-10-17:** work v1.17.2 in bundles and land it in about a week.
The milestone holds **16 open issues** (re-measured 2026-10-18): #1046 #1063
#1087 #1104 #1107 #1120 #1131 #1133 #1176 #1196 #1203 #1207 #1208 #1223 #1224 #1228.

**#1228 joined on 2026-10-18 (owner):** NIST fixed SA-15(13), SA-24 and
SI-02(07) on `usnistgov/oscal-content`'s `develop` branch (their PRs #345,
#346, #347), unreleased. SPARC's bundled catalog carries all of those errors,
including SA-15(13) showing SA-15(12)'s requirement. The owner's call: take
the `develop` content now, flagged as pre-release, so the switch to NIST's
release is caught when it ships, and add catalog integrity checks (label names
its own control, `assessment-for` stays inside its own control,
`activity-uuid` / `task-uuid` resolve). It needs a deferred data migration.
**Bundle (owner, 2026-10-19): its own bundle, right after AR** (row below).

**Fifteen issues do not fit in a week as filed.** Several are large on their own:
- #1203 is a design to validate against NIST before any code.
- #1176's ask is IdP-brokered credentials.
- #1063 is a read-every-test audit.
- #1133 is 191 findings.
- #1120 is 125 variables.

The plan below lands every issue in one of three ways: **fixed**, **scoped to a
deliverable that fits** (the remainder filed as a follow-up), or **decided**
(a recorded decision, no code). Which issues take which path is the owner's
call, listed under *Decisions* below; the bundles assume the recommended answer.

**Ordering rules:**
- One gate stack at a time, so the bundles run one after another, each its own PR.
- Every PR runs the local gate, which now includes OIDC in Chrome (PR #1225).
- **AT (#1224) is last** (owner, 10-17). By then AP to AS give it four PR cycles of the OIDC check on the local gate.
- Collision constraint: AQ and AR both edit `app/models/sparc_config.rb`, so AR's #1120 work starts after AQ merges.

<!-- markdownlint-disable MD013 -->

| Bundle | Issues | Delivers | Est. | Window |
| --- | --- | --- | --- | --- |
| **AP — Correctness on the data path** | **#1208** **#1223** **#1107** **#1131** | **Plan approved (owner, 2026-10-18).** Order: #1131, #1107, #1208, #1223. **Merged 2026-10-19: PR #1229 closed all four.** #1131 also found that props inside parts were never checked (fixed in the same walk). **#1107:** the fix shipped in PR #1110 (2026-09-10); AP adds the acceptance tests and closes it. **#1208 (option C, owner 2026-10-18):** an overdue POA&M risk converts. Measured first: hdf 3.7.2's `amend verify --json` separates expiry from schema, invalid-override and chain failures, and `hdf amend apply` itself refuses any document holding an expired amendment. So the endpoint returns the CURRENT amendments by default (it still applies cleanly) and reports the overdue ones in a response header and the audit event; `?include_overdue=true` returns the full document, documented as one `amend apply` refuses. Structural faults are still refused. **#1223 (revised plan, owner 2026-10-18):** the loop is the entrypoint: every `bin/rails` task boot (`db:prepare`, `db:reconcile_schema`, `sparc:bootstrap_admin`, `db:seed`) enqueues the job before the new container has a worker, so only the OLD container can take it (measured on a scratch database). Fix: enqueue from the server boot only; a recurring Solid Queue entry re-enqueues every 5 minutes while rows are pending or failed (the only part that helps upgrades from releases already shipped); each row is stamped with the release that registered it, so a missing class from a NEWER release leaves the row `pending` while an archived one still fails. **#1107:** `.sparc-d-none` wins the cascade over the component classes that set `display`, proven on a component in Chrome. **#1131:** specs for `check_part`, mutation-checked. | 2.5d | 10-18 → 10-20 |
| **AQ — Credential lifetime and service-account identity** | **#1176** (scoped) | **Plan approved (owner, 2026-10-18).** **Merged 2026-10-21: PR #1231 closed #1176.** Its CI also needed: the consent-banner test helper deciding from the configuration and failing loudly (owner, 10-19); the stale DS-0002 suppression retired; and three CVE reviews, two of them MEDIUMs deferred as `operational_requirement` deviations the owner approved with `/approve-deviation`, after the converter learned that an approved deviation restarts the review window (owner, 10-20). Measured while coding: the SSP and SAR `convert` endpoints CREATE a document, so they are **Write**, not Read as this plan first said; only previews, translations, CDEF coverage analysis and the entitlement-sync preview are read-only POSTs. A submitted picker with nothing ticked is refused, because an empty list has always meant every endpoint. **Option A (owner, 2026-10-17):** a service account's email stops being its identity. The unique index on `lower(email)` covers human accounts only, and a service account's email becomes a contact that may repeat, because a team's group email is often the owner and contact of several accounts. The longer-term model (option C: service accounts as their own model, team ownership, scoped tokens) is **#1227** on v1.18.0. **Lifetime:** a service-account token cannot be created without an expiry on any path (account form, admin user page, `/api/v1/users/:id/api_tokens`, `/api/v1/service_accounts`); `SPARC_API_TOKEN_MAX_DAYS` (default 365) caps it. A person's own token keeps the "Never" choice (owner, 10-18). **Renew** issues a new token with the same endpoints, CIDRs and lifetime while the old one keeps working for a grace window, `SPARC_API_TOKEN_RENEWAL_GRACE_DAYS` (default 7, owner, 10-18). **Revoke and reissue** (today's regenerate) revokes at once but carries the limits over: today the admin Regenerate button drops endpoint and CIDR limits, widening the token. Expiring-soon tokens are flagged. Existing never-expiring tokens show on the account page and in the API; they are not revoked on upgrade. **Endpoints (owner, 10-17/18):** the free-text "Allowed Endpoints (optional)" box becomes a selectable list built from the `/api/v1` route inventory, grouped by resource, with **Read** and **Write** per row and an **All endpoints** row. Read/Write is classified by the route inventory (GET, previews, converts and translations are Read; other POST, PUT, PATCH, DELETE are Write), and a spec fails on an unclassified route. Raw HTTP-method boxes were rejected: many POSTs only compute, and updates arrive as PUT or PATCH. Existing path-only patterns mean Read + Write, so nothing narrows on upgrade; the API refuses a pattern that matches no route. One definition feeds the screens, the API and enforcement. IdP-brokered short-lived credentials, the issue's full ask, become a follow-up on v1.18.0. Tests both ways; Playwright on the new control; IA-5, AC-2, AC-3, AC-6 and AU-2 CDEF remarks updated. | 3.5d | 10-19 → 10-21 |
| **AR — Config and Sonar hygiene** | **#1120** **#1104** **#1133** · **#1046** (owner closes) | **Plan approved (owner, 2026-10-20). Merged 2026-10-21: PR #1232 closed #1120, #1104 and #1133.** Its CI also needed (none of it AR's doing; `main` failed the same way): the `test` job's timeout raised 30 → 45 minutes, because the suite outgrew 30 at ~7,800 examples and `main` was cancelled at the limit on every run from 10-17; the `hdf` builder on Go 1.26.10 for CVE-2026-111943 (HIGH), with the Dockerfile and `security.yml` pins moved together (both workflow edits owner-approved, 10-21); certifi 2026.10.19 and pillow 13.0.0 in the Python test locks for GHSA-6q48-6c7w-9gw2 and seven pillow advisories. **#1120 (both halves, owner 10-19):** six dead settings retired into `SparcConfig::RETIRED_VARIABLES`, each warned about at boot with what to use instead: `SPARC_OIDC_FORCE_MFA` (never checked, yet cited for IA-2(1)/(2) — the CDEF, NIST mapping, PRODUCTION_SECURITY and issue_rules now name `SPARC_REQUIRE_AUTH_METHODS` and the IdP's MFA policy), `SPARC_ENABLE_EMAIL_CONFIRMATION`, `SPARC_WELCOME_TEXT` (dead; owner 10-20), `SPARC_RATE_LIMITING_ENABLED`, `SPARC_ARTIFACT_REAPER_ENABLED`, `SPARC_SA_INACTIVITY_DAYS`. Inferred from a neighbour, explicit `false` still wins: `SPARC_LDAP_HOST` enables LDAP and `SPARC_APP_CONFIG_SECRET_ARN` enables Secrets Manager (both behaviour changes, owner-approved). `bin/env_inventory_check.rb` runs in the suite and fails on code-vs-docs drift; it measured 154 read vs 140 documented and found **16** settings documented nowhere (the plan said 11), now documented: 153 documented + 6 retired, the #479 flag left out on purpose. **#1133:** the SAR XML parser read both logs with one entry parser and dropped `logged-by`, `related-task`, `status-change` and `related-response` (confirmed against the 1.2.3 XSD) — fixed, with the parser's first spec. Mechanical set: 20 string `raise`s get classes, `module_function` → `extend self` (7), require placement per site, empty-method comments, the chart script's unused names; contrast re-measured clean with `bin/wcag_contrast_check.rb`, so no CSS change. **#1104:** items 1, 3, 4, 5 were fixed by #966; done here: `hdf_pins.sh` `[[ ]]` (owner 10-20), a named storage-posture error, the `else nil`, `.dataset`, the repeated literals and one constants pass over the accent vocabulary. **Sonar:** the owner handles accept/false-positive in the Sonar UI, not with exclusions in code (owner, 10-19): won't-fix A/C/D, the two tabindex and three autofocus sites (each now commented), the seed literals, the design page. **Deferred to v1.18.0:** the 6 cognitive-complexity findings, each its own refactor. **Found, not fixed (reported):** the POA&M XML parser's risk-log entry keeps only five fields; a SAR imported from XML exports schema-invalid for reasons older than this bundle (empty `props`/`links` lists, party links, `include-all` beside an empty `include-controls`). | 2–3d | 10-21 → 10-22 |
| **AU — Parts, enhancements and ODPs, end to end (regression pivot)** | **#1236** | **Owner, 2026-10-21: v1.17.2 pivots to these; the #1233 bundle waits.** Found on a deployed v1.17.1 with a consumer's tailored baseline. Measured with NIST's own Rev 5 catalog and profiles (Rev 4 also loaded, as seeds load it); the data was the same on v1.16.3, v1.17.1 and `main`. **Profile import dropped every Rev 5 ODP:** a parameter was kept only when its id started with the control id plus "_", and `ac-01_odp.05` does not start with `ac-1_`. Measured on HIGH: 74 of 699 stored on `main`, 699 of 699 here (testers independently saw 615 of 690 dropped). **Aggregate parameters** (`ac-1_prm_1`, 142 in Rev 5) ignored their parts. **Baselines built from a catalog stored each parameter's LABEL as its value**, which the screens showed and the export listed as tailoring; a deferred data migration clears it. **SSP generation stored no requirement for 127 of 287 MODERATE controls** (statements written as lettered items); `ControlRequirementText` gives the whole requirement and each part's text with the baseline's values. **The SSP screen showed per-part response rows only in view mode, labelled "a." with no text;** they now render in both modes with the requirement each answers, and control-level narrative boxes are no longer offered. **Screens looked controls up in every catalog**, so a Rev 5 SSP showed Rev 4 text; every lookup is scoped to the document's catalog. **SSP export** carries a part's response as this system's by-component description. **SAP/SAR:** SAR generation created no objectives (0 of 1,795); per-objective determinations never reached the SAR export; the plan named objectives as statement-ids; enhancements were skipped in the plan's and SAR screen's resolved text. **SAR findings (owner, 2026-10-21):** only where something is known before the assessment (the SSP reports "Deferred" or "Will Not Implement"); "Implemented" gets no finding until assessed; new SSPs start with no status instead of "Deferred". An assessed failure opens the control's risk (`SarControlRiskSync`, from every write path), so it reaches the POA&M; `GET/PATCH /api/v1/sar_documents/:id/objectives` records determinations. **Fixtures:** `bin/generate_tailored_profile_fixture.rb` builds NIST's MODERATE (584 ODPs) and HIGH (699) profiles fully tailored; `spec/fixtures/files/end_to_end/` holds the SSP, SAP and SAR the pipeline produces, valid OSCAL 1.2.3, checked every run. End-to-end specs follow MODERATE through import, baseline, SSP, screen, export, re-import, SAP and SAR; every fix was reverted in turn and each revert fails them. | 1d | 10-21 |
| **#1233 bundle — API access, multi-catalog profiles, catalog import, OSCAL 1.2.3** | **#1233** **#1234** **#1235** · **#1105** **#1108** · custom-controls samples | Plan approved (owner, 2026-10-21): admin-only token limit edit in place; discovery from the route inventory (permission table `app/lib/api_route_permissions.rb`, reviewed in the PR); a profile links every imported catalog (unique-title match); catalog import lands as Draft with advisory warnings. Owner 10-21 added: **JSON, YAML and XML** profiles all link their catalogs; **API publication** needs approval or an approver; **#1105/#1108** folded in (1.2.3 already adopted in `7efee101`; the sweep re-run). **Built and gated 2026-10-22** on `sparc:v1.17.2` (preserved PG18 + fresh install, API + Chrome ui-smoke with OIDC); the gate found and the bundle fixed: a lost catalog upload address, a publish refusal shown nowhere, an SSP leveraged-authorization party that dangled. Stacked on AU (#1237). | 4–5d | after AU |
| **#1228 + #1241 — NIST catalog fixes, and catalog parameter values** | **#1228** **#1241** | **Plan approved (owner, 2026-10-22); one branch** (both change catalog import). Ship NIST's Rev 5 XML unchanged, with a provenance record and a pre-release flag: first `develop` at d56011a5, re-pinned to `main` at f0de6d8d when NIST merged it (2026-10-22; same control content, OSCAL 1.2.3, and SPARC's JSON equals NIST's published JSON). SPARC's own XML→JSON converter replaces the reduced XML import, which dropped catalog parts, parameter values, every paragraph after the first, and back-matter citations. Integrity checks 1–3. A deferred migration fixes SA-15(13), SA-24 and SI-02(07) on existing installs and keeps any part a person edited, reporting it (owner decision a). #1241: the resolver uses a catalog parameter's own `values` after any SSP or profile value, and the catalog editor gains a Value column (labels untouched). **PR #1255**, gated on the re-pinned head. | 2d | 10-23 |
| **Bundle 1 — Boundary access and scoping** | **#1244** **#1245** **#1247** **#1250** | **Merged (#1253, 2026-10-22).** #1244 (security): the web boundary controller guarded only bulk delete, and the ATO wizard could pull another boundary's documents in. One rule now covers web and API (`AuthorizationBoundaryAccess`), and API update takes a boundary-scoped write grant. The controller-coverage sweep is now per action, and it found `control_catalogs#acknowledge_warnings` unguarded. #1245/#1247: `AuthorizationBoundary.visible_to` is the one definition of which boundaries a user sees, used by the sidebar, the Enterprise menu and the list. Members counts distinct people. #1250: Completeness counts role-assigned personnel; an optional absence reads "None (optional)". | 1.5d | 10-22 |
| **Bundle 2 — Boundary pages and the homepage** | **#1249** **#1243** **#1248** **#1251** · ~~#1246~~ → v1.18.0 (owner: operational impact) | **Merged (#1254, 2026-10-22).** #1249 (security first): the back-matter API accepted any `resourceable_type`, so an owner allow-list and existence check now live in the model. Boundaries get their own back-matter section and API, and the SSP export includes it. #1243: homepage counts move onto the cards, scoped as each list is. #1248: the list adds Organization and Next decision (sortable; warns within 90 days, red once past); rows offer View only, and the API index uses `visible_to`. #1251: the boundary page leads with status, sections collapse (Completeness always open while Draft), Completeness rows link to the work, and buttons follow permissions. | 2d | 10-23 |
| **#1252 — Profile selection and alters** | **#1252** | **Owner, 2026-10-22: fix before #1242.** Profile import ignored `include-all`, `exclude-controls`, `with-child-controls`, `matching`, and `alters` removes/parts, so tailored baselines selected the wrong controls. One selection definition (`ProfileSelection`) and one alteration definition (`ProfileAlterations`) for every format; XML profiles convert to NIST's full JSON model. Catalogs now record their control tree (`parent_control_id`, `statement_item`) from the file, so selection, export and the resolved catalog work for ids that are not NIST's (FedRAMP 20x); existing catalogs are backfilled. Groups nest at any depth (owner-approved 2026-10-23): their controls join the top-level group's family, `group_data`/`group_id` record the nesting, the export rebuilds it, the family page heads it, and a file with no controls at any depth is refused. NIST's example catalog and profile run end to end. **PR #1262, stacked on #1255.** | 1d | 10-23 |
| **#1242 — SSP response counts** | **#1242** | **Plan approved (owner, 2026-10-22); built 10-24.** `SspResponseProgress` is the one definition the header, each control's badge, the statements table, the SSP list and the API (`response_progress`, `required`, `response_state`) read. The required set is the SSP's own baseline as its profile tailors it (`ControlRequirementText#required`), never stored rows or pinned figures: NIST's LOW, MODERATE and HIGH require 538, 758 and 864. States are NIST's: inherited; hybrid satisfied / not yet satisfied; customer responsibility not yet satisfied; implemented; missing. CDEF text gets a reviewed mark (who/when, cleared by a refresh that changes it); a hybrid's provider part is shown read-only. The API edit now overrides the link (one `apply_author_edit`), `reset_to_source` and `mark_reviewed` have API routes, and the export writes `inherited`/`satisfied`. | 2d | 10-24 |
| **Role rights — administrator overrides, then Policy Manager CDEFs** | **#1259** **#1257** | Design approved (owner, 2026-10-22). **#1259:** built-in role defaults move to one definition (`app/lib/built_in_roles.rb`) read by the seeds and the role editor; `roles.admin_overrides` records each value an administrator set away from its default (web and API); the roles section (`BuiltInRoleSeeder`) applies shipped defaults only to values nobody set, never re-scopes an assigned role, and audits each change and each skipped change; the upgrade records existing differences from a frozen snapshot of the 1.4.0 defaults as overrides. The editor marks values that differ and offers Reset to default. **#1257:** Policy Manager ships with `cdef.write` (roles section 1.5.0): it authors CDEFs and, holding the key across the instance, curates which are instance-wide (owner, 2026-10-23); others ask a Policy Manager. `CdefScopeService.may_scope_instance?` is the one check the web, the API and the scope picker read; and an organization-wide request with no organization (stored as the instance tier) is now refused. Playwright checks written, run in the container gate. | 1d | 10-22 |
| **#1258 — Boundary-scoped CDEF writes** | **#1258** | **Owner, 2026-10-24: pulled into v1.17.2; plan and decisions confirmed.** `CdefWriteAccess` is the one rule the web, the API and the screens read: instance-level `cdef.write` writes every CDEF; a boundary grant writes the CDEFs whose scope is that boundary (the one `CdefScopeService` records — an environment link does not count) and creates into it; organization-wide, instance-wide and unscoped CDEFs stay instance-level; no scope widening. Copies land in the copier's boundary (a copy kept its source's tier, so an AWS Labs copy was instance-wide); the authoring form and API create/import take a scope; bulk apply and field import also need write access; a parse no longer erases the scope boundary an upload recorded. Approval scoping is #1275. | 1d | 10-24 |
| **Operator batch — HDF labels, OIDC egress, custom CA** | **#1205** **#1098** **#1097** | **Owner, 2026-10-24: pulled into v1.17.2; plan approved.** **#1205:** both HDF exports read one `HdfSystemExportService.labels`: `system` (HDF's well-known key, the one results carry) plus `system_id` with the same value through v1.18.0; each hdf-system component gets `targetSelector {"labels.system": <boundary uuid>}`. **#1098:** a sign-in that cannot reach the IdP (discovery, connection, TLS, timeout) says so with the request id instead of "Unknown error"; the log names the exception, and hints at `HTTPS_PROXY` when no proxy applies to the issuer (`SparcHttp.proxied?`); one boot line (`OidcEgressPosture`), no network call; wiki troubleshooting by symptom. **#1097:** wiki *Trusting a custom CA*: runtime mount, derived image (`USER root` … `USER 1000:1000`) and source build, signing, a trust check; verified with a derived build. | 1d | 10-24 |
| **#1275 — CDEF approval at the tier it reaches** | **#1275** | **Owner, 2026-10-24: in the operator batch PR; plan and decisions confirmed.** Instance > Organization > Boundary. A boundary `cdef.approve` grant (ISSO, ISSM, System Owner / ISO) now approves its boundary's CDEFs; it was checked at instance level only. Submit for review takes a `requested_scope` (organization-wide in the boundary's organization, or instance-wide), applied on approval: the boundary's approvers approve up to organization-wide, instance-wide is Policy Manager's. No organization-level role assignment: the boundary roles carry it (owner). The submitter never approves; the instance administrator may (global authority). Refused approvals are audited; the API publish-without-review shortcut stays instance-level. Submit / Approve / Reject and the approval status are on the CDEF page; the review queue says what approving grants. | 1d | 10-24 |
| **#1263 — Reusing a deleted document's name** | **#1263** | **Owner, 2026-10-23: fix in v1.17.2.** A document named like a deleted one failed with "Slug has already been taken" (CDEF, POA&M, profile, SAP, SAR, SSP): `Sluggable` picked a free slug through `SoftDeletable`'s default scope, which hides deleted rows, while the validation and the unique index see them. It now looks unscoped; the new document gets the next suffix and the deleted one keeps its slug, so a restore cannot collide. Model and API specs for all six types. | 0.25d | 10-23 |
| **#1267 — Renaming a document, and saving its OSCAL metadata** | **#1267** | **Owner, 2026-10-23: fix in v1.17.2; UI checks required.** The name/version form on profile, CDEF, SSP, SAR and SAP pages submitted its fields unwrapped, so every rename and version change was refused with a 400 (the common route: copy a published profile, then rename and re-version the copy). The OSCAL Metadata form dropped OSCAL Version, Published Date and Description on every document type and the catalog, while reporting "Document updated". One shared name/version form for all six document pages; the metadata form scoped to its key; Published Date accepted on every type. Request specs submit each form as rendered; a Chrome check covers copy → rename → re-version and the metadata save. | 0.5d | 10-24 |
| **#1270 — Priority in place and bulk control edits** | **#1270** | **Owner, 2026-10-23: v1.17.2, quickly.** Priority is a selector in each control block (saves on change; amber "Priority not set"); controls are selected singly or by family, and a bulk bar sets priority or links/unlinks an existing back-matter resource. One change behind the selector, the bar and `PUT /api/v1/profile_documents/:id/controls/bulk` (`ProfileControlBulkEditService`); the API also returns `control_priorities`. The "Not set" chip filtered on a label no card carried and now works. The Edit screen drops the duplicate parameter table and the unread Parameter Value field. A long parameter label or value no longer pushes the parameter table out of its block. | 1d | 10-23 |
| **#1271 — A failed copy says why** | **#1271** | **Owner, 2026-10-23: v1.17.2.** `DocumentCopyReporting` is the one definition every duplicating action uses (Copy on profiles and CDEFs, a profile made from a published one): logged, audited as `<type>_copy_failed`, and shown on the source as "Could not duplicate '<name>': <reason>". A profile made from a published one copies and links in one transaction. | 0.25d | 10-23 |
| **#1268 — AWS Labs refresh reports what it did** | **#1268** | **Owner, 2026-10-23: v1.17.2.** Refresh Now says "queued" only when the job was queued. Each run is audited as started and completed / kept nothing / failed, and the CDEF screen shows the last state beside the button (`AwsLabsRefreshStatus`), including queued-but-never-started. The version filter counts what it skips per version and warns (ERROR when it kept nothing); `SPARC_AWS_LABS_OSCAL_VERSIONS` accepts commas, semicolons, spaces, quotes, brackets and a `v`; an allowed version without a schema is warned about. The listing's ETag is cached only after a run that kept files. Dialog text corrected (one to two minutes). | 0.5d | 10-23 |
| **AS — Gate truth** → **v1.18.0** (owner, 2026-10-21) | **#1087** **#1207** · **#1063** (scoped) | **#1087 / #1207:** one investigation, since both show a page's `load` waiting on cdn.jsdelivr.net. Measure, then remove the external dependency from page load if that is the cause (vendor the assets through importmap), and prove it on the PIV stack where #1207 reproduces. **#1063:** publish the both-directions matrix (per endpoint and per guarded screen: authorized success and rejection), fill the gaps it finds in security-relevant endpoints, and file the rest as a follow-up. | 2d | 10-21 → 10-22 |
| **AT — OIDC in the publish gate** | **#1224** | The workflow edit described in the issue (owner approval at PR time), proven both ways: `PROVEN oidc_idp_redirect` in the workflow, and a deliberately broken issuer failing it before build-and-push, once, on a test branch. | 0.5–1d | 10-22 → 10-23 |
| ~~**Decide, no code**~~ | ~~#1203~~ ~~#1196~~ | **Moved to v1.18.0 (owner, 2026-10-19); milestones changed on GitHub.** v1.17.2 does not carry a data-model change in its last days. | — | — |
| **Release** | — | Full local checklist on the final head, both architectures (with OIDC in Chrome); wait for main's actions; tag. | 1d | 10-23 → 10-24 |

<!-- markdownlint-enable MD013 -->

**Estimate: about 9–10 days of work into seven calendar days.** That fits only because:
- AP, AQ and AS are small, and AS is mostly measurement.
- The work in each bundle can be split into parallel lanes, with one gate run per bundle (the AI + AL pattern from v1.17.0).

The cut line, if the week slips:
- **AR and AS's #1063 slide first**: they are hygiene and audit, not defects.
- **AP, AQ and AT are the release.**

#### Decisions (owner)

1. **#1176 scope:** cap token lifetime now and broker IdP credentials in v1.18.0 (recommended), or the full ask in v1.17.2. **Decided (owner, 10-17 and 10-18):** AQ takes option A, service-account email is not an identity; option C is #1227 (v1.18.0). Lifetime: expiry required for service-account tokens, renew with a 7-day grace, reissue keeps limits, endpoint list with Read/Write per resource; IdP brokering is v1.18.0.
2. **#1203 and #1196:** **Decided (owner, 10-19):** both move to v1.18.0.
3. **#1046:** **Decided (owner, 10-19):** the owner closes it.
4. **#1120 scope:** **Decided (owner, 10-19):** both halves in v1.17.2 — remove the dead variables AND infer from neighbours.
5. **#1104 / #1133:** **Decided (owner, 10-19):** no Sonar exclusions in code or configuration; the owner accepts or marks findings in the Sonar UI.
6. **#1228:** **Decided (owner, 10-19):** its own bundle, right after AR.

---

### Phase 19: `v1.17.0` — unblock `sparc-horizon`, fix what customers hit

> **Renamed 2026-09-17, owner:** the milestone was created as `v1.17.1` with no
> `v1.17.0` above it, so the next release line had no `.0`. It is now
> **`v1.17.0`**, and every reference in this file and in the collision plan moved
> with it. Issues still *say* v1.17.1 in their own comment threads where they
> were moved there by hand; the milestone is the authority, not the prose.

**Open: 3. Closed: 22.** Re-measured **2026-10-01** from one grouped query
(`gh issue list --state open --limit 400 --json number,milestone`, grouped by
milestone) and `gh issue list --milestone v1.17.0 --state closed --limit 300`.
**Shipped as v1.17.0 on 2026-10-02.** The current phase is 20 (v1.17.2), above.

- **Closed on the milestone (22):** #871 #1103 #1115 #1144 #1151 #1154 #1155
  #1159 #1161 #1162 #1164 #1172 #1178 #1179 #1181 #1183 #1184 #1186 #1189
  #1193 #1194 #1195.
- **Open (3):** #1200, #1202, #1204 (all in AN, PR #1201). **#1203** (AO, design) moved to
  `v1.17.1` (owner, 2026-10-01), so the milestone is empty once PR #1201 merges.

**#1204 joined AN (owner, 2026-09-30):** the precompiled `pg` gem shipped its own libpq with OpenSSL 3.6.0 built in, loaded by every database connection and invisible to every scanner. `pg` is now built from source against Red Hat's libpq and OpenSSL, and the build fails if a bundled libpq returns. nokogiri's vendored libxml2 / libxslt is recorded for an owner decision.

**What moved on 2026-09-30.** The owner found the SSP list ignoring the sidebar's boundary filter. A sweep confirmed three web lists (SSP, SAP, SAR) ignore it while their API siblings honour it (#951 had fixed the same defect for CDEFs only), filed as **#1202** and bundled into AN (PR #1201), with one boundary definition shared by the sidebar, the web lists and Api::V1. The owner then separated a second problem, how many SSPs / SAPs / SARs a boundary holds and what may still change each, filed as **#1203** (design, NIST-validated first).

**What moved in the pass before (2026-09-29, after AF).** AI + AL merged as PR
#1197, closing #1154, #1178, #1179 and #1181. **#1109 (AJ) moved to a new
`v1.18.0` milestone** (owner): about 300 edits, 45 of them in JavaScript the
inline-style ratchet cannot see, for a second-order gain, since `script-src` is
already nonce-based. The **#1189 spike** measured UBI 10 and was closed with its
result; the owner decided to ship it, filed as **#1200** (bundle AN, in flight).
**#1198** (vendor the OSCAL schema bundle; the build makes 81 GitHub requests)
was filed with no milestone.

**What moved in the pass before (2026-09-28 → 09-29).** AF merged as PR #1192 on
2026-09-29, closing #1115, #1172, #1193, #1194 and #1195. AI and AL were bundled
(owner) and cut from `main` the same day. **#1196** (a confidence-score for
control mappings, for discussion) was filed onto **v1.17.1** out of #1154 part 2.

**What moved in the pass before (2026-09-27 → 09-28).** AE merged as PR #1188 on
2026-09-28, closing #1151, #1184 and #1186. AF was cut from `main` the same day
and opened as PR #1192; its three follow-ups (**#1193 #1194 #1195**) were filed
onto the milestone out of it, by the owner's decision.

**What moved in the pass before (2026-09-22 → 09-27), and why this file fell behind then.**
Four PRs merged without a plan update: #1174 (AK), #1182 (#1180), #1185 (#1183)
and the #1175/#1177 fixes that rode #1174. Two issues were **filed out of #1185**
(#1184, #1186), and **#1178, #1179, #1181** were filed 2026-09-23 as
`sparc-validate` / Horizon asks and sat unmilestoned until the owner milestoned
them on 2026-09-27. None of it was in this table.

**RE-SEQUENCED 2026-09-20 (owner), still the governing criterion.** v1.17.0 is
the release that unblocks `sparc-horizon` and fixes what customers hit; the debt
issues moved to **v1.17.1**. The Horizon items are **contract surfaces another
repository writes code against**, and getting one wrong later changes every
document in every fixture and pipeline at once. Sonar debt costs the same
whenever it is done. One of those earns a release slot and the other does not.
#1178, #1179 and #1181 were milestoned on that test.

<!-- markdownlint-disable MD013 -->

| Bundle | Issues | Theme | Est. |
| --- | --- | --- | --- |
| *delivered in flight* | ~~#1103~~ ~~#1180~~ ~~#1183~~ ~~#1175~~ ~~#1177~~ | **#1103** — PR #1163 (2026-09-20): UI-uploaded CDEFs resolved no NIST mappings or regions because enrichment was private to the AWS Labs importer; MITRE re-vendored 106/rev4 → 394/rev4+5; the gate stack gained the database volume whose absence let the squash defect ship. **#1180** — PR #1182 (2026-09-24, no milestone): every object UUID on screen and copyable, from one shared component (`shared/_uuid_badge` + `clipboard_controller`). **#1183** — PR #1185 (2026-09-24): hdf-cli pinned to **3.7.0**; 3.5.1's amendment and schema checks were false passes, and the amendment register now chains. **#1175** — PR #1174: family-id normalisation scoped to its vocabulary. **#1177** — fixed by `fa785334` in PR #1174 (CMS attestation export ordered, so deliveries are reproducible); that PR carried no closing keyword for it, so it was closed by hand 2026-09-27. | delivered |
| **AE — Upgrade safety & gate truth** ✅ **DELIVERED** — PR #1188, merged 2026-09-28 | ~~#1151~~ ~~#1186~~ ~~#1184~~ · ~~#1144~~ ~~#1164~~ | **#1151**: a container must not serve traffic on a schema it does not match. Re-scoped per the issue's own 09-19 investigation: `/up` + `/up/ready` health endpoints (there is **no health route today**, though `production.rb` already assumes `/up`), a boot gate in the entrypoint that refuses to bind the port on drift, a **generated additive reconciliation** from `db/schema.rb` with an audit record (owner-decided 2026-09-27: it lands here, not split out), and an `upgrade_path` CI job that migrates a database built by the **published** previous-release image forward (owner-decided: **advisory first**, promote to required after one release). **#1186**: `security_gate` has been **red on `main` since PR #1185** (2026-09-24). Measured: the breach is **two CodeQL rules**, not the three CSRF sites the issue names — `rb/csrf-protection-disabled` (0.88, 3 results) and `rb/clear-text-storage-sensitive-data` (0.75, 5 results, all name-matched false positives). Overrides match on the RULE, so the owner chose register entries **pinned to CodeQL result fingerprints**: a new instance still breaches. The owner authors the dispositions. **#1184**: the gate fails unless `hdf amend verify` reports the chain **established**; the dead v2 `amend apply` leg (which fails 12/12 under 3.7.0 and uploads raw results as `amended-hdfs`) is replaced by downpins of the v3 output. #1144 and #1164 delivered in PR #1165. **Built 2026-09-27 on the branch, one day against 7–9d** — the measurement had been done before planning. Proven on a UBI9 image built from the branch, over a RESTORED v1.16.3 database: the real v1.16.3 → branch upgrade reconciled nothing and verified strict-clean on 98 tables; with a column and an index dropped the container repaired both (2 statements, audited) and served; with a NOT NULL column dropped from a populated table it refused, changed nothing and exited 1 before binding. `bin/upgrade_path_check` both legs: v1.16.0 → v1.16.2 FAILS naming #1147's seven columns, v1.16.0 → v1.16.3 passes. Severity survey (hdf 3.5.1 vs 3.7.0 over every SARIF on run 36055248647): **only CodeQL crossed a band**; trivy moved within band on 20 of 21. | **7–9d → 1d** |
| **AM — Base image spike** ✅ **DELIVERED** 2026-09-29 — result on #1189, adoption filed as #1200 | ~~#1189~~ | **SPIKE ONLY — owner, 2026-09-27: measure in this milestone, NOT a commitment to upgrade.** Would a UBI 10 minimal base retire any of the **32 register entries** carried against the UBI9 base (11 `deferred` with no upstream fix, 6 HIGH risk-adjusted deviations, 15 HIGH not-applicable), and what would it break (Ruby and native gems, Postgres client tools, locale, CA trust, arm64, FIPS/OpenSSL, the signing pipeline)? Deliverable: a measured per-entry table and a recommendation; any adoption is its own issue. Filed out of AE, after the owner asked whether the Debian-era deferrals were still real. They are: measured present on RHEL 9.8. | spike |
| **AF — Catalog truth** ✅ **DELIVERED** — PR #1192, merged 2026-09-29 | ~~#1115~~ ~~#1172~~ | Must precede **AI**: #1154's second ask is to publish the KSI mapping documents Horizon reads, and the catalog they would be published from has drifted. Measured against FedRAMP `2026.07.14.01`: five theme codes renamed (`EDU`→`CED`, `CM`→`CMT`, `IR`→`INR`, `POL`→`PIY`, `REC`→`RPL`), `AUTH` is no longer a KSI family at all, and **every** indicator id is re-keyed from numbered to mnemonic. SPARC is the flagship and this is the catalog customers see. **#1172 joined this bundle 2026-09-21**: #1115 fixes the data once, #1172 is the ingestion capability whose absence caused the drift. Measured live against `FedRAMP/rules` `2026.09.13.02` — SPARC seeds **11 themes / 54 indicators** from a 431-line hand-written Ruby seed, upstream publishes **10 / 46** plus a JSON Schema with `KSI` as a top-level property. There is a `KsiExportService` and no importer at all. **Owner decisions 2026-09-28:** vendor the upstream files (17 U.S.C. 105); **1:1 renames move in place, everything else retires** (never deleted, since `KsiValidation` is `dependent: :destroy` on its indicator); import reads only the vendored snapshot, plus a separate drift tool; triggered by API and rake only (no UI control). The old→new map is owner-approved (`lib/data/fedramp/ksi_legacy_map.yml`: 10 renames, 44 retirements). **Built on the branch:** vendored rules and schema with a provenance sidecar; a retired state (`retired_at`, `superseded_by`) on controls and families; `FedrampKsiImportService` (schema-validated first, one transaction, digest no-op, dry run); a deferred data migration for existing deployments, and the seed reduced to an importer call; `POST /api/v1/ksi_catalog/import`, with retired entries left out of the read API unless `include_retired=true`; `bin/ksi_upstream_diff.rb`; retired entries badged in the catalog UI and exported to OSCAL as `withdrawn`. **Found on the way:** no deployment whose Rev 5 catalog is named after its OSCAL title ever had a KSI crosswalk, because the seed looked Rev 5 up by an exact name. The importer finds it by framework and version, and a fresh seed now resolves all **373** of FedRAMP's links. An empty family exported `controls: []`, which the OSCAL schema rejects. The drift tool, run live 2026-09-28, finds no drift from `2026.09.13.02`. | 2d + 3d |
| **AI + AL — Horizon contract surface & evidence identity** ✅ **DELIVERED** — PR #1197, merged 2026-09-29 (owner bundled AI and AL; four-lane fan-out) | ~~#1154~~ ~~#1181~~ ~~#1178~~ ~~#1179~~ | **Decided (owner, 2026-09-29):** D1 emit all nine SPARC-namespace props where the document's data supports them, and ADD the missing data points (verified schema-valid against NIST 1.2.2 and 1.2.3 — `props` is the only legal place, and NIST's prop constraints are scoped to NIST's namespace); D2 mappings carry provenance only, confidence-score deferred to #1196; D3/D4 hdf-system status map and `urn:ietf:rfc:4122` scheme, amendment `systemRef` fix bundled; D5 **OSCAL 1.2.3 is the default** and XSDs are carried PER RELEASE (1.1.2, 1.1.3, 1.2.2, 1.2.3; uncarried releases validate against the nearest carried one, flagged); a **web↔API parity spec** makes the API-first rule enforced. **Built:** #1178 finished (it was mostly already shipped in #1180 — `uuid`; now org id/uuid on boundaries and both boundary uuids on leveraged authorizations); #1181 OSCAL export over the API for SSP, SAP, SAR and POA&M (POA&M had no export route at all) with content-hash ETags and 304s; mapping collections over the API; the nine props with new boundary dates and POA&M/SAR risk decision fields, a validator in the validated export path, import round-trip; `hdf-system` export (validated in process — hdf-cli 3.7.0 itself does not enforce `unevaluatedProperties` or `uri-reference`); `docs/api/DELIVERY_CONTRACT.md`. **Found on the way and fixed here:** a production SSP could be neither baselined nor linked to a boundary from the UI (three rules deadlocked; ECS Fargate has no shell, so the UI is the only repair path); a `cdef.write` holder could make a CDEF instance-wide over the API (web refused since #980) — proven, now 403. **Parity baseline:** 232 mapped, 125 ui_only, **117 gaps** (18 partial) — the API-first backlog, listed for the owner, not filed. | ~11–12d |
| **AF follow-ups** ✅ **DELIVERED** in PR #1192 (owner bundled them) | ~~#1193~~ ~~#1194~~ ~~#1195~~ | **#1193** — the retired `AUTH` theme kept its old `sort_order` and listed first; retired families now list after current ones where families are displayed (catalog page, KSI themes API), so it also holds on a database already re-keyed. **#1194 DECIDED (owner, 2026-09-28): yes** — an old id the re-key renamed (`ksi-iam-02`) resolves on the KSI API to the current indicator, answered with `resolved_from`; read from the vendored map, so no data change. **#1195 DECIDED (owner, 2026-09-28): KSI-only for now** — documented on the models and in the catalog guide; profile, baseline and SAP paths deliberately ignore retirement until an importer retires entries in another catalog. | 1d |
| **AJ — Security tail** ➡️ **MOVED to `v1.18.0`** (owner, 2026-09-29: too much risk for a second-order gain) | **#1109** | Independent of the chain. The tail is **201 inline styles across 71 files** re-measured 2026-09-20, not the 254 across 94 the issue was filed with on 2026-09-05 — intervening work cleared ~53 declarations and 23 files, and the issue's own file table is stale by that much. Counted like for like (its table says `evidences/show.html.erb` 9; it measures 9). None holding ten — the flat tail #1047 stopped at 83%. It is the only thing standing between SPARC and removing `style-src 'unsafe-inline'`, which is binary: it comes out at zero or not at all. | 3d |
| **AN — Hardened UBI 10 image** 🔄 **IN FLIGHT** — PR #1201, branch `feature/1200_ubi10_hardened_base` | **#1200** **#1202** **#1204** | Out of the #1189 spike. The owner judged the win real only if the full release checklist passes locally, then decided to ship it. **Built:**
| **AO — Per-boundary document representation** (design) ➡️ **MOVED to `v1.17.1`** (owner, 2026-10-01) | **#1203** | Owner, 2026-09-30:
- **SSP:** one per boundary, kept current.
- **SAP:** many per boundary, kept current from the SSP.
- **SAR:** many per boundary, with states draft (SSP / SAP changes and evidence reach it) → in review (evidence only) → published (frozen).

**Validate against NIST first**: OSCAL assessment layer, SP 800-37 Assess / Authorize, SP 800-53A.

**Today:** `has_one :sap_document` / `:sar_document` pick one arbitrarily where a boundary holds several (boundary 1 has 2 SARs), in the boundary tiles, `AtoPackageExportService`, `HdfAggregationService` and `ReferenceEstate`. | TBD |
- **Base:** `ubi10/ubi-minimal` (RHEL 10.2); PostgreSQL client moves from 13 (EOL) to 16.
- **Runtime strip:** curl, the package manager, rpm, glib2 and the util-linux libraries. Removing rpm was PROVEN not to blind the scanners: they read the rpm database, and all 85 packages are enumerated by both. Build-time assertions, each mutation-proven, fail a strip that is too greedy, one that is incomplete, or one that loses the database.
- **Build freshness:** a version bump re-resolves the package install.

**Found:**
- The shipping UBI9 image carried postgresql and libxml2 builds Red Hat had already fixed: a stale layer cache and a stale digest.
- **Trivy reports zero on RHEL 10.2** (0.69.3 and 0.74.0), and grype-container was ungated. Grype is now gated at HIGH, with register dispositions reaching it as `Grype/<id>`, proven in both directions.

**Register:** 28 of the 33 base-image entries retired with rpm-database evidence; 5 remain.

**Deferred** (owner): renaming the `ubi9` artifacts. | ~3–4d |
| **AG — Identity contract** ✅ **DELIVERED** | ~~#1155~~ ~~#1162~~ | The root of the Horizon chain, and the cheapest work in the milestone. **#1155** registers the namespace URI (still the illustrative `https://risk-sentinel.org/ns/sparc`) and the federation namespace UUID, which **does not exist** — the spec carries a literal placeholder. Both are hashed inputs to every object identity in the estate. **#1162** settles the canonical control-id form: the API emits canonical in the catalog and raw everywhere else, and #1161's grammar canonicalises control ids *before* derivation, so an inconsistency here produces two UUIDs for one object. It also answers #1154's own open question, "is there a canonical form to target?" **DELIVERED 2026-09-21.** #1155 was partly a FALSE PREMISE: it asked to "confirm the real registered namespace URI" as though none existed, but `OscalNamespace::REGISTRY` has carried `https://sparc.risk-sentinel.org/ns` since #1106 and Horizon's schema const was a DIFFERENT URI. Owner-decided: Horizon adopts SPARC's, so no SPARC export moves and #1106 is not reopened. The federation namespace UUID is the UUIDv5 DERIVED from that URI (`9f434272-f796-589b-b972-954790395630`), so a peer recomputes rather than copies it, and `GET /api/v1/federation/identity` serves both with the derivation recipe. #1162 fixed the API write and filter paths; its first item was misdiagnosed — the model has canonicalised since #911, and the real defect was the controller comparing RAW input against canonical storage, so a no-op update destroyed and recreated every link. **A second, older bug surfaced with it**: `evidence_control_links` had no `autosave`, so unlinking a control never took effect on either surface. | 3d |
| **AH — Key grammar & dedup** ✅ **DELIVERED** | ~~#1161~~ ~~#1159~~ | **#1161** ports the UUIDv5 key grammar to Ruby and Python with a shared test vector file — the deliverable that matters most, because three independent implementations of a hashing grammar will disagree eventually and vectors make agreement *measured* rather than assumed. Four details drift silently: the `\x1f` separator (a printable one makes `("a|b","c")` and `("a","b|c")` collide), the grammar version being part of the hashed input, control-id canonicalisation, and NFC normalisation. **#1159** is the security half: the namespace is shared and the grammar is public, so **any peer can precompute another boundary's object UUID and claim it**. Dedup must key on **(object UUID, originating party)**, and two parties asserting one UUID is a conflict to surface, not a duplicate to collapse. Ships after #1161 because the rule is only true if runtimes derive the same UUID. **DELIVERED 2026-09-21.** The vectors were NOT authored here — Horizon already shipped 26 of them, declaring themselves provisional and naming #1155 as the blocker, so this adopted them, regenerated every uuid under the registered namespace, and made the field lists MACHINE-READABLE (upstream they were only implied by each vector's `canonical-fields`). Deriving them surfaced three rules the normative table does not state: **`vocabulary` is never hashed and decides whether a control id may be canonicalised** — under an opaque vocabulary `ACM.1` and `acm.1` are two Security Hub controls, and the first field lists written here canonicalised unconditionally until vector 26 caught it; the 11 rejections are a **validation** spec needing field types, not just presence checks; and an AO decision's `period` is a DATE. SPARC had no dedup code at all, so #1159 establishes the rule rather than fixing a bug, and `FederationBundleSigningService.verify` now returns the verified party so the scoping value comes from verification rather than the payload. | 5d |
| **AK — Deviation approval, mechanized** ✅ **DELIVERED** — PR #1174, merged 2026-09-23 (with #1175) | ~~#871~~ | **Next after AH.** A single admin cannot approve their own PR, so `deviation-requested` -> `deviation-approved` is structurally unreachable and the only route is an admin merge past a red gate. AH hit this for real: six base-image HIGH findings that are present but unreachable and have no upstream fix need a `risk_adjustment`, and there is no way to grant it. **PR #1173 merges by override, so `main` carries six `deviation-requested` entries and the container gate stays RED until this lands.** The flow is an admin commenting `/approve-deviation` — a comment is not a review, so the self-approval block never applies — with a workflow that verifies the commenter, flips the state and pushes with an App or PAT token, because a `GITHUB_TOKEN` push does not trigger workflow runs. Two properties must hold: workflow AND logic come from `main` (a PR that supplies its own `apply_deviation_approval.rb` would self-approve), and `action: created` only. **The escape hatch it retires, `admin-merge-bypass`, has ZERO spec coverage today** while carrying 8 retired entries. #871's own PR carries no deviation so nothing blocks it; the first deviation PR after it is the live test, and #1173's six are already queued to be it. **IN FLIGHT 2026-09-22.** Opening it found that **#1173 had broken `apply_deviation_approval.rb`**: the script edits the register line by line — deliberately, because a YAML round-trip destroys its comments — and #1173's round-trip re-indented the file, so its depth-pinned matchers matched nothing and it refused every approval. Sixteen green specs missed it because each built its own fixture at the old depth; **the fixture was never the artifact**. Repaired, and four specs now drive the applier against the committed register itself. The flow departs from the issue text in one place: the mechanism is recorded as `approve-deviation-comment`, not `review`, because no review occurs and the gate corroborates against the COMMENT list. **Delivered 2026-09-23. First live use 2026-09-28, on PR #1188** — the owner's `/approve-deviation` approved the CVE-2026-54876 risk_adjustment (run 36460001382; bot commit `4354d12c`, `approval_mechanism: approve-deviation-comment`), and the App-token push re-triggered CI as designed. **That first use surfaced two defects AK's own specs could not:** the converter's mechanism list omitted `approve-deviation-comment`, so the approval would have been refused and the gate left red (fixed in PR #1188, `8b560539`, with an applier → converter spec proved red first); and the `SPARC Deviation Approval` App was never INSTALLED on `sparc` — the secrets were set, the token mint returned `Not Found` (run 36433514543) — installed by the owner 2026-09-28. The six #1173 entries remain `admin-merge-bypass`. | 3d |

**The ordering that matters now is AN (#1200)**, the last open item on
v1.17.0. AI + AL, AE and AF are delivered; AJ moved to v1.18.0. (Superseded
text follows.) Previously: **the ordering that mattered was AI + AL** (in flight, one bundle), with **AJ**
and the **AM** spike independent. AE and AF are delivered. AG → AH, the identity
chain AI depended on, is complete.

<!-- markdownlint-enable MD013 -->

#### Open decisions and owed items

1. **#1186's two dispositions are the owner's to author** (`reviewed_by` and any
   approval field). AE drafts them with the rationale and fingerprint pins;
   `security_gate` stays red until they are authored.
2. **Promote `upgrade_path` to a required check** after one release of stable
   runs. Owed, owner-decided 2026-09-27. **At promotion, add a baseline matrix**
   (`[latest, oldest-supported]`, PR #1188 review): today it tests only a
   one-release hop, while the archive rule says "every supported deployment".
3. **Three empty milestones are still open on GitHub** (`v1.16.0`, `ci.v0.0.1`,
   `v1.16.1`). Closing one is an owner action.
4. **Raised by AE, not filed (owner's call):** the **grype gate ignores the
   register** — grype names requirements `Grype/<id>` and emits its own ignore
   list, so the register's overrides matched 0 grype requirements and a
   deferred (POA&M) finding's status never reaches the grype gate; and
   **sparc-iac** should point `health_check_path` at `/up` (liveness) — NOT
   `/up/ready`, which behind ECS would replace the whole fleet on a database
   blip (PR #1188 review) — verify deploys against `/up/ready`, and enable
   `deployment_circuit_breaker`.
5. **Filed 2026-09-29 as #1198** (owner asked): the build-time OSCAL schema download. Two items the owner flagged during #1185 were not written up until then: the
   image build downloads the OSCAL JSON schemas from GitHub at build time (one
   CDN 500 failed a whole build) — `lib/oscal_schemas_bundle/` is **git-ignored**,
   not committed as this item used to say (measured 2026-09-29); the tracked
   copies are `lib/oscal_schemas/` (the default-version fallback) and
   `lib/oscal_xsd_schemas/v<release>/`,
   and whether other scanners' severities moved between hdf 3.5.1 and 3.7.0.
   AE's severity survey answered the second: only CodeQL crossed a band.

#### The cadence this phase inherits

**Measured so far on v1.17.0, from merge dates:** after the 2026-09-20
re-sequence, AG merged 09-21 (PR #1171) and AH merged 09-22 (PR #1173). That is
two calendar days for both, against 3d + 5d; AH adopted Horizon's 26 vectors
rather than authoring them. AK was opened 09-22 and merged 09-23 (PR #1174),
against 3d. The rule from
v1.16.1 keeps holding: **an estimate is reliable when the work was measured
first**. AE was measured before it was planned (the two-rule breach, the
byte-identical artifact and the missing health route were all found by
measurement, not from issue text), so its 7–9d is the more trustworthy kind of
figure. The large single item inside it is the reconciliation engine.

---

## Open work — measured 2026-09-29

Re-measured against the live repository, not carried forward. **575 issues**;
**539 are closed**, **36 open** (2026-09-30). What remains:

> **This section read 36 open for part of a day.** That figure was measured
> minutes before #1162 was filed, and then quoted rather than re-measured. It is
> corrected here from a single grouped query rather than three separate ones —
> three filtered counts disagreed with the total while milestone edits were
> still propagating, which is its own trap: **reconcile the breakdown against
> the total, from one measurement, or the arithmetic hides a stale read.**

> **The closed count in this section was itself stale until 2026-08-25.** It read
> "282 issues, 252 closed" while the repository held 503 and 460 — the open
> figures below had been re-measured and the closed ones carried forward, in the
> very section that exists to stop counts being carried forward. Both figures now
> come from the same command, and the open breakdown reconciles: 15 + 22 = 37.
>
> **A second way to get this wrong, found 2026-09-05:** the milestone **page's**
> open/closed numbers count **pull requests as well as issues**. `ci.v0.0.1` reads
> 30 closed there and holds **22 closed issues plus 8 PRs**, which is where the
> "30/30" in Phase 17 and the Timeline came from. Count issues with
> `gh issue list --milestone <name>`, never with `gh api .../milestones`.
>
> ```bash
> gh issue list --state closed --limit 3000 --json number --jq 'length'   # 526
> gh issue list --state open   --limit 3000 --json number --jq 'length'   #  37
>
> # the breakdown, from ONE query, so it cannot disagree with the total:
> gh issue list --state open --limit 300 --json number,milestone \
>   --jq 'group_by(.milestone.title // "(none)")
>         | map({m: .[0].milestone.title // "(none)", n: length})'
> ```
>
> `--limit` must exceed the real count or the answer is silently truncated to the
> limit — reading 400 back from `--limit 400` is a truncation, not a measurement.

| State | Count |
| --- | --- |
| Closed | **549** |
| Open, on `ci.v0.0.1` / `v1.16.0` / `v1.16.1` | **0** — all shipped (22, 87 and 22 issues) |
| Open, on `v1.17.0` | **0** — shipped 2026-10-02 (#1200 #1202 #1204 closed by PR #1201) |
| Open, on `v1.17.1` | **0** — shipped 2026-10-16 (#1217 #1218 closed by PR #1219) |
| Open, on `v1.18.0` | **7** — #1109 (AJ; milestone created 2026-09-29, owner), #1227 (service accounts as their own model, design; filed 2026-10-17, owner), #1196 and #1203 (moved from v1.17.2, owner, 2026-10-19), #1063 #1087 #1207 (AS, moved from v1.17.2, owner, 2026-10-21) |
| Open, on `v1.17.2` | **10** (re-measured 2026-10-22) — #1046 #1105 #1108 #1224 #1228 #1233 #1234 #1235 #1236 #1238 — #1236 #1238 on AU (PR #1237); #1233 #1234 #1235 #1105 #1108 on the #1233 bundle; then #1228, AT (#1224); #1046 the owner closes (#1104 #1120 #1133 closed by PR #1232, AR; #1107 #1131 #1208 #1223 by PR #1229, AP; #1176 by PR #1231, AQ) |
| **Open, on NO milestone** | **19** (re-measured 2026-10-22, after #1105 and #1108 joined v1.17.2; 21 on 10-21, 22 on 10-17 before #1223 moved to v1.17.2, 21 on 10-16, 19 on 09-30 before #1205 / #1206, 18 on 09-29 before #1198, 19 on 09-22, 27 on 09-20, 24 on 09-17, 22 on 09-05, 25 on 09-03, 10 on 08-25) — see below |

The reconciliation, from one grouped query on 2026-10-21, after PR #1231 (AQ) merged and closed **#1176**, and **#1196** and **#1203** moved to v1.18.0 (owner, 10-19):
**0 + 0 + 9 + 4 + 21 = 34, and 549 + 34 = 583** (v1.17.0, v1.17.1, v1.17.2, v1.18.0, none). Before that, on 2026-10-19, after PR #1229 (AP) merged and closed **#1107, #1131, #1208, #1223**:
**0 + 0 + 12 + 2 + 21 = 35, and 548 + 35 = 583**. Before that, on 2026-10-18, after **#1228** was filed onto v1.17.2 (owner):
**0 + 0 + 16 + 2 + 21 = 39, and 544 + 39 = 583** (v1.17.0, v1.17.1, v1.17.2, v1.18.0, none). Before that, on 2026-10-17, after **#1223** moved to v1.17.2 (owner), PR #1225 merged and **#1227** filed onto v1.18.0:
**0 + 0 + 15 + 2 + 21 = 38, and 544 + 38 = 582** (v1.17.0, v1.17.1, v1.17.2, v1.18.0, none). Earlier the same day:
**0 + 0 + 14 + 1 + 22 = 37, and 544 + 37 = 581** (v1.17.0, v1.17.1, v1.17.2, v1.18.0, none). Since the previous pass: **#1223** (rolling deploy: the previous release fails the new release's deferred data migrations, seen in the sparc-iac v1.16.3 → v1.17.1 upgrade) filed with no milestone; **#1224** (require OIDC sign-in in Chrome before an image can be published) filed onto v1.17.2, to be worked **last** in the wave after several PR cycles of the local gate (owner). Before that, on 2026-10-16 (after the v1.17.1 tag):
**0 + 0 + 13 + 1 + 21 = 35, and 544 + 35 = 579** (v1.17.0, v1.17.1, v1.17.2, v1.18.0, none). Since the previous pass: **#1218** (Rev 5 parameter ids) filed onto v1.17.1, and **#1217** and **#1218** closed by PR #1219. Before that, on 2026-10-16:
**0 + 1 + 13 + 1 + 21 = 36, and 542 + 36 = 578** (v1.17.0, v1.17.1, v1.17.2, v1.18.0, none). Since 10-01: **#1200, #1202, #1204** closed by PR #1201 (v1.17.0 shipped 10-02); **#1217** (OIDC sign-in, v1.17.0 regression) filed onto v1.17.1; the 13 planned v1.17.1 issues moved to **v1.17.2** (owner, 10-16). Before that, on 10-01:
**3 + 13 + 1 + 21 = 38, and 539 + 38 = 577.** Since 09-30: **#1207** (PIV-stack paired page-load timeouts) and **#1208** (a POA&M with an overdue risk cannot be converted to HDF amendments) filed onto v1.17.1, and **#1203** moved from v1.17.0 to v1.17.1 (owner). Before that, on 09-30:
**4 + 10 + 1 + 21 = 36, and 539 + 36 = 575.** Since 09-29: **#1202**, **#1203** and **#1204** filed onto v1.17.0; **#1205** and **#1206** filed with no milestone. Before that, on 09-29 (after PR #1197):
**1 + 10 + 1 + 19 = 31, and 539 + 31 = 570.** Since the previous pass the same
day: **#1154, #1178, #1179, #1181** closed (PR #1197) and **#1189** closed (spike
result); **#1198** (no milestone) and **#1200** (v1.17.0) were filed; **#1109**
moved to the new **v1.18.0**.

Before that, the reconciliation read: **6 + 10 + 18 = 34,
and 534 + 34 = 568.** Since 09-28: **#1115, #1172, #1193, #1194, #1195** closed
(PR #1192); **#1196** filed onto v1.17.1. Between 09-27 and 09-28: **#1151, #1184, #1186** closed (PR #1188);
**#1193, #1194, #1195** filed onto v1.17.0 out of PR #1192. Between 09-22 and 09-27: **#1172** was already counted; **#1184 and
#1186** were filed out of PR #1185 onto v1.17.0, and **#1189** (the UBI 10 spike) out of PR #1188; **#1178, #1179, #1181** were
filed 09-23 unmilestoned and moved to v1.17.0 on 09-27; **#1176** (service-account
token brokering) was filed onto v1.17.1; **#1175, #1177, #1180** were filed and
closed by in-flight work; **#871, #1159, #1161** closed.

> **The table above disagreed with its own reconciliation line until
> 2026-09-27** — it read 10 / 8 / 19 while the sentence under it read 6 / 8 / 18.
> The rows had been re-measured on 09-20 and the sentence on 09-22, and neither
> pass touched the other. Same lesson as the box above: one measurement, written
> in one place.

> **Three milestones are still OPEN on GitHub with zero open issues** — `v1.16.0`,
> `ci.v0.0.1` and `v1.16.1`. Closing a milestone is an owner action and none is
> closed here; it is recorded because an open milestone with nothing in it reads
> as work in flight to anyone scanning the milestone list.

### The twenty-one with no milestone

These are invisible to every milestone count, which is exactly how **#950 went
missing**: it sat open with no milestone, appeared in no bundle, and was only
picked up when the owner milestoned it on 2026-08-22. **Each needs a milestone
or a deliberate decision to close, and that call is the owner's.** Re-measure
the *list*, not only its count. On 2026-09-20 it had fallen five issues behind,
and on 2026-09-27 three more (#1178 #1179 #1181) had sat here for four days
without a row.

Measured 2026-09-27 with `gh issue list --state open --limit 300 --json
number,milestone`, filtering on a null milestone. **Since 09-22:** #871 left
for v1.17.0 (then closed); #1178, #1179 and #1181 arrived 09-23 and left for
v1.17.0 on 09-27; #1175, #1177 and #1180 arrived and closed in flight.

| Issue | Opened | Title |
| --- | --- | --- |
| **#422** | 2026-04-27 | POAM Scenario B — cross-instance federated POAM visibility (carved from #415) |
| **#531** | 2026-05-23 | security(uploads): optional GuardDuty S3 tag check hook on blob serving (post-v1.7.0) |
| **#752** | 2026-07-18 | Pre-release container smoke gate + release report — block render-broken images from shipping (post-#750) |
| **#776** | 2026-07-20 | security: Go stdlib CVEs in hdf-cli (hdf-libs-owned) — needs upstream Go >= 1.26.2 rebuild |
| **#815** | 2026-07-26 | XML fingerprinting: strict namespace/version enforcement + centralization (decisions) — follow-up to #341 |
| **#838** | 2026-07-27 | chore(toolchain): emit SPARC's hdf-cli findings to consuming repos — pin belongs in sparc-ci-runner, not per-repo |
| **#864** | 2026-07-29 | security(kev): make CISA KEV a first-class input to triage, gating and POA&M prioritisation (BOD 26-04 / FedRAMP) |
| **#953** | 2026-08-14 | feat(dast): authenticated DAST against the two-boundary reference fixture |
| **#1089** | 2026-09-01 | design(cdef): a component definition belongs_to ONE profile — it should be usable by many (CDEF 1:n profiles, 1:n SSPs) |
| **#1091** | 2026-09-01 | feat(oscal): let the risk naming system be user-defined, with the rating vocabulary following it |
| **#1097** | 2026-09-02 | docs(tls): custom-CA trust has no guidance for images DERIVED from the published one — **moved to v1.17.2 (owner, 2026-10-24)** |
| **#1098** | 2026-09-02 | docs+ux(oidc): discovery is an outbound call — surface HTTPS_PROXY/NO_PROXY in OIDC docs and in the failure message — **moved to v1.17.2 (owner, 2026-10-24)** |
| **#1099** | 2026-09-03 | design(oscal): findings and risks are unrelated in SPARC, but OSCAL relates them (finding.related-risks) |
| **#1100** | 2026-09-03 | design(ssp): control sub-parts are aggregated, so an assessor cannot respond per part (ac-1a, ac-1a.1, ...) |
| **#1101** | 2026-09-03 | feat(ato): the wizard re-asks for the boundary's already-settled profile/CDEFs and does not default the SSP/SAP/SAR/POA&M |
| **#1121** | 2026-09-11 | Sample-data generation through the API, not around it — YAML-driven endpoint exerciser (moved from sparc-validate#3) |
| **#1198** | 2026-09-29 | chore(build): vendor the OSCAL schema bundle and verify it offline — the image build makes 81 GitHub requests and fails on any one |
| **#1205** | 2026-09-30 | hdf-system export: label the boundary as `system` (not `system_id`) and give components a … — **moved to v1.17.2 (owner, 2026-10-24)** |
| **#1206** | 2026-09-30 | Publish a C4 component model (docs/c4/components.yml) for sparc-iac's Level 3 diagrams |

**How they group, offered as a starting point rather than a decision:**

- **Design questions, not defects — decide before bundling:** #1089 (a CDEF
  belongs to one profile), #1091 (user-defined risk naming), #1099 (findings and
  risks unrelated where OSCAL relates them), #1100 (per-part statements; **the
  data-model change shipped on the Bundle Z branch** and the issue stays open for
  the owner to confirm the interpretation), #1101 (the ATO wizard re-asks settled
  answers).
- **OSCAL 1.2.3:** #1105 and #1108 moved to v1.17.2 (owner, 2026-10-21) and ride
  the #1233 bundle. #1105 was settled by PR #1197 (1.2.3 became the default);
  #1108's sweep is `docs/dev/1108_oscal_1_2_3_sweep.md`.
- **CI-pipeline work, the `ci.v0.0.1` shape:** #752, #776, #838, #864, #953.
- **Operator docs:** #1097 (custom-CA trust for derived images), #1098
  (OIDC discovery through a proxy).
- **Oldest, possibly closeable:** #422 and #531.

### Everything else

The **6** open `v1.17.0` issues each appear in exactly one Phase 19 bundle,
re-verified 2026-09-29: AI + AL #1154 #1181 #1178 #1179 · AJ #1109 · AM #1189. **The check is only worth anything if it is re-run
whenever the milestone changes**: it last passed on 09-17, and was false by 09-24.

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
| 14 | **Complete** | Pre-Public-Flip + API Test Validation + CDEF Mutations | ~~#545~~ ~~#433~~ ~~#498~~ ~~#499~~ ~~#528~~ ~~#447~~ ~~#341~~ ~~#246~~ ~~#413~~ ~~#616~~ ~~#618~~ · carried: **#531**, **#422** | **COMPLETE** — measured 2026-08-25: **11 of its 13 issues are closed**. It had been marked "In Progress" long after the fact. The two still open (#531, #422) carry **no milestone** and are already tracked in *The eighteen with no milestone* above — they are not Phase 14 work in flight, they are untriaged backlog. Note #528 was closed over its own undone tail; that tail is **#1047** in v1.16.1 Bundle Z |
| 15 | Complete | v1.15.4 / v1.15.5 patches — account-lifecycle and UX defects | ~~#868~~, ~~#869~~, ~~#870~~, ~~#867~~, ~~#878~~, ~~#877~~, ~~#875~~, ~~#881~~, ~~#887~~, ~~#888~~, ~~#902~~, ~~#903~~, ~~#911~~ | **COMPLETE** — v1.15.4 and v1.15.5 shipped. #879 (field-help copy) was not done here and is carried into Phase 16. #911 shipped in PR #916/#918; the boundary-roster authorization bug found during it became #919 |
| 16 | **Complete** | v1.16.0 — config correctness, authorization sweep, UX filters, auth entitlements, OSCAL fidelity (milestone `v1.16.0`) | **87 issues, 87 closed. Tagged `v1.16.0` 2026-08-24** from `main` @ `75b5bb3b`. The full closed list is the milestone itself — do not maintain a second copy here | **SHIPPED.** Bundles ran #939 → O → S → P → T → Q → hdf pin → U → W → V → R → X. Bundle X merged as [PR #1049](https://github.com/risk-sentinel/sparc/pull/1049) → `9ae84a84`; [PR #1055](https://github.com/risk-sentinel/sparc/pull/1055) → `75b5bb3b` then fixed four defects Bundle X had merged, found by running the FULL suites against a built prod image. Release verification (measured, on the tagged tree): rspec **6230/0**, API **2742 passed** over TLS and again over non-TLS, ui-smoke **524 passed / 0 failed**, rubocop + brakeman + bundle-audit clean. The milestone grew **53 → 86 because the sweeps FOUND things**, not through scope creep. Wiki published and release notes carry the measured table |
| 17 | **Complete** | `ci.v0.0.1` — evidence and gates | **22 issues, 0 open** (+ 8 PRs on the milestone page) | Closed **2026-08-30**. Detail archived in [`implemented.md`](implemented.md) |
| 18 | **Complete** | v1.16.1 — the patch release (+ v1.16.2 / v1.16.3 hotfixes) | **22 issues, 0 open. Tagged `v1.16.1` 2026-09-17**; v1.16.2 and v1.16.3 tagged 2026-09-18 | Bundles Y → Z → AA → AB → AC → AD. Detail, and the v1.16.2 un-upgradable record, archived in [`implemented.md`](implemented.md) |
| 19 | **Complete** | v1.17.0 — unblock Horizon, fix what customers hit (+ v1.17.1 hotfix) | **0 open, 28 closed. Tagged `v1.17.0` 2026-10-02.** v1.17.1 hotfix (#1217 OIDC sign-in, #1218 Rev 5 parameter ids) tagged 2026-10-16, 0 open, 2 closed | Bundles AE–AN delivered; AJ (#1109) moved to v1.18.0. Detail stays in Phase 19 until archived |
| 21 | Planned | v1.18.0 — created 2026-09-29 (owner) | **8 open** (2026-10-22): #1063 #1087 #1109 #1196 #1203 #1207 #1227 #1246. AS (#1087 #1207 #1063) moved here 10-21, #1246 10-22 (owner), with #1109 (AJ, the inline-style tail blocking removal of `style-src 'unsafe-inline'`) and #1227 (service accounts as their own model, design first) | 3–4d (re-measured: ~300 sites, 45 in JavaScript) |
| 20 | **Next** | v1.17.2 — the deferred wave (milestone was `v1.17.1` until 2026-10-16, owner) | **8 open, 23 closed** (2026-10-22): open #1046 #1224 #1228 #1241 #1242 #1252 #1257 #1259. Merged: #1239 (#1233 bundle), #1253 (Bundle 1), #1254 (Bundle 2). In review: #1255 (#1228 + #1241), then #1252 stacked on it; role rights (#1259, #1257) built; queued #1242; AT (#1224) last. **Tag by 2026-10-24 is a goal, not a hard date** (owner) — see *Phase 20* | ~4–5d remaining |

<!-- markdownlint-enable MD013 -->

**Re-measured 2026-10-01** (grouped open query + `gh issue list --state all --limit 2000`): **577
issues total — 539 closed, 38 open.** Open splits **3** on `v1.17.0`, **13** on
`v1.17.1`, **1** on `v1.18.0`, **0** on every shipped milestone, and **21** with no milestone:
3 + 13 + 1 + 21 = 38, and 539 + 38 = 577. *(09-30: 575 / 539 / 36. 09-29 after PR #1197: 570 / 539 / 31. Earlier on 09-29: 568 total, 534 closed, 34 open. 09-28: 567 total, 529 closed, 38 open. 09-27: 564 total, 526 closed, 38 open. 09-20: 551 total, 514 closed, 37 open.
09-17: 540 / 510 / 30. 09-05: 525 / 488 / 37.)*

> This footer previously read "503 issues total — 478 closed, 28 open", which
> does not add up (478 + 28 = 506), carried two different measurement dates in
> one sentence, and ended on a dangling "no milestone." fragment. It is the same
> drift the box further up warns about, in the paragraph that reports the
> measurement. Both figures now come from one command on one date, and the split
> reconciles.

> **The per-phase totals that used to sit here were stale and are removed rather
> than guessed at.** They read "Total issues tracked: 88", "Completed (Phases
> 1-13): 92 issues" and **"Current version: v1.7.2"** — the last of which was
> wrong by nine minor releases, against a repository that tagged **v1.16.0** on
> 2026-08-24. They described a document that stopped being maintained around
> v1.9.1 and were never reconciled.
>
> Phase-by-phase history lives in [`implemented.md`](implemented.md).
> [GitHub Releases](https://github.com/risk-sentinel/sparc/releases) is canonical
> for what shipped when. **The milestone pages are NOT canonical for issue
counts** — they count pull requests alongside issues, which is how `ci.v0.0.1`
was recorded as 30 in three places in this file when it holds 22 issues and 8
PRs. Count with `gh issue list --milestone <name> --state all --limit 300`.
> **Do not reintroduce a hand-maintained running total here** — every one of them
> drifted, and each drifted silently in the direction of looking finished.

**First public release: v1.0.0** (#271). Org migration to `risk-sentinel/sparc`
completed 2026-05-02 (#430).

> **Resolved:** `VERSION` in `app/models/sparc_config.rb` reads **1.16.3** and
> matches the latest tag (re-verified against the file on 2026-09-27).
