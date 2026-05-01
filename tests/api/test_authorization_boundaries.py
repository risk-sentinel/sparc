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

from conftest import assert_error_envelope, assert_paginated_envelope


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
        assert_error_envelope(
            anon_client.post(PATH, json=_new_payload()), expected_status=401
        )

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
        new_desc = f"updated {uuid.uuid4().hex[:6]}"
        response = admin_client.patch(
            f"{PATH}/{boundary['id']}",
            json={"authorization_boundary": {"description": new_desc}},
        )
        assert response.status_code == 200, response.text

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.patch(f"{PATH}/0", json={}), expected_status=401
        )


class TestDestroy:
    @pytest.mark.happy
    def test_admin_destroys_boundary(self, admin_client: httpx.Client) -> None:
        b = _create(admin_client)
        response = admin_client.delete(f"{PATH}/{b['id']}")
        assert response.status_code in (200, 204)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.delete(f"{PATH}/0"), expected_status=401)
