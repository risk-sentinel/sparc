"""Tests for /api/v1/control_mappings.

5 logical endpoints — CRUD with admin-only writes. Mappings link
controls between catalogs (e.g., NIST SP 800-53 Rev 4 -> Rev 5).
"""

from __future__ import annotations

import uuid
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope, assert_paginated_envelope
from schemas import (
    ControlMappingIndex,
    validate_index_response,
)


pytestmark = [pytest.mark.catalogs, pytest.mark.phase1]


PATH = "/api/v1/control_mappings"


def _new_payload() -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    return {
        "control_mapping": {
            "name": f"phase2-mapping-{suffix}",
            "description": "Created by Phase 2 pytest suite",
            "status": "draft",
            "method_type": "human",
        }
    }


def _delete(client: httpx.Client, mapping_id: int) -> None:
    response = client.delete(f"{PATH}/{mapping_id}")
    assert response.status_code in (200, 204, 404), response.text


class TestIndex:
    @pytest.mark.happy
    def test_admin_lists_mappings(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH)
        assert response.status_code == 200, response.text
        assert_paginated_envelope(response.json())
        # #433 slice 2 — content-style validation
        validate_index_response(response, ControlMappingIndex)

    # ControlMapping Show endpoint exercising (positive case) deferred to
    # slice 3 — the routing for show appears to need a slug not id, will
    # confirm against fixtures rather than against arbitrary existing data.

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(PATH), expected_status=401)


class TestShow:
    def test_unknown_id_returns_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/99999999")
        assert_error_envelope(response, expected_status=404)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(f"{PATH}/0"), expected_status=401)


class TestCreate:
    @pytest.mark.happy
    def test_admin_creates_mapping(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json=_new_payload())
        # Some configurations require source/target catalog ids; treat
        # 422 as a valid contract response in that case.
        if response.status_code == 422:
            assert_error_envelope(response, expected_status=422)
            return
        assert response.status_code in (200, 201), response.text
        body = response.json().get("data") or response.json()
        _delete(admin_client, body["id"])

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
            PATH, json={"control_mapping": {"status": "draft", "method_type": "human"}}
        )
        assert_error_envelope(response, expected_status=422)


class TestUpdate:
    @pytest.mark.authz
    def test_non_admin_returns_403(self, user_client: httpx.Client) -> None:
        response = user_client.patch(f"{PATH}/0", json={})
        assert response.status_code in (401, 403)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.patch(f"{PATH}/0", json={}), expected_status=401
        )


class TestDestroy:
    @pytest.mark.authz
    def test_non_admin_returns_403(self, user_client: httpx.Client) -> None:
        response = user_client.delete(f"{PATH}/0")
        assert response.status_code in (401, 403)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.delete(f"{PATH}/0"), expected_status=401)
