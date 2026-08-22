"""Tests for /api/v1/authorization_boundaries/:id/leveraged_authorizations (#1015).

A leveraged authorization records the ATO a system inherits from, and OSCAL
exports one entry per record on every SSP for the boundary. Before #1015 the
whole lifecycle was browser-only — found by the missing-endpoint axis of #995.

Authority here is MEMBERSHIP of the leveraging boundary, not a permission key.
That mirrors the web controller deliberately (#919), so the non-admin leg
asserts refusal rather than assuming a permission grant would help.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import date
from typing import Any

import httpx
import pytest

from _crud_contract import CrudContract
from conftest import assert_error_envelope

pytestmark = [pytest.mark.federation, pytest.mark.phase2]


def _path(boundary: Any) -> str:
    return f"/api/v1/authorization_boundaries/{boundary}/leveraged_authorizations"


def _payload(**overrides: Any) -> dict[str, Any]:
    body = {
        "name": f"phase2-leveraged-{uuid.uuid4().hex[:8]}",
        # Scenario 2: no leveraged boundary needed, so the fixture does not
        # depend on a second boundary existing on the instance.
        "crm_type": "oscal_no_access",
        "date_authorized": date.today().isoformat(),
        "description": "Created by the API contract suite.",
    }
    body.update(overrides)
    return {"leveraged_authorization": body}


@pytest.fixture
def leveraged_authorization(
    admin_client: httpx.Client, seeded_boundary_id: int
) -> Iterator[tuple[int, dict[str, Any]]]:
    response = admin_client.post(_path(seeded_boundary_id), json=_payload())
    assert response.status_code == 201, response.text
    record = response.json()["data"]
    try:
        yield seeded_boundary_id, record
    finally:
        admin_client.delete(f"{_path(seeded_boundary_id)}/{record['id']}")


# #995 — the shared matrix for this group.
class TestCrudContract(CrudContract):
    PARAM_KEY = "leveraged_authorization"
    IDENTIFIER = "id"
    NO_UPDATE_ROUTE_BECAUSE = (
        "a leveraged authorization is re-populated from the leveraged SSP "
        "rather than edited field by field (#1015)"
    )

    def _base_path(self, admin_client):
        boundaries = admin_client.get("/api/v1/authorization_boundaries", params={"items": 1})
        rows = boundaries.json()["data"]
        assert rows, "no authorization boundary on this instance"
        return _path(rows[0]["id"])

    def _payload(self, admin_client):
        return _payload()["leveraged_authorization"]

    def _update_fields(self):
        return {}


class TestCreate:
    @pytest.mark.happy
    def test_create_persists_and_reads_back(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        payload = _payload()
        created = admin_client.post(_path(seeded_boundary_id), json=payload)
        assert created.status_code == 201, created.text
        record = created.json()["data"]

        try:
            # Independent read — not the write's own echo.
            shown = admin_client.get(f"{_path(seeded_boundary_id)}/{record['id']}")
            assert shown.status_code == 200, shown.text

            data = shown.json()["data"]
            sent = payload["leveraged_authorization"]
            assert data["name"] == sent["name"]
            assert data["crm_type"] == "oscal_no_access"
            assert data["scenario"] == 2
            assert data["description"] == sent["description"]
            assert data["uuid"], data
        finally:
            admin_client.delete(f"{_path(seeded_boundary_id)}/{record['id']}")

    @pytest.mark.validation
    def test_missing_authorization_date_is_refused(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        """#988 — a record with no date claims an authorization that does not exist."""
        body = _payload()
        del body["leveraged_authorization"]["date_authorized"]

        response = admin_client.post(_path(seeded_boundary_id), json=body)
        assert response.status_code == 422, response.text

    @pytest.mark.validation
    def test_unknown_crm_type_is_refused(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        response = admin_client.post(
            _path(seeded_boundary_id), json=_payload(crm_type="invented")
        )
        assert response.status_code == 422, response.text

    @pytest.mark.validation
    def test_unrecognized_field_is_refused(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        response = admin_client.post(
            _path(seeded_boundary_id), json=_payload(uuid=str(uuid.uuid4()))
        )
        assert response.status_code == 422, response.text
        assert "uuid" in " ".join(response.json()["details"])

    @pytest.mark.auth
    def test_no_token_returns_401(
        self, anon_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        assert_error_envelope(
            anon_client.post(_path(seeded_boundary_id), json=_payload()),
            expected_status=401,
        )

    @pytest.mark.authz
    def test_non_member_is_refused_and_creates_nothing(
        self, admin_client: httpx.Client, user_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        before = admin_client.get(_path(seeded_boundary_id)).json()["data"]

        response = user_client.post(_path(seeded_boundary_id), json=_payload())
        assert response.status_code in (401, 403, 404), response.text

        after = admin_client.get(_path(seeded_boundary_id)).json()["data"]
        assert len(after) == len(before), "a refused request created a record anyway"


class TestIndex:
    @pytest.mark.happy
    def test_lists_the_created_record(
        self, admin_client: httpx.Client,
        leveraged_authorization: tuple[int, dict[str, Any]]
    ) -> None:
        boundary_id, record = leveraged_authorization

        response = admin_client.get(_path(boundary_id))
        assert response.status_code == 200, response.text
        assert record["id"] in [row["id"] for row in response.json()["data"]]

    @pytest.mark.authz
    def test_non_member_cannot_list(
        self, user_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        response = user_client.get(_path(seeded_boundary_id))
        assert response.status_code in (401, 403, 404), response.text


class TestDestroy:
    @pytest.mark.happy
    def test_delete_removes_it_from_the_index(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        created = admin_client.post(_path(seeded_boundary_id), json=_payload())
        record = created.json()["data"]

        deleted = admin_client.delete(f"{_path(seeded_boundary_id)}/{record['id']}")
        assert deleted.status_code == 200, deleted.text

        # Gone from show AND from the parent's index — a record that still
        # lists is not deleted.
        shown = admin_client.get(f"{_path(seeded_boundary_id)}/{record['id']}")
        assert shown.status_code == 404, shown.text

        listing = admin_client.get(_path(seeded_boundary_id))
        assert record["id"] not in [row["id"] for row in listing.json()["data"]]

    @pytest.mark.authz
    def test_non_member_cannot_delete_and_the_record_survives(
        self, admin_client: httpx.Client, user_client: httpx.Client,
        leveraged_authorization: tuple[int, dict[str, Any]]
    ) -> None:
        boundary_id, record = leveraged_authorization

        response = user_client.delete(f"{_path(boundary_id)}/{record['id']}")
        assert response.status_code in (401, 403, 404), response.text

        still_there = admin_client.get(f"{_path(boundary_id)}/{record['id']}")
        assert still_there.status_code == 200, "a refused delete removed the record anyway"
