# Scanner Findings Audit

**Last reviewed:** 2026-08-08 (v1.15.5 — catalog lineage, boundary-roster authorization fix)
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

> **v1.15.4 rescan (2026-08-04):** re-scanned the **actual v1.15.4 production
> image** with Grype and Trivy — a real rescan, not a date bump. Results:
>
> | Scanner | Critical | High | Medium |
> |---|---|---|---|
> | Grype (image) | **0** | 21 | 118 |
> | Trivy (image) | 8 | 70 | 169 |
>
> **Those numbers were the *before*.** The six Highs with fixes available
> upstream turned out to be already carried by the current UBI9 base, so the
> digest pin was bumped 9.7 → 9.8 in this same release rather than deferred:
>
> | | Critical | High | Medium | Low | Total |
> |---|---|---|---|---|---|
> | UBI 9.7 (as found) | 0 | 21 | 118 | 68 | 207 |
> | **UBI 9.8 (shipped)** | **0** | **15** | **82** | **58** | **155** |
>
> All six resolved — CVE-2026-33845, -33846, -42009, -42010 (gnutls
> 3.8.3-10.el9_7 → 3.8.10-4.el9_8), CVE-2026-54369 (libacl 2.3.1-4.el9 →
> 2.4.0-1.el9_8), CVE-2026-58016 (glib2 2.68.4-18.el9_7.2 → 2.68.4-19.el9_8.2)
> — with **zero new findings introduced**, and 52 fewer findings overall.
> curl/libcurl also moved 7.76.1-35.el9_7.3 → 7.76.1-40.el9, which does not
> clear its six CVEs (still `not-fixed`) but is the current build.
>
> **The 8 Trivy CRITICALs are all Ruby gemspecs that are not present in the
> shipped image.** Verified by running the image rather than trusting either
> scanner: `activestorage-8.1.2`, `concurrent-ruby-1.3.6`, `net-imap-0.6.3` and
> `rack-session-2.1.1` have neither a gemspec nor a gem directory in the merged
> filesystem (`spec=NO lib=NO`), and `bundle list` activates the **patched**
> versions — activestorage 8.1.3.1, concurrent-ruby 1.3.8, net-imap 0.6.6,
> rack-session 2.1.2, zlib 3.2.3, every one at or above its fix floor. Trivy is
> reporting specifications that existed in an intermediate build layer and were
> removed later in the build. Grype's image scan reports none of them, which is
> the correct answer. **Do not disposition these as accepted risk — they are not
> in the artifact.** If they persist across releases, the fix is build-layer
> hygiene, not a suppression.
>
> **The Highs at the time of the scan (21)**, by fix availability — this is what
> makes them actionable or not, and what drove the base bump above:
>
> - **8 curl / libcurl-minimal** (CVE-2026-11352, -11586, -8286, -8925, -8927,
>   -9547) — `fix=not-fixed`, awaiting a Red Hat backport. Nothing to do.
> - **2 postgresql / postgresql-private-libs** (CVE-2026-6479) — `not-fixed`.
> - **6 with fixes available upstream** — gnutls (CVE-2026-33845, -33846,
>   -42009, -42010), libacl (CVE-2026-54369), glib2 (CVE-2026-58016).
>   **Taken in this release** via the 9.7 → 9.8 digest bump. The base already
>   shipped every fixed package, so a deliberate digest bump was sufficient — no
>   `microdnf update`, which would have traded reproducibility for the same
>   result.
> - **1 erb 4.0.4** (GHSA-q339-8rmv-2mhv) — a Ruby **default-gem shadow** at
>   `specifications/default/erb-4.0.4.gemspec`. The bundle resolves erb **6.0.6**
>   at runtime. Retained deliberately: `bin/prune-shadowed-gems.rb` removes
>   *bundled* gems but never *default* ones, because deleting the gemspec while
>   the stdlib code remains would hide the package from scanners rather than
>   harden the image. Same basis for zlib 3.2.1.
>
> **Gate status:** Grype `--fail-on critical` passes on 0 Critical. The
> Critical→High ramp remains a calibration decision, not a suppression: on the
> shipped 9.8 image, raising it to HIGH would gate on **14 CVEs with no
> available fix** (curl/libcurl ×12, postgresql ×2) plus the erb default-gem
> shadow. Every remaining High is now either unfixable upstream or structurally
> a shadow — there is no longer a fixable High being carried.

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
| Brakeman | 7 (documented false positives) | any un-ignored finding fails | `config/brakeman.ignore` |
| CodeQL | 0 | default rule set | (no `.github/codeql/codeql-config.yml`) |
| Rubocop | 0 (style-only via `rubocop-rails-omakase`) | `cops_to_omit` from omakase | `.rubocop.yml` |
| Bundler-audit / dependency-audit | 5 (all `mcp`, dev-only transitive) | any vulnerable gem fails | `Gemfile.lock` + `.bundler-audit.yml` |
| Secrets scan | 0 | any secret fails | (no ignore file present) |
| Trivy filesystem | 0 CVEs + 1 misconfig (DS-0002, dev tooling) | CRITICAL + HIGH + MEDIUM | `.trivyignore` |
| Trivy container | 0 CVEs in `.trivyignore` (9 Debian-era entries removed as obsolete on UBI9, v1.12.2); container CVE dispositions tracked in `sparc-findings.yml` | CRITICAL + HIGH | `.trivyignore` + `docs/compliance/sparc-findings.yml` |
| Grype SBOM | 0 explicit per-CVE suppressions; **threshold ramp** = CRITICAL only | CRITICAL (ramp; intent is HIGH after baseline triage) | `.github/workflows/security.yml` (`GRYPE_FAIL_ON`) |

**Net state:** SPARC's app code carries 7 Brakeman suppressions, each recorded in `config/brakeman.ignore` with a written rationale. Every other scanner has zero app-code suppressions; the rest live at the container / OS / dependency layer, are documented with rationale, and have a stated review cadence. The Grype threshold is a deliberate calibration choice (ramp from CRITICAL → HIGH) flagged for follow-up, not a suppression.

> **Corrected 2026-08-08 (v1.15.5).** This section previously claimed "zero scanner suppressions" and that no Brakeman ignore file existed. Both were wrong: 4 entries were already present in `config/brakeman.ignore`. The document understated the app-code suppression count for as long as those entries have existed, which is precisely the question this audit is supposed to answer honestly.

## Per-scanner detail

### Brakeman (Rails security static analysis)

- **Covers:** XSS, SQLi, command injection, mass assignment, unsafe deserialization, weak crypto in Rails app code (`app/`, `lib/`, `config/`).
- **Suppressions:** 7, all in `config/brakeman.ignore`, each with a `note` giving its
  rationale. No inline `# brakeman:ignore` directives in `app/` or `lib/`.
  - **2 × Mass Assignment (attestations)** — `role` is descriptive metadata identifying the
    attester, not an authorization role.
  - **2 × Mass Assignment (service accounts)** — `:admin` is permitted BY DESIGN on the admin-only
    service-account screens.
  - **2 × Mass Assignment (boundary memberships, added v1.15.5)** — `:role` is permitted so the
    model validates it in one place against the configured vocabulary (#875), and escalation is
    prevented by AUTHORIZATION rather than by the permit list. Note that the web path had NO such
    authorization until v1.15.5; see the boundary-roster fix in that release.
  - **1 × File Access (help images, added v1.15.5)** — `UserGuideLibrary.image_path` is a whitelist
    lookup against the images that ship, each realpath-checked; user input is compared, never used
    to build a path. Brakeman cannot see through the service call.
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
