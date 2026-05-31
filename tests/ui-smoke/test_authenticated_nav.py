"""Authenticated navigation + render-health smoke (#573, #599).

Bridges a service-account token to a Rails session (#573 cookie-bridge) and
validates the full authenticated page surface (shared inventory in pages.py).
For every must-exist page this asserts, as HARD failures:
  - the page loads (HTTP < 400) — a 4xx/5xx is route/permission/render drift
  - it is NOT redirected to /login (session/auth drift)
  - no console errors and no CSP violations during load

Show pages are discovered at runtime from their index and skip only when the
deployment has no such record (not a failure). This is the navigation
counterpart to the a11y sweep in test_accessibility.py — both drive off pages.py
so coverage can't diverge.

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise. Run both browsers:
    uv run pytest test_authenticated_nav.py --browser chromium --browser firefox
"""

from __future__ import annotations

import re

import pytest

from helpers import collect_console_errors, csp_violations, record_csp
from pages import MUST_EXIST_PAGES, SHOW_PAGES

pytestmark = pytest.mark.authenticated


def test_session_bridge_lands_authenticated(authed_page):
    """The bridged cookie yields an authenticated session (no /login bounce)."""
    resp = authed_page.goto("/")
    assert resp is not None and resp.ok, (
        f"GET / returned {resp.status if resp else 'none'}"
    )
    assert "/login" not in authed_page.url, (
        f"bridged session bounced to login: {authed_page.url}"
    )


def _assert_clean_load(authed_page, name, path, *, status_ok=lambda s: s < 400):
    """Navigation + render-health assertions shared by every page check."""
    console_errors = collect_console_errors(authed_page)
    record_csp(authed_page)

    resp = authed_page.goto(path)
    assert resp is not None, f"{name}: no response from {path}"
    # Strict: must load. 4xx/5xx = route drift, broken render, or perms drift.
    assert status_ok(resp.status), (
        f"{name}: {path} returned HTTP {resp.status} (expected < 400)"
    )
    # A redirect that lands on /login means the session/auth path drifted.
    assert "/login" not in authed_page.url, (
        f"{name}: {path} bounced to /login (session lost / auth drift)"
    )

    authed_page.wait_for_load_state("networkidle")

    violations = csp_violations(authed_page)
    assert violations == [], f"{name}: CSP violations on {path}: {violations}"
    assert console_errors == [], (
        f"{name}: console errors on {path}: {console_errors}"
    )


@pytest.mark.parametrize(
    "name,path", MUST_EXIST_PAGES, ids=[p[0] for p in MUST_EXIST_PAGES]
)
def test_navigation_page_loads_clean(authed_page, name, path):
    """Every must-exist page loads (200-or-documented-redirect), no /login
    bounce, no console/CSP errors. Hard failure on any miss."""
    _assert_clean_load(authed_page, name, path)


@pytest.mark.parametrize(
    "name,index_path,pattern", SHOW_PAGES, ids=[p[0] for p in SHOW_PAGES]
)
def test_navigation_show_page_loads_clean(authed_page, name, index_path, pattern):
    """Show pages: discover the first record from the index, then validate it
    loads cleanly. Skips only when the deployment has no such record."""
    resp = authed_page.goto(index_path)
    assert resp is not None and resp.status < 400, (
        f"{name}: index {index_path} returned "
        f"{resp.status if resp else 'none'}"
    )
    authed_page.wait_for_load_state("networkidle")

    rx = re.compile(pattern)
    href = next(
        (
            h
            for h in authed_page.eval_on_selector_all(
                "a[href]", "els => els.map(e => e.getAttribute('href'))"
            )
            if h and rx.match(h.split("?")[0])
        ),
        None,
    )
    if not href:
        pytest.skip(f"no {name} record found on this deployment to validate")

    _assert_clean_load(authed_page, name, href)
