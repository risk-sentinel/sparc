# SPARC UI Smoke Tests (Layer 2 — Playwright)

Real-browser smoke tests that drive the **deployed** SPARC UI in **Chromium and
Firefox**. Part of the UI test net (umbrella #572); consumes the #573
cookie-bridge for authenticated walks.

## Why this layer exists

Layer 1 (RSpec + headless Chrome system specs, `spec/system/`) runs in CI
against the app build. Layer 2 runs **post-deploy against a real URL in two
browser engines** — which is what catches cross-browser regressions that
same-origin request specs and Firefox-only manual testing miss. The motivating
example is **#593**: the CSP `form-action` rule silently killed the GitHub/Okta
SSO buttons in Chromium while Firefox worked. `test_login_page.py` is the
regression net for that class of bug.

## Layout

| File | Purpose | Auth |
|------|---------|------|
| `test_login_page.py` | Login page loads; no CSP violations; SSO submit not blocked by `form-action` (#593) | none |
| `test_authenticated_nav.py` | Cookie-bridge → session; core pages render clean (no 5xx / console / CSP errors) | SA token |
| `test_accessibility.py` | axe-core WCAG 2.1 A/AA audit, baseline+ratchet (Layer 3, #599) | login: none; core pages: SA token |
| `test_csp_reporting.py` | CSP `report-uri` present in header; collector accepts reports (204) without auth; tolerates garbage (#528, #650) | none |
| `test_populate_flow.py` | Empty CDEF/SSP → "Incomplete" badge + "Populate from Profile" card; populate clears badge (#627/#628) | SA token |
| `test_bulk_delete.py` | Admin bulk-select wiring on CDEF + boundary index; select-all reveals delete bar, CSP-clean (#629) | SA token |
| `test_review_queue.py` | Submitted (via API) document surfaces in `/review_queue`; page CSP-clean (#630-634) | SA token |
| `conftest.py` | Base-URL + cookie-bridge fixtures | — |
| `_api_setup.py` | `/api/v1` helpers to provision fixtures (empty/submitted docs) for the flow tests | — |
| `helpers.py` | CSP-violation recorder + `assert_no_csp_violations` / `click_and_assert_clean` interaction checks, console collector, same-origin check | — |

## Running locally

```bash
cd tests/ui-smoke
uv sync
uv run playwright install chromium firefox

# Unauthenticated login-page smoke (no token needed):
SPARC_SMOKE_BASE_URL=https://sparc.risk-sentinel.org \
  uv run pytest test_login_page.py --browser chromium --browser firefox

# Full suite incl. authenticated nav (needs a service-account token):
SPARC_SMOKE_BASE_URL=https://sparc.risk-sentinel.org \
SPARC_SMOKE_SA_TOKEN=sparc_sa_... \
  uv run pytest --browser chromium --browser firefox
```

### Against a local container (the #650 local-first flow)

CSP / inline-handler fixes are validated against a **locally running container
first**, then promoted to a deployment. Point the suite at `localhost`:

```bash
# Terminal 1 — bring up the app (maps web to :3000):
docker compose up --build

# Terminal 2 — mint a local SA token (Admin → Service Accounts, or rails console),
# then run the interaction + CSP-reporting checks against the local image:
cd tests/ui-smoke
SPARC_SMOKE_BASE_URL=http://localhost:3000 \
SPARC_SMOKE_SA_TOKEN=sparc_sa_... \
  uv run pytest --browser chromium
```

Interaction tests assert **zero CSP violations on click** via
`helpers.click_and_assert_clean` / `assert_no_csp_violations` — the DoD for
epic #650. `test_csp_reporting.py` confirms the `report-uri` sink is wired.

### Expected results

A healthy instance runs in **~1–4 minutes** (Chromium; adding `--browser
firefox` roughly doubles it). A number of tests **skip** and that is expected,
not a failure:

- `no <type>_show record found on this deployment` — the show-page / a11y /
  inline-handler checks skip when the instance has no sample document of that
  type to open. Seed one per type to convert these to real coverage.
- `no a11y baseline for '<page>' yet` — capture with `UPDATE_A11Y_BASELINE=1`
  and commit `a11y_baseline.json` (see the Accessibility section below).
- `non-draft / read-only — expand-only check` — intentional; a read-only doc
  has no editable control to exercise. These stay skipped by design.

A wall of `502/503/504` **failures** across every route is not a code problem —
it means the deployed instance is unhealthy (e.g. an ECS task recycle). The
suite is correctly reporting an outage; check the deployment, not the tests.

## Configuration

| Env var | Default | Purpose |
|---------|---------|---------|
| `SPARC_SMOKE_BASE_URL` | `https://sparc.risk-sentinel.org` | Target deployment |
| `SPARC_SMOKE_SA_TOKEN` | _(unset)_ | Service-account bearer token; authenticated tests skip without it |
| `SPARC_SMOKE_USER_TOKEN` | _(unset)_ | Optional second, **non-admin** identity (the submitter in review/approval flows, #643); two-identity tests skip without it |
| `SPARC_SESSION_COOKIE_NAME` | _(auto-detected)_ | Override the Rails session cookie name; by default the cookie returned by the bridge is auto-detected (`_ssp_tpr_manager_session`) |

### Minting the SA token

Create/scope a service account in **Admin → Service Accounts** (admin-owned,
opt-in admin per #536) and copy its `sparc_sa_...` token. The suite exchanges it
for a session via `POST /api/v1/sessions/from_token` (#573) — the token is never
typed into the login form. Store it as the `SPARC_SMOKE_SA_TOKEN` CI secret;
revoke/rotate from the same admin page.

## Accessibility (Layer 3 — axe-core, #599)

`test_accessibility.py` runs axe-core against the login page and the core
authenticated pages, scoped to **WCAG 2.1 A + AA** (the Section 508 conformance
bar). It uses **baseline + ratchet**: existing violations are recorded in
`a11y_baseline.json` (per page, fingerprinted by rule + CSS target) and pass;
only **new** violations fail. A page with no baseline entry yet is skipped until
its baseline is captured.

```bash
# Enforce (default) — fails on NEW violations only:
uv run pytest test_accessibility.py --browser chromium --browser firefox

# Capture/refresh the baseline (e.g. after fixing debt, or to add the
# authenticated pages — needs SPARC_SMOKE_SA_TOKEN), then commit the file:
UPDATE_A11Y_BASELINE=1 SPARC_SMOKE_SA_TOKEN=sparc_sa_... \
  uv run pytest test_accessibility.py --browser chromium --browser firefox
```

The login baseline (5 violations: 4 color-contrast + 1 aria-allowed-role) is
committed; the authenticated pages' baseline is captured on the first CI run
with the token, then committed. Burn the baseline down over time — each fix is a
line removed from `a11y_baseline.json`.

## CI

Runs via `.github/workflows/ui-smoke.yml` — `workflow_dispatch` (manual, with a
base-URL input) and after deploys. **Gated / non-blocking** (`continue-on-error`)
during ramp, mirroring the Grype gate, so a flaky smoke never blocks a deploy
while the suite earns trust.
