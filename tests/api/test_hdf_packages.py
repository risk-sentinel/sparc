"""Tests for the signed HDF package download (#809 goal 2), swept for #995.

  GET /api/v1/authorization_boundaries/:id/hdf_package

The archival bundle: amendments + findings + dispositions for a boundary, signed
so a downstream consumer can prove it is the one SPARC produced. NIST AU-10.

The property that matters is not that a signature is present but that it covers
what the caller is being shown — the response carries BOTH a structured
`payload` and an `encoded_payload`, and a signature over the encoded form is
worthless to anyone reading the structured one unless the two agree.
"""

from __future__ import annotations

import base64
import json
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _hdf_triage_flow import BOUNDARIES_PATH, delete_boundary, triaged_boundary
from conftest import assert_error_envelope

pytestmark = [pytest.mark.findings, pytest.mark.phase2]


def _path(boundary_id: int) -> str:
    return f"{BOUNDARIES_PATH}/{boundary_id}/hdf_package"


@pytest.fixture(scope="module")
def triaged(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    built = triaged_boundary(admin_client, "hdf-package")
    try:
        yield built
    finally:
        delete_boundary(admin_client, built["boundary"])


@pytest.fixture(scope="module")
def package(admin_client: httpx.Client, triaged: dict[str, Any]) -> dict[str, Any]:
    response = admin_client.get(_path(triaged["boundary"]["id"]))
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.happy
class TestPackage:
    def test_returns_a_signed_bundle(self, package: dict[str, Any]) -> None:
        assert set(package) >= {"payload", "encoded_payload", "signature", "algorithm"}, package
        assert package["signature"], "the bundle carries no signature"
        assert package["algorithm"], "the bundle does not say how it was signed"

    def test_the_signature_covers_what_the_caller_is_shown(self, package: dict[str, Any]) -> None:
        """`encoded_payload` is what the signature is over; `payload` is what a
        reader looks at. If they can disagree, the signature guarantees nothing
        about the content anyone actually consumes.
        """
        raw = package["encoded_payload"]
        # URL-SAFE base64, and unpadded. Worth stating because decoding it with
        # the standard alphabet works MOST of the time and then fails on the
        # payloads that happen to contain a "-": Python's b64decode silently
        # discards out-of-alphabet characters, so the length stops being a
        # multiple of four and it raises "Incorrect padding". A consumer would
        # read that as a corrupt bundle rather than as the wrong decoder.
        decoded = json.loads(base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)))

        assert decoded == package["payload"], (
            "encoded_payload and payload differ, so the signature does not cover "
            "the structured body the response also returns"
        )
        assert not set(raw) & set("+/"), (
            "encoded_payload switched to the standard base64 alphabet; every "
            "consumer decoding it as url-safe now gets corrupt bytes"
        )

    def test_the_bundle_carries_the_triaged_material(
        self, package: dict[str, Any], triaged: dict[str, Any]
    ) -> None:
        """An archive that verifies but contains none of the boundary's work is
        a valid, useless file."""
        payload = package["payload"]
        assert set(payload) >= {"format", "boundary", "amendments", "findings", "dispositions"}

        control_id = triaged["finding"]["control_id"]
        assert any(f.get("control_id") == control_id for f in payload["findings"]), (
            f"the ingested finding {control_id} is not in the package"
        )
        assert any(d.get("control_id") == control_id for d in payload["dispositions"]), (
            f"the triaged disposition for {control_id} is not in the package"
        )

    def test_it_names_the_boundary_it_describes(
        self, package: dict[str, Any], triaged: dict[str, Any]
    ) -> None:
        """A downstream archive of several boundaries has to be able to tell
        them apart."""
        boundary = package["payload"]["boundary"]
        expected = triaged["boundary"]

        assert expected["name"] in json.dumps(boundary), (
            f"the package does not name {expected['name']}: {boundary}"
        )


@pytest.mark.validation
class TestUnknownBoundary:
    def test_an_unknown_boundary_is_a_json_404(self, admin_client: httpx.Client) -> None:
        assert_error_envelope(admin_client.get(_path(0)), expected_status=404)


@pytest.mark.authz
class TestAuthorization:
    def test_a_non_admin_without_evidence_read_is_refused(
        self, user_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        response = user_client.get(_path(triaged["boundary"]["id"]))

        assert response.status_code == 403, response.text


@pytest.mark.auth
class TestAuthentication:
    def test_an_anonymous_caller_is_refused(
        self, anon_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        assert anon_client.get(_path(triaged["boundary"]["id"])).status_code == 401
