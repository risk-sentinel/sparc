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
| `conftest.py` | Base-URL + cookie-bridge fixtures | — |
| `helpers.py` | CSP-violation recorder, console collector, same-origin check | — |

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

## Configuration

| Env var | Default | Purpose |
|---------|---------|---------|
| `SPARC_SMOKE_BASE_URL` | `https://sparc.risk-sentinel.org` | Target deployment |
| `SPARC_SMOKE_SA_TOKEN` | _(unset)_ | Service-account bearer token; authenticated tests skip without it |
| `SPARC_SESSION_COOKIE_NAME` | `_sparc_session` | Rails session cookie name |

### Minting the SA token

Create/scope a service account in **Admin → Service Accounts** (admin-owned,
opt-in admin per #536) and copy its `sparc_sa_...` token. The suite exchanges it
for a session via `POST /api/v1/sessions/from_token` (#573) — the token is never
typed into the login form. Store it as the `SPARC_SMOKE_SA_TOKEN` CI secret;
revoke/rotate from the same admin page.

## CI

Runs via `.github/workflows/ui-smoke.yml` — `workflow_dispatch` (manual, with a
base-URL input) and after deploys. **Gated / non-blocking** (`continue-on-error`)
during ramp, mirroring the Grype gate, so a flaky smoke never blocks a deploy
while the suite earns trust.
