"""Tests for the hdf-system export (#1179).

  GET /api/v1/authorization_boundaries/:id/hdf_system

The boundary as an HDF `hdf-system` document — the document HDF results and
amendments point at through `systemRef`. Like the amendments export, the body IS
the artefact (raw JSON, not wrapped in `data`).

Run against the shipped image, where the real `hdf validate --type system`
gates every 200. The rspec suite covers the mapping in depth; this module
proves the running instance answers, validates and caches.
"""

from __future__ import annotations

import hashlib
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _hdf_triage_flow import BOUNDARIES_PATH, create_boundary, delete_boundary
from conftest import assert_error_envelope

pytestmark = [pytest.mark.boundaries, pytest.mark.phase2]


def _path(key: int | str) -> str:
    return f"{BOUNDARIES_PATH}/{key}/hdf_system"


@pytest.fixture(scope="module")
def empty_boundary(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    """A boundary with no component definition linked — it cannot be exported."""
    built = create_boundary(admin_client, "hdf-system")
    try:
        yield built
    finally:
        delete_boundary(admin_client, built)


@pytest.fixture(scope="module")
def exportable(admin_client: httpx.Client) -> tuple[dict[str, Any], httpx.Response]:
    """The first boundary on the instance that exports.

    Linking a CDEF to a boundary environment has no API of its own, so this
    reads the seeded estate rather than building one. It skips — visibly —
    when nothing on the instance has a component.
    """
    listed = admin_client.get(BOUNDARIES_PATH, params={"per_page": 100})
    assert listed.status_code == 200, listed.text
    for boundary in listed.json().get("data", []):
        response = admin_client.get(_path(boundary["id"]))
        if response.status_code == 200:
            return boundary, response
        assert response.status_code == 422, (
            f"boundary {boundary['id']} answered {response.status_code}: {response.text[:300]}"
        )
    pytest.skip("no authorization boundary on this instance has a linked component")


@pytest.mark.happy
class TestExport:
    def test_the_document_is_the_boundary(
        self, exportable: tuple[dict[str, Any], httpx.Response]
    ) -> None:
        boundary, response = exportable
        doc = response.json()

        assert "data" not in doc, "the artefact is wrapped; consumers pipe this directly"
        assert doc["systemId"] == boundary["uuid"], doc
        assert doc["identifier"] == boundary["uuid"], doc
        assert doc["identifierScheme"] == "urn:ietf:rfc:4122", doc
        assert doc["name"] == boundary["name"], doc
        assert doc["components"], "an exported document listed no components"
        assert doc["generator"]["name"] == "sparc", doc

    def test_the_uuid_address_resolves_to_the_same_document(
        self, admin_client: httpx.Client, exportable: tuple[dict[str, Any], httpx.Response]
    ) -> None:
        """The uuid form is what other documents cite as systemRef."""
        boundary, response = exportable
        by_uuid = admin_client.get(_path(boundary["uuid"]))

        assert by_uuid.status_code == 200, by_uuid.text
        assert by_uuid.content == response.content

    def test_the_etag_is_strong_and_answers_304(
        self, admin_client: httpx.Client, exportable: tuple[dict[str, Any], httpx.Response]
    ) -> None:
        boundary, response = exportable
        etag = response.headers["ETag"]

        assert not etag.startswith("W/"), etag
        assert etag == f'"{hashlib.sha256(response.content).hexdigest()}"', etag

        again = admin_client.get(_path(boundary["id"]), headers={"If-None-Match": etag})
        assert again.status_code == 304, again.text
        assert again.content == b""


@pytest.mark.validation
class TestRefusals:
    def test_a_boundary_with_no_components_is_a_422_naming_the_gap(
        self, admin_client: httpx.Client, empty_boundary: dict[str, Any]
    ) -> None:
        response = admin_client.get(_path(empty_boundary["id"]))

        assert response.status_code == 422, response.text
        assert "has no components" in response.json()["details"], response.text

    def test_an_unknown_boundary_is_a_json_404(self, admin_client: httpx.Client) -> None:
        assert_error_envelope(
            admin_client.get(_path("00000000-0000-4000-8000-000000000000")), expected_status=404
        )


# Authorization (both `authorization_boundaries.read` and `ssp.read`, on this
# boundary) is proven in both directions in
# spec/requests/api/v1/hdf_systems_spec.rb. It is not asserted here because
# SPARC_TEST_USER_TOKEN is "read-level" by contract without saying whether that
# includes those two permissions instance-wide, so a 403 here would test the
# token's provisioning rather than the gate.


@pytest.mark.auth
class TestAuthentication:
    def test_an_anonymous_caller_is_refused(
        self, anon_client: httpx.Client, empty_boundary: dict[str, Any]
    ) -> None:
        assert anon_client.get(_path(empty_boundary["id"])).status_code == 401
