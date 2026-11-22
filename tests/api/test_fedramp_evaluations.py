"""Tests for the FedRAMP evaluation of each vulnerability (#1354, #1384).

    GET /api/v1/authorization_boundaries/:id/fedramp_evaluations[?unevaluated=true]
    GET /api/v1/authorization_boundaries/:id/fedramp_evaluations/:control_id
    PUT /api/v1/authorization_boundaries/:id/fedramp_evaluations/:control_id

FedRAMP's rules VER-EVA-EIR, VER-EVA-ELX and VER-EVA-EPA ask the provider to
evaluate every detected vulnerability: internet-reachable, likely exploitable,
and the Potential Agency Impact N-rating (N0-N5). The evaluation is keyed by
the finding's control_id, so it outlives each scan's finding rows. PUT is an
upsert: 201 for the first evaluation, 200 after, and only the fields sent
change. Each change of N-rating is kept; a fall is a PAIN reduction.

Each test works on this module's own phase2 boundary, with one ingested
failing finding, removed afterwards with everything on it.
"""

from __future__ import annotations

import json
import uuid
from collections.abc import Iterator
from pathlib import Path
from typing import Any
from urllib.parse import quote

import httpx
import pytest

from conftest import assert_error_envelope, assert_paginated_envelope

pytestmark = [pytest.mark.findings, pytest.mark.phase2]

BOUNDARIES = "/api/v1/authorization_boundaries"
_SAMPLE_HDF = Path(__file__).parent / "fixtures" / "sample.hdf.json"


@pytest.fixture
def scanned(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    """A boundary of the test's own with one ingested failing finding, not yet evaluated.

    Per test, so the first PUT is always a create and nothing a previous test
    recorded changes what this one measures.
    """
    created = admin_client.post(
        BOUNDARIES,
        json={
            "authorization_boundary": {
                "name": f"phase2-fedramp-evaluations-{uuid.uuid4().hex[:8]}",
                "description": "FedRAMP evaluation API contract tests (#1354)",
                # #1390 — FedRAMP features answer only once FedRAMP is on.
                "fedramp_enabled": True,
            }
        },
    )
    assert created.status_code in (200, 201), created.text
    boundary = created.json().get("data") or created.json()
    try:
        ingested = admin_client.post(
            f"{BOUNDARIES}/{boundary['id']}/scan_runs",
            json=json.loads(_SAMPLE_HDF.read_text()),
        )
        assert ingested.status_code == 201, ingested.text
        listed = admin_client.get(
            f"{BOUNDARIES}/{boundary['id']}/scanner_findings", params={"status": "failed"}
        )
        assert listed.status_code == 200, listed.text
        rows = listed.json()["data"]
        assert rows, "the scan ingested no failing finding, so every test below would be vacuous"
        yield {"boundary": boundary, "finding": rows[0]}
    finally:
        admin_client.delete(f"{BOUNDARIES}/{boundary['id']}")


def _base(scanned: dict[str, Any]) -> str:
    return f"{BOUNDARIES}/{scanned['boundary']['id']}/fedramp_evaluations"


def _path(scanned: dict[str, Any], control_id: str | None = None) -> str:
    control = control_id or scanned["finding"]["control_id"]
    return f"{_base(scanned)}/{quote(control, safe='')}"


def _put(client: httpx.Client, scanned: dict[str, Any], **fields: Any) -> httpx.Response:
    return client.put(_path(scanned), json={"fedramp_evaluation": fields})


class TestFedrampEvaluations:
    @pytest.mark.happy
    def test_detected_vulnerability_reads_unevaluated_first(
        self, admin_client: httpx.Client, scanned: dict[str, Any]
    ) -> None:
        listed = admin_client.get(_base(scanned), params={"unevaluated": "true"})
        assert listed.status_code == 200, listed.text
        assert_paginated_envelope(listed.json())
        controls = [row["control_id"] for row in listed.json()["data"]]
        assert scanned["finding"]["control_id"] in controls

        shown = admin_client.get(_path(scanned))
        assert shown.status_code == 200, shown.text
        assert shown.json()["data"]["evaluated"] is False
        assert shown.json()["data"]["pain_rating"] is None
        assert admin_client.get(_base(scanned)).json()["data"] == []

    @pytest.mark.happy
    def test_put_records_then_updates_and_keeps_the_history(
        self, admin_client: httpx.Client, scanned: dict[str, Any]
    ) -> None:
        first = _put(
            admin_client, scanned, internet_reachable=True, likely_exploitable=False, pain_rating=4
        )
        assert first.status_code == 201, first.text
        data = first.json()["data"]
        assert data["evaluated"] is True
        assert data["evaluated_at"]
        assert data["pain_label"] == "N4"
        assert data["detected_at"]

        lowered = _put(
            admin_client,
            scanned,
            pain_rating=2,
            next_reduction_rating=1,
            next_reduction_at="2026-12-15",
        )
        assert lowered.status_code == 200, lowered.text
        data = lowered.json()["data"]
        assert data["internet_reachable"] is True, "a field not sent changed"
        assert [h["rating"] for h in data["pain_history"]] == [4, 2]
        assert [h["rating"] for h in data["pain_reductions"]] == [2]
        assert data["next_reduction_rating"] == 1

        read_back = admin_client.get(_path(scanned))
        assert read_back.status_code == 200, read_back.text
        assert read_back.json()["data"]["pain_rating"] == 2

        listed = admin_client.get(_base(scanned))
        assert listed.status_code == 200, listed.text
        assert scanned["finding"]["control_id"] in [r["control_id"] for r in listed.json()["data"]]

    @pytest.mark.validation
    def test_next_reduction_must_be_lower(
        self, admin_client: httpx.Client, scanned: dict[str, Any]
    ) -> None:
        response = _put(admin_client, scanned, pain_rating=2, next_reduction_rating=3)
        assert_error_envelope(response, expected_status=422)
        assert "lower than the current N-rating" in response.json()["error"]

    @pytest.mark.validation
    def test_rating_outside_n0_to_n5_is_422(
        self, admin_client: httpx.Client, scanned: dict[str, Any]
    ) -> None:
        assert_error_envelope(_put(admin_client, scanned, pain_rating=6), expected_status=422)

    @pytest.mark.validation
    def test_unknown_field_is_422(
        self, admin_client: httpx.Client, scanned: dict[str, Any]
    ) -> None:
        response = _put(admin_client, scanned, pain_rating=1, severity="LOW")
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_control_without_a_failing_finding_is_422(
        self, admin_client: httpx.Client, scanned: dict[str, Any]
    ) -> None:
        response = admin_client.put(
            _path(scanned, "CVE-NOT-IN-THIS-BOUNDARY"),
            json={"fedramp_evaluation": {"pain_rating": 1}},
        )
        assert_error_envelope(response, expected_status=422)
        assert admin_client.get(_path(scanned, "CVE-NOT-IN-THIS-BOUNDARY")).status_code == 404

    @pytest.mark.authz
    def test_non_admin_cannot_record(
        self, admin_client: httpx.Client, user_client: httpx.Client, scanned: dict[str, Any]
    ) -> None:
        response = _put(user_client, scanned, pain_rating=0)
        assert response.status_code == 403, response.text
        after = admin_client.get(_path(scanned)).json()["data"]
        assert after["evaluated"] is False, "a refused caller recorded an evaluation"

    @pytest.mark.authz
    def test_anonymous_is_401(self, anon_client: httpx.Client, scanned: dict[str, Any]) -> None:
        assert anon_client.get(_base(scanned)).status_code == 401
