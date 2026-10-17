"""OIDC sign-in reaches the IdP — in Chrome, against a real issuer (#1217).

v1.17.0 shipped with every OIDC sign-in broken: json 3 rejected the options hash
faraday 2.14.3 passed to `JSON.parse`, so the server-side discovery fetch raised
and the browser was sent back to /login with "Authentication failed: Unknown
error". Nothing caught it. The #593 test in test_login_page.py aborts every
external request and only asserts CSP did not block the form, so it passed;
and the gate stack does not enable OIDC, so it skipped anyway.

This proves the request phase end to end: click the button, SPARC fetches the
issuer's discovery document through its real HTTP stack, and the browser is
redirected to that issuer's authorization endpoint with a well-formed request.
Nobody signs in. The request to the IdP is captured and aborted, so the run
needs no credentials and never loads the IdP's page.

Runs only when the target is configured for OIDC and the harness says which
issuer to expect:

    SPARC_SMOKE_OIDC_ISSUER   e.g. https://okta.okta.com/oauth2/default

Bring the stack up with dev/ubi9/compose.oidc-okta.yaml (a public Okta issuer,
a throwaway client id), then:

    SPARC_SMOKE_OIDC_ISSUER=https://okta.okta.com/oauth2/default \
      uv run pytest test_oidc_idp_redirect.py --browser chromium
"""

from __future__ import annotations

import os
from urllib.parse import parse_qs, urlparse

import httpx
import pytest

from helpers import csp_violations, record_csp

ISSUER = os.environ.get("SPARC_SMOKE_OIDC_ISSUER", "").rstrip("/")

# #885 — named so a skip is reported as UNPROVEN rather than passing quietly.
pytestmark = [
    pytest.mark.posture("oidc_idp_redirect"),
    pytest.mark.skipif(
        not ISSUER,
        reason="requires an OIDC-enabled target (dev/ubi9/compose.oidc-okta.yaml) "
        "and SPARC_SMOKE_OIDC_ISSUER naming its issuer",
    ),
]


def _authorization_endpoint() -> str:
    """The issuer's own answer, read independently of SPARC."""
    resp = httpx.get(f"{ISSUER}/.well-known/openid-configuration", timeout=15.0)
    resp.raise_for_status()
    return resp.json()["authorization_endpoint"]


def test_oidc_sign_in_redirects_to_the_issuers_authorize_endpoint(page):
    authorize = _authorization_endpoint()
    idp_host = urlparse(authorize).hostname
    # Never load the IdP's page: the request leaving the browser is the proof.
    page.route(lambda url: urlparse(url).hostname == idp_host, lambda route: route.abort())
    record_csp(page)
    page.goto("/login")

    # The harness declared an issuer, so a missing button is the target
    # disagreeing with the harness — a failure, never a skip.
    button = page.locator("form[action='/auth/oidc'] button[type=submit]")
    assert button.count() == 1, (
        "SPARC_SMOKE_OIDC_ISSUER is set but /login has no OIDC sign-in button; "
        "is the stack running with SPARC_ENABLE_OIDC and this issuer?"
    )

    try:
        to_idp = lambda r: r.url.startswith(authorize)  # noqa: E731
        with page.expect_request(to_idp, timeout=30_000) as sent_info:
            button.click()
    except Exception:  # noqa: BLE001 — report where the browser went instead
        page.wait_for_load_state("domcontentloaded")
        alerts = page.locator("[role=alert], .alert").all_inner_texts()
        flashes = [t.strip() for t in alerts if t.strip()]
        pytest.fail(
            f"OIDC sign-in never reached {authorize}. The browser is at {page.url} "
            f"with {flashes or 'no flash'} (the #1217 symptom is /login with "
            "'Authentication failed: Unknown error')."
        )

    sent = urlparse(sent_info.value.url)
    params = {k: v[0] for k, v in parse_qs(sent.query).items()}

    assert f"{sent.scheme}://{sent.netloc}{sent.path}" == authorize
    assert params.get("response_type") == "code", params
    assert "openid" in params.get("scope", "").split(), params
    assert params.get("client_id"), params
    assert params.get("state"), "no state: the callback could not be bound to this browser"
    assert urlparse(params.get("redirect_uri", "")).path == "/auth/oidc/callback", params

    violations = csp_violations(page)
    assert violations == [], f"CSP violations during OIDC sign-in: {violations}"
