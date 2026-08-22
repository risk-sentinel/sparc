"""Tests for the scanner-findings read endpoints (#447), swept for #995.

Two endpoints:

  GET /api/v1/authorization_boundaries/:authorization_boundary_id/scanner_findings
  GET /api/v1/scanner_findings/:uuid

Neither is in `_crud_contract.py`, and deliberately so: a scanner finding cannot
be POSTed. It exists only as the product of an HDF scan ingest, so there is no
create body to round-trip and the CRUD matrix does not describe this group. What
replaces it is the same idea by a different route — the fixture ingests an HDF
payload that DECLARES what the findings should be, and every read is checked
against that declaration rather than against itself.

The payload carries two controls, one failed/MEDIUM and one passed/LOW, because
a filter asserted against a single-row collection passes whether or not the
filter does anything.
"""

from __future__ import annotations

import copy
import json
import uuid
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.findings, pytest.mark.phase2]

BOUNDARIES_PATH = "/api/v1/authorization_boundaries"
FINDINGS_PATH = "/api/v1/scanner_findings"

_SAMPLE_HDF = Path(__file__).parent / "fixtures" / "sample.hdf.json"

# What the ingested payload declares. Every read assertion below is written
# against THIS, not against whatever the API happened to return first.
FAILED = {"control_id": "SPARC-AC-3", "status": "failed", "severity": "MEDIUM"}
PASSED = {"control_id": "SPARC-AU-2", "status": "passed", "severity": "LOW"}


def _hdf_with_two_controls() -> dict[str, Any]:
    """The sample profile plus a second, passing control.

    The shipped fixture has one failed control. A status or severity filter
    checked against a one-row collection cannot fail, so the second control is
    what gives those assertions teeth.
    """
    payload = json.loads(_SAMPLE_HDF.read_text())
    profile = payload["profiles"][0]
    failing = profile["controls"][0]

    passing = copy.deepcopy(failing)
    passing["id"] = PASSED["control_id"]
    passing["title"] = "Auditable events are defined"
    passing["impact"] = 0.3
    passing["tags"] = {"nist": ["AU-2"], "severity": PASSED["severity"].lower()}
    passing["results"] = [
        {
            "status": PASSED["status"],
            "code_desc": "Audit events should be defined",
            "run_time": 0.01,
            "start_time": "2026-06-01T00:00:00Z",
        }
    ]
    profile["controls"].append(passing)
    return payload


@pytest.fixture(scope="module")
def scanned_boundary(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    """A boundary of this module's own, with one scan ingested into it.

    Its own boundary rather than a seeded one: the index assertions count rows,
    and a shared boundary would make the count depend on what else ran.
    """
    suffix = uuid.uuid4().hex[:8]
    created = admin_client.post(
        BOUNDARIES_PATH,
        json={
            "authorization_boundary": {
                "name": f"phase2-scanner-findings-{suffix}",
                "description": "#995 scanner findings sweep",
            }
        },
    )
    assert created.status_code in (200, 201), created.text
    boundary = created.json().get("data") or created.json()

    ingested = admin_client.post(
        f"{BOUNDARIES_PATH}/{boundary['id']}/scan_runs",
        json=_hdf_with_two_controls(),
    )
    assert ingested.status_code == 201, ingested.text
    run = ingested.json()["data"]
    # The ingest must have produced what the payload declared, or every read
    # assertion below would be checking an empty collection and passing.
    assert run["finding_count"] == 2, run
    assert run["failed_count"] == 1, run

    try:
        yield {"boundary": boundary, "run": run}
    finally:
        admin_client.delete(f"{BOUNDARIES_PATH}/{boundary['id']}")


@pytest.fixture(scope="module")
def findings(admin_client: httpx.Client, scanned_boundary: dict[str, Any]) -> dict[str, Any]:
    """The ingested findings, keyed by control id."""
    path = f"{BOUNDARIES_PATH}/{scanned_boundary['boundary']['id']}/scanner_findings"
    response = admin_client.get(path, params={"items": 200})
    assert response.status_code == 200, response.text
    return {row["control_id"]: row for row in response.json()["data"]}


def _index_path(scanned_boundary: dict[str, Any]) -> str:
    return f"{BOUNDARIES_PATH}/{scanned_boundary['boundary']['id']}/scanner_findings"


@pytest.mark.happy
class TestIndex:
    def test_returns_the_documented_paginated_envelope(
        self, admin_client: httpx.Client, scanned_boundary: dict[str, Any]
    ) -> None:
        response = admin_client.get(_index_path(scanned_boundary))

        assert response.status_code == 200, response.text
        body = response.json()
        assert isinstance(body["data"], list)
        assert set(body["meta"]) >= {"page", "pages", "count", "items"}

    def test_lists_exactly_the_findings_the_scan_declared(
        self, admin_client: httpx.Client, scanned_boundary: dict[str, Any]
    ) -> None:
        response = admin_client.get(_index_path(scanned_boundary), params={"items": 200})

        assert response.status_code == 200, response.text
        body = response.json()
        assert sorted(row["control_id"] for row in body["data"]) == sorted(
            [FAILED["control_id"], PASSED["control_id"]]
        )
        assert body["meta"]["count"] == 2, (
            f"meta.count says {body['meta']['count']} for a scan that ingested 2 findings"
        )

    def test_each_finding_carries_what_the_hdf_declared(self, findings: dict[str, Any]) -> None:
        for declared in (FAILED, PASSED):
            row = findings[declared["control_id"]]
            assert row["status"] == declared["status"], row
            assert row["severity"] == declared["severity"], row
            assert row["scanner"] == "sparc-sample-profile", row


@pytest.mark.pagination
class TestFilters:
    @pytest.mark.parametrize("declared", [FAILED, PASSED], ids=["failed", "passed"])
    def test_status_filter_selects_and_excludes(
        self,
        admin_client: httpx.Client,
        scanned_boundary: dict[str, Any],
        declared: dict[str, str],
    ) -> None:
        """Both directions: the wanted row is present AND the other is gone.

        Asserting only that the match comes back would pass against a filter the
        endpoint ignored entirely.
        """
        response = admin_client.get(
            _index_path(scanned_boundary), params={"status": declared["status"], "items": 200}
        )

        assert response.status_code == 200, response.text
        returned = [row["control_id"] for row in response.json()["data"]]
        assert returned == [declared["control_id"]], (
            f"status={declared['status']} returned {returned}"
        )

    def test_severity_filter_is_case_insensitive(
        self, admin_client: httpx.Client, scanned_boundary: dict[str, Any]
    ) -> None:
        """`docs/api/` documents severity matching as case-insensitive."""
        response = admin_client.get(
            _index_path(scanned_boundary),
            params={"severity": FAILED["severity"].lower(), "items": 200},
        )

        assert response.status_code == 200, response.text
        returned = [row["control_id"] for row in response.json()["data"]]
        assert returned == [FAILED["control_id"]], (
            f"severity={FAILED['severity'].lower()} returned {returned}"
        )


@pytest.mark.happy
class TestShow:
    def test_shows_the_finding_addressed_by_uuid(
        self, admin_client: httpx.Client, findings: dict[str, Any]
    ) -> None:
        finding = findings[FAILED["control_id"]]

        response = admin_client.get(f"{FINDINGS_PATH}/{finding['uuid']}")

        assert response.status_code == 200, response.text
        data = response.json()["data"]
        assert data["uuid"] == finding["uuid"]
        assert data["control_id"] == FAILED["control_id"]
        assert data["status"] == FAILED["status"]

    def test_show_carries_the_raw_hdf_the_index_omits(
        self, admin_client: httpx.Client, findings: dict[str, Any]
    ) -> None:
        """The reason `show` exists as well as `index` — it returns the source
        record the list view leaves out."""
        finding = findings[FAILED["control_id"]]

        response = admin_client.get(f"{FINDINGS_PATH}/{finding['uuid']}")

        assert response.status_code == 200, response.text
        assert response.json()["data"].get("raw_hdf"), "show returned no raw_hdf"
        assert "raw_hdf" not in finding, "index now returns raw_hdf; this test's premise is stale"


@pytest.mark.validation
class TestUnknownRecord:
    def test_unknown_uuid_is_a_json_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{FINDINGS_PATH}/{uuid.uuid4()}")

        assert_error_envelope(response, expected_status=404)

    def test_unknown_boundary_is_a_json_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{BOUNDARIES_PATH}/0/scanner_findings")

        assert_error_envelope(response, expected_status=404)


@pytest.mark.authz
class TestAuthorization:
    def test_non_admin_without_evidence_read_is_refused_the_index(
        self, user_client: httpx.Client, scanned_boundary: dict[str, Any]
    ) -> None:
        response = user_client.get(_index_path(scanned_boundary))

        assert response.status_code == 403, response.text

    def test_non_admin_without_evidence_read_is_refused_a_finding(
        self, user_client: httpx.Client, findings: dict[str, Any]
    ) -> None:
        finding = findings[FAILED["control_id"]]

        response = user_client.get(f"{FINDINGS_PATH}/{finding['uuid']}")

        assert response.status_code == 403, response.text


@pytest.mark.auth
class TestAuthentication:
    def test_index_refuses_an_anonymous_caller(
        self, anon_client: httpx.Client, scanned_boundary: dict[str, Any]
    ) -> None:
        response = anon_client.get(_index_path(scanned_boundary))

        assert response.status_code == 401, response.text

    def test_show_refuses_an_anonymous_caller(
        self, anon_client: httpx.Client, findings: dict[str, Any]
    ) -> None:
        finding = findings[FAILED["control_id"]]

        response = anon_client.get(f"{FINDINGS_PATH}/{finding['uuid']}")

        assert response.status_code == 401, response.text
