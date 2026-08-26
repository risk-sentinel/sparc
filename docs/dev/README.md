<!-- markdownlint-disable MD013 -->
# `docs/dev/` — Internal development documentation

> **Audience: SPARC maintainers.** These documents are **internal**. They cover
> our development process, planning, and operational/engineering reference — not
> the public product documentation.

## Where documentation lives

SPARC keeps public and internal documentation in separate homes:

| Documentation | Home | Canonical |
|---|---|---|
| **Public** — product usage, configuration, architecture, API, roles, changelog | The **GitHub wiki** (source under [`wiki/`](../../wiki), published automatically on push to `main` — #1061) | ✅ Keep current |
| **Release notes** | [GitHub Releases](https://github.com/risk-sentinel/sparc/releases) | ✅ Single source |
| **In-repo artifacts** — compliance findings, OSCAL CDEFs, API endpoint specs, license policy, scan outputs | `docs/compliance/`, `docs/api/`, `docs/hdf/`, `docs/ci/`, `docs/banners/` | Consumed by code/CI |
| **Internal dev docs** — process, roadmap, coordination, engineering reference | **`docs/dev/`** (this folder) | Not public |

**Rule of thumb:** if a change is *public-facing* (a user, operator, or integrator
would read it), update the **wiki**. Only put it here if it's for us during
development. See [`issue_rules.md`](issue_rules.md) for the full doc-update process.

## What's in here

| Doc | Purpose |
|---|---|
| [`issue_rules.md`](issue_rules.md) | **Mandatory** issue-process workflow, guardrails, compliance-artifact + doc-update requirements |
| [`release_checklist.md`](release_checklist.md) | **Run end to end before tagging.** Guide prose, wiki Changelog, VERSION, real scanner rescan — none of these fail CI |
| [`Implementation_plan.md`](Implementation_plan.md) | **Live** roadmap — current and next phases, and the open-issue audit |
| [`implemented.md`](implemented.md) | **Archive** — Phases 1–16, everything shipped through v1.16.0. History, not a plan |
| [`Developer_Collision_Avoidance_Plan.md`](Developer_Collision_Avoidance_Plan.md) | Domain ownership, hot files, migration coordination |
| [`secrets_variables.md`](secrets_variables.md) | GitHub Actions secrets & variables inventory |
| [`aws_labs_cdef_coverage.md`](aws_labs_cdef_coverage.md) | AWS Labs CDEF coverage — **generated** by `bin/aws_labs_cdef_coverage_report.rb`; re-run it rather than editing |
| [`aws_security_hub_nist_mapping.md`](aws_security_hub_nist_mapping.md) | Security Hub → NIST mapping (#491, #494) — the converter design |
| [`ubi9_migration_findings.md`](ubi9_migration_findings.md) | UBI9 base-image migration validation & A/B evidence |
| [`hdf-libs-3.2.0-upstream-report.md`](hdf-libs-3.2.0-upstream-report.md) | hdf-cli 3.2.0 upstream contract report |
| [`hdf-libs-3.4.1-oscal-sar-upstream-report.md`](hdf-libs-3.4.1-oscal-sar-upstream-report.md) | hdf-cli 3.4.1 emits schema-invalid OSCAL Assessment Results — **draft, ready to file upstream** (sanitized) |
| [`reference_estate.md`](reference_estate.md) | #845 reference leveraged authorization estate — tiers, commands, committed OSCAL + drift gate, spec helper, the pinning that makes regeneration byte-identical |
| [`817_oscal_e2e_design.md`](817_oscal_e2e_design.md) | #817 end-to-end OSCAL pipeline proof — slice plan, decisions, bugs found |
| [`447_hdf_amendment_design.md`](447_hdf_amendment_design.md) | #447 HDF Amendment triage/UI epic — design pass (reconciled to hdf-cli 3.4.1 / schema v3.4.0) |
| [`809_811_hdf_aggregation_design.md`](809_811_hdf_aggregation_design.md) | #809+#811 HDF aggregation + scan/CDEF association + re-occurrence lifecycle — design pass (decisions resolved) |
| [`tls_verification_testing.md`](tls_verification_testing.md) | **Standard** for TLS/MITM testing — both-directions (positive + negative) proof with a real handshake |
| [`a11y_audit.md`](a11y_audit.md) | WCAG 2.1 AA audit — **generated 2026-05-21 and point-in-time.** The live gates are the axe checks in `tests/ui-smoke` |
| [`admin_credential_rotation.md`](admin_credential_rotation.md) | Admin-credential rotation runbook — Secrets Manager ↔ ECS ↔ database |
| [`860_idp_entitlements_design.md`](860_idp_entitlements_design.md) | #860 IdP-as-system-of-record design memo — **historical, shipped in v1.16.0.** Configuration lives in the wiki and `docs/ENVIRONMENT_VARIABLES.md` |
| [`919_authorization_triage.md`](919_authorization_triage.md) | #919 controller authorization sweep — triage record |
| [`781_screenshots.md`](781_screenshots.md) | #781 wiki screenshot capture process |
| [`hdf-libs-3.5.1-oscal-poam-upstream-report.md`](hdf-libs-3.5.1-oscal-poam-upstream-report.md) | hdf-cli 3.5.1 OSCAL POA&M upstream contract report |
| [`user_guide_template.md`](user_guide_template.md) | Template for a new wiki User Guide page |

## Retired

Deleted on 2026-08-24 — all their issues had shipped, nothing linked them, and
each had been superseded. Recoverable from git history if the reasoning is ever
needed:

| Doc | Why |
|---|---|
| `785_config_reduction_plan.md` | #785 shipped; the plan is history and `docs/ENVIRONMENT_VARIABLES.md` is the live reference |
| `idp_entitlement_flow.md` | Superseded by `860_idp_entitlements_design.md` and, for configuration, the wiki |
| `oscal-1.2.2-support.md` | 1.2.2 shipped in v1.16.0 and is now the default; the wiki and `OscalSchema` are the live record |

**Before adding a doc here, ask whether an operator or integrator would read it.**
If so it belongs in the **wiki**, not in `docs/dev/`. That test is why the OSCAL
version claim went stale in five wiki pages while the internal notes were
current — the audience question is the one that matters, not whether the work
is finished.
