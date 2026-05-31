"""Authenticated navigation smoke.

Bridges a service-account token to a Rails session (#573 cookie-bridge) and
walks the core authenticated pages, asserting each renders without server
errors, console errors, or CSP violations. Requires SPARC_SMOKE_SA_TOKEN;
skipped otherwise.

Run in both browsers to catch cross-browser rendering/CSP regressions:
    SPARC_SMOKE_SA_TOKEN=sparc_sa_... \
      uv run pytest test_authenticated_nav.py --browser chromium --browser firefox
"""

from __future__ import annotations

import pytest

from helpers import collect_console_errors, csp_violations, record_csp

pytestmark = pytest.mark.authenticated

# Core authenticated pages. Index routes only — cheap, no fixtures required,
# and they exercise the shared layout/nav where CSP + asset regressions show.
CORE_PAGES = [
    ("dashboard", "/"),
    ("ssp_index", "/ssp_documents"),
    ("sar_index", "/sar_documents"),
    ("cdef_index", "/cdef_documents"),
    ("poam_index", "/poam_documents"),
]


def test_session_bridge_lands_authenticated(authed_page):
    """The bridged cookie yields an authenticated session (no /login bounce)."""
    resp = authed_page.goto("/")
    assert resp is not None and resp.ok, f"GET / returned {resp.status if resp else 'none'}"
    assert "/login" not in authed_page.url, (
        f"bridged session bounced to login: {authed_page.url}"
    )


@pytest.mark.parametrize("name,path", CORE_PAGES, ids=[p[0] for p in CORE_PAGES])
def test_core_page_renders_clean(authed_page, name, path):
    console_errors = collect_console_errors(authed_page)
    record_csp(authed_page)

    resp = authed_page.goto(path)
    assert resp is not None, f"no response from {path}"
    assert resp.status < 500, f"{path} returned server error HTTP {resp.status}"
    assert "/login" not in authed_page.url, f"{path} bounced to login (session lost)"

    authed_page.wait_for_load_state("networkidle")

    violations = csp_violations(authed_page)
    assert violations == [], f"CSP violations on {path}: {violations}"
    assert console_errors == [], f"console errors on {path}: {console_errors}"
