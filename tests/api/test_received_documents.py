"""Tests for a boundary's received documents and its exchange index (#1354).

    /api/v1/authorization_boundaries/:id/received_documents[/:id[/file|review_export|accept|respond|reject]]
    /api/v1/authorization_boundaries/:id/exchange_index

Every version received is kept and never overwritten. A version that fails
validation is still stored, with its errors (owner, 2026-11-20). Bytes the
stream already holds are reported as unchanged. Only a byte-identical
re-delivery needs no reviewer, so every new version waits for one.

Separation of duties: the uploader cannot decide their own upload; the
instance administrator is exempt. The suite's admin token exercises that
exemption. The refusal of a non-admin uploader needs a user holding both
exchange.upload and exchange.review, which the API cannot provision (role
assignment is not exposed), so it is covered by the request specs
(spec/requests/api/v1/received_documents_spec.rb).

Each test works on a throwaway phase2 boundary, removed afterwards with
everything it received.
"""

from __future__ import annotations

import hashlib
import json
import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope, assert_paginated_envelope

pytestmark = [pytest.mark.exchange, pytest.mark.phase2]

BOUNDARIES = "/api/v1/authorization_boundaries"


def _vdr(period_end: str = "2026-10-31T23:59:59Z") -> bytes:
    return json.dumps(
        {
            "certificationPackageOverviewUri": "https://provider.example/package/cpo.json",
            "reportPeriod": {"from": "2026-10-01T00:00:00Z", "to": period_end},
            "vulnerabilities": [],
        }
    ).encode()


@pytest.fixture
def boundary(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(
        BOUNDARIES,
        json={
            "authorization_boundary": {
                "name": f"phase2-boundary-exchange-{uuid.uuid4().hex[:8]}",
                "description": "Created by the exchange API contract tests (#1354)",
            }
        },
    )
    assert response.status_code in (200, 201), response.text
    record = response.json().get("data") or response.json()
    try:
        yield record
    finally:
        admin_client.delete(f"{BOUNDARIES}/{record['id']}")


def _path(boundary: dict[str, Any]) -> str:
    return f"{BOUNDARIES}/{boundary['id']}/received_documents"


def _upload(client: httpx.Client, boundary: dict[str, Any], body: bytes) -> httpx.Response:
    return client.post(_path(boundary), files={"file": ("vdr.json", body, "application/json")})


class TestReceivedDocuments:
    @pytest.mark.happy
    def test_upload_waits_for_review(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = _upload(admin_client, boundary, _vdr())
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["status"] == "stored"
        data = body["data"]
        assert data["state"] == "pending_review"
        assert data["valid"] is True
        assert data["format"] == "fedramp"
        assert data["sha256"] == hashlib.sha256(_vdr()).hexdigest()
        assert data["delta"]["first_version"] is True
        # Uploaded, not pushed: there is no push to have confirmed.
        assert data["push_confirmed"] is None

    @pytest.mark.idempotency
    def test_same_bytes_again_are_unchanged(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        first = _upload(admin_client, boundary, _vdr())
        assert first.status_code == 201, first.text
        again = _upload(admin_client, boundary, _vdr())
        assert again.status_code == 200, again.text
        assert again.json()["status"] == "unchanged"
        assert again.json()["data"]["id"] == first.json()["data"]["id"]

    @pytest.mark.validation
    def test_invalid_document_is_stored_with_its_errors(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = _upload(admin_client, boundary, _vdr(period_end=" "))
        assert response.status_code == 201, response.text
        data = response.json()["data"]
        assert data["state"] == "invalid"
        assert any(e["pointer"] == "/reportPeriod/to" for e in data["validation"]["errors"])

        accepted = admin_client.post(f"{_path(boundary)}/{data['id']}/accept", json={})
        assert_error_envelope(accepted, expected_status=422)

    @pytest.mark.validation
    def test_unreadable_document_is_422(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            _path(boundary), content=b"not a document", headers={"Content-Type": "text/plain"}
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.happy
    def test_list_show_and_download(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        stored = _upload(admin_client, boundary, _vdr()).json()["data"]

        listed = admin_client.get(_path(boundary), params={"state": "pending_review"})
        assert listed.status_code == 200, listed.text
        assert_paginated_envelope(listed.json())
        assert [d["id"] for d in listed.json()["data"]] == [stored["id"]]

        shown = admin_client.get(f"{_path(boundary)}/{stored['id']}")
        assert shown.status_code == 200, shown.text
        assert shown.json()["data"]["may_decide"] is True

        downloaded = admin_client.get(f"{_path(boundary)}/{stored['id']}/file")
        assert downloaded.status_code == 200, downloaded.text
        assert downloaded.content == _vdr()
        assert downloaded.headers["X-Content-SHA256"] == stored["sha256"]

    @pytest.mark.happy
    def test_review_accept_respond_reject(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        first = _upload(admin_client, boundary, _vdr()).json()["data"]
        # The admin uploaded it and may still decide it: the break-glass
        # exemption from separation of duties.
        accepted = admin_client.post(
            f"{_path(boundary)}/{first['id']}/accept", json={"note": "Reviewed"}
        )
        assert accepted.status_code == 200, accepted.text
        assert accepted.json()["data"]["state"] == "accepted"
        assert accepted.json()["data"]["review"]["note"] == "Reviewed"

        second = _upload(admin_client, boundary, _vdr("2026-10-31T23:00:00Z")).json()["data"]
        assert second["state"] == "pending_review"

        no_note = admin_client.post(f"{_path(boundary)}/{second['id']}/respond", json={})
        assert_error_envelope(no_note, expected_status=422)

        responded = admin_client.post(
            f"{_path(boundary)}/{second['id']}/respond", json={"note": "Send the scan dates"}
        )
        assert responded.status_code == 200, responded.text
        assert responded.json()["data"]["state"] == "responded"
        assert responded.json()["data"]["in_effect_version_id"] == first["id"]

        rejected = admin_client.post(
            f"{_path(boundary)}/{second['id']}/reject", json={"note": "Wrong period"}
        )
        assert rejected.status_code == 200, rejected.text
        assert rejected.json()["data"]["state"] == "rejected"

    @pytest.mark.auth
    def test_requires_a_token(self, anon_client: httpx.Client, boundary: dict[str, Any]) -> None:
        assert_error_envelope(anon_client.get(_path(boundary)), expected_status=401)

    @pytest.mark.authz
    def test_read_only_user_cannot_upload(
        self, user_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        assert_error_envelope(_upload(user_client, boundary, _vdr()), expected_status=403)


class TestExchangeIndex:
    @pytest.mark.happy
    def test_lists_accepted_received_documents_only(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        first = _upload(admin_client, boundary, _vdr()).json()["data"]
        accepted = admin_client.post(f"{_path(boundary)}/{first['id']}/accept", json={})
        assert accepted.status_code == 200, accepted.text
        pending = _upload(admin_client, boundary, _vdr("2026-10-31T23:00:00Z")).json()["data"]

        response = admin_client.get(f"{BOUNDARIES}/{boundary['id']}/exchange_index")
        assert response.status_code == 200, response.text
        data = response.json()["data"]
        assert data["authorization_boundary"]["id"] == boundary["id"]
        received = [d for d in data["documents"] if d["origin"] == "received"]
        assert [d["id"] for d in received] == [first["id"]]
        assert pending["id"] not in [d["id"] for d in received]
        assert received[0]["sha256"] == first["sha256"]
        assert received[0]["download_url"].endswith(f"/received_documents/{first['id']}/file")

    @pytest.mark.auth
    def test_requires_a_token(self, anon_client: httpx.Client, boundary: dict[str, Any]) -> None:
        response = anon_client.get(f"{BOUNDARIES}/{boundary['id']}/exchange_index")
        assert_error_envelope(response, expected_status=401)


# #1390 part G — the received-document viewer's API side: compare with any
# other version of the same document (calculated on request, never stored),
# questions with a response, the review export (review_export.json / .md), and
# a version that failed validation answered but never accepted.


def _rated_vdr(rating: int, period_end: str = "2026-10-31T23:59:59Z") -> bytes:
    return json.dumps(
        {
            "certificationPackageOverviewUri": "https://provider.example/package/cpo.json",
            "reportPeriod": {"from": "2026-10-01T00:00:00Z", "to": period_end},
            "vulnerabilities": [
                {
                    "providerTrackingId": "VULN-1",
                    "detection": {
                        "detectedAt": "2026-10-02T10:00:00Z",
                        "detectionSource": "scanner",
                    },
                    "vulnerabilityDescription": "Outdated library",
                    "potentialAgencyImpact": "Low",
                    "evaluationCompletedAt": "2026-10-03T10:00:00Z",
                    "isInternetReachable": False,
                    "isLikelyExploitable": False,
                    "currentRating": rating,
                    "overdueStatus": {"isOverdue": False, "explanation": "Within the timeframe."},
                    "painReductionEvents": [
                        {"reducedAt": "2026-10-04T10:00:00Z", "rating": rating}
                    ],
                }
            ],
        }
    ).encode()


def _stored(client: httpx.Client, boundary: dict[str, Any], body: bytes) -> dict[str, Any]:
    response = client.post(_path(boundary), files={"file": ("vdr.json", body, "application/json")})
    assert response.status_code == 201, response.text
    return response.json()["data"]


def _accepted(client: httpx.Client, boundary: dict[str, Any], doc: dict[str, Any]) -> None:
    response = client.post(f"{_path(boundary)}/{doc['id']}/accept", json={})
    assert response.status_code == 200, response.text


VIEWER_QUESTION = {
    "pointer": "/vulnerabilities/VULN-1/currentRating",
    "label": "Vulnerabilities › VULN-1 › Current rating (N)",
    "detail": "Current rating raised",
    "before": "2",
    "after": "3",
    "question": "Why did the rating rise?",
}


class TestCompareWith:
    @pytest.mark.happy
    def test_recorded_by_default_and_calculated_on_request(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        v1 = _stored(admin_client, boundary, _rated_vdr(1))
        _accepted(admin_client, boundary, v1)
        v2 = _stored(admin_client, boundary, _rated_vdr(2))
        _accepted(admin_client, boundary, v2)
        v3 = _stored(admin_client, boundary, _rated_vdr(3))
        assert v3["compared_with_id"] == v2["id"]

        response = admin_client.get(f"{_path(boundary)}/{v3['id']}", params={"compare": v1["id"]})
        assert response.status_code == 200, response.text
        comparison = response.json()["data"]["comparison"]
        assert comparison["compared_with_id"] == v1["id"]
        assert comparison["recorded"] is False
        pointers = [c["pointer"] for c in comparison["changes"]]
        assert "/vulnerabilities/VULN-1/currentRating" in pointers

        unchanged = admin_client.get(f"{_path(boundary)}/{v3['id']}").json()["data"]
        assert unchanged["delta"] == v3["delta"], "a requested comparison must not be stored"

    @pytest.mark.validation
    def test_unknown_version_is_404(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        doc = _stored(admin_client, boundary, _rated_vdr(1))
        response = admin_client.get(f"{_path(boundary)}/{doc['id']}", params={"compare": 999999999})
        assert response.status_code == 404


class TestQuestionsAndExport:
    @pytest.mark.happy
    def test_questions_go_with_a_response_and_into_the_export(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        v1 = _stored(admin_client, boundary, _rated_vdr(2))
        _accepted(admin_client, boundary, v1)
        v2 = _stored(admin_client, boundary, _rated_vdr(3))

        response = admin_client.post(
            f"{_path(boundary)}/{v2['id']}/respond",
            json={"note": "", "questions": [VIEWER_QUESTION]},
        )
        assert response.status_code == 200, response.text
        review = response.json()["data"]["review"]
        assert review["action"] == "respond"
        assert review["questions"] == [VIEWER_QUESTION]

        export = admin_client.get(f"{_path(boundary)}/{v2['id']}/review_export.json")
        assert export.status_code == 200, export.text
        data = export.json()["data"]
        assert data["sparc_review_export"] == "1"
        assert data["compared_with"]["id"] == v1["id"]
        assert data["questions"][0]["question"] == "Why did the rating rise?"

        markdown = admin_client.get(f"{_path(boundary)}/{v2['id']}/review_export.md")
        assert markdown.status_code == 200, markdown.text
        assert markdown.headers["content-type"].startswith("text/markdown")
        assert "## Questions for the provider" in markdown.text

    @pytest.mark.validation
    def test_respond_needs_a_note_or_a_question(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        doc = _stored(admin_client, boundary, _rated_vdr(1))
        response = admin_client.post(f"{_path(boundary)}/{doc['id']}/respond", json={"note": ""})
        assert response.status_code == 422, response.text

    @pytest.mark.auth
    def test_export_requires_a_token(
        self, anon_client: httpx.Client, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        doc = _stored(admin_client, boundary, _rated_vdr(1))
        assert (
            anon_client.get(f"{_path(boundary)}/{doc['id']}/review_export.json").status_code == 401
        )


class TestInvalidVersion:
    @pytest.mark.validation
    def test_says_what_is_needed_answered_never_accepted(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        broken = json.loads(_rated_vdr(1))
        broken["vulnerabilities"][0]["vulnerabilityDescription"] = "   "
        doc = _stored(admin_client, boundary, json.dumps(broken).encode())
        assert doc["state"] == "invalid"

        shown = admin_client.get(f"{_path(boundary)}/{doc['id']}").json()["data"]
        guidance = shown["validation"]["guidance"]
        assert guidance, shown["validation"]
        assert guidance[0]["wrong"] == "Vulnerability description is blank."
        assert guidance[0]["needed"].endswith("FedRAMP's schema requires it.")

        assert (
            admin_client.post(f"{_path(boundary)}/{doc['id']}/accept", json={}).status_code == 422
        )
        response = admin_client.post(
            f"{_path(boundary)}/{doc['id']}/respond",
            json={"note": "Please describe the vulnerability."},
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["state"] == "invalid"
