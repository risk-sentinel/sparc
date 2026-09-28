"""Tests for /api/v1/ksi_catalog.

5 logical endpoints. Themes, indicators (with filters), indicator detail
(by control_id, NOT numeric id), KSI-to-NIST mappings, and the import from
the vendored FedRAMP/rules snapshot (#1172). The test instance must be
seeded with a KSI catalog; indicator detail tests degrade gracefully if the
seed isn't present.

#1115 — entries FedRAMP no longer publishes are retired, not deleted: the
lists return the current catalog, ``include_retired=true`` adds the rest.
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

    @pytest.mark.happy
    def test_default_list_is_current_and_include_retired_is_a_superset(
        self, admin_client: httpx.Client
    ) -> None:
        params = {"items": 100}
        current = admin_client.get(f"{PATH}/indicators", params=params).json()["data"]
        everything = admin_client.get(
            f"{PATH}/indicators", params={**params, "include_retired": "true"}
        ).json()["data"]

        assert all(row["retired_at"] is None for row in current)
        assert {r["control_id"] for r in current} <= {r["control_id"] for r in everything}

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


class TestImport:
    @pytest.mark.happy
    def test_dry_run_reports_and_changes_nothing(self, admin_client: httpx.Client) -> None:
        before = admin_client.get(f"{PATH}/themes").json()["data"]

        response = admin_client.post(f"{PATH}/import", params={"dry_run": "true"})

        assert response.status_code == 200, response.text
        data = response.json()["data"]
        assert data["status"] == "planned" and data["dry_run"] is True
        assert data["upstream_version"]
        assert admin_client.get(f"{PATH}/themes").json()["data"] == before

    @pytest.mark.happy
    def test_import_lands_or_is_already_current(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(f"{PATH}/import")

        assert response.status_code == 200, response.text
        assert response.json()["data"]["status"] in {"imported", "unchanged"}
        # A second import of the same snapshot is always a no-op.
        again = admin_client.post(f"{PATH}/import").json()["data"]
        assert again["status"] == "unchanged"

    @pytest.mark.authz
    def test_a_non_admin_without_catalogs_write_is_refused(
        self, user_client: httpx.Client
    ) -> None:
        response = user_client.post(f"{PATH}/import")
        assert response.status_code == 403, response.text

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(f"{PATH}/import"), expected_status=401
        )
