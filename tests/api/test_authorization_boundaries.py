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


class TestSort:
    """#1248 — ?sort=next_decision|-next_decision, the boundary list's sort.

    Dates are ISO strings, so order by the date; boundaries with no date come
    last in BOTH directions. An unknown sort is refused, not ignored.
    """

    def _with_dates(self, admin_client: httpx.Client) -> list[dict[str, Any]]:
        tag = uuid.uuid4().hex[:8]
        made = []
        for label, date in (("b", "2031-06-01"), ("a", "2030-01-15"), ("c", None)):
            body = _new_payload(name=f"phase2-sort-{tag}-{label}")
            if date:
                body["authorization_boundary"]["next_decision_date"] = date
            response = admin_client.post(PATH, json=body)
            assert response.status_code == 201, response.text
            made.append(response.json()["data"])
        return made

    def _names(self, admin_client: httpx.Client, sort: str, tag_prefix: str) -> list[str]:
        response = admin_client.get(PATH, params={"sort": sort, "q": tag_prefix, "items": 200})
        assert response.status_code == 200, response.text
        rows = response.json()["data"]
        return [row["name"] for row in rows if row["name"].startswith(tag_prefix)]

    @pytest.mark.happy
    def test_next_decision_both_directions_with_empty_dates_last(
        self, admin_client: httpx.Client
    ) -> None:
        made = self._with_dates(admin_client)
        prefix = made[0]["name"].rsplit("-", 1)[0]
        try:
            ascending = self._names(admin_client, "next_decision", prefix)
            descending = self._names(admin_client, "-next_decision", prefix)
            assert [n[-1] for n in ascending] == ["a", "b", "c"], ascending
            assert [n[-1] for n in descending] == ["b", "a", "c"], descending
        finally:
            for record in made:
                _delete(admin_client, record["id"])

    @pytest.mark.validation
    def test_unknown_sort_is_refused(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH, params={"sort": "name; drop table users"})
        assert response.status_code == 422, response.text
        assert "next_decision" in " ".join(response.json()["details"])


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
        created = response.json()["data"]
        try:
            yield created
        finally:
            # Organizations are never hard-deleted — deactivate preserves the
            # UUID for audit traceability — but an org left ACTIVE is a row the
            # sidebar renders forever. Without this each run leaked one per test.
            admin_client.post(f"/api/v1/organizations/{created['id']}/deactivate")

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


class TestOrganizationLink:
    """#1178 — every boundary row carries its organization's id AND uuid.

    Without them a client (sparc-horizon) cannot build the organization ->
    boundary tree from the API alone. Both list and detail carry the fields,
    and both carry explicit nulls for an unassigned boundary: a key that is
    absent and a key that is null are different contracts.
    """

    @pytest.fixture
    def organization(self, admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
        suffix = uuid.uuid4().hex[:8]
        response = admin_client.post(
            "/api/v1/organizations", json={"organization": {"name": f"phase2-1178-org-{suffix}"}}
        )
        assert response.status_code == 201, response.text
        created = response.json()["data"]
        try:
            yield created
        finally:
            admin_client.post(f"/api/v1/organizations/{created['id']}/deactivate")

    def _row(self, admin_client: httpx.Client, boundary: dict[str, Any]) -> dict[str, Any]:
        response = admin_client.get(PATH, params={"name": boundary["name"]})
        assert response.status_code == 200, response.text
        rows = [r for r in response.json()["data"] if r["id"] == boundary["id"]]
        assert len(rows) == 1, response.text
        return rows[0]

    def _detail(self, admin_client: httpx.Client, boundary: dict[str, Any]) -> dict[str, Any]:
        response = admin_client.get(f"{PATH}/{boundary['id']}")
        assert response.status_code == 200, response.text
        return response.json()["data"]

    @pytest.mark.happy
    def test_unassigned_boundary_carries_explicit_nulls(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        for body in (self._row(admin_client, boundary), self._detail(admin_client, boundary)):
            assert "organization_id" in body and body["organization_id"] is None, body
            assert "organization_uuid" in body and body["organization_uuid"] is None, body

    @pytest.mark.happy
    def test_assigned_boundary_carries_the_organization_uuid_on_list_and_detail(
        self, admin_client: httpx.Client, boundary: dict[str, Any], organization: dict[str, Any]
    ) -> None:
        response = admin_client.patch(
            f"{PATH}/{boundary['id']}/organization", json={"organization_id": organization["id"]}
        )
        assert response.status_code == 200, response.text

        for body in (self._row(admin_client, boundary), self._detail(admin_client, boundary)):
            assert body["organization_id"] == organization["id"], body
            assert body["organization_uuid"] == organization["uuid"], body
            assert body["organization_uuid"], body
