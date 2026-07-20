# Scanner Findings Audit

**Last reviewed:** 2026-07-20 (v1.12.2 — Evidence API, hdf-cli 3.4.1, boundary/org management)
**Cadence:** every major SPARC release (enforced by `docs/dev/issue_rules.md`),
or whenever a new suppression is added.

> **v1.12.0 base-image migration (#742):** the production image moved from
> Debian `ruby:3.4.4-slim` to Red Hat **UBI9 minimal**. This retired the entire
> Debian perl/glibc/libgnutls CVE-disposition treadmill: the full UBI9 app image
> scans **0 Critical** (Debian base was 15). The 26 Debian OS entries were pruned
> from `docs/compliance/sparc-findings.yml` (91 findings remain), with the prior
> Debian set preserved for rollback as `sparc-findings.debian.yml`. Residual UBI9
> Highs (gnutls/curl/libpq/glib2/libacl — Red Hat-backported; erb/net-imap
> default-gem shadows) are non-gating (`--fail-on critical`). See
> `docs/dev/ubi9_migration_findings.md` for the scan comparison + A/B evidence.

> **v1.12.2 reconciliation (2026-07-20, #770):** re-scanned the **UBI9** image
> (Trivy + Grype) and reconciled every overdue disposition against the live
> results — the first review to actually verify against the prod image rather
> than bump dates. Findings: **11 `sparc-findings.yml` entries labeled
> `remediated` were still present in the scan.** Re-triaged: 5 → **accepted**
> (curl-minimal/gnupg2, no upstream fix, mitigating controls); 4 Go-stdlib +
> 1 libtasn1 → **deferred** (fixes exist upstream — the 4 Go CVEs are in the
> hdf-cli binary and are hdf-libs-owned, tracked in **#776**; libtasn1 lands on
> the next UBI9 base refresh); 1 → **false positive** (oauth2 — runtime gem is
> 2.0.25/patched, an orphaned `oauth2-2.0.18.gemspec` from a cached build layer
> trips the scanner; add `bundle clean --force` to the image build). The other
> 20 overdue entries were confirmed accurate (remediated-gone / structural FP)
> and re-dated. **9 Debian-era `.trivyignore` entries removed** as obsolete on
> UBI9 (see Trivy container section). Grype gate remains `--fail-on critical`.

This document consolidates the state of every static-analysis and dependency-scanner suppression across SPARC's CI matrix. Goal: a pen-tester or operator asking "what's hiding behind the green CI badge?" gets a single readable answer.

For each scanner: what it covers, what threshold it gates on, what's suppressed (with rationale), and the source-of-truth file. `.trivyignore` remains the canonical source of truth for Trivy CVE suppressions — this document is the human-readable summary; do not duplicate detailed CVE rationale here.

## Summary

| Scanner | App-code suppressions | Configured threshold | Source of truth |
|---|---|---|---|
| Brakeman | 0 | any finding fails | (no ignore file present) |
| CodeQL | 0 | default rule set | (no `.github/codeql/codeql-config.yml`) |
| Rubocop | 0 (style-only via `rubocop-rails-omakase`) | `cops_to_omit` from omakase | `.rubocop.yml` |
| Bundler-audit / dependency-audit | 5 (all `mcp`, dev-only transitive) | any vulnerable gem fails | `Gemfile.lock` + `.bundler-audit.yml` |
| Secrets scan | 0 | any secret fails | (no ignore file present) |
| Trivy filesystem | 0 CVEs + 1 misconfig (DS-0002, dev tooling) | CRITICAL + HIGH + MEDIUM | `.trivyignore` |
| Trivy container | 0 CVEs in `.trivyignore` (9 Debian-era entries removed as obsolete on UBI9, v1.12.2); container CVE dispositions tracked in `sparc-findings.yml` | CRITICAL + HIGH | `.trivyignore` + `docs/compliance/sparc-findings.yml` |
| Grype SBOM | 0 explicit per-CVE suppressions; **threshold ramp** = CRITICAL only | CRITICAL (ramp; intent is HIGH after baseline triage) | `.github/workflows/security.yml` (`GRYPE_FAIL_ON`) |

**Net state:** SPARC's app code has zero scanner suppressions. All suppressions live at the container / OS / dependency layer, are documented with rationale, and have a stated review cadence. The Grype threshold is a deliberate calibration choice (ramp from CRITICAL → HIGH) flagged for follow-up, not a suppression.

## Per-scanner detail

### Brakeman (Rails security static analysis)

- **Covers:** XSS, SQLi, command injection, mass assignment, unsafe deserialization, weak crypto in Rails app code (`app/`, `lib/`, `config/`).
- **Suppressions:** none. No `.brakeman.ignore` file exists; no inline `# brakeman:ignore` directives in `app/` or `lib/` (verified via `grep -rn 'brakeman:ignore' app/ lib/`).
- **Threshold:** every Brakeman warning fails the `brakeman_scan` CI job. The job currently passes on all recent PRs (#509, #510, #511, #513, #514, #515) without any suppressions added.
- **If a finding surfaces in the future:** prefer fixing the code over adding `# brakeman:ignore`. If suppression is unavoidable, document the rationale inline AND append an entry to this doc.

### CodeQL (semantic code analysis)

- **Covers:** Ruby-language-aware taint analysis, control-flow vulnerabilities (path traversal, deserialization sinks, regex DoS, etc.).
- **Suppressions:** none. No `.github/codeql/codeql-config.yml` file; uses the default CodeQL Ruby rule set.
- **Threshold:** every CodeQL alert above the default severity fails the `codeql_scan` CI job. Passes on all recent PRs.
- **If a finding surfaces in the future:** same posture as Brakeman — fix first, suppress with rationale + doc entry if truly unavoidable.

### Rubocop (style + lint)

- **Covers:** Ruby style, layout, lint (security-relevant rules are part of the rule set: `Security/Open`, `Security/Eval`, `Security/JSONLoad`, etc.).
- **Configuration:** `.rubocop.yml` inherits `rubocop-rails-omakase` (the Rails-team-sanctioned omakase rule set) with no project-specific overrides or Excludes.
- **Suppressions:** none custom. Whatever rubocop-rails-omakase disables by default is the only "suppression" — that's intentional Rails-team curation, not a SPARC-specific exception.
- **If a Security/* cop is intentionally violated:** add inline `# rubocop:disable Security/X — reason` with a sentence of rationale. Update this doc.

### Bundler-audit / dependency-audit

- **Covers:** known CVEs in declared gem dependencies (queries `ruby-advisory-db`).
- **Suppressions:** 5 advisories on `mcp`, all ACCEPTED RISK — see `.bundler-audit.yml` (auto-loaded by bundler-audit 0.9.3, so CI's `bundle-audit check` honors it).
- **Current state (as of 2026-07-20, v1.12.2):** `bundle exec bundle-audit check --update` returns "No vulnerabilities found" with the ignore config applied; raw (no config) reports only the 5 `mcp` entries below.
- **`mcp` — ACCEPTED RISK (dev-only, unreachable):** `mcp` is a **transitive, development/CI-only** dependency (`rubocop 1.85+ → mcp ~> 0.6`, pulled via `gem "rubocop-rails-omakase", require: false`). It is never loaded in the production image or at runtime. All 5 advisories (`GHSA-52jp-gj8w-j6xh`, `GHSA-5p9g-j988-pcwv`, `GHSA-7683-3w9x-ch42`, `GHSA-h669-8m4g-r2hc`, `GHSA-rjr6-rcgv-9m7m`) are in the MCP **server** StreamableHTTPTransport / SSE path — SPARC runs no MCP server and never instantiates that transport, so the vulnerable code is unreachable. All are fixed in `>= 0.23.0`, but rubocop constrains `~> 0.6`; the finding clears when rubocop's own dependency advances (tracked, not forced). Re-review each release.
- **Resolved since last audit:** `rails-html-sanitizer` 1.7.0 → **1.7.1** (GHSA-cj75-f6xr-r4g7, XSS) via the #767 dependency bump — a real advisory on a gem SPARC uses for HTML sanitization, now cleared.
- **If a CVE shows up later:** preferred response is `bundle update <gem>` to clear it (as done for rails-html-sanitizer). If the upstream patch isn't reachable, document it here with classification (DISPUTED / MITIGATED / FALSE POSITIVE / ACCEPTED RISK) and add a rationale'd `.bundler-audit.yml` entry with a review date.

### Secrets scan

- **Covers:** committed secrets (API keys, passwords, tokens, PEM blocks) in the repo.
- **Suppressions:** none. No ignore file.
- **Threshold:** any finding fails CI. Passes on all recent PRs.

### Trivy filesystem (`trivy fs`)

- **Covers:** vulnerabilities in any package or config detectable from the source tree (gems, npm if present, Dockerfile lints, etc.) plus secrets and misconfigurations.
- **Threshold:** scans CRITICAL + HIGH + **MEDIUM** — strictest tier of the Trivy jobs.
- **Suppressions (1 — misconfig only):**
  - **DS-0002** — Trivy fs flag against `tests/api/Dockerfile` (dev / CI tooling image runs as root). Classified FALSE POSITIVE for production: this is a test-runner image used by GitHub Actions to execute pytest against deployed SPARC instances, never deployed to prod. The production `./Dockerfile` already runs as non-root UID 1000 (hardened in #342). Reviewed 2026-05-06.

### Trivy container (`trivy image`)

- **Covers:** vulnerabilities in OS packages baked into the production container image (**Red Hat UBI9 minimal** base since #742 / v1.12.0).
- **Threshold:** CRITICAL + HIGH.
- **`.trivyignore` container-CVE suppressions: 0** as of v1.12.2. The 9 prior entries (`CVE-2019-1010022`, `CVE-2011-3389`, `CVE-2005-2541`, `CVE-2025-24294`, `CVE-2025-61594`, `CVE-2025-7458`, `CVE-2023-45853`, `CVE-2026-0861`, `CVE-2023-2953`) were **Debian-era** suppressions carried over from the `ruby:3.4.4-slim` base. Re-scanning the UBI9 image (v1.12.2 review, 2026-07-20) confirmed **none of them appear** — the packages/CVEs don't exist on UBI9 — so they were removed as obsolete (recoverable from git history if a Debian rollback via `Dockerfile_debian` is ever needed, in parity with `sparc-findings.debian.yml`).
- **Container CVE dispositions now live in `docs/compliance/sparc-findings.yml`** (the Grype/Trivy disposition source of truth), reconciled against the UBI9 image in the same v1.12.2 review.

### Grype SBOM scan

- **Covers:** vulnerabilities found by Anchore Grype against the production image's SBOM (Trivy and Grype use different vuln DBs; running both catches different findings).
- **Threshold:** `GRYPE_FAIL_ON=critical` — currently only CRITICAL findings fail the build.
- **Per-CVE suppressions:** none (no `.grype/config.yaml`).
- **Calibration note:** the workflow comment explicitly flags the threshold as a "ramp — start at critical only so the first PR's findings don't block merge. Bump to high once baseline is triaged." This is documented but not yet acted on. **Follow-up item**: triage the Grype HIGH-severity baseline and tighten `GRYPE_FAIL_ON=high` once cleared. Track separately if it warrants its own issue.

## Re-evaluation cadence

- **Every major SPARC release** (e.g., v1.7.0, v1.8.0): re-run this audit. Verify each `.trivyignore` entry's `# Reviewed:` date is within 90 days; if older, re-check upstream advisory state and either bump the review date or clear the entry.
- **Every new suppression**: must include classification + rationale + reference + review date inline in the suppression file AND a row appended to this doc in the same PR.
- **Pen-test prep**: this doc is the canonical handoff. The pen-tester gets a copy; their report can reference specific entries to ask "is this still accepted?" rather than re-deriving the rationale.

## Ownership

- Adding / clearing suppressions: any maintainer; PR must touch both the suppression file and this doc, and request review from at least one other maintainer.
- Re-evaluation cadence (every major release): release champion includes "review SCANNER_FINDINGS_AUDIT.md dates" as a release-checklist item.

## Cross-references

- `.trivyignore` — canonical source for Trivy CVE suppressions
- `.github/workflows/security.yml` — scanner job definitions + thresholds (`GRYPE_FAIL_ON`, Trivy `--severity` flags, etc.)
- `docs/PRODUCTION_SECURITY.md` (#524, in progress) — operator-facing hardening guide; will cross-reference this audit
- `docs/compliance/nist-sp800-53-rev5-mapping.md` — NIST 800-53 control coverage (RA-5 Vulnerability Monitoring & Scanning satisfied here)
- `risk-sentinel/container-build-sign` issue #13 — base-image CVE clearance + hardened-runtime variants (the OS-layer side; this doc handles app-layer + dep-layer)
