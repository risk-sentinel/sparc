"""Tests for a boundary's FedRAMP significant changes (#1390).

    GET  /api/v1/authorization_boundaries/:id/fedramp_significant_changes
    POST /api/v1/authorization_boundaries/:id/fedramp_significant_changes
    GET  /api/v1/authorization_boundaries/:id/fedramp_significant_changes/:change_id
    PUT  /api/v1/authorization_boundaries/:id/fedramp_significant_changes/:change_id
    GET  .../fedramp_significant_changes/:change_id/notification
    POST .../fedramp_significant_changes/:change_id/notices

Each change evaluated is recorded; Adaptive and Transformative changes get
their notice deadlines and a Significant Change Notification, which is fed
back through POST /api/v1/document_validations and must be accepted. Each
test works on a throwaway phase2 boundary with FedRAMP on and an overview
address, removed afterwards.
"""

from __future__ import annotations

import datetime
import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

# api-inventory: covers fedramp_significant_changes#record_notice

pytestmark = [pytest.mark.exchange, pytest.mark.phase2]

BOUNDARIES = "/api/v1/authorization_boundaries"
PROFILE = {"certification_type": "20x", "certification_path": "Program", "certification_class": "B"}


@pytest.fixture
def boundary(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(
        BOUNDARIES,
        json={
            "authorization_boundary": {
                "name": f"phase2-boundary-fedramp-scn-{uuid.uuid4().hex[:8]}",
                "description": "Created by the FedRAMP significant change API tests (#1390)",
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
    return f"{BOUNDARIES}/{boundary['id']}/fedramp_significant_changes{tail}"


def _record(client: httpx.Client, boundary: dict[str, Any], **fields: Any) -> dict[str, Any]:
    response = client.post(_path(boundary), json={"fedramp_significant_change": fields})
    assert response.status_code == 201, response.text
    return response.json()["data"]


class TestFedrampSignificantChanges:
    @pytest.mark.happy
    def test_records_lists_and_updates_a_change_with_its_deadlines(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        change = _record(
            admin_client,
            boundary,
            change_type="Transformative",
            description="Move to a new region",
            plan_summary="Phased",
            planned_start="2027-01-15",
        )
        first = change["deadlines"][0]
        assert first["rule_id"] == "SCN-TRF-NIP"
        assert first["due_on"] == "2026-12-02"  # 30 federal business days before
        updated = admin_client.put(
            _path(boundary, f"/{change['uuid']}"),
            json={"fedramp_significant_change": {"reason": "Capacity"}},
        )
        assert updated.status_code == 200, updated.text
        shown = admin_client.get(_path(boundary, f"/{change['uuid']}")).json()["data"]
        assert shown["reason"] == "Capacity"
        assert shown["description"] == "Move to a new region"
        listed = admin_client.get(_path(boundary)).json()
        assert [c["uuid"] for c in listed["data"]] == [change["uuid"]]

    @pytest.mark.happy
    def test_notification_ingests_and_a_notice_is_recorded(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        change = _record(
            admin_client,
            boundary,
            change_type="Adaptive",
            description="Dashboard",
            finished_on="2026-11-20",
        )
        notification = admin_client.get(_path(boundary, f"/{change['uuid']}/notification"))
        assert notification.status_code == 200, notification.text
        assert notification.json()["changeType"] == "Adaptive"
        checked = admin_client.post(
            "/api/v1/document_validations",
            content=notification.content,
            headers={"Content-Type": "application/json"},
        )
        assert checked.status_code == 200, checked.text
        assert checked.json()["valid"] is True, checked.json()["errors"]
        assert checked.json()["document_type"] == "significant-change-notifications"

        sent = admin_client.post(
            _path(boundary, f"/{change['uuid']}/notices"),
            json={
                "notice": {"stage": "after_finish", "sent_on": datetime.date.today().isoformat()}
            },
        )
        assert sent.status_code == 201, sent.text
        assert sent.json()["data"]["notices"][0]["rule_id"] == "SCN-ADP-NTF"

    @pytest.mark.validation
    def test_routine_change_has_no_notification(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        change = _record(admin_client, boundary, change_type="Routine", description="Patching")
        assert change["deadlines"] == []
        response = admin_client.get(_path(boundary, f"/{change['uuid']}/notification"))
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_unknown_type_is_422(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            _path(boundary),
            json={"fedramp_significant_change": {"change_type": "Major", "description": "x"}},
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.auth
    def test_requires_a_token(self, anon_client: httpx.Client, boundary: dict[str, Any]) -> None:
        assert_error_envelope(anon_client.get(_path(boundary)), expected_status=401)
