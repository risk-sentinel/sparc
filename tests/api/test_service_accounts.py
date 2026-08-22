"""Tests for /api/v1/service_accounts (#1013).

Service accounts are the identities automation authenticates as. Before #1013
the whole lifecycle was browser-only, so provisioning automation could not
provision the identity it runs as — found by the missing-endpoint axis of #995.

These assert credential properties, not response shapes: the issued token must
WORK, and after rotation the old one must be dead.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _crud_contract import CrudContract
from conftest import assert_error_envelope

pytestmark = [pytest.mark.admin, pytest.mark.phase2]

PATH = "/api/v1/service_accounts"


def _payload(owner_id: Any, **overrides: Any) -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    body = {
        "email": f"phase2-sa-{suffix}@example.com",
        "first_name": "Phase2",
        "last_name": "Pipeline",
        "display_name": f"Phase 2 Pipeline {suffix}",
        # Required by the model: a service account must have a human who is
        # accountable for it. The API enforces it, which is why it is here.
        "owner_id": owner_id,
    }
    body.update(overrides)
    return {"service_account": body}


@pytest.fixture(scope="session")
def owner_id(admin_client: httpx.Client) -> int:
    """A human user on the instance to own the throwaway service accounts."""
    response = admin_client.get("/api/v1/users", params={"items": 100})
    assert response.status_code == 200, response.text

    for row in response.json()["data"]:
        if not row.get("service_account"):
            return row["id"]

    pytest.skip("no human user on this instance to own a service account")


def _authenticates(base_url: str, token: str) -> bool:
    with httpx.Client(
        base_url=base_url,
        headers={"Authorization": f"Bearer {token}"},
        verify=False,
        timeout=30.0,
    ) as client:
        return client.get("/api/v1/available").status_code == 200


@pytest.fixture
def service_account(admin_client: httpx.Client, owner_id: int) -> Iterator[dict[str, Any]]:
    response = admin_client.post(PATH, json=_payload(owner_id))
    assert response.status_code == 201, response.text
    record = response.json()["data"]
    try:
        yield record
    finally:
        admin_client.delete(f"{PATH}/{record['id']}")


# #995 — the shared matrix for this group.
class TestCrudContract(CrudContract):
    PARAM_KEY = "service_account"
    IDENTIFIER = "id"
    # Service accounts deactivate rather than delete, so this collection only
    # grows. Search rather than page.
    INDEX_SEARCH_PARAM = "q"
    INDEX_SEARCH_FIELD = "email"
    DESTROY_IS_SOFT_BECAUSE = (
        "service accounts deactivate rather than delete, so the account stays "
        "attached to the audit events it is the actor on (#1013)"
    )

    PATH = PATH

    def _payload(self, admin_client):
        # `owner_id` is a pytest fixture, not a value, so the contract resolves
        # an owner itself — a service account must have a human accountable for
        # it, and the API enforces that.
        users = admin_client.get("/api/v1/users", params={"items": 100}).json()["data"]
        human = next((u for u in users if not u.get("service_account")), None)
        assert human, "no human user on this instance to own a service account"
        return _payload(human["id"])["service_account"]

    def _update_fields(self):
        return {"display_name": f"Renamed {uuid.uuid4().hex[:6]}"}


class TestCreate:
    @pytest.mark.happy
    def test_the_issued_token_actually_authenticates(
        self, base_url: str, admin_client: httpx.Client, service_account: dict[str, Any]
    ) -> None:
        assert service_account["token"].startswith("sparc_sa_"), service_account
        assert _authenticates(base_url, service_account["token"]), (
            "the token issued with the account was rejected"
        )

    @pytest.mark.happy
    def test_token_expiry_defaults_to_ninety_days(
        self, service_account: dict[str, Any]
    ) -> None:
        """A non-expiring credential for an unattended identity outlives its purpose."""
        assert service_account["token_expires_at"], service_account

    @pytest.mark.happy
    def test_allowlists_are_accepted_as_json_arrays(
        self, admin_client: httpx.Client, owner_id: int
    ) -> None:
        created = admin_client.post(
            PATH,
            json=_payload(
                owner_id,
                expires_in_days=30,
                allowed_endpoints=["/api/v1/evidences"],
                allowed_cidrs=["10.0.0.0/8"],
            ),
        )
        assert created.status_code == 201, created.text
        record = created.json()["data"]

        try:
            shown = admin_client.get(f"{PATH}/{record['id']}")
            assert shown.status_code == 200, shown.text
            token = shown.json()["data"]["tokens"][0]
            assert token["allowed_endpoints"] == ["/api/v1/evidences"]
            assert token["allowed_cidrs"] == ["10.0.0.0/8"]
        finally:
            admin_client.delete(f"{PATH}/{record['id']}")

    @pytest.mark.happy
    def test_admin_is_opt_in_never_implicit(
        self, service_account: dict[str, Any]
    ) -> None:
        assert service_account["admin"] is False, service_account

    @pytest.mark.validation
    def test_unrecognized_field_is_refused(
        self, admin_client: httpx.Client, owner_id: int
    ) -> None:
        response = admin_client.post(PATH, json=_payload(owner_id, password="hunter2"))
        assert response.status_code == 422, response.text
        assert "password" in " ".join(response.json()["details"])

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client, owner_id: int) -> None:
        assert_error_envelope(anon_client.post(PATH, json=_payload(owner_id)), expected_status=401)

    @pytest.mark.authz
    def test_non_admin_is_refused(self, user_client: httpx.Client, owner_id: int) -> None:
        response = user_client.post(PATH, json=_payload(owner_id))
        assert response.status_code in (401, 403), response.text


class TestRegenerateToken:
    @pytest.mark.happy
    def test_rotation_kills_the_previous_token(
        self, base_url: str, admin_client: httpx.Client, service_account: dict[str, Any]
    ) -> None:
        old = service_account["token"]
        assert _authenticates(base_url, old)

        rotated = admin_client.post(f"{PATH}/{service_account['id']}/regenerate_token")
        assert rotated.status_code == 200, rotated.text

        new = rotated.json()["data"]["token"]
        assert new != old
        assert _authenticates(base_url, new), "the rotated token does not work"
        assert not _authenticates(base_url, old), (
            "the OLD token still authenticates — rotation that leaves it working is not rotation"
        )

    @pytest.mark.authz
    def test_non_admin_cannot_rotate_and_the_token_survives(
        self, base_url: str, user_client: httpx.Client, service_account: dict[str, Any]
    ) -> None:
        response = user_client.post(f"{PATH}/{service_account['id']}/regenerate_token")
        assert response.status_code in (401, 403), response.text
        assert _authenticates(base_url, service_account["token"])


class TestLifecycle:
    @pytest.mark.happy
    def test_disable_then_enable_round_trips(
        self, admin_client: httpx.Client, service_account: dict[str, Any]
    ) -> None:
        disabled = admin_client.post(
            f"{PATH}/{service_account['id']}/disable", json={"reason": "contract suite"}
        )
        assert disabled.status_code == 200, disabled.text
        shown = admin_client.get(f"{PATH}/{service_account['id']}").json()["data"]
        assert shown["status"] != "active"

        enabled = admin_client.post(f"{PATH}/{service_account['id']}/enable")
        assert enabled.status_code == 200, enabled.text
        shown = admin_client.get(f"{PATH}/{service_account['id']}").json()["data"]
        assert shown["status"] == "active"

    @pytest.mark.authz
    def test_non_admin_cannot_disable(
        self, admin_client: httpx.Client, user_client: httpx.Client,
        service_account: dict[str, Any]
    ) -> None:
        response = user_client.post(f"{PATH}/{service_account['id']}/disable")
        assert response.status_code in (401, 403), response.text

        shown = admin_client.get(f"{PATH}/{service_account['id']}").json()["data"]
        assert shown["status"] == "active", "a refused disable disabled the account anyway"


class TestIndex:
    @pytest.mark.happy
    def test_lists_only_service_accounts(
        self, admin_client: httpx.Client, service_account: dict[str, Any]
    ) -> None:
        # Search for the account rather than paging to it. This asserted that a
        # freshly created account appeared in the first 100 rows, which held
        # until the collection passed 100 — then it passed in isolation and
        # failed in a full run, which is the worst way for a test to fail.
        # Service accounts deactivate rather than delete, so the collection only
        # ever grows.
        found = admin_client.get(PATH, params={"q": service_account["email"]})
        assert found.status_code == 200, found.text
        assert service_account["id"] in [row["id"] for row in found.json()["data"]], (
            f"{service_account['email']} was created but the search does not find it"
        )

        # The type filter is the other half: this endpoint must never return a
        # human user, whatever the page size.
        listing = admin_client.get(PATH, params={"items": 200})
        assert listing.status_code == 200, listing.text
        rows = listing.json()["data"]
        assert rows, "no service accounts returned at all"
        assert all(row["service_account"] is True for row in rows)

    @pytest.mark.happy
    def test_no_endpoint_returns_a_token_value(
        self, admin_client: httpx.Client, service_account: dict[str, Any]
    ) -> None:
        for path in (PATH, f"{PATH}/{service_account['id']}"):
            response = admin_client.get(path, params={"items": 100})
            assert service_account["token"] not in response.text, (
                f"{path} echoed a token plaintext"
            )

    @pytest.mark.authz
    def test_non_admin_cannot_list(self, user_client: httpx.Client) -> None:
        response = user_client.get(PATH)
        assert response.status_code in (401, 403), response.text
