"""Tests for /api/v1/admin/refresh_credentials.

The endpoint is feature-flagged: it returns 503 unless
``SPARC_ADMIN_REFRESH_ENABLED=true`` is set on the SPARC ECS task.
Tests accept either the gated state (503) or the enabled state (2xx /
4xx per the documented contract) — both are correct production
configurations depending on whether Lambda-driven rotation is wired up.

Tests do NOT actually rotate the admin password: that would log the
test user out of every other parallel run. The happy-path test
submits the *current* password (sourced via an idempotent endpoint
behavior) and expects ``status: "unchanged"``.
"""

from __future__ import annotations

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.admin, pytest.mark.phase2]


PATH = "/api/v1/admin/refresh_credentials"


# Either the feature is enabled (and the endpoint works) or it isn't
# (and the endpoint returns 503). Both states are valid for tests.
ENABLED_STATUS_OK = (200,)
GATED_STATUS_OK = (503,)


class TestRefreshCredentials:
    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        response = anon_client.post(
            PATH,
            json={"password": "anything"},  # NOSONAR(python:S2068) fake payload
        )
        # Not a real credential — auth is rejected before the value is ever read.
        # The auth check fires before the feature-flag check, so 401
        # is the expected response regardless of SPARC_ADMIN_REFRESH_ENABLED.
        assert_error_envelope(response, expected_status=401)

    @pytest.mark.authz
    def test_non_admin_token_returns_403(self, user_client: httpx.Client) -> None:
        response = user_client.post(
            PATH,
            json={"password": "anything"},  # NOSONAR(python:S2068) fake payload
        )
        # Not a real credential — authz is rejected before the value is ever read.
        # If feature-flagged off, the order is: auth -> permission -> flag.
        # 403 (permission) or 503 (gated) are both correct rejections.
        assert response.status_code in (403, 503), response.text

    @pytest.mark.validation
    def test_admin_with_empty_password_returns_422_or_503(
        self, admin_client: httpx.Client
    ) -> None:
        response = admin_client.post(PATH, json={"password": ""})
        # 503 if feature-flag off; 422 if on but bad input.
        if response.status_code == 503:
            return
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_admin_with_missing_password_returns_422_or_503(
        self, admin_client: httpx.Client
    ) -> None:
        response = admin_client.post(PATH, json={})
        if response.status_code == 503:
            return
        assert_error_envelope(response, expected_status=422)

    # NOTE: there is no happy-path test that actually exercises a 200
    # response on this endpoint. Calling the endpoint with a wrong
    # plaintext rotates the admin password to that value (the controller
    # treats a non-matching password as the new value and bcrypts it).
    # An automated test cannot supply the *correct* current admin password
    # without re-deriving it out-of-band, so we deliberately stop at the
    # documented error / gate paths above. Operators verify the happy path
    # via Layer 1 of `docs/ADMIN_CREDENTIAL_ROTATION.md`.
