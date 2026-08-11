# Release checklist

Run this **before tagging**, in order. Everything here has been missed at least
once, which is why it is a list rather than a habit.

The v1.15.4 prep found three gaps in one go: the user guides still described
screens that had been redesigned, the wiki Changelog had no entry for **v1.15.3**
(released a week earlier) or v1.15.4, and the scanner-findings audit was four
releases stale. None of these block CI, so nothing catches them but this.

---

## 1. Testing and Security

- [ ] **Run full test suite before commit** — `bundle exec rspec` (full suite,
    not targeted specs). Targeted specs during development are fine, but the
    full suite **must pass** before releasing. Also run `bundle exec rubocop`
    on all files.
- [ ] **Local smoke + API check concludes any application-code change — against the
  PROD (UBI9) image** — Run BOTH the full `tests/api` endpoint suite and the
  `tests/ui-smoke` Playwright suite against a freshly-running local container
  (Chrome, zero CSP violations), authenticated with a locally-minted `ApiToken`.
  **The container MUST be the production UBI9 image — bring the stack up with
  `docker compose -f docker-compose.ubi9.yaml up --build -d` (builds
  `./Dockerfile`, self-seeds `SPARC_SEED_DEMO=true`).**
  Green `rspec` alone is **not** sufficient — it never exercises the running
  image, routing, or CSP. **CI-only or docs-only changes are exempt.**
- [ ] **Refresh `docs/security/SCANNER_FINDINGS_AUDIT.md` with a real rescan**,
      not a date bump. Build the release image and scan it:

      bundle exec bundle-audit check --update
      docker build --target runtime -t sparc:vX.Y.Z-audit .
      grype sparc:vX.Y.Z-audit -o json > grype.json
      trivy image --scanners vuln --severity CRITICAL,HIGH,MEDIUM \
        --format json -o trivy.json sparc:vX.Y.Z-audit

      Then refresh the **Last reviewed** date/version line and reconcile the
      finding counts against the `sparc-findings.yml` / `.trivyignore`
      suppression inventory, so the audit stays in cadence with the shipped
      image instead of drifting.

- [ ] **Scan the image, not an SBOM.** Grype's SBOM path has missed findings that
      its image path catches (#873).
- [ ] **Reconcile the two scanners; they will disagree.** When one reports a CVE
      the other does not, resolve it against the *artifact* before dispositioning
      anything:

      docker run --rm --entrypoint sh sparc:vX.Y.Z-audit -c \
        'ls /usr/local/bundle/ruby/*/specifications/ | grep <gem>; cd /rails && bundle list'

      A package that is not in the shipped image is **not** an accepted risk — it
      is not there. Say so; do not carry a disposition for it.
- [ ] Every High/Critical is classified by **fix availability** (`not-fixed` =
      nothing to do; fixed upstream = name the vehicle, usually the next base
      refresh). "It's a High" is not a disposition.
- [ ] `docs/compliance/sparc-findings.yml` dispositions are not overdue, and
      **every suppression's review date is within 90 days** — bump or clear the
      stale ones. A suppression nobody has re-read is an accepted risk nobody
      has re-accepted.

## 2. Documentation

- [ ] **Guide prose, not just screenshots.** Refreshing `wiki/images/` is *not*
      updating a guide. If the way a user does something changed — a new control,
      a new default, a different place to search — the **words** have to change
      too. A guide whose screenshots show a redesigned screen while its text
      describes the old one is worse than one that is uniformly stale, because
      the two now disagree.
- [ ] Every new or materially changed screen has a current screenshot, captured
      from **Google Chrome** via `tests/ui-smoke/capture_screenshots.py`.
- [ ] **Purge test fixtures before capturing.** Screenshots publish to a public
      wiki. Run the capture against seeded demo data only — no records created by
      a smoke run. (The `Smoke Restricted Boundary` / `SMOKE * EVIDENCE` records
      in `db/seeds.rb` are demo data and belong in the images.)
- [ ] Guides render in-app at `/help/<slug>` with images loading.
- [ ] **`wiki/Changelog.md` has an entry for this version** — and for any earlier
      version that shipped without one. Check the entries against
      `gh release list`, not against memory.

## 3. Version

- [ ] `SparcConfig::VERSION` (`app/models/sparc_config.rb`) matches the tag. It
      ships in the same PR as its changes, not a separate bump commit after the
      fact.

## 4. Release notes

- [ ] Written on the **GitHub Release** — the single source of truth. The wiki
      Changelog carries a concise linked summary, never the full text.
- [ ] **Breaking and silent behaviour changes are called out first.** Silent ones
      matter most: `POST /api/v1/users` dropping `password` still returns `201`,
      so a client keeps "working" while doing nothing it intended.
- [ ] Verification evidence quoted with skips **named**, never a bare pass count.
      See the standing rule on skip reporting.

## 5. Tag

- [ ] Full suite, ui-smoke and the API contract suite green against the **prod
      image**, on **both architectures**.
- [ ] Tag and publish — **owner action**, after the release PR merges.

---

## Related

- `docs/dev/issue_rules.md` — the per-issue process this sits on top of
- `docs/dev/781_screenshots.md` — screenshot capture setup
- `docs/security/SCANNER_FINDINGS_AUDIT.md` — what the audit must contain
