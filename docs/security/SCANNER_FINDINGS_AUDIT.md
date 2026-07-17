# Scanner Findings Audit

**Last reviewed:** 2026-07-17 (v1.12.0 — UBI9 base-image migration, #742)
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

This document consolidates the state of every static-analysis and dependency-scanner suppression across SPARC's CI matrix. Goal: a pen-tester or operator asking "what's hiding behind the green CI badge?" gets a single readable answer.

For each scanner: what it covers, what threshold it gates on, what's suppressed (with rationale), and the source-of-truth file. `.trivyignore` remains the canonical source of truth for Trivy CVE suppressions — this document is the human-readable summary; do not duplicate detailed CVE rationale here.

## Summary

| Scanner | App-code suppressions | Configured threshold | Source of truth |
|---|---|---|---|
| Brakeman | 0 | any finding fails | (no ignore file present) |
| CodeQL | 0 | default rule set | (no `.github/codeql/codeql-config.yml`) |
| Rubocop | 0 (style-only via `rubocop-rails-omakase`) | `cops_to_omit` from omakase | `.rubocop.yml` |
| Bundler-audit / dependency-audit | 0 — "No vulnerabilities found" as of 2026-05-23 | any vulnerable gem fails | `Gemfile.lock` |
| Secrets scan | 0 | any secret fails | (no ignore file present) |
| Trivy filesystem | 0 CVEs + 1 misconfig (DS-0002, dev tooling) | CRITICAL + HIGH + MEDIUM | `.trivyignore` |
| Trivy container | 9 CVEs (all classified) | CRITICAL + HIGH | `.trivyignore` |
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
- **Suppressions:** none. No bundle-audit ignore markers.
- **Current state (as of 2026-05-23):** `bundle exec bundle-audit check --update` returns "No vulnerabilities found" against 1,131 advisories in the latest ruby-advisory-db.
- **If a CVE shows up later:** preferred response is `bundle update <gem>` to clear it. If the upstream patch isn't available, document the CVE here with classification (DISPUTED / MITIGATED / FALSE POSITIVE / ACCEPTED RISK) following the same template as the `.trivyignore` entries.

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

- **Covers:** vulnerabilities in OS packages baked into the production container image (`ruby:3.4.4-slim` base + Debian Bookworm packages).
- **Threshold:** CRITICAL + HIGH.
- **Suppressions (9 CVEs):** detailed rationale per CVE in `.trivyignore` — do not edit this table; edit `.trivyignore` and copy the summary line here. All entries have a `# Reviewed: YYYY-MM-DD` comment that gates the next re-evaluation.

| CVE | Classification | One-line rationale | Reviewed |
|---|---|---|---|
| `CVE-2019-1010022` | DISPUTED | glibc stack guard page bypass; theoretical, requires existing LCE which is already game-over. Non-root container + namespaces + seccomp. | 2026-03-19 |
| `CVE-2011-3389` | MITIGATED | BEAST against SSL 3.0 / TLS 1.0 CBC. SPARC enforces TLS 1.2+; TLS 1.0/1.1 not offered. | 2026-03-19 |
| `CVE-2005-2541` | FALSE POSITIVE | GNU tar setuid/setgid extraction "vulnerability" is documented expected behavior. SPARC doesn't extract untrusted tar at runtime. | 2026-03-19 |
| `CVE-2025-24294` | FALSE POSITIVE | ReDoS in system-bundled resolv 0.6.0 in Ruby base image. SPARC's `Gemfile.lock` pins resolv 0.7.1 (patched); `BUNDLE_DEPLOYMENT=1` ensures the system copy is never loaded. | 2026-03-19 |
| `CVE-2025-61594` | FALSE POSITIVE | uri vulnerability in system-bundled uri 1.0.3 in Ruby base. SPARC's `Gemfile.lock` pins uri 1.1.1 (patched); same Bundler load-path isolation argument. | 2026-03-19 |
| `CVE-2025-7458` | REMEDIATED | SQLite integer overflow; package removed from image in #342 (transitive dep never used by SPARC — PostgreSQL only). | 2026-04-05 |
| `CVE-2023-45853` | ACCEPTED RISK | zlib minizip overflow; no Debian Bookworm patch. SPARC doesn't use minizip code path (HTTP compression via Rack middleware bypasses it). Non-root container. | 2026-03-19 |
| `CVE-2026-0861` | ACCEPTED RISK | glibc vulnerability in libc-bin / libc6; no Debian Bookworm patch. Mitigated by non-root + namespace isolation. Resolves when base image upgrades Debian. | 2026-03-19 |
| `CVE-2023-2953` | REMEDIATED | OpenLDAP libldap null deref; package removed from image in #342 (transitive dep of curl, never used by SPARC). | 2026-04-05 |

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
