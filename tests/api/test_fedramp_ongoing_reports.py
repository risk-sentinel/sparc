"""Tests for a boundary's FedRAMP Ongoing Certification Reports (#1390).

    GET  /api/v1/authorization_boundaries/:id/fedramp_ongoing_reports
    GET  /api/v1/authorization_boundaries/:id/fedramp_ongoing_reports/draft
    POST /api/v1/authorization_boundaries/:id/fedramp_ongoing_reports
    GET  /api/v1/authorization_boundaries/:id/fedramp_ongoing_reports/:report_id

The report (CCM-OCR-AVL) for a period is fed back through
POST /api/v1/document_validations, which must accept it; issuing keeps it as
issued. Each test works on a throwaway phase2 boundary with FedRAMP on, an
overview address and an agency list, removed afterwards.
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
PROFILE = {"certification_type": "20x", "certification_path": "Program", "certification_class": "B"}


@pytest.fixture
def boundary(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(
        BOUNDARIES,
        json={
            "authorization_boundary": {
                "name": f"phase2-boundary-fedramp-ocr-{uuid.uuid4().hex[:8]}",
                "description": "Created by the FedRAMP ongoing report API tests (#1390)",
                "fedramp_enabled": True,
                "fedramp_package": PROFILE,
                "fedramp_package_overview_uri": "https://provider.example/cpo.json",
                "fedramp_active_agencies": ["Example Agency"],
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
    return f"{BOUNDARIES}/{boundary['id']}/fedramp_ongoing_reports{tail}"


class TestFedrampOngoingReports:
    @pytest.mark.happy
    def test_draft_ingests(self, admin_client: httpx.Client, boundary: dict[str, Any]) -> None:
        draft = admin_client.get(_path(boundary, "/draft"), params={"recommendations[]": "Use MFA"})
        assert draft.status_code == 200, draft.text
        assert draft.json()["activeAgencies"] == ["Example Agency"]
        assert draft.json()["updatedRecommendations"] == ["Use MFA"]
        checked = admin_client.post(
            "/api/v1/document_validations",
            content=draft.content,
            headers={"Content-Type": "application/json"},
        )
        assert checked.status_code == 200, checked.text
        assert checked.json()["valid"] is True, checked.json()["errors"]
        assert checked.json()["document_type"] == "ongoing-certification-report"

    @pytest.mark.happy
    def test_issues_lists_and_shows_a_report(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        issued = admin_client.post(
            _path(boundary), json={"fedramp_ongoing_report": {"recommendations": ["Use MFA"]}}
        )
        assert issued.status_code == 201, issued.text
        report = issued.json()["data"]
        listed = admin_client.get(_path(boundary)).json()
        assert [r["uuid"] for r in listed["data"]] == [report["uuid"]]
        assert listed["meta"]["next_target_date"]
        shown = admin_client.get(_path(boundary, f"/{report['uuid']}")).json()["data"]
        assert shown["document"]["updatedRecommendations"] == ["Use MFA"]
        assert shown["sha256"] == report["sha256"]

    @pytest.mark.validation
    def test_overlapping_period_is_422(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        assert admin_client.post(_path(boundary), json={}).status_code == 201
        assert_error_envelope(admin_client.post(_path(boundary), json={}), expected_status=422)

    @pytest.mark.auth
    def test_requires_a_token(self, anon_client: httpx.Client, boundary: dict[str, Any]) -> None:
        assert_error_envelope(anon_client.get(_path(boundary)), expected_status=401)
