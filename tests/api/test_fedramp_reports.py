"""Tests for a boundary's FedRAMP vulnerability reports (#1354, #1384, #1390).

    /api/v1/authorization_boundaries/:id/fedramp/vulnerability_detail_report
    /api/v1/authorization_boundaries/:id/fedramp/accepted_vulnerability_info
    /api/v1/authorization_boundaries/:id/fedramp/historical_ver_activity

All three name the boundary's FedRAMP Certification Package Overview
address, and a boundary without one is refused with a 422 naming the
setting. The boundary API does not set that address, so these tests cover the
refusals and the exchange index's silence about reports it cannot build; the
reports' content, and the 502 when SPARC's own report fails validation, are
covered by the request and service specs
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
