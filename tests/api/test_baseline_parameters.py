"""Tests for /api/v1/profile_documents/:slug/parameters.

5 logical endpoints: show (schema), update (bulk), export, and the #697
ODP file import preview/confirm. All nested under a profile document.
Tests create their own profile parent so they don't depend on seed-data
presence.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope


pytestmark = [pytest.mark.baselines, pytest.mark.phase1]


PROFILES_PATH = "/api/v1/profile_documents"


def _path(profile_slug: str) -> str:
    return f"{PROFILES_PATH}/{profile_slug}/parameters"


def _new_profile_payload() -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    return {
        "profile_document": {
            "name": f"phase2-baselines-parent-{suffix}",
            "description": "Phase 2 baseline-parameters parent",
        }
    }


@pytest.fixture
def profile(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(PROFILES_PATH, json=_new_profile_payload())
    assert response.status_code in (200, 201), response.text
    body = response.json().get("data") or response.json()
    try:
        yield body
    finally:
        admin_client.delete(f"{PROFILES_PATH}/{body['slug']}")


class TestShow:
    @pytest.mark.happy
    def test_admin_shows_parameter_schema(
        self, admin_client: httpx.Client, profile: dict[str, Any]
    ) -> None:
        response = admin_client.get(_path(profile["slug"]))
        assert response.status_code == 200, response.text
        body = response.json()
        assert "data" in body

    @pytest.mark.pagination
    def test_filter_by_family(
        self, admin_client: httpx.Client, profile: dict[str, Any]
    ) -> None:
        response = admin_client.get(_path(profile["slug"]), params={"family": "ac"})
        assert response.status_code == 200

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(_path("anything")), expected_status=401
        )


class TestUpdate:
    @pytest.mark.happy
    def test_admin_updates_parameters(
        self, admin_client: httpx.Client, profile: dict[str, Any]
    ) -> None:
        # Sending an empty parameters map exercises the bulk-update
        # contract without depending on which parameter ids the seed
        # exposes.
        response = admin_client.put(_path(profile["slug"]), json={"parameters": {}})
        assert response.status_code in (200, 422), response.text

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.put(_path("anything"), json={"parameters": {}}),
            expected_status=401,
        )


class TestExport:
    @pytest.mark.happy
    def test_admin_exports_json(
        self, admin_client: httpx.Client, profile: dict[str, Any]
    ) -> None:
        response = admin_client.get(
            f"{_path(profile['slug'])}/export", params={"format": "json"}
        )
        assert response.status_code == 200, response.text

    @pytest.mark.happy
    def test_admin_exports_yaml(
        self, admin_client: httpx.Client, profile: dict[str, Any]
    ) -> None:
        response = admin_client.get(
            f"{_path(profile['slug'])}/export", params={"format": "yaml"}
        )
        assert response.status_code == 200, response.text

    @pytest.mark.validation
    def test_unsupported_format_returns_400(
        self, admin_client: httpx.Client, profile: dict[str, Any]
    ) -> None:
        response = admin_client.get(
            f"{_path(profile['slug'])}/export", params={"format": "csv"}
        )
        assert_error_envelope(response, expected_status=400)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{_path('anything')}/export"), expected_status=401
        )


class TestOdpImport:
    """#697 — ODP file import (import_preview -> import_confirm), multipart JSON/YAML/XML.

    A freshly-created profile has no catalog, so its parameter schema is empty
    and any uploaded id is reported as `unknown`. That's enough to exercise the
    endpoint contract without depending on seeded catalog parameters.
    """

    _JSON_BODY = (
        b'{"parameters": [{"param_id": "ac-1_prm_1", "value": "ISSO"}], '
        b'"selections": []}'
    )

    def _preview(self, slug: str) -> str:
        return f"{_path(slug)}/import/preview"

    def _confirm(self, slug: str) -> str:
        return f"{_path(slug)}/import/confirm"

    @pytest.mark.happy
    def test_preview_returns_diff_stats(
        self, admin_client: httpx.Client, profile: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            self._preview(profile["slug"]),
            files={"file": ("odp.json", self._JSON_BODY, "application/json")},
        )
        assert response.status_code == 200, response.text
        stats = response.json()["data"]["stats"]
        assert stats["total"] == 1

    @pytest.mark.validation
    def test_preview_without_file_returns_422(
        self, admin_client: httpx.Client, profile: dict[str, Any]
    ) -> None:
        response = admin_client.post(self._preview(profile["slug"]))
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_confirm_all_unknown_returns_422(
        self, admin_client: httpx.Client, profile: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            self._confirm(profile["slug"]),
            files={"file": ("odp.json", self._JSON_BODY, "application/json")},
        )
        # Bare profile: the one id is unknown -> nothing applied -> 422.
        assert response.status_code == 422, response.text

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(f"{_path('anything')}/import/preview"),
            expected_status=401,
        )
