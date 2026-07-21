"""FIDO2 security-key smoke via Chromium's virtual authenticator (#779).

No hardware: the Chrome DevTools Protocol virtual authenticator simulates a
resident FIDO2 key with user verification (PIN) and presence auto-satisfied. The
test enrolls a key on the management page, then signs in passwordlessly with it —
the full browser ceremony (Stimulus + navigator.credentials) end to end.

Runs only against a FIDO2-enabled target (set SPARC_SMOKE_FIDO2=1); skips
otherwise, so it never runs against a deployment without SPARC_FIDO2_ENABLED.
"""

from __future__ import annotations

import os

import pytest

pytestmark = pytest.mark.skipif(
    os.environ.get("SPARC_SMOKE_FIDO2") != "1",
    reason="requires a FIDO2-enabled target (set SPARC_SMOKE_FIDO2=1)",
)


def _add_virtual_authenticator(cdp):
    """Add a resident, user-verifying CTAP2 authenticator; auto touch + PIN."""
    cdp.send("WebAuthn.enable")
    result = cdp.send(
        "WebAuthn.addVirtualAuthenticator",
        {
            "options": {
                "protocol": "ctap2",
                "transport": "usb",
                "hasResidentKey": True,
                "hasUserVerification": True,
                "isUserVerified": True,               # auto-satisfy the PIN
                "automaticPresenceSimulation": True,  # auto-satisfy "touch"
            }
        },
    )
    return result["authenticatorId"]


def _dismiss_consent_if_present(page):
    """The login form is gated behind a consent banner (#190) — click Proceed to
    reveal it, when configured."""
    proceed = page.locator("button[data-action='consent-banner#proceed']")
    if proceed.count() and proceed.is_visible():
        proceed.click()


def test_enroll_then_passwordless_login(context, authed_page, base_url):
    cdp = context.new_cdp_session(authed_page)
    authenticator_id = _add_virtual_authenticator(cdp)

    # 1) Enroll a security key from the management page (attestation ceremony).
    authed_page.goto(f"{base_url}/webauthn_credentials", wait_until="networkidle")
    authed_page.fill("#webauthn-nickname", "Virtual key")
    authed_page.click("button[data-action='webauthn#register']")

    # The fresh virtual authenticator holds exactly the credential from this run,
    # so poll it directly — independent of any pre-existing DB state.
    credentials = []
    for _ in range(20):
        credentials = cdp.send("WebAuthn.getCredentials", {"authenticatorId": authenticator_id})["credentials"]
        if credentials:
            break
        authed_page.wait_for_timeout(500)
    assert len(credentials) == 1, "the attestation ceremony did not store a resident credential"

    # 2) Sign out (drop the session cookie), then sign in with the key alone.
    context.clear_cookies()
    authed_page.goto(f"{base_url}/login", wait_until="networkidle")
    _dismiss_consent_if_present(authed_page)
    authed_page.click("button[data-action='webauthn#login']")

    # A successful passwordless assertion redirects away from /login.
    authed_page.wait_for_url(lambda url: "/login" not in url, timeout=20000)
    assert "/login" not in authed_page.url, "passwordless sign-in did not establish a session"
