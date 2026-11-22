"""Tests for a boundary's FedRAMP incidents (#1390).

    GET  /api/v1/authorization_boundaries/:id/fedramp_incidents
    POST /api/v1/authorization_boundaries/:id/fedramp_incidents
    GET  /api/v1/authorization_boundaries/:id/fedramp_incidents/:incident_id
    PUT  /api/v1/authorization_boundaries/:id/fedramp_incidents/:incident_id
    GET  .../fedramp_incidents/:incident_id/report?type=Initial|Ongoing|Final
    POST .../fedramp_incidents/:incident_id/reports

Each incident evaluated is recorded with its report deadlines (by class and
N-rating); each report is fed back through POST /api/v1/document_validations
and must be accepted. Each test works on a throwaway phase2 boundary with
FedRAMP on, Class C, and an overview address, removed afterwards.
"""

from __future__ import annotations

import datetime
import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

# api-inventory: covers fedramp_incidents#record_report

pytestmark = [pytest.mark.exchange, pytest.mark.phase2]

BOUNDARIES = "/api/v1/authorization_boundaries"
PROFILE = {"certification_type": "20x", "certification_path": "Program", "certification_class": "C"}


@pytest.fixture
def boundary(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(
        BOUNDARIES,
        json={
            "authorization_boundary": {
                "name": f"phase2-boundary-fedramp-iec-{uuid.uuid4().hex[:8]}",
                "description": "Created by the FedRAMP incident API contract tests (#1390)",
                "fedramp_enabled": True,
                "fedramp_package": PROFILE,
                "fedramp_package_overview_uri": "https://provider.example/cpo.json",
            }
        },
    )
    assert response.status_code in (200, 201), response.text
    record = response.json().get("data") or response.json()
    try:
        yield record
    finally:
        admin_client.delete(f"{BOUNDARIES}/{record['id']}")


def _path(boundary: dict[str, Any], tail: str = "") -> str:
    return f"{BOUNDARIES}/{boundary['id']}/fedramp_incidents{tail}"


def _now() -> str:
    return (
        datetime.datetime.now(datetime.UTC)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


class TestFedrampIncidents:
    @pytest.mark.happy
    def test_records_an_incident_with_its_deadlines_and_updates_it(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        created = admin_client.post(
            _path(boundary),
            json={
                "fedramp_incident": {
                    "tracking_id": "INC-1",
                    "evaluation_completed_at": _now(),
                    "current_rating": 3,
                    "affected_agencies": ["Example Agency"],
                }
            },
        )
        assert created.status_code == 201, created.text
        incident = created.json()["data"]
        initial = incident["deadlines"][0]
        assert initial["rule_id"] == "IEC-CSO-IIR"
        assert initial["force"] == "MUST"
        assert initial["timeframe"] == ["hours", 1]  # Class C, N3

        updated = admin_client.put(
            _path(boundary, f"/{incident['uuid']}"),
            json={"fedramp_incident": {"current_rating": 1}},
        )
        assert updated.status_code == 200, updated.text
        shown = admin_client.get(_path(boundary, f"/{incident['uuid']}")).json()["data"]
        assert [r["rating"] for r in shown["ratings"]] == [3, 1]
        assert [i["uuid"] for i in admin_client.get(_path(boundary)).json()["data"]] == [
            incident["uuid"]
        ]

    @pytest.mark.happy
    def test_report_ingests_and_a_report_sent_is_recorded(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        incident = admin_client.post(
            _path(boundary),
            json={"fedramp_incident": {"tracking_id": "INC-2", "description": "Phishing"}},
        ).json()["data"]
        report = admin_client.get(
            _path(boundary, f"/{incident['uuid']}/report"), params={"type": "Initial"}
        )
        assert report.status_code == 200, report.text
        checked = admin_client.post(
            "/api/v1/document_validations",
            content=report.content,
            headers={"Content-Type": "application/json"},
        )
        assert checked.status_code == 200, checked.text
        assert checked.json()["valid"] is True, checked.json()["errors"]
        assert checked.json()["document_type"] == "incident-report"

        sent = admin_client.post(
            _path(boundary, f"/{incident['uuid']}/reports"),
            json={"report": {"report_type": "Initial", "sent_at": _now()}},
        )
        assert sent.status_code == 201, sent.text
        assert sent.json()["data"]["reports"][0]["report_type"] == "Initial"

    @pytest.mark.validation
    def test_final_report_needs_the_resolution(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        incident = admin_client.post(
            _path(boundary), json={"fedramp_incident": {"tracking_id": "INC-3"}}
        ).json()["data"]
        response = admin_client.get(
            _path(boundary, f"/{incident['uuid']}/report"), params={"type": "Final"}
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.auth
    def test_requires_a_token(self, anon_client: httpx.Client, boundary: dict[str, Any]) -> None:
        assert_error_envelope(anon_client.get(_path(boundary)), expected_status=401)
