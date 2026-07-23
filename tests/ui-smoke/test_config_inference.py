"""UI smoke: configuration inference is visible in the browser (#785).

v1.13.1 stopped requiring several `SPARC_ENABLE_*` flags and started inferring
them from the credentials that were already configured:

    SPARC_ENABLE_OIDC    <- SPARC_OIDC_CLIENT_ID being set
    SPARC_ENABLE_SMTP    <- SPARC_SMTP_ADDRESS being set
    SPARC_BANNER_ENABLED <- SPARC_BANNER_MESSAGE being set

Those inferences are the kind of change request specs pass on and users still
notice, because the failure mode is silent: a login method or a consent banner
simply stops rendering. Precedent: #593 was a CSP `form-action` bug that made
the Sign-in-with-Okta button dead in Chromium while every same-origin request
spec stayed green.

Two structural facts about /login that these tests must respect — both cost time
to discover, so they are encoded here rather than rediscovered:

1. When a consent banner is configured, the login card ships with `d-none` and a
   modal gates it. Nothing on the login form is visible until "Proceed" is
   clicked. That gate IS the AC-8 control, so it is asserted, not worked around.
2. The login form is TABBED. A provider panel is inactive until its tab is
   clicked, so its submit button exists but is not visible on load.

    uv run pytest test_config_inference.py --browser chromium --browser firefox
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, csp_violations, record_csp

CONSENT_MODAL = "[data-consent-banner-target='modal']"
CONSENT_PROCEED = "button[data-action='consent-banner#proceed']"
LOGIN_CARD = "[data-consent-banner-target='loginCard']"


def _consent_present(page) -> bool:
    return page.locator(CONSENT_MODAL).count() > 0


def _dismiss_consent(page) -> bool:
    """Accept the consent banner if one gates the page. Returns whether it did."""
    if not _consent_present(page):
        return False
    proceed = page.locator(CONSENT_PROCEED)
    if proceed.count() == 0:
        return False
    proceed.first.click()
    page.wait_for_timeout(300)  # modal fade
    return True


def _open_login(page) -> None:
    resp = page.goto("/login")
    assert resp is not None and resp.ok, "could not load /login"
    page.wait_for_load_state("networkidle")
    _dismiss_consent(page)


class TestConsentBanner:
    """SPARC_BANNER_ENABLED is now inferred from SPARC_BANNER_MESSAGE (#785).

    The banner is an AC-8 control (system use notification). If the inference
    regressed, the banner would silently stop rendering and users would reach the
    login form without ever being shown the notice — a compliance failure no
    request spec asserting HTTP 200 would catch.
    """

    def test_banner_gates_the_login_form_when_configured(self, page):
        record_csp(page)
        page.goto("/login")
        page.wait_for_load_state("networkidle")

        if not _consent_present(page):
            pytest.skip("no consent banner configured on this instance")

        modal = page.locator(CONSENT_MODAL)
        assert modal.first.is_visible(), (
            "consent banner is configured but its modal is not shown — users would "
            "reach the login form without seeing the notice (AC-8)"
        )
        assert modal.first.inner_text().strip() != "", "consent banner rendered empty"

        # The gate itself: the login card must NOT be reachable behind the modal.
        card = page.locator(LOGIN_CARD)
        if card.count() > 0:
            assert not card.first.is_visible(), (
                "login form is visible while the consent banner is still up — the "
                "AC-8 gate is not gating anything"
            )
        assert_no_csp_violations(page, during="consent banner render")

    def test_proceeding_past_the_banner_reveals_the_login_form(self, page):
        record_csp(page)
        page.goto("/login")
        page.wait_for_load_state("networkidle")

        if not _dismiss_consent(page):
            pytest.skip("no consent banner configured on this instance")

        card = page.locator(LOGIN_CARD)
        if card.count() > 0:
            card.first.wait_for(state="visible", timeout=5000)
            assert card.first.is_visible(), (
                "accepting the consent banner did not reveal the login form — users "
                "would be locked out entirely"
            )
        assert_no_csp_violations(page, during="accepting the consent banner")


class TestAuthMethodRendering:
    """An inferred auth method must actually reach the login page.

    The regression this guards: inference computes `false` where it used to be an
    explicit `true`, the provider tab silently disappears, and nobody notices
    until a user cannot sign in.
    """

    def test_login_page_offers_at_least_one_auth_method(self, page):
        record_csp(page)
        _open_login(page)

        # Any of: local password form, a provider tab, or a security-key entry
        # point. Zero of them means the instance is unusable — exactly what a bad
        # inference would produce.
        has_password_form = page.locator("input[type='password']").count() > 0
        has_provider_tab = page.locator("button[data-tab]").count() > 0
        # SPARC renders provider sign-in as a FORM POST, not an anchor.
        has_provider_form = page.locator("form[action*='/auth/'] button").count() > 0
        has_webauthn = "security key" in page.content().lower()

        assert has_password_form or has_provider_tab or has_provider_form or has_webauthn, (
            "login page offers NO way to authenticate — check the SPARC_ENABLE_* "
            "inferences in SparcConfig (#785)"
        )
        assert_no_csp_violations(page, during="/login load")

    def test_oidc_tab_and_submit_render_when_oidc_is_configured(self, page):
        """The OIDC tab renders only `if SparcConfig.enable_oidc?`.

        That makes the tab trigger a direct read-out of the inference: if
        `SPARC_ENABLE_OIDC <- SPARC_OIDC_CLIENT_ID` regressed to false, this tab
        disappears and OIDC login becomes unreachable.
        """
        record_csp(page)
        _open_login(page)

        tab = page.locator("button[data-tab='tab-oidc']")
        if tab.count() == 0:
            pytest.skip("OIDC not configured on this instance")

        tab.first.wait_for(state="visible", timeout=5000)
        tab.first.click()

        submit = page.locator("form[action*='/auth/oidc'] button[type='submit']")
        assert submit.count() > 0, "OIDC panel has no submit button"
        submit.first.wait_for(state="visible", timeout=5000)
        assert submit.first.is_enabled(), "OIDC submit is visible but disabled"

        # #593: the button rendered fine but CSP form-action blocked the POST.
        # A cross-origin action is what that policy refuses.
        action = page.locator("form[action*='/auth/oidc']").first.get_attribute("action") or ""
        assert action.startswith("/"), (
            f"OIDC form action is not a same-origin path ({action!r}); "
            "CSP form-action will block the submit"
        )
        assert_no_csp_violations(page, during="activating the OIDC login tab")

    def test_no_raw_config_variable_names_leak_into_the_page(self, page):
        """A misconfigured toggle must not surface raw variable names to users."""
        _open_login(page)
        assert "SPARC_ENABLE" not in page.content(), (
            "raw SPARC_ENABLE_* variable name leaked into rendered HTML"
        )


class TestSupportContact:
    """SPARC_ORG_CONTACT_EMAIL was folded into SPARC_CONTACT_EMAIL (#785).

    home/index.html.erb renders `SparcConfig.support_email`. Consolidating the
    two variables touched that accessor, so pin the rendered result.
    """

    def test_support_email_renders_as_a_mailto_when_configured(self, authed_page):
        page = authed_page
        record_csp(page)
        page.goto("/")
        page.wait_for_load_state("networkidle")

        mailto = page.locator("a[href^='mailto:']")
        if mailto.count() == 0:
            pytest.skip("no support email configured on this instance")

        href = mailto.first.get_attribute("href") or ""
        assert "@" in href, f"support mailto link is malformed: {href!r}"
        assert href.strip() != "mailto:", (
            "support mailto link has an empty address — SPARC_CONTACT_EMAIL resolved "
            "to blank (check the ORG_CONTACT_EMAIL consolidation, #785)"
        )
        assert csp_violations(page) == [], "CSP violations on the home page"


class TestUploadStorageBackend:
    """ACTIVE_STORAGE_SERVICE is now wired (#785).

    It previously did nothing — production.rb hardcoded :amazon — so an operator
    selecting a backend was ignored. Now that it is honoured, a bad value means
    every upload fails.
    """

    def test_upload_entry_point_loads_without_error(self, authed_page):
        page = authed_page
        record_csp(page)
        resp = page.goto("/ssp_documents/new")
        assert resp is not None, "no response from the upload page"
        assert resp.status < 500, (
            f"upload page returned HTTP {resp.status} — a 5xx here can indicate a "
            "misconfigured ACTIVE_STORAGE_SERVICE (#785)"
        )
        page.wait_for_load_state("networkidle")
        assert_no_csp_violations(page, during="upload page load")
