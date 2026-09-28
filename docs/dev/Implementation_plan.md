# SPARC Open GitHub Issues -- Implementation Strategy

Structured, prioritized roadmap for the open issues in the SPARC
GitHub repository.

**Last updated:** 2026-09-27 — v1.17.0 currency pass: AK delivered, AE in flight (#1151 #1186 #1184), Phases 17–18 archived

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
> the v1.16.2 / v1.16.3 hotfix pair on 2026-09-18. The latest release is **v1.16.3**.
> Phases 17 and 18 moved there on **2026-09-27**, with a record of that hotfix
> pair; their bundle detail, the Bundle Z sweep record and the cadence
> re-measures are there, unedited.


---

### Phase 19: `v1.17.0` — unblock `sparc-horizon`, fix what customers hit

> **Renamed 2026-09-17, owner:** the milestone was created as `v1.17.1` with no
> `v1.17.0` above it, so the next release line had no `.0`. It is now
> **`v1.17.0`**, and every reference in this file and in the collision plan moved
> with it. Issues still *say* v1.17.1 in their own comment threads where they
> were moved there by hand; the milestone is the authority, not the prose.

**Open: 11. Closed: 9.** Re-measured **2026-09-27** from one grouped query
(`gh issue list --state open --limit 300 --json number,milestone`, grouped by
milestone) and `gh issue list --milestone v1.17.0 --state closed --limit 300`.
**This is the current phase.**

- **Closed on the milestone (9):** #871 #1103 #1144 #1155 #1159 #1161 #1162
  #1164 #1183.
- **Open (11):** #1109 #1115 #1151 #1154 #1172 #1178 #1179 #1181 #1184 #1186 #1189.

**What moved since the last pass (2026-09-22), and why this file fell behind.**
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
| **AE — Upgrade safety & gate truth** 🔄 **IN FLIGHT** — branch `fix/1151_1186_upgrade_gate_and_gate_grading` | **#1151** **#1186** **#1184** · ~~#1144~~ ~~#1164~~ | **#1151**: a container must not serve traffic on a schema it does not match. Re-scoped per the issue's own 09-19 investigation: `/up` + `/up/ready` health endpoints (there is **no health route today**, though `production.rb` already assumes `/up`), a boot gate in the entrypoint that refuses to bind the port on drift, a **generated additive reconciliation** from `db/schema.rb` with an audit record (owner-decided 2026-09-27: it lands here, not split out), and an `upgrade_path` CI job that migrates a database built by the **published** previous-release image forward (owner-decided: **advisory first**, promote to required after one release). **#1186**: `security_gate` has been **red on `main` since PR #1185** (2026-09-24). Measured: the breach is **two CodeQL rules**, not the three CSRF sites the issue names — `rb/csrf-protection-disabled` (0.88, 3 results) and `rb/clear-text-storage-sensitive-data` (0.75, 5 results, all name-matched false positives). Overrides match on the RULE, so the owner chose register entries **pinned to CodeQL result fingerprints**: a new instance still breaches. The owner authors the dispositions. **#1184**: the gate fails unless `hdf amend verify` reports the chain **established**; the dead v2 `amend apply` leg (which fails 12/12 under 3.7.0 and uploads raw results as `amended-hdfs`) is replaced by downpins of the v3 output. #1144 and #1164 delivered in PR #1165. **Built 2026-09-27 on the branch, one day against 7–9d** — the measurement had been done before planning. Proven on a UBI9 image built from the branch, over a RESTORED v1.16.3 database: the real v1.16.3 → branch upgrade reconciled nothing and verified strict-clean on 98 tables; with a column and an index dropped the container repaired both (2 statements, audited) and served; with a NOT NULL column dropped from a populated table it refused, changed nothing and exited 1 before binding. `bin/upgrade_path_check` both legs: v1.16.0 → v1.16.2 FAILS naming #1147's seven columns, v1.16.0 → v1.16.3 passes. Severity survey (hdf 3.5.1 vs 3.7.0 over every SARIF on run 36055248647): **only CodeQL crossed a band**; trivy moved within band on 20 of 21. | **7–9d → 1d** |
| **AM — Base image spike** | **#1189** | **SPIKE ONLY — owner, 2026-09-27: measure in this milestone, NOT a commitment to upgrade.** Would a UBI 10 minimal base retire any of the **32 register entries** carried against the UBI9 base (11 `deferred` with no upstream fix, 6 HIGH risk-adjusted deviations, 15 HIGH not-applicable), and what would it break (Ruby and native gems, Postgres client tools, locale, CA trust, arm64, FIPS/OpenSSL, the signing pipeline)? Deliverable: a measured per-entry table and a recommendation; any adoption is its own issue. Filed out of AE, after the owner asked whether the Debian-era deferrals were still real. They are: measured present on RHEL 9.8. | spike |
| **AL — Evidence identity** | **#1178** → **#1179** | Filed 2026-09-23 from `sparc-validate#432`/`#441`, milestoned 2026-09-27. **#1178** exposes `AuthorizationBoundary#uuid` in the API serializer. The column already exists (`gen_random_uuid()`, non-null), and its absence forces `sparc-validate` to *mint* a second identity for a system SPARC already identifies. **#1179** has SPARC mint and export `hdf-system` documents, so `systemRef` in every HDF v3 results and amendments document resolves to something. Most of the mapping exists in `authorization_boundaries`. #1178 is small and gates #1179. | 0.5d + 3d |
| **AF — Catalog truth** | **#1115** **#1172** | Must precede **AI**: #1154's second ask is to publish the KSI mapping documents Horizon reads, and the catalog they would be published from has drifted. Measured against FedRAMP `2026.07.14.01`: five theme codes renamed (`EDU`→`CED`, `CM`→`CMT`, `IR`→`INR`, `POL`→`PIY`, `REC`→`RPL`), `AUTH` is no longer a KSI family at all, and **every** indicator id is re-keyed from numbered to mnemonic. SPARC is the flagship and this is the catalog customers see. **#1172 joined this bundle 2026-09-21**: #1115 fixes the data once, #1172 is the ingestion capability whose absence caused the drift. Measured live against `FedRAMP/rules` `2026.09.13.02` — SPARC seeds **11 themes / 54 indicators** from a 431-line hand-written Ruby seed, upstream publishes **10 / 46** plus a JSON Schema with `KSI` as a top-level property. There is a `KsiExportService` and no importer at all. | 2d + 3d |
| **AI — Horizon contract surface** | **#1154** **#1181** | Three asks, sequenced by the issue: (1) `sparc-validate` rules for the nine SPARC-namespace props, gating Horizon's **P0**. **The 09-22 comment makes the linked schema stale**: adopt the current `sparc-namespace-props.v1.schema.json` (`const` = `https://sparc.risk-sentinel.org/ns`), not the copy linked at filing. (2) Publish the KSI and 800-53 mapping documents with provenance, which depends on **AF**. (3) Confirm the Delivery API surface; Horizon's `fixtures/sparc/` were written from `docs/api`, not live responses. **#1181 joined 2026-09-27** because it *is* the gap in (3): only `cdef_documents` export OSCAL over the API; SSP, SAP, SAR and POA&M have the export services and no API route to them. | 6d + 1.5d |
| **AJ — Security tail** | **#1109** | Independent of the chain. The tail is **201 inline styles across 71 files** re-measured 2026-09-20, not the 254 across 94 the issue was filed with on 2026-09-05 — intervening work cleared ~53 declarations and 23 files, and the issue's own file table is stale by that much. Counted like for like (its table says `evidences/show.html.erb` 9; it measures 9). None holding ten — the flat tail #1047 stopped at 83%. It is the only thing standing between SPARC and removing `style-src 'unsafe-inline'`, which is binary: it comes out at zero or not at all. | 3d |
| **AG — Identity contract** ✅ **DELIVERED** | ~~#1155~~ ~~#1162~~ | The root of the Horizon chain, and the cheapest work in the milestone. **#1155** registers the namespace URI (still the illustrative `https://risk-sentinel.org/ns/sparc`) and the federation namespace UUID, which **does not exist** — the spec carries a literal placeholder. Both are hashed inputs to every object identity in the estate. **#1162** settles the canonical control-id form: the API emits canonical in the catalog and raw everywhere else, and #1161's grammar canonicalises control ids *before* derivation, so an inconsistency here produces two UUIDs for one object. It also answers #1154's own open question, "is there a canonical form to target?" **DELIVERED 2026-09-21.** #1155 was partly a FALSE PREMISE: it asked to "confirm the real registered namespace URI" as though none existed, but `OscalNamespace::REGISTRY` has carried `https://sparc.risk-sentinel.org/ns` since #1106 and Horizon's schema const was a DIFFERENT URI. Owner-decided: Horizon adopts SPARC's, so no SPARC export moves and #1106 is not reopened. The federation namespace UUID is the UUIDv5 DERIVED from that URI (`9f434272-f796-589b-b972-954790395630`), so a peer recomputes rather than copies it, and `GET /api/v1/federation/identity` serves both with the derivation recipe. #1162 fixed the API write and filter paths; its first item was misdiagnosed — the model has canonicalised since #911, and the real defect was the controller comparing RAW input against canonical storage, so a no-op update destroyed and recreated every link. **A second, older bug surfaced with it**: `evidence_control_links` had no `autosave`, so unlinking a control never took effect on either surface. | 3d |
| **AH — Key grammar & dedup** ✅ **DELIVERED** | ~~#1161~~ ~~#1159~~ | **#1161** ports the UUIDv5 key grammar to Ruby and Python with a shared test vector file — the deliverable that matters most, because three independent implementations of a hashing grammar will disagree eventually and vectors make agreement *measured* rather than assumed. Four details drift silently: the `\x1f` separator (a printable one makes `("a|b","c")` and `("a","b|c")` collide), the grammar version being part of the hashed input, control-id canonicalisation, and NFC normalisation. **#1159** is the security half: the namespace is shared and the grammar is public, so **any peer can precompute another boundary's object UUID and claim it**. Dedup must key on **(object UUID, originating party)**, and two parties asserting one UUID is a conflict to surface, not a duplicate to collapse. Ships after #1161 because the rule is only true if runtimes derive the same UUID. **DELIVERED 2026-09-21.** The vectors were NOT authored here — Horizon already shipped 26 of them, declaring themselves provisional and naming #1155 as the blocker, so this adopted them, regenerated every uuid under the registered namespace, and made the field lists MACHINE-READABLE (upstream they were only implied by each vector's `canonical-fields`). Deriving them surfaced three rules the normative table does not state: **`vocabulary` is never hashed and decides whether a control id may be canonicalised** — under an opaque vocabulary `ACM.1` and `acm.1` are two Security Hub controls, and the first field lists written here canonicalised unconditionally until vector 26 caught it; the 11 rejections are a **validation** spec needing field types, not just presence checks; and an AO decision's `period` is a DATE. SPARC had no dedup code at all, so #1159 establishes the rule rather than fixing a bug, and `FederationBundleSigningService.verify` now returns the verified party so the scoping value comes from verification rather than the payload. | 5d |
| **AK — Deviation approval, mechanized** ✅ **DELIVERED** — PR #1174, merged 2026-09-23 (with #1175) | ~~#871~~ | **Next after AH.** A single admin cannot approve their own PR, so `deviation-requested` -> `deviation-approved` is structurally unreachable and the only route is an admin merge past a red gate. AH hit this for real: six base-image HIGH findings that are present but unreachable and have no upstream fix need a `risk_adjustment`, and there is no way to grant it. **PR #1173 merges by override, so `main` carries six `deviation-requested` entries and the container gate stays RED until this lands.** The flow is an admin commenting `/approve-deviation` — a comment is not a review, so the self-approval block never applies — with a workflow that verifies the commenter, flips the state and pushes with an App or PAT token, because a `GITHUB_TOKEN` push does not trigger workflow runs. Two properties must hold: workflow AND logic come from `main` (a PR that supplies its own `apply_deviation_approval.rb` would self-approve), and `action: created` only. **The escape hatch it retires, `admin-merge-bypass`, has ZERO spec coverage today** while carrying 8 retired entries. #871's own PR carries no deviation so nothing blocks it; the first deviation PR after it is the live test, and #1173's six are already queued to be it. **IN FLIGHT 2026-09-22.** Opening it found that **#1173 had broken `apply_deviation_approval.rb`**: the script edits the register line by line — deliberately, because a YAML round-trip destroys its comments — and #1173's round-trip re-indented the file, so its depth-pinned matchers matched nothing and it refused every approval. Sixteen green specs missed it because each built its own fixture at the old depth; **the fixture was never the artifact**. Repaired, and four specs now drive the applier against the committed register itself. The flow departs from the issue text in one place: the mechanism is recorded as `approve-deviation-comment`, not `review`, because no review occurs and the gate corroborates against the COMMENT list. **Delivered 2026-09-23. First live use 2026-09-28, on PR #1188** — the owner's `/approve-deviation` approved the CVE-2026-54876 risk_adjustment (run 36460001382; bot commit `4354d12c`, `approval_mechanism: approve-deviation-comment`), and the App-token push re-triggered CI as designed. **That first use surfaced two defects AK's own specs could not:** the converter's mechanism list omitted `approve-deviation-comment`, so the approval would have been refused and the gate left red (fixed in PR #1188, `8b560539`, with an applier → converter spec proved red first); and the `SPARC Deviation Approval` App was never INSTALLED on `sparc` — the secrets were set, the token mint returned `Not Found` (run 36433514543) — installed by the owner 2026-09-28. The six #1173 entries remain `admin-merge-bypass`. | 3d |

**The ordering that matters now is AE → AF → AI**, with **AL** in parallel once
#1178 lands, and **AJ** and the **AM** spike independent. AE goes first because `main`'s security gate
is red until #1186 is dispositioned, and every PR after it inherits that red. AG
→ AH, the identity chain AI depended on, is complete.

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
5. **Two items the owner flagged during #1185 are still not written up:** the
   image build downloads all 44 OSCAL schemas from GitHub at build time though
   `lib/oscal_schemas_bundle/` is committed (one CDN 500 failed a whole build),
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

## Open work — measured 2026-09-27

Re-measured against the live repository, not carried forward. **564 issues**;
**526 are closed**, **38 open**. What remains:

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
| Closed | **526** |
| Open, on `ci.v0.0.1` / `v1.16.0` / `v1.16.1` | **0** — all shipped (22, 87 and 22 issues) |
| Open, on `v1.17.0` | **11** — #1109 #1115 #1151 #1154 #1172 #1178 #1179 #1181 #1184 #1186 #1189 (bundles in Phase 19) |
| Open, on `v1.17.1` | **9** — #1046 #1063 #1087 #1104 #1107 #1120 #1131 #1133 #1176 |
| **Open, on NO milestone** | **18** (19 on 09-22, 27 on 09-20, 24 on 09-17, 22 on 09-05, 25 on 09-03, 10 on 08-25) — see below |

The reconciliation, from one grouped query on 2026-09-27: **11 + 9 + 18 = 38,
and 526 + 38 = 564.** Since 09-22: **#1172** was already counted; **#1184 and
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

### The eighteen with no milestone

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
| **#1097** | 2026-09-02 | docs(tls): custom-CA trust has no guidance for images DERIVED from the published one |
| **#1098** | 2026-09-02 | docs+ux(oidc): discovery is an outbound call — surface HTTPS_PROXY/NO_PROXY in OIDC docs and in the failure message |
| **#1099** | 2026-09-03 | design(oscal): findings and risks are unrelated in SPARC, but OSCAL relates them (finding.related-risks) |
| **#1100** | 2026-09-03 | design(ssp): control sub-parts are aggregated, so an assessor cannot respond per part (ac-1a, ac-1a.1, ...) |
| **#1101** | 2026-09-03 | feat(ato): the wizard re-asks for the boundary's already-settled profile/CDEFs and does not default the SSP/SAP/SAR/POA&M |
| **#1105** | 2026-09-05 | chore(oscal): review OSCAL 1.2.3 and decide whether to adopt it (SPARC ships 1.2.2) |
| **#1108** | 2026-09-05 | audit(oscal): re-run the seven-model conformance sweep against OSCAL 1.2.3, after #1105 decides adoption |
| **#1121** | 2026-09-11 | Sample-data generation through the API, not around it — YAML-driven endpoint exerciser (moved from sparc-validate#3) |

**How they group, offered as a starting point rather than a decision:**

- **Design questions, not defects — decide before bundling:** #1089 (a CDEF
  belongs to one profile), #1091 (user-defined risk naming), #1099 (findings and
  risks unrelated where OSCAL relates them), #1100 (per-part statements; **the
  data-model change shipped on the Bundle Z branch** and the issue stays open for
  the owner to confirm the interpretation), #1101 (the ATO wizard re-asks settled
  answers).
- **OSCAL 1.2.3:** #1105 decides adoption; #1108 re-runs the conformance sweep
  after it.
- **CI-pipeline work, the `ci.v0.0.1` shape:** #752, #776, #838, #864, #953.
- **Operator docs:** #1097 (custom-CA trust for derived images), #1098
  (OIDC discovery through a proxy).
- **Oldest, possibly closeable:** #422 and #531.

### Everything else

The **11** open `v1.17.0` issues each appear in exactly one Phase 19 bundle,
re-verified 2026-09-27: AE #1151 #1186 #1184 · AF #1115 #1172 · AI #1154 #1181 ·
AJ #1109 · AL #1178 #1179 · AM #1189. **The check is only worth anything if it is re-run
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
| 19 | **Current** | v1.17.0 — unblock Horizon, fix what customers hit | **11 open, 9 closed** (2026-09-27): open #1109 #1115 #1151 #1154 #1172 #1178 #1179 #1181 #1184 #1186 #1189. Delivered: AG, AH, AK, and #1103 #1180 #1183 #1175 #1177 in flight. **AE in flight** (#1151 #1186 #1184); then **AF → AI**; **AL** (#1178 → #1179), **AJ** (#1109) and the **AM** spike (#1189) in parallel | AE 7–9d · AF 5d · AI 7.5d · AL 3.5d · AJ 3d. The bundle list lives in Phase 19; do not maintain a second copy here |
| 20 | Planned | v1.17.1 — the deferred wave | **9 open, 0 closed** (2026-09-27): #1046 #1063 #1087 #1104 #1107 #1120 #1131 #1133 #1176. Sonar backlog, gates that must mean something, two UI tails, and **#1176** (service accounts on non-expiring static tokens; broker short-lived IdP credentials) | est. TBD — scope when v1.17.0 is cut |

<!-- markdownlint-enable MD013 -->

**Re-measured 2026-09-27** (`gh issue list --state all --limit 3000`): **564
issues total — 526 closed, 38 open.** Open splits **11** on `v1.17.0`, **9** on
`v1.17.1`, **0** on every shipped milestone, and **18** with no milestone:
11 + 9 + 18 = 38, and 526 + 38 = 564. *(09-20: 551 total, 514 closed, 37 open.
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
