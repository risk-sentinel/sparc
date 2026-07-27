"""Consent banner persistence (#824).

The consent banner re-fired on EVERY login-page load. That was not merely
annoying: it made PIV/CAC sign-in impossible. The banner interposed between the
request that carried the smart-card certificate and ``/auth/piv``, so by the
time the user clicked "Sign in with your CAC / smart card" the certificate was
no longer on the request and login failed with "No smart card certificate was
presented" — while the card was working the whole time.

Acceptance is now remembered for the browser SESSION. Session scope is the
deliberate middle ground: AC-8 wants the notice shown before access is granted,
so a long-lived cookie suppressing it for weeks is not acceptable; but
re-firing on every page load broke authentication outright.

These run against a live instance with the banner configured
(SPARC_BANNER_ENABLED / SPARC_BANNER_MESSAGE) and skip when it is not.
"""

from __future__ import annotations

import pytest

CONSENT_MODAL = "[data-consent-banner-target='modal']"
CONSENT_PROCEED = "button[data-action='consent-banner#proceed']"
LOGIN_CARD = "[data-consent-banner-target='loginCard']"
STORAGE_KEY = "sparc.consent.accepted"


def _open_login(page):
    resp = page.goto("/login")
    assert resp is not None and resp.ok, "could not load /login"
    page.wait_for_load_state("networkidle")
    return resp


def _require_banner(page) -> None:
    if page.locator(CONSENT_MODAL).count() == 0:
        pytest.skip("consent banner not configured on this instance")


def _modal_visible(page) -> bool:
    modal = page.locator(CONSENT_MODAL)
    return modal.count() > 0 and modal.first.is_visible()


def test_banner_shows_on_a_fresh_session(page):
    """Control: without prior acceptance the banner MUST gate the login card."""
    _open_login(page)
    _require_banner(page)

    assert _modal_visible(page), "consent banner did not appear on a fresh session"
    assert not page.locator(LOGIN_CARD).first.is_visible(), (
        "login card was reachable before consent was given"
    )


def test_consent_is_remembered_across_page_loads(page):
    """The regression itself: re-firing on every load is what broke PIV login."""
    _open_login(page)
    _require_banner(page)

    page.locator(CONSENT_PROCEED).first.click()
    page.wait_for_timeout(400)  # modal fade-out
    assert page.locator(LOGIN_CARD).first.is_visible(), "login card hidden after Proceed"

    # Reload — this is the step that used to re-fire the banner.
    _open_login(page)
    assert not _modal_visible(page), (
        "consent banner re-fired after acceptance — this is the #824 regression "
        "that made PIV login impossible"
    )
    assert page.locator(LOGIN_CARD).first.is_visible(), (
        "login card is not reachable after consent was already given"
    )


def test_acceptance_is_session_scoped_not_permanent(page):
    """Clearing session storage brings the notice back.

    Pins the AC-8 half of the trade-off: acceptance must NOT be permanent. If
    someone later swaps sessionStorage for a long-lived cookie, this fails.
    """
    _open_login(page)
    _require_banner(page)

    page.locator(CONSENT_PROCEED).first.click()
    page.wait_for_timeout(400)

    page.evaluate("window.sessionStorage.clear()")
    _open_login(page)

    assert _modal_visible(page), (
        "consent did not re-appear after the browser session was cleared — "
        "acceptance must be session-scoped, not permanent"
    )


def test_acceptance_is_recorded_under_the_expected_key(page):
    """Guards the storage key, which the system-spec teardown also clears."""
    _open_login(page)
    _require_banner(page)

    page.locator(CONSENT_PROCEED).first.click()
    page.wait_for_timeout(400)

    stored = page.evaluate(f"window.sessionStorage.getItem({STORAGE_KEY!r})")
    assert stored == "1", f"expected sessionStorage[{STORAGE_KEY!r}] == '1', got {stored!r}"
