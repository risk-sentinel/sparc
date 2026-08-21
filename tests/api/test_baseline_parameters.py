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

from _export_contract import ExportContract
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


# #995 — the shared export contract.
class TestExportContract(ExportContract):
    EXPORT_FORMATS = ("json", "yaml")

    def _export_path(self, admin_client):
        profiles = admin_client.get(PROFILES_PATH, params={"items": 100}).json()["data"]
        for row in profiles:
            params_response = admin_client.get(_path(row["slug"]))
            if params_response.status_code == 200 and params_response.json()["data"]["parameters"]:
                self._profile = row
                return f"{_path(row['slug'])}/export"
        raise AssertionError("no profile on this instance exposes tailorable parameters")

    def _expected_content(self, admin_client):
        self._export_path(admin_client)
        return self._profile["name"]


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


@pytest.fixture
def tailorable_parameter(
    admin_client: httpx.Client,
) -> Iterator[tuple[str, dict[str, Any]]] | None:
    """A (profile_slug, parameter) pair on a profile that actually has ODPs.

    The module's own ``profile`` fixture creates an empty profile, which has no
    parameters at all — nothing there can prove a parameter update persisted.
    Parameters come from a profile's resolved catalog, so this finds a profile
    that has some and restores whatever it changes.
    """
    listing = admin_client.get(PROFILES_PATH, params={"items": 100})
    assert listing.status_code == 200, listing.text

    for item in listing.json().get("data", []):
        slug = item.get("slug")
        if not slug:
            continue
        # #1008 — a published profile is read-only, so it cannot demonstrate
        # that an update persists. Skipping it here is the product rule, not a
        # convenience: the refusal itself is asserted below.
        if item.get("lifecycle_status") == "published":
            continue
        response = admin_client.get(_path(slug))
        if response.status_code != 200:
            continue
        parameters = response.json().get("data", {}).get("parameters") or []
        if parameters:
            original = parameters[0]
            yield slug, original
            admin_client.put(
                _path(slug),
                json={
                    "parameters": [
                        {
                            "param_id": original["param_id"],
                            "value": original.get("current_value"),
                        }
                    ]
                },
            )
            return

    pytest.skip("no profile on this instance exposes any tailorable parameters")


class TestUpdate:
    @pytest.mark.happy
    def test_admin_updates_parameters(
        self,
        admin_client: httpx.Client,
        tailorable_parameter: tuple[str, dict[str, Any]],
    ) -> None:
        """A tailored ODP value persists, confirmed by an independent read.

        What this replaced sent ``{"parameters": {}}`` — an empty *object map*
        — and accepted ``200 or 422``. Both halves were vacuous. The map shape
        is the one #994's parser rejects, so the test named
        ``test_admin_updates_parameters`` and marked ``happy`` exercised the
        refusal path and never once verified that a parameter update persists;
        and accepting either status meant no response could fail it.
        """
        slug, parameter = tailorable_parameter
        param_id = parameter["param_id"]
        new_value = f"sweep-{uuid.uuid4().hex[:8]}"
        assert parameter.get("current_value") != new_value

        response = admin_client.put(
            _path(slug),
            json={"parameters": [{"param_id": param_id, "value": new_value}]},
        )
        assert response.status_code == 200, response.text

        result = response.json()["data"]
        assert result["parameters_updated"] == 1, result
        assert result["validation_errors"] == [], result

        after = admin_client.get(_path(slug))
        assert after.status_code == 200, after.text
        persisted = {
            row["param_id"]: row.get("current_value")
            for row in after.json()["data"]["parameters"]
        }
        assert persisted[param_id] == new_value, (
            f"{param_id} reported updated but an independent read shows "
            f"{persisted[param_id]!r}"
        )

    @pytest.mark.authz
    def test_published_profile_is_refused(self, admin_client: httpx.Client) -> None:
        """A published profile cannot be edited, and says so (#1008).

        The Lifecycle concern has documented "Published documents are read-only"
        since it was written, and nothing enforced it on this path: a published
        baseline's ODPs could be rewritten through the API, with the change
        persisting. A published baseline is what other documents are derived
        from and attested against.
        """
        listing = admin_client.get(PROFILES_PATH, params={"items": 100})
        assert listing.status_code == 200, listing.text

        published = next(
            (
                item
                for item in listing.json().get("data", [])
                if item.get("lifecycle_status") == "published"
            ),
            None,
        )
        if published is None:
            pytest.skip("no published profile on this instance")

        before = admin_client.get(_path(published["slug"]))
        assert before.status_code == 200, before.text
        original = before.json()["data"]["parameters"]
        if not original:
            pytest.skip("the published profile exposes no parameters")

        param_id = original[0]["param_id"]
        response = admin_client.put(
            _path(published["slug"]),
            json={"parameters": [{"param_id": param_id, "value": "must-be-refused"}]},
        )
        assert response.status_code == 422, response.text
        assert "published" in response.json()["error"].lower(), response.text

        after = admin_client.get(_path(published["slug"]))
        persisted = {
            row["param_id"]: row.get("current_value")
            for row in after.json()["data"]["parameters"]
        }
        assert persisted[param_id] == original[0].get("current_value"), (
            "the update was refused but the value changed anyway"
        )

    @pytest.mark.validation
    def test_object_map_shape_is_refused_with_a_named_reason(
        self, admin_client: httpx.Client, profile: dict[str, Any]
    ) -> None:
        """The #994 shape: an object map where an array is expected.

        It must be told apart from "nothing to do" — before #994 this answered
        ``200 {"status": "updated", "parameters_updated": 0}``.
        """
        response = admin_client.put(_path(profile["slug"]), json={"parameters": {}})
        assert response.status_code == 422, response.text

        body = response.json()
        assert "could not be parsed" in body["error"], body
        assert any("ARRAY" in detail for detail in body["details"]), body
        assert body["expected"]["parameters"] == [
            {"param_id": "string", "value": "string"}
        ], body

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
