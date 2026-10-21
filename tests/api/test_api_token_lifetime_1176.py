"""Tests for API token lifetime, renewal and per-resource limits (#1176).

Against the running instance:

- a service account's token must expire (a person's may still be "Never");
- Regenerate keeps the limits instead of widening the token;
- a token limited to one resource's Read can read it, cannot write it, and
  cannot reach another resource;
- one team mailbox may own several service accounts (owner, option A).

Renew and reissue are in test_api_tokens.py and the endpoint catalog in
test_api_endpoints.py, the modules the API inventory reads for those routes.

As with the other token tests, the property asserted is what the token DOES
(authenticates, is refused) rather than what the response says about it.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

pytestmark = [pytest.mark.admin, pytest.mark.phase2]

SA_PATH = "/api/v1/service_accounts"
GATE_REFUSAL = "Token is not authorized for this endpoint"


def _client(base_url: str, token: str) -> httpx.Client:
    return httpx.Client(
        base_url=base_url,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        verify=False,
        timeout=30.0,
    )


def _authenticates(base_url: str, token: str) -> bool:
    with _client(base_url, token) as client:
        return client.get("/api/v1/available").status_code == 200


@pytest.fixture(scope="module")
def owner_id(admin_client: httpx.Client) -> int:
    response = admin_client.get("/api/v1/users", params={"items": 100})
    assert response.status_code == 200, response.text
    for row in response.json()["data"]:
        if not row.get("service_account"):
            return row["id"]
    pytest.skip("no human user on this instance to own a service account")


def _create_account(admin_client: httpx.Client, owner_id: int, **fields: Any) -> httpx.Response:
    suffix = uuid.uuid4().hex[:8]
    body = {
        "email": f"phase2-sa-{suffix}@example.com",
        "display_name": f"Phase 2 #1176 {suffix}",
        "owner_id": owner_id,
    }
    body.update(fields)
    return admin_client.post(SA_PATH, json={"service_account": body})


@pytest.fixture
def accounts(admin_client: httpx.Client) -> Iterator[list[int]]:
    """Ids of service accounts a test created; deactivated afterwards."""
    created: list[int] = []
    try:
        yield created
    finally:
        for account_id in created:
            admin_client.delete(f"{SA_PATH}/{account_id}")


class TestLifetime:
    @pytest.mark.validation
    def test_a_service_account_token_must_expire(
        self, admin_client: httpx.Client, owner_id: int, accounts: list[int]
    ) -> None:
        email = f"phase2-never-{uuid.uuid4().hex[:8]}@example.com"
        response = _create_account(admin_client, owner_id, email=email, expires_in_days=0)

        assert response.status_code == 422, response.text
        assert "required for a service account's token" in " ".join(response.json()["details"])
        # The account is not left behind without its credential.
        listed = admin_client.get(SA_PATH, params={"q": email}).json()["data"]
        assert listed == [], f"a refused token must not leave an account: {listed}"

    @pytest.mark.happy
    def test_a_person_may_still_hold_a_never_expiring_token(
        self, admin_client: httpx.Client
    ) -> None:
        suffix = uuid.uuid4().hex[:8]
        person = admin_client.post(
            "/api/v1/users",
            json={"user": {"email": f"phase2-1176-{suffix}@example.com",
                           "first_name": "Never", "last_name": "Expires"}},
        )
        assert person.status_code in (200, 201), person.text
        person_id = person.json()["data"]["id"]
        try:
            issued = admin_client.post(
                f"/api/v1/users/{person_id}/api_tokens",
                json={"api_token": {"name": "forever", "expires_in_days": 0}},
            )
            assert issued.status_code == 201, issued.text
            assert issued.json()["data"]["never_expires"] is True
        finally:
            admin_client.delete(f"/api/v1/users/{person_id}")


class TestTeamMailbox:
    @pytest.mark.happy
    def test_one_mailbox_owns_two_accounts(
        self, admin_client: httpx.Client, owner_id: int, accounts: list[int]
    ) -> None:
        email = f"phase2-team-{uuid.uuid4().hex[:8]}@example.com"
        for _ in range(2):
            response = _create_account(admin_client, owner_id, email=email)
            assert response.status_code == 201, response.text
            accounts.append(response.json()["data"]["id"])

        listed = admin_client.get(SA_PATH, params={"q": email}).json()["data"]
        assert len(listed) == 2, listed


class TestReadWriteLimits:
    @pytest.mark.authz
    def test_a_read_limit_reads_and_does_not_write(
        self, base_url: str, admin_client: httpx.Client, owner_id: int, accounts: list[int]
    ) -> None:
        response = _create_account(admin_client, owner_id, allowed_endpoints=["ssp_documents:read"])
        assert response.status_code == 201, response.text
        data = response.json()["data"]
        accounts.append(data["id"])

        with _client(base_url, data["token"]) as limited:
            read = limited.get("/api/v1/ssp_documents")
            assert read.status_code == 200, read.text

            # Refused at the token gate, before the body is even read.
            write = limited.post("/api/v1/ssp_documents", json={})
            assert write.status_code == 403, write.text
            assert write.json()["error"] == GATE_REFUSAL

            other = limited.get("/api/v1/sar_documents")
            assert other.status_code == 403, other.text
            assert other.json()["error"] == GATE_REFUSAL

    @pytest.mark.validation
    def test_an_entry_naming_nothing_is_refused(
        self, admin_client: httpx.Client, owner_id: int, accounts: list[int]
    ) -> None:
        response = _create_account(admin_client, owner_id, allowed_endpoints=["no_such_group:read"])

        assert response.status_code == 422, response.text
        assert "not an API resource group" in " ".join(response.json()["details"])


class TestRegenerate:
    def _account(self, admin_client, owner_id, accounts) -> dict[str, Any]:
        response = _create_account(
            admin_client, owner_id, expires_in_days=30,
            allowed_endpoints=["available:read"], allowed_cidrs=["0.0.0.0/0"],
        )
        assert response.status_code == 201, response.text
        data = response.json()["data"]
        accounts.append(data["id"])
        return data

    @pytest.mark.happy
    def test_regenerate_does_not_widen_the_token(
        self, admin_client: httpx.Client, owner_id: int, accounts: list[int]
    ) -> None:
        account = self._account(admin_client, owner_id, accounts)

        response = admin_client.post(f"{SA_PATH}/{account['id']}/regenerate_token")
        assert response.status_code == 200, response.text

        tokens = response.json()["data"]["tokens"]
        assert len(tokens) == 1, tokens
        assert tokens[0]["allowed_endpoints"] == ["available:read"]
        assert tokens[0]["allowed_cidrs"] == ["0.0.0.0/0"]
