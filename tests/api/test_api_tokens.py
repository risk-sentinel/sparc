"""Tests for /api/v1/users/:user_id/api_tokens (#1016).

Issuing and revoking the credential the API authenticates with. Found by the
missing-endpoint axis of #995 — before this the whole lifecycle was
browser-only, so automation could not rotate its own credential.

The interesting property is not that a token is created but that it WORKS and,
after revocation, stops working. A test that only counts rows would pass
against an endpoint that issued a token nothing accepts.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.users, pytest.mark.phase2]


def _path(user_id: Any) -> str:
    return f"/api/v1/users/{user_id}/api_tokens"


@pytest.fixture
def token_owner(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    """A throwaway user to hang tokens off, so no real account is touched."""
    suffix = uuid.uuid4().hex[:8]
    response = admin_client.post(
        "/api/v1/users",
        json={
            "user": {
                "email": f"phase2-token-owner-{suffix}@example.com",
                "first_name": "Token",
                "last_name": "Owner",
            }
        },
    )
    assert response.status_code in (200, 201), response.text
    user = response.json()["data"]
    try:
        yield user
    finally:
        admin_client.delete(f"/api/v1/users/{user['id']}")


class TestIssue:
    @pytest.mark.happy
    def test_issued_token_actually_authenticates(
        self, base_url: str, admin_client: httpx.Client, token_owner: dict[str, Any]
    ) -> None:
        """The issued plaintext must be a working credential.

        This is the assertion the endpoint exists for. Counting rows, or
        checking the response has a `token` key, would both pass against an
        endpoint handing back a string nothing accepts.
        """
        response = admin_client.post(
            _path(token_owner["id"]), json={"api_token": {"name": "contract-suite"}}
        )
        assert response.status_code == 201, response.text

        data = response.json()["data"]
        assert data["token"].startswith("sparc_"), data
        assert "cannot be retrieved again" in data["warning"]

        with httpx.Client(
            base_url=base_url,
            headers={"Authorization": f"Bearer {data['token']}"},
            verify=False,
            timeout=30.0,
        ) as issued:
            whoami = issued.get("/api/v1/available")
            assert whoami.status_code == 200, (
                f"the issued token was rejected: {whoami.status_code} {whoami.text[:200]}"
            )

    @pytest.mark.happy
    def test_the_plaintext_is_never_returned_again(
        self, admin_client: httpx.Client, token_owner: dict[str, Any]
    ) -> None:
        created = admin_client.post(
            _path(token_owner["id"]), json={"api_token": {"name": "write-once"}}
        )
        assert created.status_code == 201, created.text
        plaintext = created.json()["data"]["token"]

        listing = admin_client.get(_path(token_owner["id"]))
        assert listing.status_code == 200, listing.text
        assert plaintext not in listing.text, "the token plaintext was readable after creation"

    @pytest.mark.happy
    def test_expires_in_days_sets_an_expiry(
        self, admin_client: httpx.Client, token_owner: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            _path(token_owner["id"]),
            json={"api_token": {"name": "short-lived", "expires_in_days": 7}},
        )
        assert response.status_code == 201, response.text
        assert response.json()["data"]["expires_at"], response.text

        forever = admin_client.post(
            _path(token_owner["id"]), json={"api_token": {"name": "long-lived"}}
        )
        assert forever.status_code == 201, forever.text
        assert forever.json()["data"]["expires_at"] is None, forever.text

    @pytest.mark.validation
    def test_unrecognized_field_is_refused(
        self, admin_client: httpx.Client, token_owner: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            _path(token_owner["id"]),
            json={"api_token": {"name": "bad", "token_digest": "injected"}},
        )
        assert response.status_code == 422, response.text
        assert "token_digest" in " ".join(response.json()["details"])

    @pytest.mark.auth
    def test_no_token_returns_401(
        self, anon_client: httpx.Client, token_owner: dict[str, Any]
    ) -> None:
        assert_error_envelope(
            anon_client.post(_path(token_owner["id"]), json={"api_token": {"name": "x"}}),
            expected_status=401,
        )

    @pytest.mark.authz
    def test_non_admin_is_refused(
        self, user_client: httpx.Client, admin_client: httpx.Client,
        token_owner: dict[str, Any]
    ) -> None:
        before = admin_client.get(_path(token_owner["id"])).json()["data"]

        response = user_client.post(
            _path(token_owner["id"]), json={"api_token": {"name": "should-not-exist"}}
        )
        assert response.status_code in (401, 403), response.text

        after = admin_client.get(_path(token_owner["id"])).json()["data"]
        assert len(after) == len(before), "a refused request issued a token anyway"


class TestRevoke:
    @pytest.mark.happy
    def test_revoked_token_stops_authenticating(
        self, base_url: str, admin_client: httpx.Client, token_owner: dict[str, Any]
    ) -> None:
        """Revoked must mean revoked, not merely absent from a listing."""
        created = admin_client.post(
            _path(token_owner["id"]), json={"api_token": {"name": "doomed"}}
        )
        assert created.status_code == 201, created.text
        data = created.json()["data"]

        with httpx.Client(
            base_url=base_url,
            headers={"Authorization": f"Bearer {data['token']}"},
            verify=False,
            timeout=30.0,
        ) as issued:
            assert issued.get("/api/v1/available").status_code == 200

            revoked = admin_client.delete(f"{_path(token_owner['id'])}/{data['id']}")
            assert revoked.status_code == 200, revoked.text
            assert revoked.json()["data"]["revoked"] is True

            after = issued.get("/api/v1/available")
            assert after.status_code == 401, (
                f"a revoked token still authenticates: {after.status_code}"
            )

    @pytest.mark.authz
    def test_non_admin_cannot_revoke_and_the_token_survives(
        self, base_url: str, admin_client: httpx.Client, user_client: httpx.Client,
        token_owner: dict[str, Any]
    ) -> None:
        created = admin_client.post(
            _path(token_owner["id"]), json={"api_token": {"name": "survivor"}}
        )
        data = created.json()["data"]

        response = user_client.delete(f"{_path(token_owner['id'])}/{data['id']}")
        assert response.status_code in (401, 403), response.text

        with httpx.Client(
            base_url=base_url,
            headers={"Authorization": f"Bearer {data['token']}"},
            verify=False,
            timeout=30.0,
        ) as issued:
            assert issued.get("/api/v1/available").status_code == 200, (
                "a refused revocation revoked the token anyway"
            )
