"""Tests for a connection's Class A certification materials (#1354).

    GET  /api/v1/exchange_connections/:exchange_connection_id/certification_materials
    POST /api/v1/exchange_connections/:exchange_connection_id/certification_materials

The materials a Class A certification rests on (FedRAMP FRC-CLA-EAM): a SOC 2
Type II report, a bridge letter, a Readiness Assessment Report, and the like.
Each is a multipart ``file`` plus a ``kind``, stored by SHA-256 as a received
document of the connection's boundary (never schema-checked) and decided
there like any other received document. The same bytes again are reported
as unchanged.

Adding one needs what managing the connection needs: ``connections.manage``
across the instance, or an instance administrator.

Each test works on a throwaway phase2 boundary and a Class A connection on it,
both removed afterwards with everything received.
"""

from __future__ import annotations

import hashlib
import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope, assert_paginated_envelope

pytestmark = [pytest.mark.exchange, pytest.mark.phase2]

BOUNDARIES = "/api/v1/authorization_boundaries"
CONNECTIONS = "/api/v1/exchange_connections"
HOST = "trust.provider.example"
REPORT = b"%PDF-1.7\n% phase2 SOC 2 Type II report (#1354)\n%%EOF\n"


@pytest.fixture
def boundary(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(
        BOUNDARIES,
        json={
            "authorization_boundary": {
                "name": f"phase2-boundary-class-a-{uuid.uuid4().hex[:8]}",
                "description": "Created by the Class A materials API contract tests (#1354)",
            }
        },
    )
    assert response.status_code in (200, 201), response.text
    record = response.json().get("data") or response.json()
    try:
        yield record
    finally:
        admin_client.delete(f"{BOUNDARIES}/{record['id']}")


def _create_connection(
    client: httpx.Client, boundary: dict[str, Any], certification_class: str
) -> dict[str, Any]:
    response = client.post(
        CONNECTIONS,
        json={
            "exchange_connection": {
                "name": f"phase2-class-a-connection-{uuid.uuid4().hex[:8]}",
                "authorization_boundary_id": boundary["id"],
                "root_url": f"https://{HOST}/",
                "auth_scheme": "none",
                "fedramp_id": "FR2400000001",
                "certification_class": certification_class,
                "certification_type": "20x",
            }
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["data"]


@pytest.fixture
def class_a(admin_client: httpx.Client, boundary: dict[str, Any]) -> Iterator[dict[str, Any]]:
    # Removed before its boundary, which refuses deletion while a connection
    # names it.
    connection = _create_connection(admin_client, boundary, "A")
    try:
        yield connection
    finally:
        admin_client.delete(f"{CONNECTIONS}/{connection['id']}")


@pytest.fixture
def class_b(admin_client: httpx.Client, boundary: dict[str, Any]) -> Iterator[dict[str, Any]]:
    connection = _create_connection(admin_client, boundary, "B")
    try:
        yield connection
    finally:
        admin_client.delete(f"{CONNECTIONS}/{connection['id']}")


def _path(connection: dict[str, Any]) -> str:
    return f"{CONNECTIONS}/{connection['id']}/certification_materials"


def _add(
    client: httpx.Client,
    connection: dict[str, Any],
    *,
    kind: str = "soc2_report",
    body: bytes = REPORT,
    filename: str = "soc2.pdf",
) -> httpx.Response:
    return client.post(
        _path(connection),
        data={"kind": kind},
        files={"file": (filename, body, "application/pdf")},
    )


class TestCertificationMaterials:
    @pytest.mark.happy
    def test_add_is_stored_pending_review(
        self, admin_client: httpx.Client, class_a: dict[str, Any], boundary: dict[str, Any]
    ) -> None:
        response = _add(admin_client, class_a)
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["status"] == "stored"
        data = body["data"]
        assert data["exchange_connection_id"] == class_a["id"]
        assert data["kind"] == "soc2_report"
        assert data["kind_label"] == "SOC 2 Type II complete report"
        assert data["filename"] == "soc2.pdf"
        assert data["content_type"] == "application/pdf"
        assert data["sha256"] == hashlib.sha256(REPORT).hexdigest()
        assert data["byte_size"] == len(REPORT)
        assert data["state"] == "pending_review"
        path = f"{BOUNDARIES}/{boundary['id']}/received_documents/{data['id']}"
        assert data["links"] == {"received_document": path, "file": f"{path}/file"}

    @pytest.mark.idempotency
    def test_same_bytes_again_are_unchanged(
        self, admin_client: httpx.Client, class_a: dict[str, Any]
    ) -> None:
        first = _add(admin_client, class_a)
        assert first.status_code == 201, first.text
        again = _add(admin_client, class_a)
        assert again.status_code == 200, again.text
        assert again.json()["status"] == "unchanged"
        assert again.json()["data"]["id"] == first.json()["data"]["id"]

    @pytest.mark.happy
    def test_list_shows_the_connections_materials(
        self, admin_client: httpx.Client, class_a: dict[str, Any]
    ) -> None:
        empty = admin_client.get(_path(class_a))
        assert empty.status_code == 200, empty.text
        assert_paginated_envelope(empty.json())
        assert empty.json()["data"] == []

        report = _add(admin_client, class_a).json()["data"]
        letter = _add(
            admin_client, class_a, kind="bridge_letter", body=b"%PDF-1.7 letter", filename="b.pdf"
        ).json()["data"]

        listed = admin_client.get(_path(class_a))
        assert listed.status_code == 200, listed.text
        assert_paginated_envelope(listed.json())
        assert sorted(m["id"] for m in listed.json()["data"]) == sorted(
            [report["id"], letter["id"]]
        )
        assert {m["kind"] for m in listed.json()["data"]} == {"soc2_report", "bridge_letter"}

    @pytest.mark.happy
    def test_material_is_a_received_document_of_the_boundary(
        self, admin_client: httpx.Client, class_a: dict[str, Any], boundary: dict[str, Any]
    ) -> None:
        material = _add(admin_client, class_a).json()["data"]

        shown = admin_client.get(material["links"]["received_document"])
        assert shown.status_code == 200, shown.text
        data = shown.json()["data"]
        assert data["authorization_boundary_id"] == boundary["id"]
        assert data["exchange_connection_id"] == class_a["id"]
        assert data["format"] == "class_a_material"
        assert data["document_type"] == "soc2_report"
        assert data["state"] == "pending_review"
        assert data["sha256"] == material["sha256"]
        # Not from a push.
        assert data["push_confirmed"] is None

        downloaded = admin_client.get(material["links"]["file"])
        assert downloaded.status_code == 200, downloaded.text
        assert downloaded.content == REPORT
        assert downloaded.headers["content-type"].startswith("application/pdf")
        assert downloaded.headers["X-Content-SHA256"] == material["sha256"]

        # Decided on the boundary like any received document; the admin is
        # exempt from separation of duties.
        accepted = admin_client.post(f"{material['links']['received_document']}/accept", json={})
        assert accepted.status_code == 200, accepted.text
        assert accepted.json()["data"]["state"] == "accepted"

    @pytest.mark.validation
    def test_unknown_kind_is_refused(
        self, admin_client: httpx.Client, class_a: dict[str, Any]
    ) -> None:
        response = _add(admin_client, class_a, kind="iso27001")
        assert_error_envelope(response, expected_status=422)
        assert "soc2_report" in " ".join(response.json()["details"])

    @pytest.mark.validation
    def test_missing_file_is_refused(
        self, admin_client: httpx.Client, class_a: dict[str, Any]
    ) -> None:
        response = admin_client.post(_path(class_a), data={"kind": "soc2_report"})
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_a_connection_that_is_not_class_a_is_refused(
        self, admin_client: httpx.Client, class_b: dict[str, Any]
    ) -> None:
        assert_error_envelope(_add(admin_client, class_b), expected_status=422)
        assert admin_client.get(_path(class_b)).json()["data"] == []

    @pytest.mark.validation
    def test_unknown_connection_is_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{CONNECTIONS}/0/certification_materials")
        assert_error_envelope(response, expected_status=404)

    @pytest.mark.auth
    def test_requires_a_token(self, anon_client: httpx.Client, class_a: dict[str, Any]) -> None:
        assert_error_envelope(anon_client.get(_path(class_a)), expected_status=401)
        assert_error_envelope(_add(anon_client, class_a), expected_status=401)

    @pytest.mark.authz
    def test_non_admin_without_connections_manage_is_refused(
        self, user_client: httpx.Client, admin_client: httpx.Client, class_a: dict[str, Any]
    ) -> None:
        assert_error_envelope(user_client.get(_path(class_a)), expected_status=403)
        assert_error_envelope(_add(user_client, class_a), expected_status=403)
        assert admin_client.get(_path(class_a)).json()["data"] == []
