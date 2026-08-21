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

from _crud_contract import CrudContract
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


# #995 — the shared matrix for this group.
class TestCrudContract(CrudContract):
    PARAM_KEY = "authorization_boundary_membership"
    IDENTIFIER = "id"


    def _base_path(self, admin_client):
        boundaries = admin_client.get(BOUNDARIES, params={"items": 1})
        rows = boundaries.json()["data"]
        assert rows, "no authorization boundary on this instance"
        self._boundary = rows[0]
        return _path(rows[0])

    def _payload(self, admin_client):
        roles = admin_client.get(f"{self._base_path(admin_client)}/roles")
        available = roles.json()["data"]["available"]
        return {"user_name": f"Contract Person {uuid.uuid4().hex[:6]}",
                "user_email": f"contract-{uuid.uuid4().hex[:6]}@example.gov",
                "role": available[0]["value"]}

    def _update_fields(self):
        return {"user_name": f"Renamed {uuid.uuid4().hex[:6]}"}


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


class TestAuthorization:
    """A non-admin without `authorization_boundaries.write` must be refused.

    This class exists because its absence hid a real vulnerability. The web
    controller for this same resource shipped with NO authorization at all from
    2026-03-09 until v1.15.5 — any signed-in user could add, re-role or remove
    members on any boundary whose slug they knew, and boundary roles gate access
    to compliance documents.

    Nothing caught it for five months: Brakeman has no check for *missing*
    authorization (it flags patterns in code that exists, not a guard that was
    never written), and every test here exercised the permitted path with
    `admin_client`. A contract suite that only ever asks "can the authorized
    caller do this?" cannot answer "is anyone else stopped?".

    So these assert the negative, on every mutating verb, against the API — and
    the web surface has the equivalent in
    spec/requests/authorization_boundary_memberships_authz_spec.rb.
    """

    @pytest.mark.authz
    def test_non_admin_cannot_list_the_roster(
        self, user_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = user_client.get(_path(boundary))
        assert response.status_code in (401, 403, 404), response.text

    @pytest.mark.authz
    def test_non_admin_cannot_add_a_member(
        self, user_client: httpx.Client, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        role = _available_roles(admin_client, boundary)[0]["value"]
        response = user_client.post(
            _path(boundary),
            json={"authorization_boundary_membership": {
                "user_name": "Unauthorized Add",
                "user_email": "intruder@example.gov",
                "role": role,
            }},
        )
        assert response.status_code in (401, 403, 404), response.text

        # And it genuinely did not happen — a refusal that still writes is worse
        # than no refusal, because it reads as safe.
        roster = admin_client.get(_path(boundary)).json()["data"]
        assert not any(m.get("user_email") == "intruder@example.gov" for m in roster), roster

    @pytest.mark.authz
    def test_non_admin_cannot_change_a_members_role(
        self, user_client: httpx.Client, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        member = _create(admin_client, boundary)
        roles = _available_roles(admin_client, boundary)
        other = next(
            (r["value"] for r in roles if r["value"] != member.get("role")),
            roles[0]["value"],
        )

        response = user_client.patch(
            f"{_path(boundary)}/{member['id']}",
            json={"authorization_boundary_membership": {"role": other}},
        )
        assert response.status_code in (401, 403, 404), response.text

        after = admin_client.get(f"{_path(boundary)}/{member['id']}").json()["data"]
        assert after.get("role") == member.get("role"), "role must be unchanged"

    @pytest.mark.authz
    def test_non_admin_cannot_remove_a_member(
        self, user_client: httpx.Client, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        member = _create(admin_client, boundary)

        response = user_client.delete(f"{_path(boundary)}/{member['id']}")
        assert response.status_code in (401, 403, 404), response.text

        still_there = admin_client.get(f"{_path(boundary)}/{member['id']}")
        assert still_there.status_code == 200, "the member must survive an unauthorized delete"

    @pytest.mark.authz
    def test_anonymous_is_rejected_on_every_verb(
        self, anon_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        path = _path(boundary)
        assert anon_client.get(path).status_code == 401
        assert anon_client.post(path, json={}).status_code == 401
        assert anon_client.patch(f"{path}/1", json={}).status_code == 401
        assert anon_client.delete(f"{path}/1").status_code == 401
