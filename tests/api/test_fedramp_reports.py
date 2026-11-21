"""Tests for a boundary's FedRAMP reports (#1354, #1384, #1390).

    /api/v1/authorization_boundaries/:id/fedramp/vulnerability_detail_report
    /api/v1/authorization_boundaries/:id/fedramp/accepted_vulnerability_info
    /api/v1/authorization_boundaries/:id/fedramp/historical_ver_activity
    /api/v1/authorization_boundaries/:id/fedramp/certification_package_overview

The three vulnerability reports name the boundary's FedRAMP Certification
Package Overview address, and a boundary without one is refused with a 422
naming the setting. The overview is written from the boundary's FedRAMP
fields, set through the boundary API, and is refused with a 422 listing what
is missing until they are complete. A complete overview is fed back through
POST /api/v1/document_validations, which must accept it: SPARC's own output
ingests. The reports' content, and the 502 when SPARC's own report fails
validation, are covered by the request and service specs
(spec/requests/api/v1/fedramp_reports_spec.rb,
spec/services/fedramp_vulnerability_report_service_spec.rb).

Each test works on a throwaway phase2 boundary, removed afterwards.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.exchange, pytest.mark.phase2]

BOUNDARIES = "/api/v1/authorization_boundaries"
REPORTS = ("vulnerability_detail_report", "accepted_vulnerability_info", "historical_ver_activity")


@pytest.fixture
def boundary(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(
        BOUNDARIES,
        json={
            "authorization_boundary": {
                "name": f"phase2-boundary-fedramp-{uuid.uuid4().hex[:8]}",
                "description": "Created by the FedRAMP report API contract tests (#1354)",
            }
        },
    )
    assert response.status_code in (200, 201), response.text
    record = response.json().get("data") or response.json()
    try:
        yield record
    finally:
        admin_client.delete(f"{BOUNDARIES}/{record['id']}")


def _path(boundary: dict[str, Any], report: str) -> str:
    return f"{BOUNDARIES}/{boundary['id']}/fedramp/{report}"


class TestFedrampReports:
    @pytest.mark.validation
    @pytest.mark.parametrize("report", REPORTS)
    def test_boundary_without_package_overview_is_422(
        self, admin_client: httpx.Client, boundary: dict[str, Any], report: str
    ) -> None:
        response = admin_client.get(_path(boundary, report))
        assert_error_envelope(response, expected_status=422)
        assert "fedramp_package_overview_uri" in response.json()["error"]

    @pytest.mark.validation
    @pytest.mark.parametrize("report", REPORTS)
    def test_unreadable_period_is_422(
        self, admin_client: httpx.Client, boundary: dict[str, Any], report: str
    ) -> None:
        response = admin_client.get(_path(boundary, report), params={"from": "last week"})
        assert_error_envelope(response, expected_status=422)
        assert "ISO 8601" in response.json()["error"]

    @pytest.mark.auth
    @pytest.mark.parametrize("report", REPORTS)
    def test_requires_a_token(
        self, anon_client: httpx.Client, boundary: dict[str, Any], report: str
    ) -> None:
        assert_error_envelope(anon_client.get(_path(boundary, report)), expected_status=401)

    @pytest.mark.happy
    def test_exchange_index_lists_no_report_it_cannot_build(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{BOUNDARIES}/{boundary['id']}/exchange_index")
        assert response.status_code == 200, response.text
        formats = [d["format"] for d in response.json()["data"]["documents"]]
        assert "fedramp" not in formats


OVERVIEW = "certification_package_overview"
OVERVIEW_FIELDS = {
    "fedramp_package": {
        "package_id": "FR2400000001",
        "provider_name": "Example Provider",
        "service_name": "Example Cloud",
        "service_acronym": "EXC",
        "service_description": "Created by the FedRAMP report API contract tests (#1390).",
        "certification_type": "20x",
        "website": "https://provider.example",
        "logo": "https://provider.example/logo.png",
        "service_types": ["SaaS"],
        "deployment_model": "Public Cloud",
    },
    "fedramp_contacts": [
        {"contact_type": "Security", "name": "Security Team", "email": "security@provider.example"},
        {"contact_type": "Sales", "name": "Sales Team", "phone": "202-555-0123"},
    ],
}


class TestFedrampPackageOverview:
    @pytest.mark.validation
    def test_incomplete_boundary_is_422_listing_what_is_missing(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.get(_path(boundary, OVERVIEW))
        assert_error_envelope(response, expected_status=422)
        assert "Missing: FedRAMP ID" in response.json()["error"]

    @pytest.mark.happy
    def test_complete_overview_is_served_and_ingests(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        saved = admin_client.patch(
            f"{BOUNDARIES}/{boundary['id']}", json={"authorization_boundary": OVERVIEW_FIELDS}
        )
        assert saved.status_code == 200, saved.text
        assert saved.json()["data"]["fedramp_package"]["service_types"] == ["SaaS"]

        response = admin_client.get(_path(boundary, OVERVIEW))
        assert response.status_code == 200, response.text
        overview = response.json()
        assert overview["serviceIdentification"]["fedRampPackageId"] == "FR2400000001"
        assert {c["contactType"] for c in overview["contactInformation"]} == {"Security", "Sales"}

        checked = admin_client.post(
            "/api/v1/document_validations",
            content=response.content,
            headers={"Content-Type": "application/json"},
        )
        assert checked.status_code == 200, checked.text
        body = checked.json()
        assert body["valid"] is True, body["errors"]
        assert body["document_type"] == "certification-package-overview"

        index = admin_client.get(f"{BOUNDARIES}/{boundary['id']}/exchange_index")
        documents = index.json()["data"]["documents"]
        types = [d["document_type"] for d in documents if d["format"] == "fedramp"]
        assert types == ["certification-package-overview"]

    @pytest.mark.validation
    def test_value_the_schema_does_not_allow_is_422(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.patch(
            f"{BOUNDARIES}/{boundary['id']}",
            json={"authorization_boundary": {"fedramp_package": {"certification_type": "Rev4"}}},
        )
        assert response.status_code == 422, response.text
        assert "Certification type must be one of" in response.text

    @pytest.mark.auth
    def test_requires_a_token(self, anon_client: httpx.Client, boundary: dict[str, Any]) -> None:
        assert_error_envelope(anon_client.get(_path(boundary, OVERVIEW)), expected_status=401)
