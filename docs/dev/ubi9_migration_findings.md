# UBI9 Base-Image Migration — Prototype Findings (#742)

Status: **prototype validated locally + in CI**. This documents the working
`Dockerfile.ubi9` (Red Hat UBI9 minimal, Ruby + jemalloc from source), the gaps
a real UBI9 migration must handle, the CVE outcome, and the triage of the
residual High findings. Supersedes #639 (base-image CVE audit) for the OS-CVE
clearance + hardened-variant scope.

## Why UBI9

Iron Bank / DISA-aligned base. It **retires the entire Debian perl/glibc
CVE-disposition treadmill** we hand-maintain in `docs/compliance/sparc-findings.yml`.

Grype, same DB, Debian vs UBI9:

| | Debian `ruby:3.4.4-slim` | **UBI9 (this prototype)** |
|---|---|---|
| Critical | **15** | **0** |
| High | 77 | ~21 |
| perl CVEs (incl. critical CVE-2026-12087) | many | **0** |
| glibc criticals | yes | **0** |

## What was validated

- **Build:** Ruby 3.4.4 (+PRISM) and jemalloc compiled from source on
  `ubi9/ubi-minimal:9.7`; native gems (`pg`, `nokogiri`, `websocket-driver`)
  build and load; assets precompile; OSCAL schema bundle bakes; hdf-cli baked.
  (Local build is `linux/amd64` — see aarch64 note below.)
- **Boot + serve:** `db:prepare` creates all four DBs, demo seed runs, puma
  serves. `/login` 200; API responds.
- **`tests/api`:** 337 / 338 pass (the 1 failure = the cookie-bridge test, which
  needs TLS for the Secure session cookie — a prod `assume_ssl` artifact, not UBI9).
- **`ui-smoke` (over the TLS proxy):** 147 pass / 17 fail (after serving
  favicon/manifest via the caddy proxy, as production infra does).

### A/B vs the Debian image — ZERO regression (the proof)

The identical harness (same `docker-compose`, caddy TLS, env, seed) was run
against **both** the UBI9 image and a locally-built **Debian prod image**
(`sparc:debian-prod`, same `linux/amd64`). Results are byte-for-byte identical:

| Suite (over TLS) | UBI9 | Debian | Diff |
|---|---|---|---|
| `tests/api` | 337 pass / 1 fail | 337 pass / 1 fail | **same failing test** |
| `ui-smoke` | 147 pass / 17 fail | 147 pass / 17 fail | **same 17 tests; 0 divergence** |

**No test passes on Debian but fails on UBI9 (or vice versa).** The 17+1 residual
failures are therefore **pre-existing local-harness/data gaps, not UBI9**:
- 1 API: `test_bridged_cookie_authenticates_ui` — an httpx cookie round-trip
  detail through the proxy (the same bridge authenticates fine in the browser,
  so all 147 authenticated ui-smoke tests pass).
- 17 ui-smoke: `index_search` / `review_queue` / `populate_flow` /
  `authoritative_sources` — the post-deploy suite expects specific deployment
  fixtures (empty CDEFs, submitted docs) the demo seed doesn't create. Fails
  identically on the current Debian production image.

**Conclusion: the UBI9 pivot is behavior-equivalent to Debian with zero
regression.** Closing the residual 17+1 to literal-green is a demo-seed/harness
task that applies to both images, tracked separately.

Reproduce locally: `docker compose -f docker-compose.ubi9.yaml up -d --build`,
then run `tests/api` (http) and `ui-smoke` (via the `--profile tls` caddy proxy).

## Migration gaps surfaced (UBI9 ≠ Debian)

1. **aarch64 UBI9 baseos metadata on `cdn-ubi.redhat.com` is currently broken**
   (empty package index) — build `linux/amd64` until Red Hat fixes it. amd64 is
   the deploy target anyway; aarch64 builds run under emulation locally.
2. **`readline` / `gdbm` / `ncurses` `-devel` are not in the UBI9 repos** — they
   are optional for a Rails Ruby (3.4 uses pure-Ruby `reline`; Rails needs no
   gdbm/curses), so they are dropped. If ever required, enable the CRB repo.
3. **No usable system zoneinfo** — UBI9 `tzdata` ships no `zone.tab`/`iso3166.tab`
   files that TZInfo needs. Fixed portably by bundling the **`tzinfo-data`** gem
   (unconditional in the Gemfile) so TZInfo needs no system zoneinfo at all.
4. **Runtime tools the entrypoint needs** — `bash` and `postgresql` (for
   `pg_isready`) are not in ubi-minimal by default; added to the runtime stage.

Prod-image-run config (identical for the Debian image; handled in
`docker-compose.ubi9.yaml` for local validation, not UBI9-specific):
`SPARC_DB_*` env (not `DATABASE_URL`), Active Storage `:local` override (prod
hardcodes S3), `SPARC_RATE_LIMITING_ENABLED=false`, `FORCE_SSL=false`.

## Residual High-severity CVE triage

All are base-image OS packages or Ruby default-gem shadows. The Grype gate is
`--fail-on critical`, so none gate today; documented here for the ramp to `high`.

| CVE(s) | Package | Fix | Disposition |
|---|---|---|---|
| CVE-2026-33845/33846/42009/42010 | `gnutls` | **fixed** (RH backport) | Remediate via base-digest bump; not reached by SPARC directly. |
| CVE-2026-11352/11586/12064/8286/8925/9547 | `curl` / `libcurl-minimal` | not-fixed | Low reachability — SPARC does outbound via Ruby `net/http`/OpenSSL, not libcurl; curl is base tooling. Monitor RH backport. |
| CVE-2026-6477 | `libpq` | not-fixed | Used by the `pg` gem. Monitor; RH backport expected. |
| CVE-2026-58016 | `glib2` | not-fixed | Base-image transitive, not exercised by the app. Monitor. |
| CVE-2026-54369 | `libacl` | not-fixed | Base-image transitive, not exercised. Monitor. |
| GHSA-q339-8rmv-2mhv | `erb` 4.0.4 | fixed | **False positive** — Ruby default-gem shadow; Bundler activates the pinned `erb >= 6.0.4`. Same basis as the Debian `sparc-findings.yml` entry. |
| GHSA-vcgp-9326-pqcp | `net-imap` 0.5.8 | fixed | **False positive** — default-gem shadow; Gemfile pins `net-imap >= 0.6.4`. |

**Unlike Debian's `wont-fix` perl/glibc, the UBI9 residuals are Red Hat-backported**
— they clear with a base-digest bump rather than perpetual dispositions.

## Remaining before production cutover

- Wait for aarch64 UBI9 metadata fix (or build amd64-only); confirm on native amd64 CI.
- Re-baseline `sparc-findings.yml`: prune the Debian perl/glibc entries, add any
  UBI9 residuals that survive a base-digest bump.
- Wire the digest-pin auto-bump (Dependabot/Renovate) per the folded-in #639 policy.
- Validate the `sparc-iac` deploy against the UBI9 image.
