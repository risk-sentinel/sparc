# SPARC Open GitHub Issues -- Implementation Strategy

Structured, prioritized roadmap for the open issues in the SPARC
GitHub repository.

**Last updated:** 2026-09-05 (second pass — the sweep count was measuring one syntax)

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

> **Phases 1–16 have shipped and are archived in
> [`implemented.md`](implemented.md)**, together with the per-bundle detail and
> the original theme checklist. They were moved on 2026-08-24 because the great
> majority of what this file referenced was already closed, so most of it was
> history and the live work was buried inside it. Nothing was deleted — look
> there for why a decision was made. (The "248 of 282" figures this note used to
> quote were stale; see *Open work* below for the measured counts.)
>
> **The most recent shipped phase is 16 — v1.16.0, tagged 2026-08-24.**


---

### Phase 17: `ci.v0.0.1` — Evidence and Gates (COMPLETE)

**v1.16.0 shipped 2026-08-24** (tag `v1.16.0`, `main` @ `75b5bb3b`). Owner
decision: **the CI milestone runs BEFORE the v1.16.1 patch work**, so v1.16.1
gets real-environment soak time rather than shipping on the heels of the release
it patches.

**Phase 17 closed 2026-08-30 — 22 issues, 0 open** (re-measured 2026-09-05 with
`gh issue list --milestone ci.v0.0.1 --state all --limit 300`). This phase and
the *Timeline* below both recorded it as **30/30**, which is the milestone
**page's** figure and counts the **8 PRs** attached to the milestone alongside
its issues: 22 + 8 = 30. Nothing slipped — the work is the same work — but the
number was never a count of issues, and this file warns against exactly that
misreading in *Open work* below while using it here. Corrected in both places
2026-09-05.

**Measured velocity — read from the repo on 2026-08-24, not estimated:**

| Measure | v1.16.0 actual |
| --- | --- |
| Issues closed | 87 over **14 calendar days** (2026-08-11 → 08-24) |
| Per calendar day | **6.2** raw · **4.2** excluding the Bundle V discovery spike |
| PRs merged | **26** in the window = **1.9/day**, median **1 day** between merge days |
| Milestone growth during execution | **53 → 86 issues (+62%)** |

Two things that table is saying, and they pull in opposite directions:

1. **The raw rate flatters us.** 32 of the 87 closed on a single day
(2026-08-22)
   because Bundle V *filed and closed* them inside its own sweep. Planning
   against 6.2/day would assume that repeats. **Use 4.2.**
2. **The backlog is not the workload.** The milestone grew by **62%** while it
   was being worked. A 16-issue milestone should be planned as roughly **25**,
   because the sweeps find things. That is not scope creep — every one was a
   defect already shipped and previously invisible.

**Historical, as measured mid-flight on 2026-08-25 — kept because the churn it
records is the point, not the totals.** *Open: 15, closed 5* — re-measured
against the live repository on 2026-08-25, after CI-1 merged and #977 was closed
as superseded. The milestone was written
as 16 open; it has since taken in **#1061** (slotted into CI-3 below), and CI-1
filed **#1064**, **#1065** and **#1067** out of its own work while closing four.

**The near-flat count hides the churn rather than reflecting stability** — nine
issues moved in or out to shift the total by one. The +62% discovery factor is
doing exactly what the table above predicts: the backlog refills from the work
itself. Do not read a steady milestone count as a milestone that is not moving.
Grouped into four bundles by what they share, not by label:

| Bundle | Issues | Theme | Est. |
| --- | --- | --- | --- |
| **CI-1 — Gates that can actually fail** ✅ **MERGED** (PR #1066, `cfa9ed77`) | ~~#1048~~ ~~#1050~~ ~~#987~~ ~~#885~~ (filed out of it: #1064 #1065 #1067; #1063 → v1.16.1) | The scan→decision gap. A scan runs, produces an artifact, and nothing assesses it: bundler-audit reaches no threshold gate (#1048), neither API contract gate runs in CI and both are inert without `--check` (#1050), Brakeman is `continue-on-error` so SAST can never fail a build (#987), and posture-gated tests can silently skip rather than prove both conditions (#885). | 2d |
| **CI-2 — Evidence completeness** ✅ **MERGED** (PR #1068, 2026-08-25) | #962 #985 #990 #1027 (~~#977~~ **closed as superseded**; **#917 → CI-4**) | Not the gap the issues described. Gitleaks **has** been converted since 2026-03-15 (#186); the real defect is that a **zero-control HDF passes every band trivially**, so a clean scan and a broken scanner are the same green check. Fixed by moving the SARIF conversions to `hdf convert` (which names the scanner and emits an execution record), an injected canary for the saf-path scanners, and a gate that asserts both the canary and the expected scanner set. | 3d |
| **CI-3 — Test-job fidelity** | ~~#835~~ ~~#927~~ ~~#1061~~ · **#711 re-aimed** | Shipped: pinned `hdf-cli` in the test job so the OSCAL specs run rather than skip (#835); the deprecation wall cleared, which was also a scheduled Rack failure (#927); the wiki now publishes on merge (#1061). **#711 was re-aimed 2026-08-26 (owner):** checking a DEPLOYED instance is sparc-dast's job and does not belong here. It becomes an **in-runner pre-release gate** — build the prod image, stand it up, run the suites against it, block the release. Measured: no workflow does this today. `build-sign-publish` starts the image and runs `bin/rails --version` against it; `security.yml` builds and only SCANS. | 2d |
| **CI-4 — Posture and architecture coverage** | #858 #859 #965 **#917** | Release smoke runs one TLS posture and one does not imply the other (#858); **the arm64 half of every published image ships unverified** (#859) — which matters more now that `build-sign-publish` emits a multi-arch manifest on every tag; metrics collide in the bucket root (#965). **#917 moved here from CI-2** (2026-08-25): attesting SCA results with `cosign attest` is the same shape as #859 — both are about whether a consumer can verify something about a **published artifact**, and both change `build-sign-publish.yml`, so they share one pass through the build/sign/publish path and the same `cosign verify-attestation` testing surface. | 3d |

**Estimate: 11 working days, target 2026-09-08. Actual: ~7 working days, closed
2026-08-30.** The original figure was 8 (bundle work bracketed 6–9 by two
methods). **CI-1 superseded it** — see the revision under *CI-1 — landed* below,
which is the number that governed. The two were left contradicting each other in
this section until 2026-08-25. The 11-day revision was the more conservative of
the two and was the one that was wrong; see the Timeline note for why.

### CI-1 — landed 2026-08-24

The bundle's premise turned out to understate the problem. #1048 was filed as
"bundler-audit is the one scan artifact that reaches no threshold gate". The
measurement said: **no artifact reached a threshold gate**, because
`security_gate` invoked `saf validate threshold -F amended`, and `-F` is not a
saf flag in any released version. `saf_action` surfaced the oclif parse error as
a *warning*, exited 0, and the next step wrote "Security gate passed" — on every
run since #244 shipped.

Ten further defects sat behind that one, each independently sufficient to keep
the gate inert. The full list is `docs/compliance/scan-artifact-inventory.md`,
which is the deliverable that stops this recurring: an inventory of every
artifact `security.yml` produces against what actually assesses it.

Two findings became their own issues rather than being absorbed silently:

- **#1064** — the container gate would have used NVD worst-case severity on a
  Red Hat image. `cyclonedx_sbom2hdf` takes the maximum rating across up to
  seven sources, so Red Hat "low"/"medium" arrived as "critical": **45 of 74
  findings disagreed**. Gating on Trivy's own SARIF instead reduced the residual
  from 3 critical / 25 high to 0 critical / 2 high.
- **#1065** — `resolv` and `uri` lacked the override/disposition pair every
  other shadowed default gem has, and `uri` had no Gemfile pin at all.

**What this says about the remaining estimate.** CI-1 consumed roughly what the
plan allowed for CI-1 and CI-2 together. The cause is specific and does not
generalise to every bundle: thresholds that have never been applied have never
been calibrated, so turning the gate on meant measuring the real residual of
thirteen scanners and deciding a policy for each. CI-2 through CI-4 are closer
to the original "pipeline wiring with known shapes" description. Revised
estimate **11 working days**, target **2026-09-08**.

**Sequencing note:** CI-1 first. Everything after it is evidence that a gate
should be able to reject, and #1050 in particular guards the #995 contract
result that v1.16.0 just shipped — that guarantee is currently unenforced.

### CI-2 — merged 2026-08-25 (PR #1068)

**The bundle's stated premise did not survive measurement, and the real defect
was larger.**

**#962 is stale.** "Gitleaks SARIF is never converted to HDF" was wrong against
`main`: it has been converted since **2026-03-15** (`f8f3b4ab`, #186),
`security.yml:1135`. The organisation-wide audit that filed it read the scan
step and missed the conversion job. Only its third acceptance criterion —
verify on a SARIF containing an actual finding — was genuinely unmet, and that
is now done.

**What was actually wrong.** A zero-control HDF passes every threshold band
trivially: saf compares `count > max`, so against no controls every count is 0.
Measured on run `32840183630`, the first run with CI-1's gate live, **gitleaks,
brakeman and bundler-audit all reached the gate as zero-control documents
sitting under all-zero bands**, and 5 of 12 HDFs were anonymous
(`profiles[0].name` = `"SARIF"`). So a scanner that ran and found nothing was
byte-identical to one that never ran — for the secrets scanner, the
highest-consequence vacuous pass in the pipeline.

This is the direct successor to CI-1. CI-1 fixed *"the gate assessed nothing"*;
CI-2's finding is *"several of the things it now assesses cannot fail"*.

The fix is three parts that only work together — `hdf convert` for scanner
identity and a native execution record, `bin/hdf_ensure_canary.rb` for the
scanners still on saf, and a gate that asserts both the canary and the expected
scanner set (`docs/compliance/expected-hdfs.txt`). Detail and the measurements
are in `docs/compliance/scan-artifact-inventory.md`.

**Two scope corrections, decided by the owner 2026-08-25:**

- **#977 is CLOSED as superseded** (not planned). It asked for a TruffleHog
  emit; PR **#979** implemented exactly that and was closed 2026-08-19 with
  *"Superseded by #985"*, because this repository is declared
  `secrets: {tools: [gitleaks]}` and TruffleHog evidence is never read for it.
  The gap it described is closed by this bundle via a different route: the
  evidence was not missing, it was **empty**. Its one surviving requirement —
  a clean scan must still emit — is now enforced for *every* scanner, not just
  secrets.
- **#917 moves to CI-4.** Attesting SCA results with `cosign attest` lives in
  `build-sign-publish.yml`, not `security.yml`, and needs a predicate-format
  decision (in-toto `vuln` vs OpenVEX vs CycloneDX-VEX). It pairs with **#859**,
  which is the same question about the same file — can a consumer verify
  something about a published artifact. Note for that work: hdf-libs 3.5.1 can
  already emit `hdf-amendments → openvex` / `cyclonedx-vex` / `csaf-vex`, and
  `sparc-findings.yml` is already the register of accepted findings *with
  rationale* — but **#1067 means amendments currently suppress nothing**, so
  what gets attested must be measured rather than assumed.

**Two things worth carrying forward:**

- **The `--to hdf@2` down-pin has a shelf life tied to #1067.** It is harmless
  only while amendments no-op; once #1067 is fixed the down-pin would drop the
  `effectiveStatus` suppression depends on.
- **`hdf convert` cannot read our filesystem grype scans at all** — grype's
  `.source.target` is an object for image scans and a string for `sbom-file`
  scans, and hdf-libs types it as a struct only. Upstream-reportable, same class
  as mitre/hdf-libs#248. It bounds how far the migration off saf can go today.

---

### Phase 18: `v1.16.1` — The Patch Release

**SHIPPED — `v1.16.1` tagged 2026-09-17** from `main` @ `df6439c0`, 0 open / 22
closed. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.16.1).
Bundle AD (#1116 #1117 #1134) merged as
[PR #1135](https://github.com/risk-sentinel/sparc/pull/1135); every main workflow
on the merge commit was green before the tag. Release verification, measured on a
locally built UBI9 prod image (`bc7fc87ca975`, arm64) carrying `VERSION 1.16.1`:
rspec **6901/0** (10 pending), API contract **2877 passed / 2 skipped**, ui-smoke
chromium **541 passed / 17 skipped / 0 failed**, rubocop **1387 files / 0**,
brakeman **0**, bundle-audit **0**, Postman **306/306**. Both deferred data
migrations ran to completion on a real prod boot.
Phase 17 closed **2026-08-30** (22 issues; see the correction under Phase 17 —
the "30/30" this file used to quote was the milestone page counting PRs),
three working days ahead of the ~09-02 the cadence predicted.

**#968 met its date.** The one dated item in either milestone was due
**2026-09-06**. It closed **2026-08-31**, with the rest of Bundle Y — six
calendar days early, and on the first of the five working days the window had
allotted it. The blockquote below is the ordering decision that protected it,
kept as a record of a call that worked rather than as live guidance.

> **HISTORICAL — resolved 2026-08-31.** Everything below was written before
> Bundle Y ran.
>
> **#968 carries a hard due date of 2026-09-06** — the only dated item in either
> milestone. This previously stood as an owner decision: on the measured cadence
> v1.16.1 would open 09-03 leaving **three working days**, and on the standing
> 11-day estimate it would open *after* #968 was already due.
>
> **That decision is no longer needed.** `ci.v0.0.1` closed **2026-08-30**, not
> ~09-02, so Bundle Y opens **Monday 08-31** and #968 has **five working days**
> before its date. Nothing needs pulling forward and the date does not need to
> move — *provided Y starts with #968* rather than the correctness defects beside
> it. That ordering is now the only thing protecting the date, so it is stated
> here rather than left to the bundle to infer.
>
> This is the audit of swallow-and-continue rescue patterns; #963 already showed
> the hazard is not theoretical.

<!-- markdownlint-disable MD013 -->

| Bundle | Issues | Theme | Est. |
| --- | --- | --- | --- |
| **Y — Reliability, and the deadline** ✅ **SHIPPED 2026-08-31** | ~~#968~~ ~~#1051~~ ~~#1022~~ ~~#1058~~ | The rescue-pattern audit (54 sites, 11 log-and-continue in services/jobs, 17 combining a transaction with a rescue). Alongside it the two correctness defects the release run surfaced: 163 of 232 CDEFs export schema-invalid OSCAL (#1051) and `/api/v1/controls` ignores `?items`/`?per_page` so 4,054 rows come back whole (#1022). **All four closed 2026-08-31 — one working day against a 3d estimate**, because the rescue-pattern audit found the 54 sites concentrated in a handful of shapes rather than needing 54 separate decisions. | 3d → **1d** |
| **Z — The CSP tail** ✅ **DELIVERED** (PR #1102, then PR #1110 merged 2026-09-10) | ~~#1047~~ ~~#728~~ ~~#1113~~ ~~#980~~ · **#1046 moved to v1.17.0** (owner, 09-10: 213 bare-symbol routes is tech debt, not user value) · folded in: ~~#1090~~ ~~#1092~~ ~~#1093~~ ~~#1094~~ ~~#1095~~ ~~#1096~~ · **#1047 sweep: 1,516 → 254 (1,262 done, 83%)** — every file holding TEN OR MORE inline styles is at zero; the tail is #1109 on v1.17.0 · plus the OSCAL assessment chain an owner screen-review took apart (see below) | **#528's tail is paid down to the point where `style-src 'unsafe-inline'` becomes possible**: it is binary and cannot happen at 254, so #1109 carries it. #728 closed — one real AA failure fixed, the rest were Sonar findings our own WCAG gate contradicts. | **4d est.; took 10d** — the sweep was ~4d; the other 6 were the assessment chain |
| **AA — Auth and access debt** ✅ **DELIVERED** (PR #1119, then PR #1122 merged 2026-09-11) | ~~#978~~ ~~#1059~~ ~~#1082~~ ~~#1044~~ · filed out of its own work: ~~#1120~~ (v1.17.0) ~~#1123~~ | Four issues that shared one failure mode: an auth misconfiguration that ships green and fails at REQUEST time with nothing on screen. #978 — a CSRF rejection re-rendered the login form blank-faced, indistinguishable from a wrong password. #1082 — requiring a method now ENABLES it, and a policy that cannot be satisfied fails at BOOT rather than locking the instance; the login page offers only methods that can hold a session, and OIDC became a button rather than a one-button tab. #1059 — the IdP revoke ceiling removed, per the owner's ruling. #1044 — instance-administrator AUTHORITY an IdP grants and revokes, separate from the break-glass IDENTITY. | **3d est.; took 2d.** The estimate held for once, because the surprises were found by MEASURING before writing rather than mid-build |
| **AB — Onboarding, and the Sonar backlog** ✅ **DELIVERED** (PR #1125 merged 2026-09-12, then PR #1126 and PR #1128 on 09-13) | ~~#1040~~ ~~#940~~ ~~#1033~~ ~~#930~~ ~~#966~~ ~~#836~~ ~~#1123~~ | The guided boundary onboarding flow (#1040) is a feature, not a fix — it takes a team from "a pile of Word documents" to a boundary SPARC can work with, and carries the platform axis that makes CDEF recommendation possible. #966 triages 281 SonarCloud findings including 2 Blockers — note that **#1104, filed 2026-09-04, measures ~40 findings standing on `main`**; the two figures are not in conflict but nobody has reconciled them, and #966 should be re-scoped against a live measurement before it is planned rather than against its own filing text. **Delivered 09-12 → 09-13.** #966 was re-scoped as predicted: PR #1126 did the supply-chain hardening and got coverage reporting to SonarCloud, and the remaining 191 findings were filed as **#1133** on v1.17.0 | 5d est.; **took 2d** |
| **AC — Coverage and conformance** ✅ **RESOLVED** — #1106 delivered by PR #1130 (merged 2026-09-15, with #1124's migration squash; PR #1132 follow-up 09-16); **#1063 moved to v1.17.0** (owner, 2026-09-16) | ~~#1106~~ ~~#1124~~ · #1063 → v1.17.0 | Two open issues on this milestone appear in **no bundle**, which this file previously asserted could not happen. **#1063** is per-endpoint `tests/api` and per-screen ui-smoke both-direction coverage — filed out of CI-1 and moved here. **#1106** was filed 2026-09-03 out of Bundle Z's `implementation-status` defect and asks the same question of all seven exports: are the namespaces, vocabularies and constraints right, not merely the schema version. Both are audits over a surface the other bundles are actively changing, so they are cheapest **last** — but that is an argument, not a decision, and the owner has not made one. **The owner decided on 09-16:** #1106 shipped (conformance dataset, `OscalNamespace` registry, declarable roles), and #1063 moved to v1.17.0. #1106's audit found the gaps that became Bundle AD | — |
| **AD — OSCAL roles and SPARC's own compliance evidence** 🔄 **IN PR** — one branch, `fix/1116_1117_roles_and_compliance_posture` | #1116 #1117 #1134 | **#1116**: the data migration was the last open acceptance criterion from PR #1130. It resolves the free-text responsible-role ids written before the picker existed, and drops none of them. **#1117**: SPARC's five CDEFs claimed OSCAL 1.1.2 while shipping 1.2.2, and are now re-stamped with a drift guard. The control mapping's statistics were off by 66 controls, and the wiki gained a Compliance Posture page. **#1134**: importing boundary members wrote raw membership roles into `role-ids`, where they referenced nothing, and the conformance check never collected `role-ids`. Roles are now declared by choosing from the boundary's membership vocabulary, through the API and on the enrich page. A second data migration fixes the values already written. Filed out of the work: **#1133** (Sonar triage, v1.17.0). | ~2d |

<!-- markdownlint-enable MD013 -->

#### Bundle Z — the detail the table cannot hold

**DELIVERED 2026-09-10 as PR #1110.** What Bundle Z turned out to be is not what
it was scoped as, and that is the useful record.

It was scoped as a CSP sweep: #1047, #728, #1046. It shipped the sweep at 83%
and, alongside it, a repair of the OSCAL assessment chain that no issue
described when the bundle was cut. Every one of those defects was found the same
way — the owner reading a real screen on a running container:

| reported as | actually |
|---|---|
| "assessment objectives forced into a single objective" | the resolved catalog dropped EVERY objective; the plan carried 288 controls and 0 objectives |
| "test text is missing the 800-53a" | `assessment-objects` dropped twice over — absent from the allowlist AND skipped because NIST ships it with no id |
| "control status seems duplicated by SSP status" | four Assessment Context rows were stale SSP snapshots |
| "empty parent control labels (no prose)" | NIST container nodes counted as work, so a fully assessed control could only reach 71% |
| "not sure why severity by family is a thing" | severity is an XCCDF concept an OSCAL CDEF has no source for |
| "4 nested CDEFs I cannot drill into" | AWS Config Rules rendered as peer components; 4 imported, 1 exported |

Two defects were introduced BY this bundle and caught by its own gates: the
#1047 sweep left the ATO wizard unable to open a single step panel (ten panels,
all six steps — `.sparc-d-none` is `!important` and the controller wrote
`style.display`), and the CDEF export briefly emitted a source's own
`component_uuid` without checking it was a v4 uuid.

**The estimate was not the problem.** 4d was about right for the sweep. The other
six days were work that existed before the bundle and that no issue named. Two
bundles running, the same pattern: **a page-by-page review of a running container
finds work the issue list does not contain.** That is an argument for scheduling
the review, not for padding estimates.


**Sweep progress — every figure this file has published was counting ONE
SYNTAX.** The ratchet matched `style="..."` and nothing else, but Rails helpers
take the style as a keyword (`link_to "x", path, style: "..."`) and it reaches
the browser as an ordinary attribute, so `style-src 'unsafe-inline'` is exactly
as load-bearing for it. **113 inline styles were invisible to every measurement
in this bundle, and 33 of them sat in eight files whose own commits said "to
0"** — every slice but one left some behind.

| | published | actual |
| --- | --- | --- |
| branch point (`dc739d50`) | 1,403 | **1,516** |
| after slice 9 | 745 | **858** |
| mid-bundle | — | **790** |
| **delivered** | — | **254** |

**The sweep was at 43%, not the 47% published on 2026-09-04. It finished at
83%** (1,262 of 1,516; the figures below were the mid-bundle position and are
kept because the correction they record is the point),
after a leftovers pass that took all eight of those files to a TRUE zero and
slice 10 (`sap_documents/show`, 35). Ten slices: sar_enrich 136, ssp_enrich 97,
ato_wizard 99, ssp_show 90, poam_show 72, cdef_show 47, control_families 43,
sar_show 39, sap_show 35, catalog_import 34, plus 33 helper-form leftovers.
Slice 4 was the first to convert DYNAMIC styles — **20 remain** repo-wide
(re-measured 2026-09-05; the 769 others are static), in three shapes:
enumerable status COLOUR and indent DEPTH become classes, and the ~8 continuous
percentage widths go through a Stimulus controller writing
`element.style.width`, which `style-src` does not govern. Each is verified by a
full-surface pixel A/B against a baseline captured on the *previous* image,
plus `--check-cascade`; slice 3 came back byte-identical on the screen it
rewrote. Two defects were found by re-verifying slices 1-2 and are fixed: a
duplicate `.sparc-field-label` that restyled 2,456 `<th>`s across five screens,
and the utility layer losing the cascade to `application.css` on 638 form
controls. **Largest files remaining, re-measured 2026-09-05 on the corrected
count** — 790 declarations across **127 files**, mean **6.2**:
`catalog_controls/_form` 29, `converters/stig_parser` 25,
`ssp_documents/wizard` 25, `home/index` 23, `profile_controls/_form` 23,
`profile_documents/show` 21. **The distribution has flattened, and that changes
the remaining cost.** Slices 1–4 averaged 105 declarations per file; only
**eight files now hold 20 or more**, and **78 hold five or fewer**. So the
remaining 52% is not four more slices — it is **127 files**, most of which need
a per-screen judgement about whether an existing token fits before any
conversion happens, and the per-file overhead (visual baseline, cascade check)
stops amortising. **`converters/stig_parser` is blocked**:
`converter_search_controller` reveals by writing an EMPTY inline `display`,
which a class cannot override, so it must move to `setVisible` first — the same
defect class as `baseline_editor` in slice 8 and `heatmap_controller`.

**OWNER-DECIDED 2026-09-05: #1047 CLOSES with this bundle's PR.** Its scope is
the sweep of every view file holding **ten or more** inline styles — 1,262 of
1,516, **83%** — which is done. The remaining **254 across 94 files**, none
holding ten, are **#1109 on v1.17.0**, and that issue also owns the deliverable
#1047 was originally written around: removing `style-src 'unsafe-inline'`, which
is binary and cannot happen at 254.

The decision is sound because the delta is now MEASURED rather than estimated —
every remaining file is named with its count in #1109, the method is written
down, and the guards that make the work safe are in the suite. What #1047 cannot
do is deliver the directive removal, so that moved rather than being quietly
dropped.

*(Superseded, kept for the record:)* PR #1102 was a verified INCREMENT and
merged 2026-09-03; #1047 did NOT close

**Bundle Z has taken in work that is not the sweep, and that is where its time
has gone.** Since the increment merged, the branch has also carried: the SSP
control edit panel hiding the control being implemented; the catalog control
edit screen 500-ing once a control had linked back-matter; the SSP export
putting SPARC's status vocabulary in NIST's `implementation-status` namespace;
and **#1100** — the catalog importer discarded `ctrl["parts"]` entirely, so the
OSCAL parts tree has never been stored, the resolver emitted one flattened
statement, and an SSP author answered a nine-statement control in one box. That
chain is four layers deep and none of it is CSP work. It is in this bundle
because the owner's page-by-page review of the Bundle Z container is what
surfaced it, and the fixes are in the screens the sweep was already rewriting.

**Four issues were filed out of Bundle Z's own work after the increment
merged** — #1103 (AWS Labs CDEFs import with no controls), #1104 (~40
SonarCloud findings standing on `main`), #1105 (review OSCAL 1.2.3) and
**#1106** (sweep all seven exports for namespace, vocabulary and constraint
conformance — the generalisation of the `implementation-status` defect, and the
only one milestoned **at the time**). Since then the owner milestoned **#1103**
and **#1104** onto v1.17.0; #1105 is still unmilestoned.

**Two failure modes the pixel gate cannot see, both found by the owner's
page-by-page review rather than by the harness.** Converting `style="display:
none"` to a class **inverts** any controller that decides state by reading
`element.style.display` — the attribute is now empty, the read returns
"visible", and the first click hides the panel it was meant to reveal. It
shipped in the SSP control **Edit** button and the doc-meta Edit toggle, and
was latent in three more controllers on views the sweep had not reached.
Separately, `.sparc-edit-panel` baked `display: none` **into a component
class**, so removing `.sparc-d-none` could not reveal it: **hiding is a state
and belongs to `.sparc-d-none`; a component class carries layout only.**
Neither defect exists until someone clicks, so a byte-identical screenshot
proves nothing about them. The same blind spot covers `cursor` — 449 elements
changed rule in slice 4 with an unchanged computed value.

**Estimate: 14 working days, and it is now the weaker half of it that is being
tested.** The issue count is smaller than v1.16.0's but the *weight* is not —
issues #1047, #1040 and #966 are each multi-day, where much of v1.16.0 was
small defects found in sweeps. Do **not** plan this milestone at 4.2 issues/day
— that rate was earned on a different size distribution.

**Re-measured after Bundle Y, as this section asked for.** Y estimated 3d and
took **1**. Z estimated 4d and took **10** — the sweep was roughly the 4d
estimated; the other six days were the OSCAL assessment chain an owner
screen-review uncovered, which carried no issue when Z was scoped. The lesson is
not that the estimate was wrong: it is that **a page-by-page review of a running
container finds work no issue list contains**, and Z is the second bundle where
that has been the larger half. At **83% of #1047's
sweep**, having also absorbed the four-layer #1100 chain and three owner-review
defects that are not CSP work at all. The two errors point opposite ways and do
not cancel: **the small-defect bundles keep landing faster than estimated, and
the one large single item keeps absorbing whatever is next to it.** The
distribution warning above was right about the shape and wrong about the
consequence — the risk is not that every bundle runs long, it is that #1047
alone can carry the milestone's date, which is what the Confidence note already
said and is now measured rather than predicted.

### Timeline

Back-to-back, from **2026-08-24**, working days only, at the measured cadence of
one bundle every 1.5–2 days:

| Window | Work | Milestone |
| --- | --- | --- |
| **08-24 Mon** | CI-1 — gates that can fail | ✅ **merged**, PR #1066 |
| **08-25 Tue** | CI-2 — evidence completeness | 🔄 **in review**, PR #1068 |
| 08-26 → 08-29 | CI-3 + CI-4, and the unbundled tail (#1064 #1065 #1067 #1080) | ✅ ci.v0.0.1 |
| **08-30 Sun** | **`ci.v0.0.1` closes — 22 issues, 0 open** *(recorded here as 30/30 until 2026-09-05; that was the milestone page counting its 8 PRs)*, three days ahead of the ~09-02 predicted | ✅ |
| **08-31 Mon** | **Y — reliability. All four closed in ONE day** against 3d; **#968 met its 09-06 date, closing on the first of the five working days allotted** | ✅ v1.16.1 |
| **09-01 → 09-10** | **Z — the CSP tail. DELIVERED.** PR #1102 (09-03) then PR #1110 (09-10); sweep 1,516 → **254 (83%)**; absorbed the #1100 statement chain, the #1114 assessment chain, #1113, #980, and the defects two owner screen-reviews found | ✅ v1.16.1 |
| ~~09-08 → 09-12~~ **09-10 → 09-11** | ~~AA — auth and access debt~~ **DELIVERED, 2 days** | v1.16.1 |
| ~~09-15 → 09-19~~ **09-12 → 09-13** | ~~AB — onboarding and Sonar (carries #1123)~~ **DELIVERED, 2 days**, PR #1125 / #1126 / #1128 | ✅ v1.16.1 |
| **09-14 → 09-16** | ~~AC~~ **#1106 + #1124 delivered**, PR #1130 (09-15); #1063 → v1.17.0 | ✅ v1.16.1 |
| **09-16 → 09-17** | **AD — #1116 #1117 #1134** — PR #1135, merged 09-17 | ✅ v1.16.1 |
| **09-17** | **`v1.16.1` TAGGED** from `df6439c0` — five working days inside the ~09-22 target | ✅ |
| **next** | **Phase 19 — `v1.17.0`**, 6 issues milestoned and unbundled; see below | v1.17.0 |

**These dates are projected from the assumption that Z finishes this week, and
that assumption is not measured.** Z finished #1047 at 83% with the flat tail
still ahead of it (127 files averaging 6.2 declarations each). If the remaining
sweep costs per-file what the tail's shape suggests rather than per-declaration
what the head cost, Z runs past this week and every row below it moves. **The
tag date is the least reliable figure in this file** and should be redrawn from
a measurement after Z closes, not defended.

**The re-measure is settled: the measured cadence was right.** `ci.v0.0.1` closed
**2026-08-30** — 22 issues, and 8 PRs, which is where the "30/30" came from —
against a measured-cadence prediction of ~09-02 and a standing conservative
estimate of 11 working days → 09-08. **Actual: ~7 working days.** The
conservative bound was wrong by more than the cadence was.

Worth recording *why*, because the same reasoning will be applied to v1.16.1:
the gap was said to be "entirely CI-3 and CI-4", on the grounds that #859 and
#711 were not the concentrated-in-one-file shape that made CI-1 and CI-2 cheap.
That held — those were the expensive bundles — but the milestone still landed
early because four issues filed *out of* the work (#1064 #1065 #1067 #1080)
turned out to share one root cause each rather than needing separate
investigations.

**The caution transfers, and inverts.** v1.16.1 is weighted toward large single
items (#1047, #1040, #966), where CI's work was weighted toward pipeline wiring
with known shapes. Do not carry the 7-day result into this milestone as a rate —
it was earned on a different distribution, which is the same mistake the v1.16.0
cadence note warns about. ~~**Re-measure after Bundle Y.**~~

**Re-measured 2026-08-31 / 2026-09-05, and the caution was half right.** Bundle
Y — four issues, 3d estimate — closed in **one day**. Bundle Z is on day four
of a 4d estimate; it delivered at **83%** of its single large item on day 10. The distribution argument
predicted both bundles would run long; instead the small-defect bundle ran
*shorter* and the large single item is running long on its own. **What governs
this milestone's date is #1047 and nothing else**, so the useful re-measure is
not a rate at all — it is the sweep count, which is now published in the Bundle
Z row and re-read from the ratchet rather than from this file.

**Confidence.** The CI window is the firmer of the two: its issues are mostly
pipeline wiring with known shapes — and it closed, so it is now history rather
than a forecast. The v1.16.1 window depends almost entirely on #1047, which
four days of measurement have confirmed: Z has slipped its estimate not through
Trusted Types but through **the sweep's own tail flattening** and through
absorbing owner-review defects (#1100 and three others) that share its screens.
The historic pattern says the count will also grow: apply **+62%** and this
becomes **early October**, which is the honest outer bound rather than the
target.

**What would make this wrong.** v1.16.0 ran at 4.2 issues/day on a distribution
dominated by small sweep-found defects. Both remaining milestones are weighted
toward large single items. ~~**Re-measure after CI-2**~~ — done; CI-2 merged
2026-08-25 and the milestone closed early, so the cadence held for Phase 17.

**The live version of that question, for Phase 18:** the dates below Z are
fiction until the #1047 sweep count is at or near zero, because #1047 is the
only item that can move them. **Re-measure by running the ratchet spec, not by
reading the figure in this file** — the count in the Bundle Z row was 980 and
stale within two days of being written, and only re-running the count caught
it.

---


### Phase 19: `v1.17.0` — The Next Milestone

> **Renamed 2026-09-17, owner:** the milestone was created as `v1.17.1` with no
> `v1.17.0` above it, so the next release line had no `.0`. It is now
> **`v1.17.0`** (same milestone, same six issues), and every reference in this
> file and in the collision plan moved with it. Issues still *say* v1.17.1 in
> their own comment threads where they were moved there by hand; the milestone
> is the authority, not the prose.

**Open: 8. Closed: 5.** Re-measured 2026-09-21 from ONE grouped query
(`gh issue list --state open --limit 200 --json number,milestone`, grouped by
milestone), because three separate filtered counts disagreed with the total
while milestone edits were propagating. **This is the current phase.** The
figure read "Open: 6. Closed: 0." from 2026-09-17 until this pass: it predated
the re-sequence, #1162 and #1164 were filed after it, and #1103 closed. Every issue on it was *moved* here by an owner decision or
*filed out of* v1.16.1's own work, so the milestone is real but it has never
been sequenced, and it is small: six issues against v1.16.1's 22.

**RE-SEQUENCED 2026-09-20 (owner).** The milestone *was* a tail rather than a
release — six of its nine issues were debt the last two milestones deferred, and
none of them was a thing a user asks for. The question "what is v1.17.0 *for*"
now has an answer, and it came from the open-issue sweep rather than from the
debt list.

**v1.17.0 is the release that unblocks `sparc-horizon` and fixes what customers
hit.** The six debt issues — #1046 #1063 #1104 #1120 #1131 #1133 — moved to
**v1.17.1**, together with #1087 and #1107.

The reasoning is worth stating, because it is the criterion for the next sweep
too: the Horizon items are **contract surfaces another repository writes code
against**. The namespace URI is a `const` in Horizon's schema and the federation
namespace UUID does not exist yet, so getting either wrong later is a change to
every document in every fixture and every producing pipeline *at once*. Sonar
debt costs the same whenever it is done. One of those is worth a release slot and
the other is not.

<!-- markdownlint-disable MD013 -->

| Bundle | Issues | Theme | Est. |
| --- | --- | --- | --- |
| *delivered in flight* | **#1103** | PR **#1163**. Enrichment and region re-indexing were both PRIVATE to `AwsLabsCdefImportService`, so a CDEF uploaded through the UI resolved no NIST mappings and, if it arrived before its regions CDEF, no regions — permanently. Also re-vendored MITRE 106/rev4 → **394/rev4+5** and re-scraped Security Hub (595 → 597). Found and fixed the reason the squash defect escaped: the gate stack had **no database volume at all**, so every run was a fresh install. | delivered |
| **AE — Upgrade safety & release artifacts** | **#1151** ~~#1144~~ ~~#1164~~ | First, because it protects every release after it. **#1151** is the squash stamp assuming a database is already current — `high priority`, and #1103 has just built the mechanism it needs (`dev/ubi9/compose.baseline.yaml` runs the released image so the branch image upgrades real prior data). The supported hop is **v1.16.3 → current** (owner-decided 2026-09-20). **#1144** is the OpenVEX attestation naming a placeholder product (`HDFPID-0001`) instead of the image it describes — a supply-chain artifact that ships with every release and currently misidentifies its own subject. **#1144 and #1164 are DELIVERED** — `bin/vex_set_product_identity.rb` names the image by purl and digest and the release asserts that identity against the digest it attests, and the finding register was reconciled against a fresh grype scan of a UBI9 image built from the branch (CVE-2026-14456 retired as remediated, two versions corrected). **#1164 was filed after this table was written and appeared in no row until now.** #1151 remains, and is blocked on an owner decision — whether the generated reconciliation lands in it or splits out — with its re-scope still unapproved. | 3d |
| **AF — Catalog truth** | **#1115** **#1172** | Must precede **AI**: #1154's second ask is to publish the KSI mapping documents Horizon reads, and the catalog they would be published from has drifted. Measured against FedRAMP `2026.07.14.01`: five theme codes renamed (`EDU`→`CED`, `CM`→`CMT`, `IR`→`INR`, `POL`→`PIY`, `REC`→`RPL`), `AUTH` is no longer a KSI family at all, and **every** indicator id is re-keyed from numbered to mnemonic. SPARC is the flagship and this is the catalog customers see. **#1172 joined this bundle 2026-09-21**: #1115 fixes the data once, #1172 is the ingestion capability whose absence caused the drift. Measured live against `FedRAMP/rules` `2026.09.13.02` — SPARC seeds **11 themes / 54 indicators** from a 431-line hand-written Ruby seed, upstream publishes **10 / 46** plus a JSON Schema with `KSI` as a top-level property. There is a `KsiExportService` and no importer at all. | 2d + 3d |
| **AG — Identity contract** ✅ **DELIVERED** | ~~#1155~~ ~~#1162~~ | The root of the Horizon chain, and the cheapest work in the milestone. **#1155** registers the namespace URI (still the illustrative `https://risk-sentinel.org/ns/sparc`) and the federation namespace UUID, which **does not exist** — the spec carries a literal placeholder. Both are hashed inputs to every object identity in the estate. **#1162** settles the canonical control-id form: the API emits canonical in the catalog and raw everywhere else, and #1161's grammar canonicalises control ids *before* derivation, so an inconsistency here produces two UUIDs for one object. It also answers #1154's own open question, "is there a canonical form to target?" **DELIVERED 2026-09-21.** #1155 was partly a FALSE PREMISE: it asked to "confirm the real registered namespace URI" as though none existed, but `OscalNamespace::REGISTRY` has carried `https://sparc.risk-sentinel.org/ns` since #1106 and Horizon's schema const was a DIFFERENT URI. Owner-decided: Horizon adopts SPARC's, so no SPARC export moves and #1106 is not reopened. The federation namespace UUID is the UUIDv5 DERIVED from that URI (`9f434272-f796-589b-b972-954790395630`), so a peer recomputes rather than copies it, and `GET /api/v1/federation/identity` serves both with the derivation recipe. #1162 fixed the API write and filter paths; its first item was misdiagnosed — the model has canonicalised since #911, and the real defect was the controller comparing RAW input against canonical storage, so a no-op update destroyed and recreated every link. **A second, older bug surfaced with it**: `evidence_control_links` had no `autosave`, so unlinking a control never took effect on either surface. | 3d |
| **AH — Key grammar & dedup** ✅ **DELIVERED** | ~~#1161~~ ~~#1159~~ | **#1161** ports the UUIDv5 key grammar to Ruby and Python with a shared test vector file — the deliverable that matters most, because three independent implementations of a hashing grammar will disagree eventually and vectors make agreement *measured* rather than assumed. Four details drift silently: the `\x1f` separator (a printable one makes `("a|b","c")` and `("a","b|c")` collide), the grammar version being part of the hashed input, control-id canonicalisation, and NFC normalisation. **#1159** is the security half: the namespace is shared and the grammar is public, so **any peer can precompute another boundary's object UUID and claim it**. Dedup must key on **(object UUID, originating party)**, and two parties asserting one UUID is a conflict to surface, not a duplicate to collapse. Ships after #1161 because the rule is only true if runtimes derive the same UUID. **DELIVERED 2026-09-21.** The vectors were NOT authored here — Horizon already shipped 26 of them, declaring themselves provisional and naming #1155 as the blocker, so this adopted them, regenerated every uuid under the registered namespace, and made the field lists MACHINE-READABLE (upstream they were only implied by each vector's `canonical-fields`). Deriving them surfaced three rules the normative table does not state: **`vocabulary` is never hashed and decides whether a control id may be canonicalised** — under an opaque vocabulary `ACM.1` and `acm.1` are two Security Hub controls, and the first field lists written here canonicalised unconditionally until vector 26 caught it; the 11 rejections are a **validation** spec needing field types, not just presence checks; and an AO decision's `period` is a DATE. SPARC had no dedup code at all, so #1159 establishes the rule rather than fixing a bug, and `FederationBundleSigningService.verify` now returns the verified party so the scoping value comes from verification rather than the payload. | 5d |
| **AK — Deviation approval, mechanized** ⏳ **IN FLIGHT** | **#871** | **Next after AH.** A single admin cannot approve their own PR, so `deviation-requested` -> `deviation-approved` is structurally unreachable and the only route is an admin merge past a red gate. AH hit this for real: six base-image HIGH findings that are present but unreachable and have no upstream fix need a `risk_adjustment`, and there is no way to grant it. **PR #1173 merges by override, so `main` carries six `deviation-requested` entries and the container gate stays RED until this lands.** The flow is an admin commenting `/approve-deviation` — a comment is not a review, so the self-approval block never applies — with a workflow that verifies the commenter, flips the state and pushes with an App or PAT token, because a `GITHUB_TOKEN` push does not trigger workflow runs. Two properties must hold: workflow AND logic come from `main` (a PR that supplies its own `apply_deviation_approval.rb` would self-approve), and `action: created` only. **The escape hatch it retires, `admin-merge-bypass`, has ZERO spec coverage today** while carrying 8 retired entries. #871's own PR carries no deviation so nothing blocks it; the first deviation PR after it is the live test, and #1173's six are already queued to be it. **IN FLIGHT 2026-09-22.** Opening it found that **#1173 had broken `apply_deviation_approval.rb`**: the script edits the register line by line — deliberately, because a YAML round-trip destroys its comments — and #1173's round-trip re-indented the file, so its depth-pinned matchers matched nothing and it refused every approval. Sixteen green specs missed it because each built its own fixture at the old depth; **the fixture was never the artifact**. Repaired, and four specs now drive the applier against the committed register itself. The flow departs from the issue text in one place: the mechanism is recorded as `approve-deviation-comment`, not `review`, because no review occurs and the gate corroborates against the COMMENT list. | 3d |
| **AI — Horizon contract surface** | **#1154** | Three asks of very different sizes, and the issue sequences them itself: item 1 gates Horizon's **P0**, items 2–3 gate P1/P2. (1) `sparc-validate` rules for the nine SPARC-namespace props — the schema exists and is already green in Horizon's CI, 17 assertions in both directions, adoptable as-is; a missing `parent-uuid` does not error, it produces a node that disappears from every rollup above it. (2) Publish the KSI and 800-53 mapping documents, with per-mapping provenance and a confidence signal — depends on **AF**. (3) Confirm the Delivery API surface: which endpoints serve SSP/AR/POA&M, ETag support, how attestations and AO decisions come back, and whether mTLS is the inter-service model. | 6d |
| **AJ — Security tail** | **#1109** | Independent of the chain. The tail is **201 inline styles across 71 files** re-measured 2026-09-20, not the 254 across 94 the issue was filed with on 2026-09-05 — intervening work cleared ~53 declarations and 23 files, and the issue's own file table is stale by that much. Counted like for like (its table says `evidences/show.html.erb` 9; it measures 9). None holding ten — the flat tail #1047 stopped at 83%. It is the only thing standing between SPARC and removing `style-src 'unsafe-inline'`, which is binary: it comes out at zero or not at all. | 3d |

**The ordering that matters is AG → AH → AI**, with AF before AI. Register the
namespace, settle the canonical control id, port the grammar and prove the
runtimes agree, state the dedup rule, then confirm the surface. Doing AI first
would mean writing the contract against a namespace URI that is still
illustrative and a federation UUID that does not exist.

AE and AJ are independent and can run in parallel with the chain.

<!-- markdownlint-enable MD013 -->

#### What has to be decided before this phase can be estimated

1. **Is v1.17.0 a patch or a minor?** Its number says patch; #1105, #1089 and
   #1099 are not patch-shaped. The milestone's name may be wrong rather than its
   contents.
2. **#1104 and #1133 overlap and nobody has reconciled them.** #1104 (filed
   09-04) measures **~40 findings on `main`**; #1133 (filed 09-16) measures
   **191**. Both are open, both are Sonar triage, and the difference is almost
   certainly *what was scanned* rather than a real change. Reconcile them against
   one live measurement before either is planned, or the bundle is scoped against
   a number nobody trusts.
3. **#1046 is already owner-ACCEPTED.** Closing it is a decision, not work, and
   it should not sit in a bundle as though it were work.
4. **Three empty milestones are still open** (`v1.16.0`, `ci.v0.0.1`,
   `v1.16.1`) — see *Open work* below.

#### The cadence this phase inherits

Five bundles in v1.16.1 came in at or under estimate; the one that did not (Z,
4d → 10d) overran because an owner screen-review discovered the work *after* it
was scoped. **AD is the cleanest datapoint: ~2 days for three issues, because
#1106's audit had already measured the defects it would fix.** The rule that
keeps holding: an estimate is reliable when the work was measured first. AG is
unestimated for exactly that reason.

---

---

## Open work — measured 2026-09-20 (re-measured after the open-issue sweep)

Re-measured against the live repository, not carried forward. **553 issues**;
**519 are closed**, **34 open**. What remains:

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
> gh issue list --state closed --limit 3000 --json number --jq 'length'   # 514
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
| Closed | **514** |
| Open, on `ci.v0.0.1` | **0** — the milestone closed 2026-08-30 at **22 issues** (+ 8 PRs) |
| Open, on `v1.16.1` | **0** — all 22 closed; **tagged 2026-09-17** |
| Open, on `v1.17.0` | **10** — #1103 #1109 #1115 #1144 #1151 #1154 #1155 #1159 #1161 #1162, re-sequenced by the owner 2026-09-20 |
| Open, on `v1.17.1` | **8** — #1046 #1063 #1087 #1104 #1107 #1120 #1131 #1133. Milestone created 2026-09-20 to hold the deferred debt and the two UI tails |
| **Open, on NO milestone** | **19** (27 earlier on 2026-09-20, 24 on 09-17, 22 on 09-05, 25 on 09-03, 10 on 08-25) — see below |

The reconciliation: 0 + 8 + 8 + 18 = 34, and 519 + 34 = 553 (re-measured 2026-09-21 with the AH bundle PR; #1155 and #1162 closed with PR #1171, #1161 and #1159 close with this one, and **#1172 was filed onto v1.17.0** — FedRAMP KSI schema ingestion, the capability whose absence produced #1115's drift — and **#871 was brought onto it from unmilestoned** when AH proved the deviation-approval gap is not theoretical).

> **Three milestones are still OPEN on GitHub with zero open issues** — `v1.16.0`,
> `ci.v0.0.1` and `v1.16.1`. Closing a milestone is an owner action and none is
> closed here; it is recorded because an open milestone with nothing in it reads
> as work in flight to anyone scanning the milestone list.

**The no-milestone count went DOWN for the first time**, 25 → 22, and the
movement is worth reading rather than the net: **six closed** with PR #1102
(#1090 #1092 #1093 #1094 #1095 #1096 — the Bundle Z fold-ins), **three new**
were filed out of the work that followed it (#1103 #1104 #1105 — #1103 and
#1104 have since moved to v1.17.0), and **#1106** was filed and milestoned
straight onto v1.16.1. The discovery factor has not
stopped; a bundle merged faster than it filed, once.

### The nineteen with no milestone

> **This register had fallen five issues behind when it was re-measured on
> 2026-09-20** — #1144, #1154, #1155, #1159 and #1161 were open and unmilestoned
> and appeared in no row, while the heading still read twenty-four. The register
> exists precisely because #950 went missing by sitting in it, so a row that is
> never added is the failure mode, not a formatting detail. Re-measure the list
> itself, not only its count.
>
> **All five were milestoned onto v1.17.0 hours later, in the same day's sweep** —
> four of them are the `sparc-horizon` contract chain and one is the OpenVEX
> product-name defect. That is the cost of the register falling behind stated
> plainly: they were not low-priority, they were *invisible*.

These are invisible to every milestone count, which is exactly how **#950 went
missing** — it sat open with no milestone after being split from #949, appeared
in no bundle, and was only picked up when the owner milestoned it on 2026-08-22.
Listing them so the same thing cannot happen quietly again. **Each needs a
milestone or a deliberate decision to close — that call is the owner's.**

**The count more than doubled between 2026-08-25 and 09-03, then fell for the
first time on 09-05.** That is the discovery factor working as documented rather
than a backlog going unattended: PR #1102 closed six of them at once, and the
work that continued after it filed three more. Twelve of the twenty-two were
filed out of Bundle Y and Bundle Z. The +62% figure this plan applies to
milestone sizing is visible here in the raw.

Re-measured 2026-09-17 with `gh issue list --state open --limit 3000`, filtering
on a null milestone — never off this file, and never off a milestone page, which
counts PRs too. **Since 09-05:** #980 and #1088 closed on 2026-09-10 with the
Bundle Z work, and four were filed: #1107 and #1108 on 09-05, #1115 on 09-07,
and #1121 on 09-11.

| Issue | Opened | Title |
| --- | --- | --- |
| **#422** | 2026-04-27 | POAM Scenario B — cross-instance federated POAM visibility (carved from #415) |
| **#531** | 2026-05-23 | security(uploads): optional GuardDuty S3 tag check hook on blob serving (post-v1.7.0) |
| **#752** | 2026-07-18 | Pre-release container smoke gate + release report — block render-broken images from shipping (post-#750) |
| **#776** | 2026-07-20 | security: Go stdlib CVEs in hdf-cli (hdf-libs-owned) — needs upstream Go >= 1.26.2 rebuild |
| **#815** | 2026-07-26 | XML fingerprinting: strict namespace/version enforcement + centralization (decisions) — follow-up to #341 |
| **#838** | 2026-07-27 | chore(toolchain): emit SPARC's hdf-cli findings to consuming repos — pin belongs in sparc-ci-runner, not per-repo |
| **#864** | 2026-07-29 | security(kev): make CISA KEV a first-class input to triage, gating and POA&M prioritisation (BOD 26-04 / FedRAMP) |
| **#871** | 2026-07-30 | compliance(ci): mechanize deviation approval — /approve-deviation comment, token-triggered pipeline, retire the admin-merge-bypass |
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

**Six rows left this table on 2026-09-05** — the Bundle Z fold-ins
(#1090, #1092, #1093, #1094, #1095, #1096), closed by PR #1102 rather than by a
milestone decision.

**#1100 has NOT left it**: the design question it raises is answered on the
Bundle Z branch, but the issue stays open and unmilestoned until the owner
reads the implementation, because the fix chose an interpretation of
`implemented-requirement.statements` that is the owner's call to confirm.

**#1087 is worth a decision sooner than the rest.** It is the only one that
degrades the gate itself: every page's `load` event waits on cdn.jsdelivr.net,
which is where the intermittent 30s ui-smoke navigation timeouts come from. A
flaky gate gets ignored, and this plan leans on that gate.

**Five of the older six are CI-pipeline work** — #752, #776, #838, #864 and
#871. They sit squarely alongside what `ci.v0.0.1` did, and #871 in particular is
the approval mechanism CI-1 leaned on when dispositioning #1065.

My read, offered as a starting point rather than a decision:

- **#1099, #1100 and #1101 are DESIGN questions, not defects**, and they are the
  three most consequential things the owner's review produced. #1099 (findings
and risks are unrelated in SPARC where OSCAL relates them n:m through
`finding.related-risks`) and #1100 (control sub-parts are aggregated, so an
assessor cannot respond per part) both change the data model; neither belongs
in a bundle until it is decided.   **#1100 was decided by implementing it,
which is a departure worth naming.**   The owner's instruction was *fix now,
then proceed*, so the data-model change   shipped on the Bundle Z branch rather
than waiting for a bundle: catalog parts   are now stored, and an SSP carries
one statement per addressable part. It is   still listed here as open because
the design question — what   `implemented-requirement.statements` should
contain for a control the catalog   gives no statement, and whether the flat
fallback for pre-existing documents is   the right compromise — is the owner's
to confirm on review. **#1099 and #1101   are untouched.** - ~~**#980**~~ (CDEFs need an
authorization boundary) **closed 2026-09-10** with the Bundle Z work. - **#953** (authenticated DAST against the two-boundary fixture)
belongs with the CI   milestone if it belongs anywhere — the fixture it needs
(#845) already shipped. - **#422** and **#531** have been open longest and may
simply be closeable.

### Everything else

The **6** milestoned open issues are all on `v1.17.0` and are bundled in Phase 19
below. (`v1.16.1` tagged 2026-09-17 at 22 issues; `ci.v0.0.1` closed 2026-08-30 at
22.) **Re-verified 2026-09-17, after the tag:** no open issue sits on a shipped
milestone, and every open `v1.17.0` issue appears in exactly one proposed bundle.

**Re-verified 2026-09-05, and the previous verification had gone stale.** This
paragraph asserted on 2026-09-02 that "every open issue on the milestone appears
in exactly one bundle". By 09-05 that was false in both directions:

- **#1063** and **#1106** were on the milestone and in **no bundle** — #1106
  because it was filed and milestoned on 09-03, after the check; #1063 because
it   moved here from CI-1 and was never picked up by a bundle. Both are now in
a new   **AC** row in Phase 18, marked unsequenced, because putting them
somewhere is   not the same as the owner deciding where they go. - **Bundle Y's
four issues are all closed**, so the "no bundle cites an issue   that is not
open" half now needs reading as "no *open* bundle does" — Y is   struck through
and kept as a record.

**The check is only worth anything if it is re-run.** It passed on 09-02 and was
wrong within a day, because a milestone gains issues from the work in flight.
Re-run it whenever the milestone list changes, not on a schedule.

The six Bundle Z folded in (#1090 #1092 #1093 #1094 #1095 #1096) are **not** on
the milestone — they are in the unmilestoned table above and are being closed by
the bundle's PR rather than by a milestone decision.

**#1046 is NOT addressed by this PR.** The commit that removes the duplicate
family heatmap from the SAR and SAP screens originally cited `(#1046)` in its
subject. That reference was wrong — #1046 is `research(sonar): revisit S7875 —
explicit route action mapping, 213 occurrences in config/routes.rb`, which this
branch does not touch — and the subject was corrected before the branch was
pushed, so no cross-reference reaches the issue. The heatmap removal is
owner-review work carrying no issue, and the PR body uses no closing keyword for
#1046.

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
| 14 | **Complete** | Pre-Public-Flip + API Test Validation + CDEF Mutations | ~~#545~~ ~~#433~~ ~~#498~~ ~~#499~~ ~~#528~~ ~~#447~~ ~~#341~~ ~~#246~~ ~~#413~~ ~~#616~~ ~~#618~~ · carried: **#531**, **#422** | **COMPLETE** — measured 2026-08-25: **11 of its 13 issues are closed**. It had been marked "In Progress" long after the fact. The two still open (#531, #422) carry **no milestone** and are already tracked in *The nineteen with no milestone* below — they are not Phase 14 work in flight, they are untriaged backlog. Note #528 was closed over its own undone tail; that tail is **#1047** in v1.16.1 Bundle Z |
| 15 | Complete | v1.15.4 / v1.15.5 patches — account-lifecycle and UX defects | ~~#868~~, ~~#869~~, ~~#870~~, ~~#867~~, ~~#878~~, ~~#877~~, ~~#875~~, ~~#881~~, ~~#887~~, ~~#888~~, ~~#902~~, ~~#903~~, ~~#911~~ | **COMPLETE** — v1.15.4 and v1.15.5 shipped. #879 (field-help copy) was not done here and is carried into Phase 16. #911 shipped in PR #916/#918; the boundary-roster authorization bug found during it became #919 |
| 16 | **Complete** | v1.16.0 — config correctness, authorization sweep, UX filters, auth entitlements, OSCAL fidelity (milestone `v1.16.0`) | **87 issues, 87 closed. Tagged `v1.16.0` 2026-08-24** from `main` @ `75b5bb3b`. The full closed list is the milestone itself — do not maintain a second copy here | **SHIPPED.** Bundles ran #939 → O → S → P → T → Q → hdf pin → U → W → V → R → X. Bundle X merged as [PR #1049](https://github.com/risk-sentinel/sparc/pull/1049) → `9ae84a84`; [PR #1055](https://github.com/risk-sentinel/sparc/pull/1055) → `75b5bb3b` then fixed four defects Bundle X had merged, found by running the FULL suites against a built prod image. Release verification (measured, on the tagged tree): rspec **6230/0**, API **2742 passed** over TLS and again over non-TLS, ui-smoke **524 passed / 0 failed**, rubocop + brakeman + bundle-audit clean. The milestone grew **53 → 86 because the sweeps FOUND things**, not through scope creep. Wiki published and release notes carry the measured table |
| 17 | **Complete** | `ci.v0.0.1` — evidence and gates | **0 open, 22 closed** — re-measured 2026-09-05 with `gh issue list --milestone ci.v0.0.1`. This row read **30 closed** until then; that is the milestone **page's** number and it counts the milestone's **8 PRs** alongside its issues. CI-1 #1048 #1050 #987 #885 · CI-2 #962 #985 #990 #1027 · CI-3 #835 #927 #711 #1061 · CI-4 #858 #859 #965 #917 · filed and closed out of it: #1064 #1065 #1067 #1080 | Closed **2026-08-30**, three working days ahead of the ~09-02 the cadence predicted. **CI-1**: `security_gate` had never assessed a single HDF — `saf validate threshold -F` names a flag that has never existed in any released saf, oclif rejected the parse, `saf_action` reported a warning and exited 0, and the next step wrote "Security gate passed". **CI-2**: several of the 12 HDFs had ZERO controls, and a zero-control document passes every band trivially — a clean scan and a broken scanner were the same green check. **#1080** closed the milestone by finding that local scans disagreed with CI 68-to-0 because `.dockerignore` did not exclude gitignored local scan output: `COPY . .` baked a developer's own CycloneDX SBOM into the image and Trivy parsed it back as installed packages. CI was correct throughout. Inventory: `docs/compliance/scan-artifact-inventory.md`. Estimated 8 → revised 11 → **actual ~7 working days** |
| 18 | **Complete** | v1.16.1 — the patch release | **0 open, 22 closed. Tagged `v1.16.1` 2026-09-17** from `main` @ `df6439c0`, against a ~09-22 soft target. Bundles Y → Z → AA → AB → AC → AD, all delivered. Earlier detail: **AB DELIVERED 09-12 → 09-13** (PR #1125 #1126 #1128; 5d est → 2d). **AC resolved 09-16**: #1106 + #1124 in PR #1130, #1063 → v1.17.0. **AD — #1116 #1117 #1134 — in PR, the last bundle.** Earlier: **Y SHIPPED 2026-08-31** (3d est → 1d). **Z DELIVERED 2026-09-10** (4d est → 10d; the overrun was the OSCAL assessment chain an owner screen-review uncovered, not the sweep). **AA DELIVERED 2026-09-11** via [PR #1119](https://github.com/risk-sentinel/sparc/pull/1119) and [PR #1122](https://github.com/risk-sentinel/sparc/pull/1122) — #978 #1059 #1082 #1044, **3d est → 2d**. AA filed two issues out of its own work: **#1120** (audit all 125 SPARC_* variables, v1.17.0) and **#1123** (the CI gate times out on healthy runs, owner-scheduled onto AB). Bundles: ~~Y~~ · ~~Z~~ · ~~AA~~ · ~~AB~~ · ~~AC~~ · ~~AD~~ | Estimated **14 working days**, target **~2026-09-22 and soft**. **Re-measured after AA:** Y 3d→1d, Z 4d→10d, AA 3d→2d. Two of three bundles have come in at or under estimate; the one that did not was the one whose scope was discovered by an owner screen-review AFTER it was scoped. **That is the pattern worth acting on — the estimate is reliable when the work is measured first, and unreliable when a review finds the work mid-bundle.** **AB is the largest remaining bundle and contains an owner-decision item (#1033) and a 281-finding triage (#966); it should be re-scoped before it starts rather than after.** |

| 19 | **Current** | v1.17.0 — unblock Horizon, fix what customers hit | **10 open, 0 closed** (re-sequenced by the owner 2026-09-20): #1103 #1109 #1115 #1144 #1151 #1154 #1155 #1159 #1161 #1162. Bundles **AE** (upgrade safety & release artifacts — #1151 #1144), **AF** (catalog truth — #1115), **AG** (identity contract — #1155 #1162), **AH** (key grammar & dedup — #1161 #1159), **AI** (Horizon contract surface — #1154), **AJ** (security tail — #1109). #1103 is delivered in flight via PR #1163. **The chain is AG → AH → AI, with AF before AI**; AE and AJ run in parallel. | 22d across six bundles. The milestone is no longer debt: six debt issues moved to v1.17.1, and what remains is a dependent repository's contract surface plus the defects customers actually hit |
| 20 | Planned | v1.17.1 — the deferred wave | **8 open, 0 closed** (milestone created 2026-09-20): #1046 #1063 #1087 #1104 #1107 #1120 #1131 #1133. The Sonar backlog (#1104 #1133 #1046), the gates that must mean something (#1063 #1131 #1120), and two UI tails — **#1107**, where `.sparc-d-none` is defined before all 70 component classes that bake a `display` value and so loses the cascade to every one of them, and **#1087**, where every page's `load` event waits on `cdn.jsdelivr.net`. | est. TBD — scope when v1.17.0 is cut |

<!-- markdownlint-enable MD013 -->

**Re-measured 2026-09-20, after the open-issue sweep** (`gh issue list --state
all --limit 3000`): **551 issues total — 514 closed, 37 open.** Open splits **0**
on `v1.16.1` (tagged 2026-09-17 at **22 issues**), **10** on `v1.17.0`, **8** on
`v1.17.1` (created 2026-09-20), **0** on `ci.v0.0.1` (closed 2026-08-30 at **22
issues**), and **19** with no milestone.
0 + 10 + 8 + 19 = 37, and 514 + 37 = 551. *(09-17 measurement: 540 total, 510 closed,
30 open. 09-05: 525 total, 488 closed,
37 open.)* Since 2026-09-03: PR #1102 closed **six** of
the unmilestoned spot-check issues, and **four** new ones were filed out of the
work that followed it (#1103 #1104 #1105 unmilestoned at the time — #1103 and
#1104 are now on **v1.17.0** — and **#1106** milestoned onto v1.16.1). The
no-milestone count fell for the first time, 25 → 22; it has since risen to 27.

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

> **Resolved:** `VERSION` in `app/models/sparc_config.rb` reads **1.16.0** and
> matches the tag. Session notes had carried "still 1.15.5" forward from before
> the release; verified against the file on 2026-08-25, it is correct.
