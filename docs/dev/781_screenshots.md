# Capturing User-Guide screenshots (#781)

Repeatable capture of per-screen screenshots for the wiki User Guides, so images
refresh as the UI changes instead of drifting (the #771/#781 rule: UI changes
update the relevant guide).

## Why real Chrome, not bundled Chromium

Screenshots must look like a real deployment. Playwright's bundled Chromium is
not representative (font stack, rendering), so the capture script drives the
**installed Google Chrome** via `channel="chrome"` at a 2x device scale. And it
targets the **local UBI9 prod-image stack** — the same image that ships — with
`SPARC_SEED_DEMO=true`, so the pixels are the production asset pipeline over
synthetic "ACME Cloud Platform" demo data (no real identifiers in a public wiki).

The screen list is not hand-maintained: `capture_screenshots.py` iterates
`tests/ui-smoke/pages.py` (the same inventory the smoke + a11y suites use), so a
new page added there is captured automatically.

## Prerequisites

- Google Chrome installed (`/Applications/Google Chrome.app`).
- The ui-smoke venv with Playwright (`tests/ui-smoke/.venv`).

## Steps

1. **Bring up the prod-image stack with TLS + demo data** (authenticated pages
   need the Secure session cookie, so go through caddy on `:3443`):

   ```bash
   docker compose -f docker-compose.ubi9.yaml --profile tls up -d --build
   ```

2. **Clear the seeded-admin bootstrap password gate + mint a token** (a freshly
   seeded admin has `must_reset_password?` true and 302s every page to
   `/password/edit`):

   ```bash
   docker compose -f docker-compose.ubi9.yaml exec web bin/rails runner '
     u = User.find_by(admin: true)
     u.update!(must_reset_password: false, password_changed_at: Time.current)
     puts ApiToken.generate!(user: u, name: "shots").plaintext_token'
   ```

3. **Capture** (run from `tests/ui-smoke/`):

   ```bash
   SPARC_SMOKE_BASE_URL=https://localhost:3443 \
   SPARC_SMOKE_SA_TOKEN=<token-from-step-2> \
   SPARC_SMOKE_INSECURE_TLS=1 \
     .venv/bin/python capture_screenshots.py
   ```

   PNGs land in `wiki/images/<page-label>.png`, one per screen in `pages.py`.

4. **Publish** to the wiki (`PUSH_TO_WIKI.sh` now also copies `wiki/images/`):

   ```bash
   ./wiki/PUSH_TO_WIKI.sh
   ```

   Guides reference images by relative path: `![alt](images/ssp_index.png)`.

## Refreshing after a UI change

Re-run steps 1–3. Because the inventory is shared with the smoke suite, the set
of screenshots stays in lockstep with the real screen surface.
