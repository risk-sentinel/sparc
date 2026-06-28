"""Tests for the API session-from-token cookie bridge (#573, #610).

Single endpoint: POST /api/v1/sessions/from_token

Exchanges a SPARC API Bearer token (or OIDC JWT) for a Rails session
cookie, so headless runners can drive the UI authenticated. On success:
204 No Content + Set-Cookie. On failure: 401, no cookie.
"""

from __future__ import annotations

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.sessions, pytest.mark.phase2]

FROM_TOKEN_PATH = "/api/v1/sessions/from_token"
# Rails session cookie name (config/initializers/session_store.rb). Verified
# against the live bridge response (#644).
SESSION_COOKIE = "_ssp_tpr_manager_session"


class TestFromToken:
    @pytest.mark.happy
    def test_valid_token_sets_session_cookie(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(FROM_TOKEN_PATH)
        assert response.status_code == 204, response.text
        # A Set-Cookie for the Rails session must be present.
        set_cookie = response.headers.get("set-cookie", "")
        assert SESSION_COOKIE in set_cookie, f"missing session cookie: {set_cookie!r}"

    @pytest.mark.happy
    def test_bridged_cookie_authenticates_ui(
        self, base_url: str, admin_client: httpx.Client
    ) -> None:
        # The cookie returned by the bridge should authenticate a UI request
        # (no redirect to /login).
        bridge = admin_client.post(FROM_TOKEN_PATH)
        assert bridge.status_code == 204, bridge.text
        cookie = bridge.cookies.get(SESSION_COOKIE)
        if not cookie:
            pytest.skip("session cookie not exposed via httpx cookie jar on this instance")

        with httpx.Client(
            base_url=base_url,
            cookies={SESSION_COOKIE: cookie},
            follow_redirects=False,
            timeout=30.0,
        ) as cookie_client:
            home = cookie_client.get("/")
            # Authenticated: a real page, not a 302 bounce to the login form.
            assert home.status_code == 200, f"expected authenticated 200, got {home.status_code}"

    @pytest.mark.auth
    def test_missing_token_returns_401(self, anon_client: httpx.Client) -> None:
        response = anon_client.post(FROM_TOKEN_PATH)
        assert_error_envelope(response, expected_status=401)
        assert SESSION_COOKIE not in response.headers.get("set-cookie", "")

    @pytest.mark.auth
    def test_bad_token_returns_401(self, bad_token_client: httpx.Client) -> None:
        response = bad_token_client.post(FROM_TOKEN_PATH)
        # /sessions/from_token is rate-limited per IP; a full-suite run can
        # saturate the bucket and return 429 before this test. Skip on 429 —
        # it's environment state leakage, not a contract failure (#644).
        if response.status_code == 429:
            pytest.skip("rate-limited (429) — bucket saturated by prior tests")
        assert response.status_code == 401, response.text
        assert SESSION_COOKIE not in response.headers.get("set-cookie", "")
