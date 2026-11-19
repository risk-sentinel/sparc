"""Tests for the dispositions as an OSCAL POA&M (#1368).

  GET /api/v1/authorization_boundaries/:id/disposition_poam

SPARC exports the dispositions as HDF amendments, the image's hdf converts them
to an OSCAL POA&M, and SPARC completes each risk with the NIST OSCAL v1.2.3
vocabulary the disposition records: risk status, risk prop, response type and
lifecycle, a typed risk-log entry, and likelihood / impact / risk facets on
NIST SP 800-30's scale. Only a request against a running instance runs the real
converter; rspec stubs it where CI has no hdf.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _hdf_triage_flow import BOUNDARIES_PATH, NIST_POAM_FIELDS, delete_boundary, triaged_boundary
from conftest import assert_error_envelope

pytestmark = [pytest.mark.findings, pytest.mark.phase2]

NIST_FACETS = "http://csrc.nist.gov/ns/oscal"


def _path(boundary_id: int) -> str:
    return f"{BOUNDARIES_PATH}/{boundary_id}/disposition_poam"


@pytest.fixture(scope="module")
def triaged(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    built = triaged_boundary(admin_client, "disposition-poam")
    try:
        yield built
    finally:
        delete_boundary(admin_client, built["boundary"])


def _risk_for(doc: dict[str, Any], control_id: str) -> dict[str, Any]:
    risks = doc["plan-of-action-and-milestones"]["risks"]
    risk = next(
        (r for r in risks if any(p.get("value") == control_id for p in r.get("props", []))), None
    )
    assert risk, f"no risk for {control_id}: {[r.get('title') for r in risks]}"
    return risk


@pytest.mark.happy
class TestExport:
    def test_returns_a_poam_with_the_nist_risk_the_disposition_records(
        self, admin_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        response = admin_client.get(_path(triaged["boundary"]["id"]))
        assert response.status_code == 200, response.text
        risk = _risk_for(response.json(), triaged["finding"]["control_id"])

        assert risk["status"] == NIST_POAM_FIELDS["nist_risk_status"], risk["status"]
        assert {"name": "accepted", "value": "yes"} in risk["props"], risk["props"]

    def test_rates_likelihood_impact_and_derived_risk_on_sp_800_30s_scale(
        self, admin_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        risk = _risk_for(admin_client.get(_path(triaged["boundary"]["id"])).json(),
                         triaged["finding"]["control_id"])
        facets = {f["name"]: f for f in risk["characterizations"][0]["facets"]}

        # moderate likelihood x high impact is moderate risk (SP 800-30 Table I-2).
        assert facets["likelihood"]["value"] == "moderate"
        assert facets["impact"]["value"] == "high"
        assert facets["risk"]["value"] == "moderate"
        assert all(f["system"] == NIST_FACETS for f in facets.values())
        assert all(f["props"] == [{"name": "state", "value": "initial"}] for f in facets.values())

    def test_an_inherited_finding_is_a_shared_response(
        self, admin_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        risk = _risk_for(admin_client.get(_path(triaged["boundary"]["id"])).json(),
                         triaged["finding"]["control_id"])
        response_ = risk["remediations"][0]

        assert response_["lifecycle"] == NIST_POAM_FIELDS["nist_response_lifecycle"]
        assert response_["props"] == [{"name": "type", "value": "share"}], response_


@pytest.mark.authz
class TestRefusal:
    def test_a_caller_without_evidence_read_is_refused(
        self, user_client: httpx.Client, triaged: dict[str, Any]
    ) -> None:
        response = user_client.get(_path(triaged["boundary"]["id"]))
        assert_error_envelope(response, expected_status=403)
