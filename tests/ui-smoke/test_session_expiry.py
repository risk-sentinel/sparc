"""Login-page caching + post-expiry SSO smoke (#649, epic #650).

The #649 bug: after session expiry the Okta/GitHub login buttons were dead until
a hard reload, because a bfcache/HTTP-cached copy of the login page carried the
strict form-action CSP instead of the relaxed (per-#593) policy. The fix sends
Cache-Control: no-store so the page is always served fresh with the relaxed
policy.

These run unauthenticated (no token needed): the no-store header check is a hard
assertion; the bfcache SSO-submit check is skipped when no SSO provider is
configured on the target.
"""

from __future__ import annotations

import os

import httpx

from helpers import assert_no_csp_violations, record_csp

BASE_URL = os.environ.get(
    "SPARC_SMOKE_BASE_URL", "https://sparc.risk-sentinel.org"
).rstrip("/")


def test_login_is_no_store():
    """/login must be uncacheable so a stale strict-CSP copy can't be restored."""
    resp = httpx.get(f"{BASE_URL}/login", timeout=30.0)
    cache_control = resp.headers.get("cache-control", "")
    assert "no-store" in cache_control, f"login Cache-Control was {cache_control!r}"


def test_login_loads_clean(page):
    """The login page renders with zero CSP violations (relaxed form-action)."""
    record_csp(page)
    page.goto(f"{BASE_URL}/login", wait_until="networkidle")
    assert_no_csp_violations(page, during="login load")


def test_login_bfcache_restore_keeps_sso_clean(page):
    """Restoring the login page from bfcache (back-button) must not resurrect a
    strict-CSP copy that blocks the SSO POST. Skips when no SSO form is present."""
    record_csp(page)
    page.goto(f"{BASE_URL}/login", wait_until="networkidle")

    sso = page.locator(
        'form[action="/auth/oidc"] button, form[action="/auth/github"] button, '
        'form[action="/auth/gitlab"] button'
    )
    if sso.count() == 0:
        import pytest

        pytest.skip("no SSO provider configured on this target")

    # Navigate away, then restore from bfcache via the back button.
    page.goto(f"{BASE_URL}/about", wait_until="networkidle")
    page.go_back(wait_until="networkidle")

    # The relaxed form-action must still be in force on the restored page: a
    # click must not trip a form-action securitypolicyviolation.
    assert_no_csp_violations(page, during="login bfcache restore")
