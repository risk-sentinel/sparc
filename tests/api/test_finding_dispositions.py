"""Tests for the finding-disposition endpoints (#447, #809, #1034), swept for #995.

Five endpoints, all nested on a scanner finding — one disposition per finding,
keyed by boundary + control id:

  GET    /api/v1/scanner_findings/:scanner_finding_id/disposition
  POST   /api/v1/scanner_findings/:scanner_finding_id/disposition   (create/update)
  DELETE /api/v1/scanner_findings/:scanner_finding_id/disposition
  POST   /api/v1/scanner_findings/:scanner_finding_id/disposition/approve
  POST   /api/v1/scanner_findings/:scanner_finding_id/disposition/reject

Not `_crud_contract.py`: this is a singleton sub-resource with no index, no
slug, and no PATCH — POST both creates and updates. The matrix still applies,
it just cannot come from the mixin, so each write below is confirmed by an
INDEPENDENT read rather than by the write's own echo.

A disposition is the decision that a failing finding no longer counts against a
boundary — a waiver, a deferral, an inheritance claim. Every `kind` must link a
subject of a specific class (`FindingDispositionService::LINKAGE`), and
`inherited` is the one that links an AuthorizationBoundary, which the fixture
already has. That is why these tests use it: it needs no evidence file, no
attestation and no POA&M finding to exist first.
"""

from __future__ import annotations

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


def _disposition_path(finding_uuid: str) -> str:
    return f"{FINDINGS_PATH}/{finding_uuid}/disposition"


@pytest.fixture(scope="module")
def scanned(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    """A boundary of this module's own with one ingested finding."""
    suffix = uuid.uuid4().hex[:8]
    created = admin_client.post(
        BOUNDARIES_PATH,
        json={
            "authorization_boundary": {
                "name": f"phase2-dispositions-{suffix}",
                "description": "#995 finding disposition sweep",
            }
        },
    )
    assert created.status_code in (200, 201), created.text
    boundary = created.json().get("data") or created.json()

    ingested = admin_client.post(
        f"{BOUNDARIES_PATH}/{boundary['id']}/scan_runs",
        json=json.loads(_SAMPLE_HDF.read_text()),
    )
    assert ingested.status_code == 201, ingested.text

    listed = admin_client.get(f"{BOUNDARIES_PATH}/{boundary['id']}/scanner_findings")
    assert listed.status_code == 200, listed.text
    rows = listed.json()["data"]
    assert rows, "the scan ingested no findings, so every test below would be vacuous"

    try:
        yield {"boundary": boundary, "finding": rows[0]}
    finally:
        admin_client.delete(f"{BOUNDARIES_PATH}/{boundary['id']}")


@pytest.fixture
def finding(admin_client: httpx.Client, scanned: dict[str, Any]) -> Iterator[dict[str, Any]]:
    """The finding, with no disposition on it before or after the test.

    One disposition per finding, so a leftover from a previous test would turn
    the next create into an update and change what is being measured.
    """
    row = scanned["finding"]
    admin_client.delete(_disposition_path(row["uuid"]))
    try:
        yield row
    finally:
        admin_client.delete(_disposition_path(row["uuid"]))


def _payload(scanned: dict[str, Any], **overrides: Any) -> dict[str, Any]:
    body = {
        "kind": "inherited",
        "reason": "#995 sweep — inherited from the parent boundary",
        "linked_subject_type": "AuthorizationBoundary",
        "linked_subject_id": scanned["boundary"]["id"],
    }
    body.update(overrides)
    return body


@pytest.mark.happy
class TestCreate:
    def test_creates_the_disposition_and_an_independent_read_confirms_it(
        self, admin_client: httpx.Client, scanned: dict[str, Any], finding: dict[str, Any]
    ) -> None:
        created = admin_client.post(_disposition_path(finding["uuid"]), json=_payload(scanned))

        assert created.status_code == 201, created.text

        read_back = admin_client.get(_disposition_path(finding["uuid"]))
        assert read_back.status_code == 200, read_back.text
        data = read_back.json()["data"]
        assert data["kind"] == "inherited"
        assert data["reason"] == _payload(scanned)["reason"]
        assert data["control_id"] == finding["control_id"]

    def test_a_new_disposition_starts_unapproved(
        self, admin_client: httpx.Client, scanned: dict[str, Any], finding: dict[str, Any]
    ) -> None:
        """Deciding is not approving — the two-stage workflow #809 exists for."""
        admin_client.post(_disposition_path(finding["uuid"]), json=_payload(scanned))

        data = admin_client.get(_disposition_path(finding["uuid"])).json()["data"]
        assert data["approval_status"] == "draft", data
        assert data["approved_by"] is None, data

    def test_the_finding_itself_reports_the_disposition(
        self, admin_client: httpx.Client, scanned: dict[str, Any], finding: dict[str, Any]
    ) -> None:
        """Confirmed through a DIFFERENT endpoint than the one that wrote it.

        The finding read is what the triage screens and the amended-HDF export
        consume, so a disposition the disposition endpoint reports and the
        finding endpoint does not would be invisible where it matters.
        """
        admin_client.post(_disposition_path(finding["uuid"]), json=_payload(scanned))

        data = admin_client.get(f"{FINDINGS_PATH}/{finding['uuid']}").json()["data"]
        assert data["disposition_kind"] == "inherited", data
        assert data["disposition_approval"] == "draft", data


@pytest.mark.validation
class TestRefusals:
    def test_an_unknown_kind_is_refused_by_name_and_nothing_is_written(
        self, admin_client: httpx.Client, scanned: dict[str, Any], finding: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            _disposition_path(finding["uuid"]), json=_payload(scanned, kind="carrier_pigeon")
        )

        assert_error_envelope(response, expected_status=422)
        assert "carrier_pigeon" in response.json()["error"], response.text

        after = admin_client.get(_disposition_path(finding["uuid"]))
        assert after.status_code == 404, "a refused request still created a disposition"

    def test_a_kind_linked_to_the_wrong_class_is_refused_by_name(
        self, admin_client: httpx.Client, scanned: dict[str, Any], finding: dict[str, Any]
    ) -> None:
        """`falsePositive` must link an Evidence; the fixture offers a boundary."""
        response = admin_client.post(
            _disposition_path(finding["uuid"]), json=_payload(scanned, kind="falsePositive")
        )

        assert_error_envelope(response, expected_status=422)
        assert "Evidence" in response.json()["error"], response.text

    def test_an_unresolvable_linked_subject_type_is_refused(
        self, admin_client: httpx.Client, scanned: dict[str, Any], finding: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            _disposition_path(finding["uuid"]),
            json=_payload(scanned, linked_subject_type="User"),
        )

        assert_error_envelope(response, expected_status=422)

    def test_a_finding_with_no_disposition_reads_as_a_json_404(
        self, admin_client: httpx.Client, finding: dict[str, Any]
    ) -> None:
        response = admin_client.get(_disposition_path(finding["uuid"]))

        assert_error_envelope(response, expected_status=404)


@pytest.mark.happy
class TestApprovalWorkflow:
    def test_approve_records_the_approver_and_an_independent_read_confirms(
        self, admin_client: httpx.Client, scanned: dict[str, Any], finding: dict[str, Any]
    ) -> None:
        admin_client.post(_disposition_path(finding["uuid"]), json=_payload(scanned))

        approved = admin_client.post(f"{_disposition_path(finding['uuid'])}/approve")
        assert approved.status_code == 200, approved.text

        data = admin_client.get(_disposition_path(finding["uuid"])).json()["data"]
        assert data["approval_status"] == "approved", data
        assert data["approved_by"], "approved with no approver recorded"
        assert data["approved_at"], "approved with no approval time recorded"

    def test_reject_is_recorded_and_confirmed_by_an_independent_read(
        self, admin_client: httpx.Client, scanned: dict[str, Any], finding: dict[str, Any]
    ) -> None:
        admin_client.post(_disposition_path(finding["uuid"]), json=_payload(scanned))

        rejected = admin_client.post(f"{_disposition_path(finding['uuid'])}/reject")
        assert rejected.status_code == 200, rejected.text

        data = admin_client.get(_disposition_path(finding["uuid"])).json()["data"]
        assert data["approval_status"] == "rejected", data

    def test_editing_an_approved_disposition_resets_its_approval(
        self, admin_client: httpx.Client, scanned: dict[str, Any], finding: dict[str, Any]
    ) -> None:
        """The property that keeps an approval attached to what was approved.

        Without it, someone could get a narrow disposition approved and then
        broaden its reason while it still reads as approved.
        """
        admin_client.post(_disposition_path(finding["uuid"]), json=_payload(scanned))
        admin_client.post(f"{_disposition_path(finding['uuid'])}/approve")
        assert (
            admin_client.get(_disposition_path(finding["uuid"])).json()["data"]["approval_status"]
            == "approved"
        ), "the disposition was not approved, so the reset below proves nothing"

        admin_client.post(
            _disposition_path(finding["uuid"]),
            json=_payload(scanned, reason="#995 sweep — edited after approval"),
        )

        data = admin_client.get(_disposition_path(finding["uuid"])).json()["data"]
        assert data["approval_status"] == "draft", data
        assert data["approved_by"] is None, "an edited disposition kept its approver"

    def test_approving_a_finding_with_no_disposition_is_a_json_404(
        self, admin_client: httpx.Client, finding: dict[str, Any]
    ) -> None:
        response = admin_client.post(f"{_disposition_path(finding['uuid'])}/approve")

        assert_error_envelope(response, expected_status=404)


@pytest.mark.happy
class TestDestroy:
    def test_delete_removes_it_and_the_finding_stops_reporting_it(
        self, admin_client: httpx.Client, scanned: dict[str, Any], finding: dict[str, Any]
    ) -> None:
        admin_client.post(_disposition_path(finding["uuid"]), json=_payload(scanned))

        deleted = admin_client.delete(_disposition_path(finding["uuid"]))
        assert deleted.status_code == 200, deleted.text

        gone = admin_client.get(_disposition_path(finding["uuid"]))
        assert_error_envelope(gone, expected_status=404)

        # Gone from the parent record too, not merely from its own endpoint.
        data = admin_client.get(f"{FINDINGS_PATH}/{finding['uuid']}").json()["data"]
        assert data["disposition_kind"] is None, data

    def test_deleting_a_disposition_that_is_not_there_is_a_json_404(
        self, admin_client: httpx.Client, finding: dict[str, Any]
    ) -> None:
        response = admin_client.delete(_disposition_path(finding["uuid"]))

        assert_error_envelope(response, expected_status=404)


@pytest.mark.authz
class TestAuthorization:
    def test_non_admin_cannot_create_and_nothing_is_written(
        self,
        admin_client: httpx.Client,
        user_client: httpx.Client,
        scanned: dict[str, Any],
        finding: dict[str, Any],
    ) -> None:
        response = user_client.post(_disposition_path(finding["uuid"]), json=_payload(scanned))

        assert response.status_code == 403, response.text
        after = admin_client.get(_disposition_path(finding["uuid"]))
        assert after.status_code == 404, "a refused caller still created a disposition"

    def test_non_admin_cannot_approve_and_the_status_is_unchanged(
        self,
        admin_client: httpx.Client,
        user_client: httpx.Client,
        scanned: dict[str, Any],
        finding: dict[str, Any],
    ) -> None:
        admin_client.post(_disposition_path(finding["uuid"]), json=_payload(scanned))

        response = user_client.post(f"{_disposition_path(finding['uuid'])}/approve")

        assert response.status_code == 403, response.text
        data = admin_client.get(_disposition_path(finding["uuid"])).json()["data"]
        assert data["approval_status"] == "draft", "a refused approval still took effect"

    def test_non_admin_cannot_delete_and_it_survives(
        self,
        admin_client: httpx.Client,
        user_client: httpx.Client,
        scanned: dict[str, Any],
        finding: dict[str, Any],
    ) -> None:
        admin_client.post(_disposition_path(finding["uuid"]), json=_payload(scanned))

        response = user_client.delete(_disposition_path(finding["uuid"]))

        assert response.status_code == 403, response.text
        assert admin_client.get(_disposition_path(finding["uuid"])).status_code == 200


@pytest.mark.auth
class TestAuthentication:
    def test_every_disposition_endpoint_refuses_an_anonymous_caller(
        self, anon_client: httpx.Client, scanned: dict[str, Any], finding: dict[str, Any]
    ) -> None:
        path = _disposition_path(finding["uuid"])

        assert anon_client.get(path).status_code == 401
        assert anon_client.post(path, json=_payload(scanned)).status_code == 401
        assert anon_client.post(f"{path}/approve").status_code == 401
        assert anon_client.post(f"{path}/reject").status_code == 401
        assert anon_client.delete(path).status_code == 401
