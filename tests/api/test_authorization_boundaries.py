"""Tests for /api/v1/authorization_boundaries.

5 logical endpoints — CRUD. Authorization boundaries are the parent
container for SSPs, SARs, SAPs, POAMs, and KSI validations; tests
own their boundaries and clean up on teardown so no orphaned
boundaries leak between runs.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _bulk_destroy import BulkDestroyContract
from _crud_contract import CrudContract
from conftest import assert_error_envelope, assert_paginated_envelope
from schemas import assert_update_round_trip

pytestmark = [pytest.mark.boundaries, pytest.mark.phase1]


PATH = "/api/v1/authorization_boundaries"


def _new_payload(**overrides: Any) -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    body = {
        "name": f"phase2-boundary-{suffix}",
        "description": "Created by Phase 2 pytest suite",
    }
    body.update(overrides)
    return {"authorization_boundary": body}


def _create(client: httpx.Client) -> dict[str, Any]:
    response = client.post(PATH, json=_new_payload())
    assert response.status_code in (200, 201), response.text
    return response.json().get("data") or response.json()


def _delete(client: httpx.Client, boundary_id: int) -> None:
    response = client.delete(f"{PATH}/{boundary_id}")
    assert response.status_code in (200, 204, 404), response.text


@pytest.fixture
def boundary(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    b = _create(admin_client)
    try:
        yield b
    finally:
        _delete(admin_client, b["id"])


# #995 — the shared matrix for this group.
class TestCrudContract(CrudContract):
    PATH = PATH
    PARAM_KEY = "authorization_boundary"
    IDENTIFIER = "id"

    def _payload(self, admin_client):
        return _new_payload()["authorization_boundary"]


class TestBulkDestroy(BulkDestroyContract):
    """Admin-only bulk delete (#629). Contract lives in _bulk_destroy."""

    PATH = PATH

    def _create_id(self, admin_client: httpx.Client) -> int:
        return _create(admin_client)["id"]


class TestIndex:
    @pytest.mark.happy
    def test_admin_lists_boundaries(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH)
        assert response.status_code == 200, response.text
        body = response.json()
        if "data" in body:
            assert_paginated_envelope(body)
        else:
            assert isinstance(body, dict) or isinstance(body, list)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(PATH), expected_status=401)


class TestShow:
    @pytest.mark.happy
    def test_admin_shows_boundary(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{boundary['id']}")
        assert response.status_code == 200
        body = response.json().get("data", response.json())
        assert body["id"] == boundary["id"]

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(f"{PATH}/0"), expected_status=401)

    def test_unknown_id_returns_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/99999999")
        assert_error_envelope(response, expected_status=404)


class TestCreate:
    @pytest.mark.happy
    def test_admin_creates_boundary(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json=_new_payload())
        assert response.status_code in (200, 201)
        b = response.json().get("data") or response.json()
        _delete(admin_client, b["id"])

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.post(PATH, json=_new_payload()), expected_status=401)

    @pytest.mark.authz
    def test_non_admin_returns_403(self, user_client: httpx.Client) -> None:
        response = user_client.post(PATH, json=_new_payload())
        assert response.status_code in (401, 403)

    @pytest.mark.validation
    def test_missing_name_returns_422(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(
            PATH, json={"authorization_boundary": {"description": "no name"}}
        )
        assert_error_envelope(response, expected_status=422)


class TestUpdate:
    @pytest.mark.happy
    def test_admin_updates_boundary(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        """The PATCH persists, confirmed by an independent read.

        This asserted only a status code until #995 — it would have passed
        against an endpoint that discarded the payload entirely, which is
        exactly what #994 did.
        """
        assert_update_round_trip(
            admin_client,
            PATH,
            boundary["id"],
            {"description": f"updated {uuid.uuid4().hex[:6]}"},
            "authorization_boundary",
            restore=False,  # the fixture owns this boundary and deletes it
        )

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.patch(f"{PATH}/0", json={}), expected_status=401)


class TestDestroy:
    @pytest.mark.happy
    def test_admin_destroys_boundary(self, admin_client: httpx.Client) -> None:
        b = _create(admin_client)
        response = admin_client.delete(f"{PATH}/{b['id']}")
        assert response.status_code in (200, 204)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.delete(f"{PATH}/0"), expected_status=401)


# api-inventory: covers authorization_boundaries#assign_organization
class TestAssignOrganization:
    """`PATCH /authorization_boundaries/:id/organization` — the boundary side.

    Every check reads the result back through a separate GET. The write's own
    body cannot serve: `assign_organization` serialises the NON-detailed shape,
    and `organization` only appears in the detailed one, so the response to the
    call that sets the organization does not mention the organization. That is
    an omission rather than a wrong answer, but it means the write's echo is not
    evidence — which is the #995 rule anyway.
    """

    @pytest.fixture
    def organization(self, admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
        suffix = uuid.uuid4().hex[:8]
        response = admin_client.post(
            "/api/v1/organizations", json={"organization": {"name": f"phase2-bnd-org-{suffix}"}}
        )
        assert response.status_code == 201, response.text
        yield response.json()["data"]

    def _organization_of(self, admin_client: httpx.Client, boundary_id: int):
        response = admin_client.get(f"{PATH}/{boundary_id}")
        assert response.status_code == 200, response.text
        return response.json()["data"].get("organization")

    @pytest.mark.happy
    def test_assigning_is_confirmed_by_an_independent_read(
        self, admin_client: httpx.Client, boundary: dict[str, Any], organization: dict[str, Any]
    ) -> None:
        response = admin_client.patch(
            f"{PATH}/{boundary['id']}/organization", json={"organization_id": organization["id"]}
        )

        assert response.status_code == 200, response.text
        assert self._organization_of(admin_client, boundary["id"]) == organization["name"]

    @pytest.mark.happy
    def test_clearing_the_organization_is_confirmed_by_an_independent_read(
        self, admin_client: httpx.Client, boundary: dict[str, Any], organization: dict[str, Any]
    ) -> None:
        """Both directions. Only asserting the assignment would pass against an
        endpoint that could assign and never unassign."""
        admin_client.patch(
            f"{PATH}/{boundary['id']}/organization", json={"organization_id": organization["id"]}
        )
        assert self._organization_of(admin_client, boundary["id"]) == organization["name"]

        response = admin_client.patch(
            f"{PATH}/{boundary['id']}/organization", json={"organization_id": None}
        )

        assert response.status_code == 200, response.text
        assert self._organization_of(admin_client, boundary["id"]) is None, (
            "the boundary still belongs to an organization after being cleared"
        )

    @pytest.mark.validation
    def test_an_unknown_organization_is_refused_and_nothing_changes(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.patch(
            f"{PATH}/{boundary['id']}/organization", json={"organization_id": 999_999_999}
        )

        assert response.status_code == 404, response.text
        assert self._organization_of(admin_client, boundary["id"]) is None

    @pytest.mark.authz
    def test_a_non_admin_cannot_assign_and_nothing_changes(
        self,
        admin_client: httpx.Client,
        user_client: httpx.Client,
        boundary: dict[str, Any],
        organization: dict[str, Any],
    ) -> None:
        response = user_client.patch(
            f"{PATH}/{boundary['id']}/organization", json={"organization_id": organization["id"]}
        )

        # Exactly 403, measured. Accepting "403 or 404" would not distinguish a
        # permission gate from a boundary the caller simply cannot see.
        assert_error_envelope(response, expected_status=403)
        assert self._organization_of(admin_client, boundary["id"]) is None, (
            "a refused caller still assigned the boundary to an organization"
        )

    @pytest.mark.auth
    def test_an_anonymous_caller_is_refused(
        self, anon_client: httpx.Client, boundary: dict[str, Any], organization: dict[str, Any]
    ) -> None:
        response = anon_client.patch(
            f"{PATH}/{boundary['id']}/organization", json={"organization_id": organization["id"]}
        )

        assert response.status_code == 401, response.text
