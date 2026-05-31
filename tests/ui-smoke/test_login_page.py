"""Login-page smoke — the #593 cross-browser regression net.

The CSP `form-action` bug (Sign-in-with-GitHub/Okta buttons silently dead in
Chromium, working in Firefox) is invisible to same-origin request specs and to
Firefox. It only surfaces in a real Chromium browser. Run this in BOTH:

    uv run pytest test_login_page.py --browser chromium --browser firefox

None of these require authentication.
"""

from __future__ import annotations

from helpers import csp_violations, record_csp, same_origin


def test_login_page_loads(page):
    resp = page.goto("/login")
    assert resp is not None, "no response from /login"
    assert resp.ok, f"/login returned HTTP {resp.status}"
    assert page.locator("form").count() > 0, "no <form> rendered on /login"


def test_login_page_has_no_csp_violations_on_load(page):
    record_csp(page)
    page.goto("/login")
    page.wait_for_load_state("networkidle")
    violations = csp_violations(page)
    assert violations == [], f"CSP violations on /login load: {violations}"


def test_sso_submit_not_blocked_by_csp_form_action(page, context, base_url):
    """#593 regression: clicking an SSO button must not trip `form-action`.

    Egress to external IdPs is aborted so the smoke run never actually leaves
    to github.com/okta — we only assert the submission itself isn't blocked by
    CSP (which is exactly how the bug manifested in Chromium).
    """
    context.route(
        "**/*",
        lambda route: (
            route.continue_()
            if same_origin(route.request.url, base_url)
            else route.abort()
        ),
    )
    record_csp(page)
    page.goto("/login")

    sso = page.get_by_role("button", name="Sign in with GitHub")
    if sso.count() == 0:
        sso = page.get_by_role("button", name="Sign in with Okta")
    if sso.count() == 0:
        import pytest

        pytest.skip("no GitHub/Okta SSO button on this deployment")

    sso.first.click()
    page.wait_for_timeout(1500)

    blocked = [v for v in csp_violations(page) if v.get("directive") == "form-action"]
    assert not blocked, (
        "CSP form-action blocked the SSO submission (#593 regression): "
        f"{blocked}"
    )
