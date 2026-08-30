# SPARC Open GitHub Issues -- Implementation Strategy

Structured, prioritized roadmap for the open issues in the SPARC
GitHub repository.

**Last updated:** 2026-08-25

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

**v1.16.0 shipped 2026-08-24** (tag `v1.16.0`, `main` @ `75b5bb3b`). Milestone
closed **86/86**. Owner decision: **the CI milestone runs BEFORE the v1.16.1
patch work**, so v1.16.1 gets real-environment soak time rather than shipping on
the heels of the release it patches.

**Measured velocity — read from the repo on 2026-08-24, not estimated:**

| Measure | v1.16.0 actual |
| --- | --- |
| Issues closed | 87 over **14 calendar days** (2026-08-11 → 08-24) |
| Per calendar day | **6.2** raw · **4.2** excluding the Bundle V discovery spike |
| PRs merged | **26** in the window = **1.9/day**, median **1 day** between merge days |
| Milestone growth during execution | **53 → 86 issues (+62%)** |

Two things that table is saying, and they pull in opposite directions:

1. **The raw rate flatters us.** 32 of the 87 closed on a single day (2026-08-22)
   because Bundle V *filed and closed* them inside its own sweep. Planning
   against 6.2/day would assume that repeats. **Use 4.2.**
2. **The backlog is not the workload.** The milestone grew by **62%** while it
   was being worked. A 16-issue milestone should be planned as roughly **25**,
   because the sweeps find things. That is not scope creep — every one was a
   defect already shipped and previously invisible.

**Open: 15, closed 5** — re-measured against the live repository on 2026-08-25,
after CI-1 merged and #977 was closed as superseded. The milestone was written
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
| **CI-2 — Evidence completeness** 🔄 **IN REVIEW** (PR #1068) | #962 #985 #990 #1027 (~~#977~~ **closed as superseded**; **#917 → CI-4**) | Not the gap the issues described. Gitleaks **has** been converted since 2026-03-15 (#186); the real defect is that a **zero-control HDF passes every band trivially**, so a clean scan and a broken scanner are the same green check. Fixed by moving the SARIF conversions to `hdf convert` (which names the scanner and emits an execution record), an injected canary for the saf-path scanners, and a gate that asserts both the canary and the expected scanner set. | 3d |
| **CI-3 — Test-job fidelity** | ~~#835~~ ~~#927~~ ~~#1061~~ · **#711 re-aimed** | Shipped: pinned `hdf-cli` in the test job so the OSCAL specs run rather than skip (#835); the deprecation wall cleared, which was also a scheduled Rack failure (#927); the wiki now publishes on merge (#1061). **#711 was re-aimed 2026-08-26 (owner):** checking a DEPLOYED instance is sparc-dast's job and does not belong here. It becomes an **in-runner pre-release gate** — build the prod image, stand it up, run the suites against it, block the release. Measured: no workflow does this today. `build-sign-publish` starts the image and runs `bin/rails --version` against it; `security.yml` builds and only SCANS. | 2d |
| **CI-4 — Posture and architecture coverage** | #858 #859 #965 **#917** | Release smoke runs one TLS posture and one does not imply the other (#858); **the arm64 half of every published image ships unverified** (#859) — which matters more now that `build-sign-publish` emits a multi-arch manifest on every tag; metrics collide in the bucket root (#965). **#917 moved here from CI-2** (2026-08-25): attesting SCA results with `cosign attest` is the same shape as #859 — both are about whether a consumer can verify something about a **published artifact**, and both change `build-sign-publish.yml`, so they share one pass through the build/sign/publish path and the same `cosign verify-attestation` testing surface. | 3d |

**Estimate: 11 working days, target 2026-09-08.** The original figure was 8
(bundle work bracketed 6–9 by two methods). **CI-1 superseded it** — see the
revision under *CI-1 — landed* below, which is the number that governs. The two
were left contradicting each other in this section until 2026-08-25.

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

### CI-2 — in review 2026-08-25

**The bundle's stated premise did not survive measurement, and the real defect
was larger.**

**#962 is stale.** "Gitleaks SARIF is never converted to HDF" was wrong against
`main`: it has been converted since **2026-03-15** (`f8f3b4ab`, #186),
`security.yml:1135`. The organisation-wide audit that filed it read the scan step
and missed the conversion job. Only its third acceptance criterion — verify on a
SARIF containing an actual finding — was genuinely unmet, and that is now done.

**What was actually wrong.** A zero-control HDF passes every threshold band
trivially: saf compares `count > max`, so against no controls every count is 0.
Measured on run `32840183630`, the first run with CI-1's gate live, **gitleaks,
brakeman and bundler-audit all reached the gate as zero-control documents sitting
under all-zero bands**, and 5 of 12 HDFs were anonymous (`profiles[0].name` =
`"SARIF"`). So a scanner that ran and found nothing was byte-identical to one
that never ran — for the secrets scanner, the highest-consequence vacuous pass in
the pipeline.

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

**Open: 18** (measured 2026-08-30 with `--limit 300` — the 17 previously audited
plus **#1082**, filed out of the CI work). **This is the current phase.** Phase 17
closed **2026-08-30 at 30/30**, three working days ahead of the ~09-02 the
cadence predicted.

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

| Bundle | Issues | Theme | Est. |
| --- | --- | --- | --- |
| **Y — Reliability, and the deadline** | **#968** (due 09-06) #1051 #1022 **#1058** | The rescue-pattern audit (54 sites, 11 log-and-continue in services/jobs, 17 combining a transaction with a rescue). Alongside it the two correctness defects the release run surfaced: 163 of 232 CDEFs export schema-invalid OSCAL (#1051) and `/api/v1/controls` ignores `?items`/`?per_page` so 4,054 rows come back whole (#1022). | 3d |
| **Z — The CSP tail** | #1047 #728 #1046 | **#528 was closed with two of its four items explicitly undone.** Removing `style-src 'unsafe-inline'` means 1,399 inline styles, and Trusted Types has to be settled rather than deferred again. #728 (30 contrast findings vs our WCAG AA gate) and #1046 (S7875, 213 route occurrences) are the same surface. **Largest single item in either milestone.** | 4d |
| **AA — Auth and access debt** | #978 #1044 **#1059** **#1082** | Signing in over plain HTTP on a prod-mode container fails **silently** on a CSRF Origin mismatch (#978) — a support call that looks like broken auth. #1044 adds a time-boxed instance administrator via the IdP, distinct from the break-glass account, which is the natural follow-on from Bundle R. **#1082** consolidates enable-vs-require: `SPARC_REQUIRE_AUTH_METHODS` does not imply enablement, so requiring a method that is not enabled locks every non-break-glass user out at request time rather than failing at boot. | 3d |
| **AB — Onboarding, and the Sonar backlog** | #1040 #940 #1033 #930 #966 #836 | The guided boundary onboarding flow (#1040) is a feature, not a fix — it takes a team from "a pile of Word documents" to a boundary SPARC can work with, and carries the platform axis that makes CDEF recommendation possible. #966 triages 281 SonarCloud findings including 2 Blockers. | 5d |

**Estimate: 14 working days.** The issue count is smaller than v1.16.0's but the
*weight* is not: #1047, #1040 and #966 are each multi-day, where much of v1.16.0
was small defects found in sweeps. Do **not** plan this milestone at 4.2
issues/day — that rate was earned on a different size distribution.

### Timeline

Back-to-back, from **2026-08-24**, working days only, at the measured cadence of
one bundle every 1.5–2 days:

| Window | Work | Milestone |
| --- | --- | --- |
| **08-24 Mon** | CI-1 — gates that can fail | ✅ **merged**, PR #1066 |
| **08-25 Tue** | CI-2 — evidence completeness | 🔄 **in review**, PR #1068 |
| 08-26 → 08-29 | CI-3 + CI-4, and the unbundled tail (#1064 #1065 #1067 #1080) | ✅ ci.v0.0.1 |
| **08-30 Sun** | **`ci.v0.0.1` closes at 30/30** — *three days ahead of the ~09-02 predicted* | ✅ |
| **08-31 → 09-04** | **Y — reliability (#968 due 09-06, now with five working days)** | v1.16.1 |
| 09-07 → 09-10 | Z — the CSP tail | v1.16.1 |
| 09-11 → 09-15 | AA — auth and access debt (now carries #1082) | v1.16.1 |
| 09-16 → 09-22 | AB — onboarding and Sonar | v1.16.1 |
| **~09-23** | **`v1.16.1` tag** | |

**The re-measure is settled: the measured cadence was right.** `ci.v0.0.1` closed
**2026-08-30 at 30/30**, against a measured-cadence prediction of ~09-02 and a
standing conservative estimate of 11 working days → 09-08. **Actual: ~7 working
days.** The conservative bound was wrong by more than the cadence was.

Worth recording *why*, because the same reasoning will be applied to v1.16.1: the
gap was said to be "entirely CI-3 and CI-4", on the grounds that #859 and #711
were not the concentrated-in-one-file shape that made CI-1 and CI-2 cheap. That
held — those were the expensive bundles — but the milestone still landed early
because four issues filed *out of* the work (#1064 #1065 #1067 #1080) turned out
to share one root cause each rather than needing separate investigations.

**The caution transfers, and inverts.** v1.16.1 is weighted toward large single
items (#1047, #1040, #966), where CI's work was weighted toward pipeline wiring
with known shapes. Do not carry the 7-day result into this milestone as a rate —
it was earned on a different distribution, which is the same mistake the v1.16.0
cadence note warns about. **Re-measure after Bundle Y.**

**Confidence.** The CI window is the firmer of the two: its issues are mostly
pipeline wiring with known shapes. The v1.16.1 window depends almost entirely on
#1047 — if Trusted Types forces a refactor rather than a policy change, Z slips
and everything after it moves with it. The historic pattern says the count will
also grow: apply **+62%** and this becomes **early October**, which is the honest
outer bound rather than the target.

**What would make this wrong.** v1.16.0 ran at 4.2 issues/day on a distribution
dominated by small sweep-found defects. Both remaining milestones are weighted
toward large single items. **Re-measure after CI-2** — if the first two bundles
land on schedule the cadence holds; if they slip, the v1.16.1 dates are fiction
and should be redrawn rather than defended.

---


---

## Open work — measured 2026-08-25

Re-measured against the live repository, not carried forward. **503 issues**;
**461 are closed**, **42 open**. What remains:

> **The closed count in this section was itself stale until 2026-08-25.** It read
> "282 issues, 252 closed" while the repository held 503 and 460 — the open
> figures below had been re-measured and the closed ones carried forward, in the
> very section that exists to stop counts being carried forward. Both figures now
> come from the same command, and the open breakdown reconciles: 15 + 17 + 10 = 42.
>
> ```bash
> gh issue list --state closed --limit 1000 --json number --jq 'length'   # 461
> gh issue list --state open   --limit 1000 --json number --jq 'length'   #  42
> ```
>
> `--limit` must exceed the real count or the answer is silently truncated to the
> limit — reading 400 back from `--limit 400` is a truncation, not a measurement.

| State | Count |
| --- | --- |
| Closed | **461** |
| Open, on `ci.v0.0.1` | **15** — re-measured 2026-08-25 after #977 was closed as superseded. CI-1 closed #885 #987 #1048 #1050 and filed #1064 #1065 #1067; #1061 also joined |
| Open, on `v1.16.1` | **18** (14 audited + #1058, #1059, #1063, #1082) — measured 2026-08-30 |
| **Open, on NO milestone** | **10** (was recorded as 4 — the count was wrong) |

### The ten with no milestone

These are invisible to every milestone count, which is exactly how **#950 went
missing** — it sat open with no milestone after being split from #949, appeared
in no bundle, and was only picked up when the owner milestoned it on 2026-08-22.
Listing them so the same thing cannot happen quietly again. **Each needs a
milestone or a deliberate decision to close — that call is the owner's.**

**The previous count of 4 was itself wrong.** Re-measured against the live
repository on 2026-08-24 there are **ten**, and the six that were missing had
been invisible for between four weeks and five months. That is the same failure
this section exists to prevent, occurring inside the section that documents it.

| Issue | Opened | Title |
| --- | --- | --- |
| **#422** | 2026-04-27 | POAM Scenario B — cross-instance federated POAM visibility (carved from #415) |
| **#531** | 2026-05-23 | security(uploads): optional GuardDuty S3 tag check hook on blob serving (post-v1.7.0) |
| **#752** | 2026-07-18 | Pre-release container smoke gate + release report — block render-broken images |
| **#776** | 2026-07-20 | security: Go stdlib CVEs in hdf-cli (hdf-libs-owned) — needs upstream Go >= 1.26.2 rebuild |
| **#815** | 2026-07-26 | XML fingerprinting: strict namespace/version enforcement + centralization |
| **#838** | 2026-07-27 | chore(toolchain): emit SPARC's hdf-cli findings to consuming repos |
| **#864** | 2026-07-29 | security(kev): make CISA KEV a first-class input to triage, gating and POA&M prioritisation |
| **#871** | 2026-07-30 | compliance(ci): mechanize deviation approval — /approve-deviation comment |
| **#953** | 2026-08-14 | feat(dast): authenticated DAST against the two-boundary reference fixture |
| **#980** | 2026-08-18 | feat(cdef): give component definitions an authorization boundary, so they can be scoped and tiered |

**Five of the six newly-surfaced ones are CI-pipeline work** — #752 (pre-release
container smoke gate), #776 and #838 (hdf-cli toolchain and its findings), #864
(KEV as a gating input) and #871 (mechanized deviation approval). They sit
squarely alongside what `ci.v0.0.1` is doing, and #871 in particular is the
approval mechanism CI-1 just leaned on when deciding how to disposition #1065.
Whether they join this milestone is the owner's call, but they should not stay
invisible while it runs.

My read, offered as a starting point rather than a decision:

- **#980** (CDEFs need an authorization boundary) is the closest to live work — it
  sits beside #1040's platform axis in Bundle AB, and shipping that flow without it
  may be awkward.
- **#953** (authenticated DAST against the two-boundary fixture) belongs with the CI
  milestone if it belongs anywhere — the fixture it needs (#845) already shipped.
- **#422** and **#531** have been open longest and may simply be closeable.

### Everything else

The **18** milestoned open issues (all on `v1.16.1`; `ci.v0.0.1` is closed) are
bundled in Phases 17 and 18 above. Re-verified 2026-08-25 after #977 closed and
#917 moved to CI-4: every open issue on both milestones appears in exactly one
bundle, and no bundle cites an issue that is not open.

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
| 14 | **Complete** | Pre-Public-Flip + API Test Validation + CDEF Mutations | ~~#545~~ ~~#433~~ ~~#498~~ ~~#499~~ ~~#528~~ ~~#447~~ ~~#341~~ ~~#246~~ ~~#413~~ ~~#616~~ ~~#618~~ · carried: **#531**, **#422** | **COMPLETE** — measured 2026-08-25: **11 of its 13 issues are closed**. It had been marked "In Progress" long after the fact. The two still open (#531, #422) carry **no milestone** and are already tracked in *The ten with no milestone* below — they are not Phase 14 work in flight, they are untriaged backlog. Note #528 was closed over its own undone tail; that tail is **#1047** in v1.16.1 Bundle Z |
| 15 | Complete | v1.15.4 / v1.15.5 patches — account-lifecycle and UX defects | ~~#868~~, ~~#869~~, ~~#870~~, ~~#867~~, ~~#878~~, ~~#877~~, ~~#875~~, ~~#881~~, ~~#887~~, ~~#888~~, ~~#902~~, ~~#903~~, ~~#911~~ | **COMPLETE** — v1.15.4 and v1.15.5 shipped. #879 (field-help copy) was not done here and is carried into Phase 16. #911 shipped in PR #916/#918; the boundary-roster authorization bug found during it became #919 |
| 16 | **Complete** | v1.16.0 — config correctness, authorization sweep, UX filters, auth entitlements, OSCAL fidelity (milestone `v1.16.0`) | **87 issues, 87 closed. Tagged `v1.16.0` 2026-08-24** from `main` @ `75b5bb3b`. The full closed list is the milestone itself — do not maintain a second copy here | **SHIPPED.** Bundles ran #939 → O → S → P → T → Q → hdf pin → U → W → V → R → X. Bundle X merged as [PR #1049](https://github.com/risk-sentinel/sparc/pull/1049) → `9ae84a84`; [PR #1055](https://github.com/risk-sentinel/sparc/pull/1055) → `75b5bb3b` then fixed four defects Bundle X had merged, found by running the FULL suites against a built prod image. Release verification (measured, on the tagged tree): rspec **6230/0**, API **2742 passed** over TLS and again over non-TLS, ui-smoke **524 passed / 0 failed**, rubocop + brakeman + bundle-audit clean. The milestone grew **53 → 86 because the sweeps FOUND things**, not through scope creep. Wiki published and release notes carry the measured table |
| 17 | **Complete** | `ci.v0.0.1` — evidence and gates | **0 open, 30 closed** (measured 2026-08-30, `--limit 300`). CI-1 #1048 #1050 #987 #885 · CI-2 #962 #985 #990 #1027 · CI-3 #835 #927 #711 #1061 · CI-4 #858 #859 #965 #917 · filed and closed out of it: #1064 #1065 #1067 #1080 | Closed **2026-08-30**, three working days ahead of the ~09-02 the cadence predicted. **CI-1**: `security_gate` had never assessed a single HDF — `saf validate threshold -F` names a flag that has never existed in any released saf, oclif rejected the parse, `saf_action` reported a warning and exited 0, and the next step wrote "Security gate passed". **CI-2**: several of the 12 HDFs had ZERO controls, and a zero-control document passes every band trivially — a clean scan and a broken scanner were the same green check. **#1080** closed the milestone by finding that local scans disagreed with CI 68-to-0 because `.dockerignore` did not exclude gitignored local scan output: `COPY . .` baked a developer's own CycloneDX SBOM into the image and Trivy parsed it back as installed packages. CI was correct throughout. Inventory: `docs/compliance/scan-artifact-inventory.md`. Estimated 8 → revised 11 → **actual ~7 working days** |
| 18 | Planned | v1.16.1 — the patch release | **17 open** (was 14; +#1058 #1059 #1063). Y reliability + the deadline (**#968 due 2026-09-06** #1051 #1022) · Z the CSP tail (#1047 #728 #1046) · AA auth and access debt (#978 #1044 #1059) · AB onboarding and Sonar (#1040 #940 #1033 #930 #966 #836) | Estimated **14 working days**, target **~2026-09-24**. **#968 is the only dated item in either milestone and must ride the FIRST bundle** or the date moves. Do NOT plan this at v1.16.0's 4.2 issues/day — that rate came from a distribution of small sweep-found defects; #1047, #1040 and #966 are each multi-day. Re-measure after CI-2 |

<!-- markdownlint-enable MD013 -->

**Measured 2026-08-25** (`gh issue list --limit 1000`): **503 issues total —
478 closed, 28 open.** Open splits **18** on `v1.16.1`, **0** on `ci.v0.0.1` (closed 2026-08-30), 10 with no milestone. Measured 2026-08-30 with `--limit 300`.
no milestone.

> **The per-phase totals that used to sit here were stale and are removed rather
> than guessed at.** They read "Total issues tracked: 88", "Completed (Phases
> 1-13): 92 issues" and **"Current version: v1.7.2"** — the last of which was
> wrong by nine minor releases, against a repository that tagged **v1.16.0** on
> 2026-08-24. They described a document that stopped being maintained around
> v1.9.1 and were never reconciled.
>
> Phase-by-phase history lives in [`implemented.md`](implemented.md).
> [GitHub Releases](https://github.com/risk-sentinel/sparc/releases) is canonical
> for what shipped when, and the milestone pages are canonical for issue counts.
> **Do not reintroduce a hand-maintained running total here** — every one of them
> drifted, and each drifted silently in the direction of looking finished.

**First public release: v1.0.0** (#271). Org migration to `risk-sentinel/sparc`
completed 2026-05-02 (#430).

> **Resolved:** `VERSION` in `app/models/sparc_config.rb` reads **1.16.0** and
> matches the tag. Session notes had carried "still 1.15.5" forward from before
> the release; verified against the file on 2026-08-25, it is correct.
