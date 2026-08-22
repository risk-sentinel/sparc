"""Tests for /api/v1/admin/refresh_credentials (#403).

The endpoint receives a new admin password from a sparc-iac-managed Lambda and
bcrypts it into the admin user. It is feature-flagged: without
``SPARC_ADMIN_REFRESH_ENABLED=true`` it returns 503, failing closed in
environments that have not opted in to remote rotation.

Both configurations are legitimate, so this module DETECTS which one the target
is in, once, and then asserts that configuration's contract in full. It no
longer accepts "422 or 503" per test — an assertion that passes on either
cannot tell a working validator from a disabled feature, and on a gated
instance the whole module proved nothing while still reporting green.

There is deliberately no happy-path test, and this is a real limitation rather
than an oversight. The controller treats a password that does NOT match the
current one as the new value and rotates to it; only the current password
returns ``{"status": "unchanged"}`` without changing anything. A test cannot
supply the current admin password without re-deriving it out of band, and a
wrong guess would rotate the live admin credential and lock out every other
run. Operators verify that path via Layer 1 of
`docs/ADMIN_CREDENTIAL_ROTATION.md`.

(The previous docstring claimed the opposite — that a happy-path test submitted
the current password and expected "unchanged" — while a note at the foot of the
same file said no such test existed. The note was the accurate one.)
"""

from __future__ import annotations

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.admin, pytest.mark.phase2]


PATH = "/api/v1/admin/refresh_credentials"

ENABLED = "enabled"
GATED = "gated"


@pytest.fixture(scope="module")
def mode(admin_client: httpx.Client) -> str:
    """Which configuration the target instance is in.

    Probed with an empty body, which is refused by validation when the feature
    is on and by the flag when it is off — so it establishes the mode without
    ever submitting a value that could rotate the credential.
    """
    response = admin_client.post(PATH, json={})

    if response.status_code == 503:
        return GATED
    assert response.status_code == 422, (
        "refresh_credentials answered an empty body with "
        f"{response.status_code}; expected 422 (feature on) or 503 (feature off)"
    )
    return ENABLED


@pytest.mark.validation
class TestValidation:
    def test_an_empty_password_is_refused_by_name(
        self, admin_client: httpx.Client, mode: str
    ) -> None:
        response = admin_client.post(PATH, json={"password": ""})

        if mode == GATED:
            assert_error_envelope(response, expected_status=503)
            return

        assert_error_envelope(response, expected_status=422)
        assert response.json()["error"] == "password is required", response.text

    def test_a_missing_password_is_refused_the_same_way(
        self, admin_client: httpx.Client, mode: str
    ) -> None:
        """A field omitted and a field sent empty must not be told apart here —
        both are "you did not give me a password", and #995 check 4 is about a
        refusal that says which."""
        response = admin_client.post(PATH, json={})

        if mode == GATED:
            assert_error_envelope(response, expected_status=503)
            return

        assert_error_envelope(response, expected_status=422)
        assert response.json()["error"] == "password is required", response.text

    def test_a_refused_call_leaves_the_existing_credential_working(
        self, admin_client: httpx.Client
    ) -> None:
        """The property that makes the refusals above safe to assert.

        This endpoint rotates a real credential. A validation failure that
        nonetheless wrote something would lock out the admin account, and the
        422 alone cannot tell the difference.
        """
        refused = admin_client.post(PATH, json={"password": ""})
        assert refused.status_code in (422, 503), refused.text

        still_authenticated = admin_client.get("/api/v1/users", params={"items": 1})
        assert still_authenticated.status_code == 200, (
            "the admin token stopped working after a refused rotation"
        )


@pytest.mark.authz
class TestAuthorization:
    def test_a_non_admin_is_refused_whatever_the_feature_flag_says(
        self, user_client: httpx.Client
    ) -> None:
        """Exactly 403, in both configurations.

        `Api::V1::Admin::CredentialsController` declares
        `before_action :authorize_rotate!` ahead of
        `before_action :require_feature_enabled!`, so authorization is settled
        before the flag is consulted. This previously accepted 403 or 503, which
        could not distinguish a permission gate that works from one that is
        never reached.
        """
        response = user_client.post(PATH, json={"password": "not-a-real-password"})

        assert_error_envelope(response, expected_status=403)


@pytest.mark.auth
class TestAuthentication:
    def test_an_anonymous_caller_is_refused_before_anything_is_read(
        self, anon_client: httpx.Client
    ) -> None:
        # NOSONAR(python:S2068) — not a credential; rejected before it is read.
        response = anon_client.post(PATH, json={"password": "not-a-real-password"})

        assert_error_envelope(response, expected_status=401)

    def test_an_unrecognized_token_is_refused_identically(
        self, bad_token_client: httpx.Client
    ) -> None:
        """A well-formed token that is not ours must look like no token at all,
        or the response distinguishes 'wrong token' from 'no token'."""
        # NOSONAR(python:S2068) — not a credential; rejected before it is read.
        response = bad_token_client.post(PATH, json={"password": "not-a-real-password"})

        assert_error_envelope(response, expected_status=401)
