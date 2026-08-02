"""Tests for /api/v1/authorization_boundaries/:id/memberships (#875).

The boundary personnel roster was the one mutation SPARC offered exclusively
through the UI — nothing automated could provision the people on an ATO
package. These cover the CRUD surface plus the `roles` endpoint, which reports
the configured role vocabulary so a client does not have to hardcode the seven
built-ins (they are configurable via SPARC_AUTH_BOUNDARY_ROLES).

The role assertions are deliberately written against whatever THIS instance
offers rather than a fixed list: the point of #875 is that the vocabulary is
configurable, so a test that hardcoded it would pass only on a default
deployment and fail on exactly the configured ones that used to 500.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope, assert_paginated_envelope

pytestmark = [pytest.mark.boundaries, pytest.mark.phase2]

BOUNDARIES = "/api/v1/authorization_boundaries"


def _boundary_payload() -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    return {
        "authorization_boundary": {
            "name": f"phase2-membership-ab-{suffix}",
            "description": "Created by the #875 membership suite",
        }
    }


@pytest.fixture
def boundary(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(BOUNDARIES, json=_boundary_payload())
    assert response.status_code in (200, 201), response.text
    b = response.json().get("data") or response.json()
    try:
        yield b
    finally:
        admin_client.delete(f"{BOUNDARIES}/{b['id']}")


def _path(boundary: dict[str, Any]) -> str:
    return f"{BOUNDARIES}/{boundary['id']}/memberships"


def _available_roles(client: httpx.Client, boundary: dict[str, Any]) -> list[dict[str, str]]:
    response = client.get(f"{_path(boundary)}/roles")
    assert response.status_code == 200, response.text
    return response.json()["data"]["available"]


def _create(
    client: httpx.Client, boundary: dict[str, Any], **overrides: Any
) -> dict[str, Any]:
    body = {
        "user_name": f"Contract Person {uuid.uuid4().hex[:6]}",
        "user_email": "contract@example.gov",
        "role": _available_roles(client, boundary)[0]["value"],
    }
    body.update(overrides)
    response = client.post(_path(boundary), json={"authorization_boundary_membership": body})
    assert response.status_code in (200, 201), response.text
    return response.json().get("data") or response.json()


class TestRoles:
    @pytest.mark.happy
    def test_reports_the_configured_vocabulary(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        data = admin_client.get(f"{_path(boundary)}/roles").json()["data"]

        assert data["available"], "instance offers no boundary roles at all"
        for entry in data["available"]:
            assert entry["value"], f"role with an empty value: {entry}"
            assert entry["label"], f"role with an empty label: {entry}"

    @pytest.mark.happy
    def test_every_offered_role_is_acceptable(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        """The 500 in #875 was the offered list and the accepted list
        disagreeing. They must not diverge again."""
        data = admin_client.get(f"{_path(boundary)}/roles").json()["data"]

        offered = {entry["value"] for entry in data["available"]}
        assert offered <= set(data["acceptable"]), (
            f"roles offered but not acceptable: {offered - set(data['acceptable'])}"
        )

    @pytest.mark.auth
    def test_no_token_returns_401(
        self, anon_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        assert_error_envelope(anon_client.get(f"{_path(boundary)}/roles"), expected_status=401)


class TestIndex:
    @pytest.mark.happy
    def test_lists_the_roster(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        member = _create(admin_client, boundary)

        response = admin_client.get(_path(boundary))
        assert response.status_code == 200, response.text
        body = response.json()
        assert_paginated_envelope(body)
        assert member["id"] in [m["id"] for m in body["data"]]

    @pytest.mark.auth
    def test_no_token_returns_401(
        self, anon_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        assert_error_envelope(anon_client.get(_path(boundary)), expected_status=401)


class TestCreate:
    @pytest.mark.happy
    def test_creates_a_member_with_a_resolved_role(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        offered = _available_roles(admin_client, boundary)[0]
        member = _create(admin_client, boundary, role=offered["value"], user_name="Dana Reed")

        assert member["user_name"] == "Dana Reed"
        assert member["role"] == offered["value"]
        assert member["role_label"] == offered["label"]

    @pytest.mark.happy
    def test_accepts_a_role_spelled_differently(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        """Case and punctuation fold, so an integrator sending ISSO rather than
        isso is not silently rejected — nor does it create a second role."""
        offered = _available_roles(admin_client, boundary)[0]["value"]
        member = _create(admin_client, boundary, role=offered.upper())

        assert member["role"] == offered

    @pytest.mark.validation
    def test_rejects_a_role_outside_the_vocabulary(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            _path(boundary),
            json={
                "authorization_boundary_membership": {
                    "user_name": "Dana Reed",
                    "role": f"not-a-real-role-{uuid.uuid4().hex[:6]}",
                }
            },
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_rejects_a_member_with_no_name(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            _path(boundary),
            json={
                "authorization_boundary_membership": {
                    "user_name": "",
                    "role": _available_roles(admin_client, boundary)[0]["value"],
                }
            },
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.auth
    def test_no_token_returns_401(
        self, anon_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = anon_client.post(
            _path(boundary),
            json={"authorization_boundary_membership": {"user_name": "X", "role": "isso"}},
        )
        assert_error_envelope(response, expected_status=401)


class TestShowUpdateDestroy:
    @pytest.mark.happy
    def test_shows_a_member(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        member = _create(admin_client, boundary)

        response = admin_client.get(f"{_path(boundary)}/{member['id']}")
        assert response.status_code == 200, response.text
        assert response.json()["data"]["id"] == member["id"]

    @pytest.mark.happy
    def test_updates_a_member(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        member = _create(admin_client, boundary)

        response = admin_client.patch(
            f"{_path(boundary)}/{member['id']}",
            json={"authorization_boundary_membership": {"user_name": "Renamed Person"}},
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["user_name"] == "Renamed Person"

    @pytest.mark.happy
    def test_deletes_a_member(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        member = _create(admin_client, boundary)

        response = admin_client.delete(f"{_path(boundary)}/{member['id']}")
        assert response.status_code in (200, 204), response.text

        assert admin_client.get(f"{_path(boundary)}/{member['id']}").status_code == 404

    @pytest.mark.authz
    def test_member_of_another_boundary_is_not_reachable(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        """Scoped to the parent boundary, so an id from elsewhere 404s rather
        than leaking or mutating a roster reached by the wrong path."""
        other = admin_client.post(BOUNDARIES, json=_boundary_payload())
        other_boundary = other.json().get("data") or other.json()
        try:
            member = _create(admin_client, other_boundary)
            response = admin_client.get(f"{_path(boundary)}/{member['id']}")
            assert response.status_code == 404, response.text
        finally:
            admin_client.delete(f"{BOUNDARIES}/{other_boundary['id']}")

    @pytest.mark.authz
    def test_non_admin_cannot_write(
        self, user_client: httpx.Client, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = user_client.post(
            _path(boundary),
            json={
                "authorization_boundary_membership": {
                    "user_name": "Should Not Exist",
                    "role": _available_roles(admin_client, boundary)[0]["value"],
                }
            },
        )
        assert response.status_code in (401, 403, 404), response.text
