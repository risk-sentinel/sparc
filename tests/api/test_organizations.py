"""Tests for /api/v1/organizations (#1012).

Organizations scope boundaries and documents, and membership decides who can
see what. Before #1012 creating one, assigning a boundary and managing
membership were browser-only — found by the missing-endpoint axis of #995.
"""

# api-inventory: covers organizations#add_member
# api-inventory: covers organizations#remove_member

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _crud_contract import CrudContract
from conftest import assert_error_envelope

pytestmark = [pytest.mark.admin, pytest.mark.phase2]

PATH = "/api/v1/organizations"


def _payload(**overrides: Any) -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    body = {
        "name": f"phase2-org-{suffix}",
        "description": "Created by the API contract suite.",
        "contact_person": "Contract Suite",
        "contact_email": f"phase2-{suffix}@example.gov",
    }
    body.update(overrides)
    return {"organization": body}


@pytest.fixture
def organization(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(PATH, json=_payload())
    assert response.status_code == 201, response.text
    record = response.json()["data"]
    try:
        yield record
    finally:
        # No DELETE by design — deactivation is the terminal state.
        admin_client.post(f"{PATH}/{record['id']}/deactivate")


# #995 — the shared matrix for this group.
class TestCrudContract(CrudContract):
    PATH = PATH
    PARAM_KEY = "organization"
    IDENTIFIER = "id"
    # The collection has passed MAX_PAGINATION_LIMIT, so paging can no longer
    # reach a new record. Organizations support ?q=.
    INDEX_SEARCH_PARAM = "q"
    NO_DESTROY_ROUTE_BECAUSE = (
        "organizations are never hard-deleted (#1012): deactivate/reactivate "
        "preserve the UUID so a boundary that referenced one still resolves"
    )

    def _payload(self, admin_client):
        return _payload()["organization"]

    def _update_fields(self):
        return {"description": f"updated {uuid.uuid4().hex[:8]}"}

    def _destroy(self, client, record):
        # There is no destroy route, so the default DELETE would 404 and leave
        # the record behind forever. Deactivating is the terminal state this
        # resource actually offers.
        client.post(f"{PATH}/{record['id']}/deactivate")


class TestCreate:
    @pytest.mark.happy
    def test_create_persists_and_reads_back(
        self, admin_client: httpx.Client, organization: dict[str, Any]
    ) -> None:
        shown = admin_client.get(f"{PATH}/{organization['id']}")
        assert shown.status_code == 200, shown.text

        data = shown.json()["data"]
        assert data["name"] == organization["name"]
        assert data["contact_person"] == "Contract Suite"
        assert data["active"] is True

    @pytest.mark.validation
    def test_unrecognized_field_is_refused(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json=_payload(status="active"))
        assert response.status_code == 422, response.text
        assert "status" in " ".join(response.json()["details"])

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.post(PATH, json=_payload()), expected_status=401)

    @pytest.mark.authz
    def test_non_admin_is_refused(self, user_client: httpx.Client) -> None:
        response = user_client.post(PATH, json=_payload())
        assert response.status_code in (401, 403), response.text


class TestLifecycle:
    @pytest.mark.happy
    def test_deactivate_then_reactivate_and_the_record_survives(
        self, admin_client: httpx.Client, organization: dict[str, Any]
    ) -> None:
        deactivated = admin_client.post(f"{PATH}/{organization['id']}/deactivate")
        assert deactivated.status_code == 200, deactivated.text
        assert admin_client.get(f"{PATH}/{organization['id']}").json()["data"]["active"] is False

        reactivated = admin_client.post(f"{PATH}/{organization['id']}/reactivate")
        assert reactivated.status_code == 200, reactivated.text

        shown = admin_client.get(f"{PATH}/{organization['id']}")
        assert shown.status_code == 200, "the organization was deleted rather than deactivated"
        assert shown.json()["data"]["active"] is True

    @pytest.mark.authz
    def test_non_admin_cannot_deactivate(
        self, admin_client: httpx.Client, user_client: httpx.Client,
        organization: dict[str, Any]
    ) -> None:
        response = user_client.post(f"{PATH}/{organization['id']}/deactivate")
        assert response.status_code in (401, 403), response.text
        assert admin_client.get(f"{PATH}/{organization['id']}").json()["data"]["active"] is True


class TestMembership:
    @pytest.mark.happy
    def test_add_then_remove_a_member(
        self, admin_client: httpx.Client, organization: dict[str, Any]
    ) -> None:
        users = admin_client.get("/api/v1/users", params={"items": 100}).json()["data"]
        candidate = next((u for u in users if not u.get("service_account")), None)
        if candidate is None:
            pytest.skip("no human user on this instance to add as a member")

        added = admin_client.post(
            f"{PATH}/{organization['id']}/members",
            json={"user_id": candidate["id"], "role": "org_admin"},
        )
        assert added.status_code == 201, added.text
        membership_id = added.json()["data"]["id"]

        roster = admin_client.get(f"{PATH}/{organization['id']}/members")
        assert roster.status_code == 200, roster.text
        assert membership_id in [row["id"] for row in roster.json()["data"]]

        removed = admin_client.delete(
            f"{PATH}/{organization['id']}/members/{membership_id}"
        )
        assert removed.status_code == 200, removed.text

        after = admin_client.get(f"{PATH}/{organization['id']}/members").json()["data"]
        assert membership_id not in [row["id"] for row in after], (
            "the member was removed but still appears in the roster"
        )

    @pytest.mark.validation
    def test_role_outside_the_configured_set_is_refused(
        self, admin_client: httpx.Client, organization: dict[str, Any]
    ) -> None:
        users = admin_client.get("/api/v1/users", params={"items": 100}).json()["data"]
        candidate = next((u for u in users if not u.get("service_account")), None)
        if candidate is None:
            pytest.skip("no human user on this instance to add as a member")

        response = admin_client.post(
            f"{PATH}/{organization['id']}/members",
            json={"user_id": candidate["id"], "role": "supreme_overlord"},
        )
        assert response.status_code == 422, response.text

        roster = admin_client.get(f"{PATH}/{organization['id']}/members").json()["data"]
        assert roster == [], "a refused role added a member anyway"

    @pytest.mark.authz
    def test_non_admin_cannot_read_the_roster(
        self, user_client: httpx.Client, organization: dict[str, Any]
    ) -> None:
        response = user_client.get(f"{PATH}/{organization['id']}/members")
        assert response.status_code in (401, 403), response.text


class TestIndex:
    @pytest.mark.pagination
    def test_search_narrows_truthfully(
        self, admin_client: httpx.Client, organization: dict[str, Any]
    ) -> None:
        """A search that returns everything is worse than no search."""
        response = admin_client.get(PATH, params={"q": organization["name"], "items": 100})
        assert response.status_code == 200, response.text

        rows = response.json()["data"]
        assert organization["id"] in [row["id"] for row in rows]

        unfiltered = admin_client.get(PATH, params={"items": 200}).json()["data"]
        assert len(rows) <= len(unfiltered)
        assert all(
            organization["name"].lower() in (row["name"] or "").lower() for row in rows
        ), "the search returned rows that do not match the term"

    @pytest.mark.authz
    def test_non_admin_cannot_list(self, user_client: httpx.Client) -> None:
        response = user_client.get(PATH)
        assert response.status_code in (401, 403), response.text
