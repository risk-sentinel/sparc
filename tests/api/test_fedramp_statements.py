"""Tests for a boundary's FedRAMP statements (#1390).

    GET /api/v1/authorization_boundaries/:id/fedramp_statements[?kind=frr|ksi]
    GET /api/v1/authorization_boundaries/:id/fedramp_statements/:kind/:rule_id
    PUT /api/v1/authorization_boundaries/:id/fedramp_statements/:kind/:rule_id

The boundary's answer to each FedRAMP rule that applies to its certification
profile, and to each Key Security Indicator: what its Security Decision
Record carries. Each test works on a throwaway phase2 boundary with FedRAMP
on and a 20x Program Class B profile, removed afterwards.
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
                "name": f"phase2-boundary-fedramp-sdr-{uuid.uuid4().hex[:8]}",
                "description": "Created by the FedRAMP statement API contract tests (#1390)",
                "fedramp_enabled": True,
                "fedramp_package": PROFILE,
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
    return f"{BOUNDARIES}/{boundary['id']}/fedramp_statements{tail}"


class TestFedrampStatements:
    @pytest.mark.happy
    def test_lists_rules_for_the_profile(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.get(_path(boundary))
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["meta"]["certification_class"] == "B"
        ids = {r["rule_id"] for r in body["data"]}
        assert "SDR-CSO-FRR" in ids
        assert "FRC-CSF-BSL" not in ids  # Rev5 only

    @pytest.mark.happy
    def test_records_and_reads_back_a_statement(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        path = _path(boundary, "/ksi/KSI-CED-RAT")
        first = admin_client.put(
            path,
            json={"fedramp_statement": {"status": "Implemented", "tests": ["quarterly review"]}},
        )
        assert first.status_code == 201, first.text
        again = admin_client.put(path, json={"fedramp_statement": {"implementation": "Reviewed."}})
        assert again.status_code == 200, again.text
        answer = admin_client.get(path).json()["data"]["answer"]
        assert answer["status"] == "Implemented"
        assert answer["tests"] == ["quarterly review"]
        assert answer["implementation"] == "Reviewed."

    @pytest.mark.validation
    def test_rule_outside_the_profile_is_422(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.put(
            _path(boundary, "/frr/FRC-CSF-BSL"),
            json={"fedramp_statement": {"status": "Implemented"}},
        )
        assert_error_envelope(response, expected_status=422)
        assert "does not apply" in response.json()["error"]

    @pytest.mark.validation
    def test_status_outside_the_schema_is_422(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.put(
            _path(boundary, "/frr/SDR-CSO-FRR"), json={"fedramp_statement": {"status": "Done"}}
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.auth
    def test_requires_a_token(self, anon_client: httpx.Client, boundary: dict[str, Any]) -> None:
        assert_error_envelope(anon_client.get(_path(boundary)), expected_status=401)
