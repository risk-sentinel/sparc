"""Tests for /api/v1/control_catalogs.

5 logical endpoints — CRUD with admin-only writes. Reads are open to
any authenticated user.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope, assert_paginated_envelope
from schemas import (
    ControlCatalogIndex,
    ControlCatalogShow,
    assert_create_round_trip,
    validate_index_response,
    validate_show_response,
)


pytestmark = [pytest.mark.catalogs, pytest.mark.phase1]


PATH = "/api/v1/control_catalogs"


def _new_payload() -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    return {
        "control_catalog": {
            "name": f"phase2-catalog-{suffix}",
            "description": "Created by Phase 2 pytest suite",
            "version": "0.0.1",
            "source": "phase2-test",
        }
    }


def _create(client: httpx.Client) -> dict[str, Any]:
    response = client.post(PATH, json=_new_payload())
    assert response.status_code in (200, 201), response.text
    return response.json().get("data") or response.json()


def _delete(client: httpx.Client, catalog_id: int) -> None:
    response = client.delete(f"{PATH}/{catalog_id}")
    assert response.status_code in (200, 204, 404), response.text


@pytest.fixture
def catalog(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    c = _create(admin_client)
    try:
        yield c
    finally:
        _delete(admin_client, c["id"])


class TestIndex:
    @pytest.mark.happy
    def test_admin_lists_catalogs(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH)
        assert response.status_code == 200, response.text
        assert_paginated_envelope(response.json())
        # #433 slice 2 — content-style validation
        validate_index_response(response, ControlCatalogIndex)

    @pytest.mark.happy
    def test_user_lists_catalogs(self, user_client: httpx.Client) -> None:
        # Reads are open to any authenticated user.
        response = user_client.get(PATH)
        assert response.status_code == 200, response.text

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(PATH), expected_status=401)


class TestShow:
    @pytest.mark.happy
    def test_admin_shows_catalog(
        self, admin_client: httpx.Client, catalog: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{catalog['id']}")
        # #433 slice 2 — content-style validation (detailed Show shape)
        validate_show_response(response, ControlCatalogShow)

    def test_unknown_id_returns_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/99999999")
        assert_error_envelope(response, expected_status=404)


class TestCreate:
    @pytest.mark.happy
    def test_admin_creates_catalog(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json=_new_payload())
        assert response.status_code in (200, 201)
        c = response.json().get("data") or response.json()
        _delete(admin_client, c["id"])

    @pytest.mark.happy
    def test_create_round_trip(self, admin_client: httpx.Client) -> None:
        """#433 slice 4 — Create payload fields survive Create → Show.

        Catalog create returns both ``id`` and ``slug``, but the show /
        update / destroy URLs take ``slug`` only. The existing tests use
        ``id`` and silently tolerate 404 from the delete — this round-trip
        uses the correct ``slug`` identifier.
        """
        assert_create_round_trip(
            admin_client,
            PATH,
            _new_payload(),
            "control_catalog",
            ControlCatalogShow,
            identifier="slug",
        )

    @pytest.mark.authz
    def test_non_admin_returns_403(self, user_client: httpx.Client) -> None:
        response = user_client.post(PATH, json=_new_payload())
        assert response.status_code in (401, 403)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(PATH, json=_new_payload()), expected_status=401
        )

    @pytest.mark.validation
    def test_missing_name_returns_422(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(
            PATH, json={"control_catalog": {"description": "no name"}}
        )
        assert_error_envelope(response, expected_status=422)


class TestUpdate:
    @pytest.mark.happy
    def test_admin_updates_catalog(
        self, admin_client: httpx.Client, catalog: dict[str, Any]
    ) -> None:
        new_desc = f"updated {uuid.uuid4().hex[:6]}"
        response = admin_client.patch(
            f"{PATH}/{catalog['id']}",
            json={"control_catalog": {"description": new_desc}},
        )
        assert response.status_code == 200, response.text

    @pytest.mark.authz
    def test_non_admin_returns_403(self, user_client: httpx.Client) -> None:
        response = user_client.patch(f"{PATH}/0", json={})
        assert response.status_code in (401, 403)


class TestDestroy:
    @pytest.mark.happy
    def test_admin_destroys_catalog(self, admin_client: httpx.Client) -> None:
        c = _create(admin_client)
        response = admin_client.delete(f"{PATH}/{c['id']}")
        assert response.status_code in (200, 204)

    @pytest.mark.authz
    def test_non_admin_returns_403(self, user_client: httpx.Client) -> None:
        response = user_client.delete(f"{PATH}/0")
        assert response.status_code in (401, 403)
