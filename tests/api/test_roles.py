"""Tests for /api/v1/roles (#1014).

Roles carry the permission sets every authorization check reads. Before #1014
they were editable only in a browser, so an instance's RBAC configuration could
not be reviewed or reproduced programmatically — found by the missing-endpoint
axis of #995.

What matters here is what a role GRANTS after a write, not that the response
echoed the request back.
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

PATH = "/api/v1/roles"


def _payload(**overrides: Any) -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    body = {
        "name": f"phase2_role_{suffix}",
        "display_name": f"Phase 2 Role {suffix}",
        "scope": "authorization_boundary",
        "description": "Created by the API contract suite.",
        "sort_order": 99,
    }
    body.update(overrides)
    return {"role": body}


@pytest.fixture
def role(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(PATH, json=_payload())
    assert response.status_code == 201, response.text
    record = response.json()["data"]
    try:
        yield record
    finally:
        admin_client.delete(f"{PATH}/{record['id']}")


# #995 — the shared matrix for this group.
class TestCrudContract(CrudContract):
    PATH = PATH
    PARAM_KEY = "role"
    IDENTIFIER = "id"

    def _payload(self, admin_client):
        return _payload()["role"]

    def _update_fields(self):
        return {"display_name": f"Renamed {uuid.uuid4().hex[:6]}"}


class TestCreate:
    @pytest.mark.happy
    def test_create_grants_exactly_what_was_asked_for(
        self, admin_client: httpx.Client
    ) -> None:
        body = _payload()
        body["role"]["permissions"] = {"catalogs.read": True, "catalogs.write": False}

        created = admin_client.post(PATH, json=body)
        assert created.status_code == 201, created.text
        record = created.json()["data"]

        try:
            # Independent read, not the write's echo.
            shown = admin_client.get(f"{PATH}/{record['id']}")
            assert shown.status_code == 200, shown.text

            granted = shown.json()["data"]["permissions"]
            assert granted == ["catalogs.read"], granted
        finally:
            admin_client.delete(f"{PATH}/{record['id']}")

    @pytest.mark.happy
    def test_a_key_the_application_does_not_enforce_cannot_be_written(
        self, admin_client: httpx.Client
    ) -> None:
        body = _payload()
        body["role"]["permissions"] = {"catalogs.read": True, "invented.superpower": True}

        created = admin_client.post(PATH, json=body)
        assert created.status_code == 201, created.text
        record = created.json()["data"]

        try:
            shown = admin_client.get(f"{PATH}/{record['id']}").json()["data"]
            assert "invented.superpower" not in shown["permissions"]
            assert "invented.superpower" not in shown["available_permissions"]
        finally:
            admin_client.delete(f"{PATH}/{record['id']}")

    @pytest.mark.validation
    def test_invalid_scope_is_refused(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json=_payload(scope="galaxy"))
        assert response.status_code == 422, response.text

    @pytest.mark.validation
    def test_unrecognized_field_is_refused(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json=_payload(id=999999))
        assert response.status_code == 422, response.text
        assert "id" in " ".join(response.json()["details"])

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.post(PATH, json=_payload()), expected_status=401)

    @pytest.mark.authz
    def test_non_admin_is_refused_and_creates_nothing(
        self, admin_client: httpx.Client, user_client: httpx.Client
    ) -> None:
        before = admin_client.get(PATH, params={"items": 200}).json()["meta"]["count"]

        response = user_client.post(PATH, json=_payload())
        assert response.status_code in (401, 403), response.text

        after = admin_client.get(PATH, params={"items": 200}).json()["meta"]["count"]
        assert after == before, "a refused request created a role anyway"


class TestUpdate:
    @pytest.mark.happy
    def test_permissions_are_replaced_so_an_omitted_key_is_revoked(
        self, admin_client: httpx.Client, role: dict[str, Any]
    ) -> None:
        grant = admin_client.patch(
            f"{PATH}/{role['id']}",
            json={"role": {"permissions": {"catalogs.read": True, "catalogs.write": True}}},
        )
        assert grant.status_code == 200, grant.text
        assert set(admin_client.get(f"{PATH}/{role['id']}").json()["data"]["permissions"]) == {
            "catalogs.read",
            "catalogs.write",
        }

        narrow = admin_client.patch(
            f"{PATH}/{role['id']}", json={"role": {"permissions": {"catalogs.read": True}}}
        )
        assert narrow.status_code == 200, narrow.text

        after = admin_client.get(f"{PATH}/{role['id']}").json()["data"]["permissions"]
        assert after == ["catalogs.read"], (
            f"omitting a key must revoke it; still granted: {after}"
        )

    @pytest.mark.happy
    def test_permissions_survive_an_update_that_does_not_mention_them(
        self, admin_client: httpx.Client, role: dict[str, Any]
    ) -> None:
        admin_client.patch(
            f"{PATH}/{role['id']}", json={"role": {"permissions": {"catalogs.write": True}}}
        )

        renamed = admin_client.patch(
            f"{PATH}/{role['id']}", json={"role": {"display_name": "Renamed by suite"}}
        )
        assert renamed.status_code == 200, renamed.text

        shown = admin_client.get(f"{PATH}/{role['id']}").json()["data"]
        assert shown["display_name"] == "Renamed by suite"
        assert shown["permissions"] == ["catalogs.write"]

    @pytest.mark.authz
    def test_non_admin_cannot_update(
        self, admin_client: httpx.Client, user_client: httpx.Client, role: dict[str, Any]
    ) -> None:
        response = user_client.patch(
            f"{PATH}/{role['id']}", json={"role": {"display_name": "Hijacked"}}
        )
        assert response.status_code in (401, 403), response.text

        shown = admin_client.get(f"{PATH}/{role['id']}").json()["data"]
        assert shown["display_name"] != "Hijacked"


class TestIndex:
    @pytest.mark.pagination
    def test_scope_filter_narrows_truthfully(self, admin_client: httpx.Client) -> None:
        """A filter that returns everything is worse than no filter."""
        response = admin_client.get(PATH, params={"scope": "instance", "items": 200})
        assert response.status_code == 200, response.text

        rows = response.json()["data"]
        assert rows, "no instance-scoped roles at all — the filter cannot be verified"
        assert all(row["scope"] == "instance" for row in rows), (
            "the scope filter returned rows outside the requested scope"
        )

        unfiltered = admin_client.get(PATH, params={"items": 200}).json()["data"]
        assert len(unfiltered) > len(rows), "the filter did not narrow the set at all"

    @pytest.mark.authz
    def test_non_admin_cannot_list(self, user_client: httpx.Client) -> None:
        response = user_client.get(PATH)
        assert response.status_code in (401, 403), response.text


class TestDestroy:
    @pytest.mark.happy
    def test_delete_removes_it(self, admin_client: httpx.Client) -> None:
        created = admin_client.post(PATH, json=_payload())
        record = created.json()["data"]

        deleted = admin_client.delete(f"{PATH}/{record['id']}")
        assert deleted.status_code == 200, deleted.text
        assert admin_client.get(f"{PATH}/{record['id']}").status_code == 404

    @pytest.mark.authz
    def test_non_admin_cannot_delete_and_the_role_survives(
        self, admin_client: httpx.Client, user_client: httpx.Client, role: dict[str, Any]
    ) -> None:
        response = user_client.delete(f"{PATH}/{role['id']}")
        assert response.status_code in (401, 403), response.text
        assert admin_client.get(f"{PATH}/{role['id']}").status_code == 200
