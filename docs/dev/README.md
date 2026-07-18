<!-- markdownlint-disable MD013 -->
# `docs/dev/` — Internal development documentation

> **Audience: SPARC maintainers.** These documents are **internal**. They cover
> our development process, planning, and operational/engineering reference — not
> the public product documentation.

## Where documentation lives

SPARC keeps public and internal documentation in separate homes:

| Documentation | Home | Canonical |
|---|---|---|
| **Public** — product usage, configuration, architecture, API, roles, changelog | The **GitHub wiki** (source under [`wiki/`](../../wiki), mirrored via `wiki/PUSH_TO_WIKI.sh`) | ✅ Keep current |
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
| [`Implemenation_plan.md`](Implemenation_plan.md) | Phased roadmap & issue tracking |
| [`Developer_Collision_Avoidance_Plan.md`](Developer_Collision_Avoidance_Plan.md) | Domain ownership, hot files, migration coordination |
| [`secrets_variables.md`](secrets_variables.md) | GitHub Actions secrets & variables inventory |
| [`aws_labs_cdef_coverage.md`](aws_labs_cdef_coverage.md) · [`aws_security_hub_nist_mapping.md`](aws_security_hub_nist_mapping.md) | AWS Labs CDEF coverage; Security Hub → NIST mapping |
| [`ubi9_migration_findings.md`](ubi9_migration_findings.md) | UBI9 base-image migration validation & A/B evidence |
| [`hdf-libs-3.2.0-upstream-report.md`](hdf-libs-3.2.0-upstream-report.md) | hdf-cli 3.2.0 upstream contract report |
| [`a11y_audit.md`](a11y_audit.md) | Accessibility (WCAG 2.1 AA) audit record |
| [`admin_credential_rotation.md`](admin_credential_rotation.md) | Admin-credential rotation (operational/engineering reference) |
