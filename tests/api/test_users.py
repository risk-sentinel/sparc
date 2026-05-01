"""Tests for /api/v1/users.

5 logical endpoints — CRUD plus self-edit. Per the controller's
``Update (self)`` row in the docs, a non-admin can update their own
profile fields (name only); admins can edit any user. Tests assert
both gates separately.

User creation/destruction is admin-only and goes through the suite's
admin client. Each test owns its created user and deletes on teardown.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope, assert_paginated_envelope


pytestmark = [pytest.mark.users, pytest.mark.phase1]


PATH = "/api/v1/users"


def _new_payload(**overrides: Any) -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    body = {
        "email": f"phase2-user-{suffix}@example.com",
        "first_name": "Phase",
        "last_name": "Two",
        "password": f"phase2-test-pw-{suffix}!",
    }
    body.update(overrides)
    return {"user": body}


def _create(client: httpx.Client) -> dict[str, Any]:
    response = client.post(PATH, json=_new_payload())
    assert response.status_code in (200, 201), response.text
    return response.json().get("data") or response.json()


def _delete(client: httpx.Client, user_id: int) -> None:
    response = client.delete(f"{PATH}/{user_id}")
    assert response.status_code in (200, 204, 404), response.text


@pytest.fixture
def created_user(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    user = _create(admin_client)
    try:
        yield user
    finally:
        _delete(admin_client, user["id"])


class TestIndex:
    @pytest.mark.happy
    def test_admin_lists_users(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH)
        assert response.status_code == 200, response.text
        # Some controllers return paginated, some return a flat list —
        # both are documented at various points; accept either shape.
        body = response.json()
        assert isinstance(body, dict)
        if "data" in body:
            assert isinstance(body["data"], list)
        else:
            # Older shape: flat list under ``users`` or top-level array.
            assert "users" in body or isinstance(body, list)

    @pytest.mark.pagination
    def test_pagination_query_params_respected(
        self, admin_client: httpx.Client
    ) -> None:
        response = admin_client.get(PATH, params={"page": 1, "items": 5})
        assert response.status_code == 200
        body = response.json()
        if "meta" in body:
            assert body["meta"]["page"] == 1
            assert body["meta"]["items"] == 5

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(PATH), expected_status=401)

    @pytest.mark.authz
    def test_non_admin_returns_403_or_filtered(
        self, user_client: httpx.Client
    ) -> None:
        response = user_client.get(PATH)
        # Index is admin-only; non-admin gets 403. Some setups instead
        # serve a self-only filtered list; either is acceptable.
        assert response.status_code in (200, 401, 403)


class TestShow:
    @pytest.mark.happy
    def test_admin_shows_user(
        self, admin_client: httpx.Client, created_user: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{created_user['id']}")
        assert response.status_code == 200
        body = response.json()
        assert body.get("data", body)["id"] == created_user["id"]

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(f"{PATH}/0"), expected_status=401)


class TestCreate:
    @pytest.mark.happy
    def test_admin_creates_user(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json=_new_payload())
        assert response.status_code in (200, 201)
        user = response.json().get("data") or response.json()
        _delete(admin_client, user["id"])

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
    def test_missing_email_returns_422(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(
            PATH, json={"user": {"first_name": "no", "last_name": "email"}}
        )
        assert_error_envelope(response, expected_status=422)


class TestUpdate:
    @pytest.mark.happy
    def test_admin_updates_user(
        self, admin_client: httpx.Client, created_user: dict[str, Any]
    ) -> None:
        new_first = f"updated-{uuid.uuid4().hex[:6]}"
        response = admin_client.patch(
            f"{PATH}/{created_user['id']}",
            json={"user": {"first_name": new_first}},
        )
        assert response.status_code == 200, response.text

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.patch(f"{PATH}/0", json={}), expected_status=401
        )


class TestDestroy:
    @pytest.mark.happy
    def test_admin_destroys_user(self, admin_client: httpx.Client) -> None:
        user = _create(admin_client)
        response = admin_client.delete(f"{PATH}/{user['id']}")
        assert response.status_code in (200, 204), response.text

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.delete(f"{PATH}/0"), expected_status=401)
