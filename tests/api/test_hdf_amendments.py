"""Tests for the HDF Amendments export (#447), swept for #995.

  GET /api/v1/authorization_boundaries/:id/hdf_amendments[?verify=false]

Translation OUT: the artefact a tenant's CI pulls to apply SPARC's triage
decisions to its own scan results, via `hdf amend apply`. The response body IS
the artefact — raw Amendments JSON, deliberately not wrapped in `data`, so it
can be piped straight to the CLI. That is the opposite of #1036, where an
unwrapped body is an inconsistency; here it is the point.

This module exists because of #1037. `verify` defaults to true, and in that
default mode the endpoint returned 422 for EVERY boundary: the generated JSON
was handed to `hdf amend verify` as a filename, because `HdfRunner` treats a
String argument as a path. The unit spec could not see it — it stubs the runner
and asserted `with(kind_of(String))`, which was the defect written down as an
expectation. Only a request against a running instance with the real CLI behind
it catches this, which is why the coverage belongs here as well as in rspec.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _hdf_triage_flow import BOUNDARIES_PATH, delete_boundary, triaged_boundary
from conftest import assert_error_envelope

pytestmark = [pytest.mark.findings, pytest.mark.phase2]


def _path(boundary_id: int) -> str:
    return f"{BOUNDARIES_PATH}/{boundary_id}/hdf_amendments"


@pytest.fixture(scope="module")
def triaged(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    built = triaged_boundary(admin_client, "hdf-amendments")
    try:
        yield built
    finally:
        delete_boundary(admin_client, built["boundary"])


@pytest.mark.happy
class TestExport:
    def test_the_default_mode_verifies_and_returns_a_document(
        self, admin_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        """#1037 — this is the regression test.

        No `verify` parameter, so verification runs, which means the emitted
        document goes through the real `hdf amend verify`. Before the fix this
        was a 422 for every boundary on every instance.
        """
        response = admin_client.get(_path(triaged["boundary"]["id"]))

        assert response.status_code == 200, response.text
        doc = response.json()
        assert doc["amendmentId"], doc
        assert doc["version"], doc

    def test_the_body_is_the_artefact_not_a_wrapper(
        self, admin_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        """Deliberately unwrapped so it can be piped to `hdf amend apply`.

        Pinned because it is the exception to this API's `data` convention, and
        an integrator needs to know which endpoints are artefact downloads.
        """
        doc = admin_client.get(_path(triaged["boundary"]["id"])).json()

        assert "data" not in doc, "the artefact is now wrapped; CI consumers pipe this directly"
        assert set(doc) >= {"amendmentId", "name", "version", "generator", "overrides"}, doc

    def test_the_triaged_disposition_appears_as_an_override(
        self, admin_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        """The reason the endpoint exists. An amendments document that verifies
        but carries none of the decisions made is a valid, useless file."""
        doc = admin_client.get(_path(triaged["boundary"]["id"])).json()

        overrides = doc["overrides"]
        assert overrides, "a boundary with a triaged finding exported no overrides"

        control_id = triaged["finding"]["control_id"]
        override = next((o for o in overrides if o.get("requirementId") == control_id), None)
        assert override, f"no override for {control_id}: {overrides}"

        # The decision itself has to survive the translation, not just the id.
        assert override["type"] == "inherited", override
        assert override["reason"] == "#995 HDF triage sweep", override
        assert override["appliedBy"]["identifier"], override
        # `inherited` is one of FindingDisposition::NOT_APPLICABLE_KINDS, and the
        # export maps kind -> HDF status. That mapping is the whole translation:
        # a failing finding the tenant should stop being failed by.
        assert override["status"] == "notApplicable", (
            f"inherited mapped to {override['status']!r}, not notApplicable"
        )

    def test_re_export_is_byte_identical(
        self, admin_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        """The amendmentId is content-seeded so a re-export is cache-pinnable.
        A document whose id changed on every call could not be diffed by a
        consumer to see whether anything had actually been re-triaged."""
        first = admin_client.get(_path(triaged["boundary"]["id"])).json()
        second = admin_client.get(_path(triaged["boundary"]["id"])).json()

        assert first["amendmentId"] == second["amendmentId"], (
            "the amendmentId moved between two identical exports"
        )
        assert first == second


@pytest.mark.happy
class TestVerifyToggle:
    def test_verification_can_be_skipped(
        self, admin_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        """`verify=false` is the escape hatch for an instance whose hdf-cli is
        unavailable. It must return the same document, not a different one."""
        verified = admin_client.get(_path(triaged["boundary"]["id"])).json()
        unverified = admin_client.get(_path(triaged["boundary"]["id"]), params={"verify": "false"})

        assert unverified.status_code == 200, unverified.text
        assert unverified.json() == verified, (
            "skipping verification changed the document, so the two modes do not "
            "agree about what is being exported"
        )


@pytest.mark.validation
class TestUnknownBoundary:
    def test_an_unknown_boundary_is_a_json_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(_path(0))

        assert_error_envelope(response, expected_status=404)


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
