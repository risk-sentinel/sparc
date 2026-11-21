"""Tests for a boundary's received documents and its exchange index (#1354).

    /api/v1/authorization_boundaries/:id/received_documents[/:id[/file|accept|respond|reject]]
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
