"""Tests for the HDF <-> OSCAL translation bridge (#449, #610).

Three stateless endpoints, all POST under /api/v1/:
  - oscal/sar_from_hdf              HDF results -> OSCAL SAR
  - oscal/poam_from_hdf             HDF results -> OSCAL POAM
  - hdf/amendments_from_oscal_poam  OSCAL POAM -> HDF Amendments

Happy paths exercise the real MITRE hdf-libs CLI baked into the SPARC
container (https://github.com/mitre/hdf-libs), so they require a running
instance with the `hdf` binary on PATH.

hdf-cli 3.2.0 contract changes (#648, upstream mitre/hdf-libs#104):
  - hdf -> oscal-sar now requires a top-level `baselines` field; SPARC injects
    an empty one for standard scanner HDF, so sar_from_hdf still returns 200.
  - hdf -> oscal-poam was removed entirely; poam_from_hdf now returns 501.
    The amendments test therefore loads a committed OSCAL POAM fixture instead
    of generating one from HDF.
"""

from __future__ import annotations

import json
import uuid
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.translations, pytest.mark.phase2]

SAR_PATH = "/api/v1/oscal/sar_from_hdf"
POAM_PATH = "/api/v1/oscal/poam_from_hdf"
AMENDMENTS_PATH = "/api/v1/hdf/amendments_from_oscal_poam"
BOUNDARIES_PATH = "/api/v1/authorization_boundaries"

_HDF_FIXTURE = Path(__file__).parent / "fixtures" / "sample.hdf.json"
_OSCAL_POAM_FIXTURE = Path(__file__).parent / "fixtures" / "sample.oscal-poam.json"


def _hdf_bytes() -> bytes:
    return _HDF_FIXTURE.read_bytes()


def _oscal_poam_bytes() -> bytes:
    return _OSCAL_POAM_FIXTURE.read_bytes()


def _post_raw(client: httpx.Client, path: str, body: bytes) -> httpx.Response:
    return client.post(
        path, content=body, headers={"Content-Type": "application/json"}
    )


class TestSarFromHdf:
    @pytest.mark.happy
    def test_raw_body_returns_oscal_sar(self, admin_client: httpx.Client) -> None:
        # #648 regression: sample.hdf.json is standard scanner HDF with NO
        # top-level `baselines` field — exactly the shape hdf-cli 3.2.0 rejects
        # ("missing baselines field") absent SPARC's injection. A 200 here
        # proves the baselines normalization is working end-to-end.
        assert "baselines" not in json.loads(_hdf_bytes()), "fixture must stay baseline-less"
        response = _post_raw(admin_client, SAR_PATH, _hdf_bytes())
        assert response.status_code == 200, response.text
        body = response.json()
        # OSCAL SAR documents are rooted at "assessment-results".
        assert "assessment-results" in body, body

    @pytest.mark.happy
    def test_multipart_upload_returns_oscal_sar(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(
            SAR_PATH, files={"file": ("sample.hdf.json", _hdf_bytes(), "application/json")}
        )
        assert response.status_code == 200, response.text
        assert "assessment-results" in response.json()

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(_post_raw(anon_client, SAR_PATH, _hdf_bytes()), expected_status=401)

    @pytest.mark.validation
    def test_no_payload_returns_400(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(SAR_PATH)
        assert_error_envelope(response, expected_status=400)

    @pytest.mark.validation
    def test_garbage_payload_returns_422(self, admin_client: httpx.Client) -> None:
        response = _post_raw(admin_client, SAR_PATH, b'{"not": "hdf"}')
        assert_error_envelope(response, expected_status=422)


class TestPoamFromHdf:
    @pytest.mark.happy
    def test_returns_501_converter_removed(self, admin_client: httpx.Client) -> None:
        # hdf-cli 3.2.0 removed the hdf -> oscal-poam converter
        # (upstream mitre/hdf-libs#104). The controller maps the resulting
        # "no converter found" to 501 Not Implemented so callers can tell an
        # unsupported path apart from bad input. When a future hdf-cli restores
        # the converter, flip this back to a 200 happy-path assertion. See #648.
        response = _post_raw(admin_client, POAM_PATH, _hdf_bytes())
        assert response.status_code == 501, response.text
        body = response.json()
        assert "mitre/hdf-libs" in body.get("note", ""), body

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(_post_raw(anon_client, POAM_PATH, _hdf_bytes()), expected_status=401)


class TestAmendmentsFromOscalPoam:
    @pytest.mark.happy
    def test_oscal_poam_converts_to_amendments(self, admin_client: httpx.Client) -> None:
        # Translate a committed OSCAL POA&M into HDF Amendments. This used to
        # chain off poam_from_hdf, but hdf-cli 3.2.0 removed hdf -> oscal-poam
        # (#648), so we feed a committed OSCAL POAM fixture directly. Still
        # proves the round-trip the controller guards with `hdf amend verify`.
        response = _post_raw(admin_client, AMENDMENTS_PATH, _oscal_poam_bytes())
        assert response.status_code == 200, response.text
        assert isinstance(response.json(), dict)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            _post_raw(anon_client, AMENDMENTS_PATH, b"{}"), expected_status=401
        )

    @pytest.mark.validation
    def test_garbage_payload_returns_422(self, admin_client: httpx.Client) -> None:
        response = _post_raw(admin_client, AMENDMENTS_PATH, b'{"not": "an oscal poam"}')
        assert_error_envelope(response, expected_status=422)


class TestBoundaryEnrichment:
    """`?authorization_boundary_id=N` merges Evidence into OSCAL back-matter
    and requires `evidence.read` on the boundary."""

    @pytest.fixture
    def boundary(self, admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
        suffix = uuid.uuid4().hex[:8]
        payload = {
            "authorization_boundary": {
                "name": f"phase2-xlate-{suffix}",
                "description": "Phase 2 translation enrichment parent",
            }
        }
        response = admin_client.post(BOUNDARIES_PATH, json=payload)
        assert response.status_code in (200, 201), response.text
        body = response.json().get("data") or response.json()
        try:
            yield body
        finally:
            admin_client.delete(f"{BOUNDARIES_PATH}/{body['id']}")

    @pytest.mark.happy
    def test_admin_with_boundary_enriches(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = _post_raw(
            admin_client, f"{SAR_PATH}?authorization_boundary_id={boundary['id']}", _hdf_bytes()
        )
        assert response.status_code == 200, response.text
        assert "assessment-results" in response.json()

    @pytest.mark.authz
    def test_non_privileged_user_forbidden(
        self, admin_client: httpx.Client, user_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        # A user without evidence.read may not request boundary enrichment.
        response = _post_raw(
            user_client, f"{SAR_PATH}?authorization_boundary_id={boundary['id']}", _hdf_bytes()
        )
        assert response.status_code in (401, 403), response.text
