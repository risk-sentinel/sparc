"""Tests for /api/v1/exchange_connections and their document sources (#1354).

A connection is another system SPARC pulls FedRAMP, OSCAL, HDF or XCCDF
documents from. These tests stay off the network: they register, read,
update and remove connections and their document addresses. Pull, discover
and test_connection are exercised only where they reach nothing (a
connection with no address answers 422; a caller without the permission,
403). Fetching from a real trust center is covered by the request specs,
with ExchangeFetcher stubbed.

The credential SPARC sends there is write-only: no response may carry it.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.exchange, pytest.mark.phase2]

PATH = "/api/v1/exchange_connections"
SECRET = "phase2-credential-never-echoed"
HOST = "trust.provider.example"


def _payload(boundary_id: int, **overrides: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "name": f"phase2-connection-{uuid.uuid4().hex[:8]}",
        "authorization_boundary_id": boundary_id,
        "root_url": f"https://{HOST}/",
        "auth_scheme": "bearer",
        "credential": SECRET,
        "fedramp_id": "FR2400000001",
        "certification_class": "B",
        "certification_type": "20x",
        "spki_sha256": ["ab" * 32],
        "allowed_cidrs": ["203.0.113.0/24"],
    }
    body.update(overrides)
    return {"exchange_connection": body}


@pytest.fixture
def connection(admin_client: httpx.Client, seeded_boundary_id: int) -> Iterator[dict[str, Any]]:
    response = admin_client.post(PATH, json=_payload(seeded_boundary_id))
    assert response.status_code == 201, response.text
    record = response.json()["data"]
    try:
        yield record
    finally:
        admin_client.delete(f"{PATH}/{record['id']}")


class TestExchangeConnections:
    @pytest.mark.happy
    def test_create_returns_the_connection_without_its_credential(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        response = admin_client.post(PATH, json=_payload(seeded_boundary_id))
        assert response.status_code == 201, response.text
        try:
            data = response.json()["data"]
            assert data["credential_set"] is True
            assert "credential" not in data
            assert SECRET not in response.text
            assert data["pinned_hosts"] == [HOST]
            assert data["spki_sha256"] == ["ab" * 32]
            assert data["allowed_cidrs"] == ["203.0.113.0/24"]
        finally:
            admin_client.delete(f"{PATH}/{response.json()['data']['id']}")

    @pytest.mark.happy
    def test_list_and_show_never_carry_the_credential(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        listed = admin_client.get(PATH, params={"items": 200})
        assert listed.status_code == 200, listed.text
        assert connection["id"] in [c["id"] for c in listed.json()["data"]]
        assert SECRET not in listed.text

        shown = admin_client.get(f"{PATH}/{connection['id']}")
        assert shown.status_code == 200, shown.text
        assert shown.json()["data"]["document_sources"] == []
        assert SECRET not in shown.text

    def test_update_keeps_the_credential_unless_sent(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        response = admin_client.patch(
            f"{PATH}/{connection['id']}", json={"exchange_connection": {"enabled": False}}
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["enabled"] is False
        assert response.json()["data"]["credential_set"] is True

        cleared = admin_client.patch(
            f"{PATH}/{connection['id']}", json={"exchange_connection": {"credential": ""}}
        )
        assert cleared.status_code == 200, cleared.text
        assert cleared.json()["data"]["credential_set"] is False

    @pytest.mark.validation
    def test_plain_http_is_refused(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        response = admin_client.post(
            PATH, json=_payload(seeded_boundary_id, root_url=f"http://{HOST}/")
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_unrecognized_field_is_refused(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        response = admin_client.post(
            PATH, json=_payload(seeded_boundary_id, encrypted_credential="x")
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.auth
    def test_requires_a_token(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(PATH), expected_status=401)

    @pytest.mark.authz
    def test_non_admin_without_connections_manage_is_refused(
        self, user_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        assert_error_envelope(user_client.get(PATH), expected_status=403)
        assert_error_envelope(
            user_client.post(PATH, json=_payload(seeded_boundary_id)), expected_status=403
        )

    @pytest.mark.validation
    def test_pull_discover_and_test_refuse_a_connection_with_nothing_to_reach(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        # No root address and no documents: nothing SPARC may reach, so each
        # action answers 422 without leaving the instance.
        created = admin_client.post(PATH, json=_payload(seeded_boundary_id, root_url=None))
        assert created.status_code == 201, created.text
        record_id = created.json()["data"]["id"]
        try:
            pulled = admin_client.post(f"{PATH}/{record_id}/pull")
            assert_error_envelope(pulled, expected_status=422)

            discovered = admin_client.post(f"{PATH}/{record_id}/discover")
            assert_error_envelope(discovered, expected_status=422)

            tested = admin_client.post(f"{PATH}/{record_id}/test_connection")
            assert_error_envelope(tested, expected_status=422)
            assert tested.json()["reason"] == "configuration"
        finally:
            admin_client.delete(f"{PATH}/{record_id}")

    @pytest.mark.authz
    def test_non_admin_cannot_pull_discover_or_test(
        self, user_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        for action in ("pull", "discover", "test_connection"):
            response = user_client.post(f"{PATH}/{connection['id']}/{action}")
            assert_error_envelope(response, expected_status=403)

    def test_delete_removes_it(self, admin_client: httpx.Client, seeded_boundary_id: int) -> None:
        created = admin_client.post(PATH, json=_payload(seeded_boundary_id))
        assert created.status_code == 201, created.text
        record_id = created.json()["data"]["id"]

        deleted = admin_client.delete(f"{PATH}/{record_id}")
        assert deleted.status_code == 200, deleted.text
        assert deleted.json()["data"] == {"id": record_id, "deleted": True}
        assert admin_client.get(f"{PATH}/{record_id}").status_code == 404


class TestExchangeDocumentSources:
    @pytest.mark.happy
    def test_add_update_list_and_remove(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        path = f"{PATH}/{connection['id']}/document_sources"
        created = admin_client.post(
            path,
            json={
                "exchange_document_source": {
                    "url": f"https://{HOST}/package/vdr.json",
                    "format": "fedramp",
                    "document_type": "vulnerability-detail-report",
                    "pull_interval_hours": 12,
                }
            },
        )
        assert created.status_code == 201, created.text
        source = created.json()["data"]
        assert source["format"] == "fedramp"
        assert source["pull_interval_hours"] == 12

        updated = admin_client.patch(
            f"{path}/{source['id']}", json={"exchange_document_source": {"enabled": False}}
        )
        assert updated.status_code == 200, updated.text
        assert updated.json()["data"]["enabled"] is False

        listed = admin_client.get(path)
        assert listed.status_code == 200, listed.text
        assert [s["id"] for s in listed.json()["data"]] == [source["id"]]

        removed = admin_client.delete(f"{path}/{source['id']}")
        assert removed.status_code == 200, removed.text
        assert admin_client.get(path).json()["data"] == []

    @pytest.mark.validation
    def test_unknown_format_is_refused(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            f"{PATH}/{connection['id']}/document_sources",
            json={
                "exchange_document_source": {
                    "url": f"https://{HOST}/package/x.docx",
                    "format": "docx",
                }
            },
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.authz
    def test_non_admin_is_refused(
        self, user_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        response = user_client.get(f"{PATH}/{connection['id']}/document_sources")
        assert_error_envelope(response, expected_status=403)
