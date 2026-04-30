"""Tests for /api/v1/ksi_catalog.

4 logical endpoints — all read-only. Themes, indicators (with filters),
indicator detail (by control_id, NOT numeric id), and KSI-to-NIST
mappings. The test instance must be seeded with a KSI catalog;
indicator detail tests degrade gracefully if the seed isn't present.
"""

from __future__ import annotations

import httpx
import pytest

from conftest import assert_error_envelope


pytestmark = [pytest.mark.ksi, pytest.mark.phase1]


PATH = "/api/v1/ksi_catalog"


class TestThemes:
    @pytest.mark.happy
    def test_lists_themes(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/themes")
        assert response.status_code == 200, response.text
        body = response.json()
        assert "data" in body and isinstance(body["data"], list)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{PATH}/themes"), expected_status=401
        )


class TestIndicators:
    @pytest.mark.happy
    def test_lists_indicators(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/indicators")
        assert response.status_code == 200, response.text
        body = response.json()
        assert "data" in body and isinstance(body["data"], list)

    @pytest.mark.pagination
    def test_filter_by_theme(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/indicators", params={"theme": "ac"})
        assert response.status_code == 200

    @pytest.mark.pagination
    def test_filter_by_impact_level(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(
            f"{PATH}/indicators", params={"impact_level": "moderate"}
        )
        assert response.status_code == 200

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{PATH}/indicators"), expected_status=401
        )


class TestShowIndicator:
    def test_unknown_indicator_returns_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(
            f"{PATH}/indicators/phase2-this-control-id-does-not-exist"
        )
        assert_error_envelope(response, expected_status=404)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{PATH}/indicators/anything"), expected_status=401
        )


class TestMappings:
    @pytest.mark.happy
    def test_lists_mappings(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/mappings")
        # 200 if a KSI-to-NIST mapping is registered; the controller
        # also returns 200 with an empty list + helpful meta when no
        # mapping is defined yet.
        assert response.status_code == 200, response.text
        body = response.json()
        assert "data" in body and isinstance(body["data"], list)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{PATH}/mappings"), expected_status=401
        )
