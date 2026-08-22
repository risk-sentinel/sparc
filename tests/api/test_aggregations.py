"""Tests for finding aggregation into a boundary's documents (#809), for #995.

  POST /api/v1/authorization_boundaries/:id/aggregate[?async=true]

Rolls a boundary's scanner findings and triage dispositions into its SSP / SAP /
SAR / POA&M documents. Two modes: synchronous by default, returning the
per-document summary, or `async=true` to enqueue `AggregateFindingsJob` and
return 202.

LIMITATION, stated rather than papered over: the per-document counts are
exercised for SHAPE, not for value. Making them non-zero needs a boundary whose
documents carry controls matching the ingested findings' control ids — an SSP
populated from a profile baseline, and an HDF payload whose control ids are real
catalog controls. The fixture here ingests `sample.hdf.json`, whose control id
is `SPARC-AC-3` and matches no catalog control, so every count is legitimately
0. A test that asserted those zeros would be asserting that nothing happened.

What IS asserted is what can be told apart without that setup: that the two
modes are genuinely different, that the summary names every document type, and
that the endpoint refuses the callers it should. A value-level check belongs
with the profile-populated SSP fixture and is not faked here.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _hdf_triage_flow import BOUNDARIES_PATH, delete_boundary, triaged_boundary
from conftest import assert_error_envelope

pytestmark = [pytest.mark.findings, pytest.mark.phase2]

DOCUMENT_TYPES = ("ssp", "sar", "sap", "poam")


def _path(boundary_id: int) -> str:
    return f"{BOUNDARIES_PATH}/{boundary_id}/aggregate"


@pytest.fixture(scope="module")
def triaged(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    built = triaged_boundary(admin_client, "aggregate")
    try:
        yield built
    finally:
        delete_boundary(admin_client, built["boundary"])


@pytest.mark.happy
class TestSynchronousMode:
    def test_reports_a_summary_naming_every_document_type(
        self, admin_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        response = admin_client.post(_path(triaged["boundary"]["id"]))

        assert response.status_code == 200, response.text
        data = response.json()["data"]
        assert data["status"] == "aggregated", data
        for kind in DOCUMENT_TYPES:
            assert kind in data, f"the summary does not mention {kind}: {data}"
            assert isinstance(data[kind], int), f"{kind} is not a count: {data[kind]!r}"

    def test_it_is_repeatable(self, admin_client: httpx.Client, triaged: dict[str, Any]) -> None:
        """Aggregation is re-run whenever triage changes, so running it twice
        must not error or report a different shape."""
        first = admin_client.post(_path(triaged["boundary"]["id"]))
        second = admin_client.post(_path(triaged["boundary"]["id"]))

        assert first.status_code == 200, first.text
        assert second.status_code == 200, second.text
        assert set(first.json()["data"]) == set(second.json()["data"])


@pytest.mark.happy
class TestAsynchronousMode:
    def test_enqueues_instead_of_running_and_says_so(
        self, admin_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        """The two modes must be distinguishable by more than a status code, or
        a caller cannot tell whether the work is done or merely scheduled."""
        response = admin_client.post(_path(triaged["boundary"]["id"]), params={"async": "true"})

        assert response.status_code == 202, response.text
        data = response.json()["data"]
        assert data["status"] == "enqueued", data
        assert data["authorization_boundary_id"] == triaged["boundary"]["id"], data

    def test_the_async_answer_carries_no_completed_summary(
        self, admin_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        """Nothing has been aggregated yet, so reporting per-document counts
        would be reporting work that has not happened."""
        data = admin_client.post(_path(triaged["boundary"]["id"]), params={"async": "true"}).json()[
            "data"
        ]

        present = [k for k in DOCUMENT_TYPES if k in data]
        assert not present, f"the enqueued response already claims results for {present}"


@pytest.mark.validation
class TestUnknownBoundary:
    def test_an_unknown_boundary_is_a_json_404(self, admin_client: httpx.Client) -> None:
        assert_error_envelope(admin_client.post(_path(0)), expected_status=404)


@pytest.mark.authz
class TestAuthorization:
    def test_a_non_admin_without_evidence_write_is_refused(
        self, user_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        response = user_client.post(_path(triaged["boundary"]["id"]))

        assert response.status_code == 403, response.text


@pytest.mark.auth
class TestAuthentication:
    def test_an_anonymous_caller_is_refused(
        self, anon_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        assert anon_client.post(_path(triaged["boundary"]["id"])).status_code == 401
