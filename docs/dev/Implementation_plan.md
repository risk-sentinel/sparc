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


## Phased Roadmap

> **Phases 1–16 have shipped and are archived in
> [`implemented.md`](implemented.md)**, together with the per-bundle detail and
> the original theme checklist. They were moved on 2026-08-24: 248 of the 282
> issues this file referenced were closed, so 88% of it was history and the live
> work was buried inside it. Nothing was deleted — look there for why a decision
> was made.
>
> **The most recent shipped phase is 16 — v1.16.0, tagged 2026-08-24.**


---

### Phase 17: `ci.v0.0.1` — Evidence and Gates (NEXT)

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

**Open: 16.** Grouped into four bundles by what they share, not by label:

| Bundle | Issues | Theme | Est. |
| --- | --- | --- | --- |
| **CI-1 — Gates that can actually fail** | #1048 #1050 #987 #885 | The scan→decision gap. A scan runs, produces an artifact, and nothing assesses it: bundler-audit reaches no threshold gate (#1048), neither API contract gate runs in CI and both are inert without `--check` (#1050), Brakeman is `continue-on-error` so SAST can never fail a build (#987), and posture-gated tests can silently skip rather than prove both conditions (#885). | 2d |
| **CI-2 — Evidence completeness** | #962 #977 #985 #917 #1027 #990 | This repository is **unevidenced for secrets scanning**: Gitleaks SARIF is never converted to HDF (#962) though the converter works, the emit is missing (#977), and what is filed lands where the profile cannot see it (#985). Plus SCA attestation (#917) and keeping the SonarQube HDF job self-contained (#1027). | 3d |
| **CI-3 — Test-job fidelity** | #835 #927 #711 | The HDF translation specs do not actually run without a pinned `hdf-cli` in the test job (#835); deprecation warnings flood the log (#927); and there is no deployed API-contract runner (#711). | 2d |
| **CI-4 — Posture and architecture coverage** | #858 #859 #965 | Release smoke runs one TLS posture and one does not imply the other (#858); **the arm64 half of every published image ships unverified** (#859) — which matters more now that `build-sign-publish` emits a multi-arch manifest on every tag; metrics collide in the bucket root (#965). | 2d |

**Estimate: 9 working days of bundle work.** With the +62% discovery factor
applied to a 16-issue backlog (→ ~25 issues at 4.2/day ≈ 6 days) the two methods
bracket **6–9 working days**. Plan **8**, target **2026-09-03**.

**Sequencing note:** CI-1 first. Everything after it is evidence that a gate
should be able to reject, and #1050 in particular guards the #995 contract
result that v1.16.0 just shipped — that guarantee is currently unenforced.

---

### Phase 18: `v1.16.1` — The Patch Release

**Open: 14.** Runs after Phase 17, on a v1.16.0 that has had real-environment
time behind it.

> **#968 carries a hard due date of 2026-09-06** — 13 days from 2026-08-24, and
> the only dated item in either milestone. If Phase 17 runs the full 8 days
> (→ 2026-09-03), **#968 has three days left when v1.16.1 opens.** It must ride
> the FIRST v1.16.1 bundle, or the date has to move. Flagging it rather than
> quietly letting it lapse: this is the audit of swallow-and-continue rescue
> patterns, and #963 already showed that hazard is not theoretical.

| Bundle | Issues | Theme | Est. |
| --- | --- | --- | --- |
| **Y — Reliability, and the deadline** | **#968** (due 09-06) #1051 #1022 **#1058** | The rescue-pattern audit (54 sites, 11 log-and-continue in services/jobs, 17 combining a transaction with a rescue). Alongside it the two correctness defects the release run surfaced: 163 of 232 CDEFs export schema-invalid OSCAL (#1051) and `/api/v1/controls` ignores `?items`/`?per_page` so 4,054 rows come back whole (#1022). | 3d |
| **Z — The CSP tail** | #1047 #728 #1046 | **#528 was closed with two of its four items explicitly undone.** Removing `style-src 'unsafe-inline'` means 1,399 inline styles, and Trusted Types has to be settled rather than deferred again. #728 (30 contrast findings vs our WCAG AA gate) and #1046 (S7875, 213 route occurrences) are the same surface. **Largest single item in either milestone.** | 4d |
| **AA — Auth and access debt** | #978 #1044 | Signing in over plain HTTP on a prod-mode container fails **silently** on a CSRF Origin mismatch (#978) — a support call that looks like broken auth. #1044 adds a time-boxed instance administrator via the IdP, distinct from the break-glass account, which is the natural follow-on from Bundle R. | 2d |
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
| 08-25 → 08-26 | CI-1 — gates that can fail | ci.v0.0.1 |
| 08-27 → 08-29 | CI-2 — evidence completeness | ci.v0.0.1 |
| 09-01 → 09-02 | CI-3 — test-job fidelity | ci.v0.0.1 |
| 09-02 → 09-03 | CI-4 — posture and architecture | ci.v0.0.1 |
| **09-03** | **`ci.v0.0.1` closes** | |
| 09-04 → 09-08 | **Y — reliability (#968 due 09-06)** | v1.16.1 |
| 09-09 → 09-12 | Z — the CSP tail | v1.16.1 |
| 09-15 → 09-16 | AA — auth and access debt | v1.16.1 |
| 09-17 → 09-23 | AB — onboarding and Sonar | v1.16.1 |
| **~09-24** | **`v1.16.1` tag** | |

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

## Open work — measured 2026-08-24

Re-measured against the live repository, not carried forward. The plan referenced
**282 issues**; **248 are closed**. What remains:

| State | Count |
| --- | --- |
| Closed | **248** |
| Open, on `ci.v0.0.1` | **16** |
| Open, on `v1.16.1` | **15** (14 audited + #1058, filed 2026-08-24) |
| **Open, on NO milestone** | **4** |

### The four with no milestone

These are invisible to every milestone count, which is exactly how **#950 went
missing** — it sat open with no milestone after being split from #949, appeared
in no bundle, and was only picked up when the owner milestoned it on 2026-08-22.
Listing them so the same thing cannot happen quietly again. **Each needs a
milestone or a deliberate decision to close — that call is the owner's.**

| Issue | Title |
| --- | --- |
| **#422** | POAM Scenario B — cross-instance federated POAM visibility (carved from #415) |
| **#531** | security(uploads): optional GuardDuty S3 tag check hook on blob serving (post-v1.7.0) |
| **#953** | feat(dast): authenticated DAST against the two-boundary reference fixture |
| **#980** | feat(cdef): give component definitions an authorization boundary, so they can be scoped and tiered |

My read, offered as a starting point rather than a decision:

- **#980** (CDEFs need an authorization boundary) is the closest to live work — it
  sits beside #1040's platform axis in Bundle AB, and shipping that flow without it
  may be awkward.
- **#953** (authenticated DAST against the two-boundary fixture) belongs with the CI
  milestone if it belongs anywhere — the fixture it needs (#845) already shipped.
- **#422** and **#531** have been open longest and may simply be closeable.

### Everything else

The 30 milestoned issues are bundled in Phases 17 and 18 above. Verified
programmatically on 2026-08-24: every open issue on both milestones appears in
exactly one bundle, and no bundle cites an issue that is not open.

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
| 16 | **Complete** | v1.16.0 — config correctness, authorization sweep, UX filters, auth entitlements, OSCAL fidelity (milestone `v1.16.0`) | **87 issues, 87 closed. Tagged `v1.16.0` 2026-08-24** from `main` @ `75b5bb3b`. The full closed list is the milestone itself — do not maintain a second copy here | **SHIPPED.** Bundles ran #939 → O → S → P → T → Q → hdf pin → U → W → V → R → X. Bundle X merged as [PR #1049](https://github.com/risk-sentinel/sparc/pull/1049) → `9ae84a84`; [PR #1055](https://github.com/risk-sentinel/sparc/pull/1055) → `75b5bb3b` then fixed four defects Bundle X had merged, found by running the FULL suites against a built prod image. Release verification (measured, on the tagged tree): rspec **6230/0**, API **2742 passed** over TLS and again over non-TLS, ui-smoke **524 passed / 0 failed**, rubocop + brakeman + bundle-audit clean. The milestone grew **53 → 86 because the sweeps FOUND things**, not through scope creep. Wiki published and release notes carry the measured table |
| 17 | **Next** | `ci.v0.0.1` — evidence and gates | **16 open.** CI-1 gates that can fail (#1048 #1050 #987 #885) · CI-2 evidence completeness (#962 #977 #985 #917 #1027 #990) · CI-3 test-job fidelity (#835 #927 #711) · CI-4 posture and architecture (#858 #859 #965) | Runs **BEFORE** v1.16.1 so the patch release gets real-environment soak time (owner decision, 2026-08-24). Estimated **6–9 working days**, plan 8, target **2026-09-03**. CI-1 first: everything after it is evidence a gate should be able to reject, and **#1050 guards the #995 contract result v1.16.0 just shipped — currently unenforced** |
| 18 | Planned | v1.16.1 — the patch release | **14 open.** Y reliability + the deadline (**#968 due 2026-09-06** #1051 #1022) · Z the CSP tail (#1047 #728 #1046) · AA auth and access debt (#978 #1044) · AB onboarding and Sonar (#1040 #940 #1033 #930 #966 #836) | Estimated **14 working days**, target **~2026-09-24**. **#968 is the only dated item in either milestone and must ride the FIRST bundle** or the date moves. Do NOT plan this at v1.16.0's 4.2 issues/day — that rate came from a distribution of small sweep-found defects; #1047, #1040 and #966 are each multi-day. Re-measure after CI-2 |

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
