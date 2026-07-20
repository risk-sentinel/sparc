"""Tests for the HDF <-> OSCAL translation bridge (#449, #610).

Four stateless endpoints, all POST under /api/v1/:
  - oscal/sar_from_hdf              HDF results    -> OSCAL SAR
  - oscal/poam_from_hdf             HDF results    -> OSCAL POAM (501 on 3.2.0)
  - oscal/poam_from_amendments      HDF Amendments -> OSCAL POAM (#663)
  - hdf/amendments_from_oscal_poam  OSCAL POAM     -> HDF Amendments

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
POAM_FROM_AMENDMENTS_PATH = "/api/v1/oscal/poam_from_amendments"
AMENDMENTS_PATH = "/api/v1/hdf/amendments_from_oscal_poam"
BOUNDARIES_PATH = "/api/v1/authorization_boundaries"

_HDF_FIXTURE = Path(__file__).parent / "fixtures" / "sample.hdf.json"
_OSCAL_POAM_FIXTURE = Path(__file__).parent / "fixtures" / "sample.oscal-poam.json"
_HDF_AMENDMENTS_FIXTURE = Path(__file__).parent / "fixtures" / "sample.hdf-amendments.json"


def _hdf_bytes() -> bytes:
    return _HDF_FIXTURE.read_bytes()


def _oscal_poam_bytes() -> bytes:
    return _OSCAL_POAM_FIXTURE.read_bytes()


def _hdf_amendments_bytes() -> bytes:
    return _HDF_AMENDMENTS_FIXTURE.read_bytes()


def _post_raw(client: httpx.Client, path: str, body: bytes) -> httpx.Response:
    return client.post(
        path, content=body, headers={"Content-Type": "application/json"}
    )


class TestSarFromHdf:
    @pytest.mark.happy
    def test_raw_body_returns_oscal_sar(self, admin_client: httpx.Client) -> None:
        # sample.hdf.json is standard scanner HDF with NO top-level `baselines`
        # field. hdf-cli 3.2.0 rejected that shape ("missing baselines field"),
        # which #648 worked around by injecting an empty array. Upstream fixed
        # it in 3.3.1 and #764 removed the injection, so a 200 here now proves
        # the UPSTREAM fix holds on the pinned binary — not that SPARC is
        # mutating the input. Keep the fixture baseline-less or the assertion
        # stops testing anything.
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


class TestPoamFromAmendments:
    """hdf-cli 3.2.0 replaced the direct hdf->oscal-poam path with
    hdf-amendments->oscal-poam (#663, upstream mitre/hdf-libs#104). This is the
    supported way to produce an OSCAL POA&M. Note the converter is permissive
    (it accepts any JSON object), so there is no garbage->422 case here."""

    @pytest.mark.happy
    def test_raw_body_returns_oscal_poam(self, admin_client: httpx.Client) -> None:
        response = _post_raw(admin_client, POAM_FROM_AMENDMENTS_PATH, _hdf_amendments_bytes())
        assert response.status_code == 200, response.text
        assert "plan-of-action-and-milestones" in response.json(), response.text

    @pytest.mark.happy
    def test_multipart_upload_returns_oscal_poam(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(
            POAM_FROM_AMENDMENTS_PATH,
            files={
                "file": (
                    "sample.hdf-amendments.json",
                    _hdf_amendments_bytes(),
                    "application/json",
                )
            },
        )
        assert response.status_code == 200, response.text
        assert "plan-of-action-and-milestones" in response.json()

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            _post_raw(anon_client, POAM_FROM_AMENDMENTS_PATH, _hdf_amendments_bytes()),
            expected_status=401,
        )

    @pytest.mark.validation
    def test_no_payload_returns_400(self, admin_client: httpx.Client) -> None:
        assert_error_envelope(admin_client.post(POAM_FROM_AMENDMENTS_PATH), expected_status=400)


class TestAmendmentsFromOscalPoam:
    @pytest.mark.happy
    def test_oscal_poam_converts_to_amendments(self, admin_client: httpx.Client) -> None:
        # Translate a committed OSCAL POA&M into HDF Amendments. This used to
        # chain off poam_from_hdf, but hdf-cli 3.2.0 removed hdf -> oscal-poam
        # (#648), so we feed a committed OSCAL POAM fixture directly. Still
        # proves the round-trip the controller guards with `hdf amend verify`.
        response = _post_raw(admin_client, AMENDMENTS_PATH, _oscal_poam_bytes())
        assert response.status_code == 200, response.text
        body = response.json()
        assert isinstance(body, dict)

        # #764: the converter must carry the SOURCE deadline through, not a
        # fabricated one. hdf-cli 3.3.2 and earlier emitted conversion
        # wall-clock + 1 year here; 3.4.1 extracts risks[].deadline. Asserting
        # the exact value is what would catch a regression back to invention.
        overrides = body.get("overrides") or []
        assert overrides, f"expected at least one override, got: {body}"
        assert overrides[0]["expiresAt"] == "2027-06-30T00:00:00Z", (
            "expiresAt must equal the fixture's risks[].deadline, not a "
            f"generated date: {overrides[0].get('expiresAt')}"
        )

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            _post_raw(anon_client, AMENDMENTS_PATH, b"{}"), expected_status=401
        )

    @pytest.mark.validation
    def test_garbage_payload_returns_422(self, admin_client: httpx.Client) -> None:
        response = _post_raw(admin_client, AMENDMENTS_PATH, b'{"not": "an oscal poam"}')
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_poam_without_deadline_returns_actionable_422(
        self, admin_client: httpx.Client
    ) -> None:
        """#764: a POA&M with no risks[].deadline must fail with a specific message.

        hdf-cli 3.4.1 stopped fabricating expiry dates and fails loud instead.
        That is a correction — 3.3.2 exited 0 by inventing conversion-time + 1
        year — but it is a NEW exit-1 path, and the fix is entirely in the
        caller's input. The response must say what to add rather than reading
        as a generic bridge failure.
        """
        poam = json.loads(_oscal_poam_bytes())
        # Strip the deadline the fixture carries, leave everything else intact.
        for risk in poam["plan-of-action-and-milestones"].get("risks", []):
            risk.pop("deadline", None)

        response = _post_raw(admin_client, AMENDMENTS_PATH, json.dumps(poam).encode())
        assert response.status_code == 422, response.text
        body = response.json()
        assert body["error"] == "POA&M is missing a remediation deadline", body
        assert "risks[].deadline" in body.get("note", ""), body


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
