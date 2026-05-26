"""Tests for /api/v1/federation_peers.

6 logical endpoints: index/show/create/update/destroy + sync. Tests
manage their own peer records in setup/teardown so the suite leaves
no FederationPeer rows behind. The sync endpoint is exercised against
an unreachable peer (4xx/5xx path) — a happy-path sync test would
require a second running SPARC instance, out of scope for the contract
tests in this suite.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope
from schemas import (
    FederationPeerIndex,
    FederationPeerShow,
    assert_create_round_trip,
    validate_index_response,
    validate_show_response,
)


pytestmark = [pytest.mark.federation, pytest.mark.phase2]


PATH = "/api/v1/federation_peers"


def _new_payload(**overrides: Any) -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    body = {
        "name": f"phase2-peer-{suffix}",
        "base_url": f"https://phase2-{suffix}.example.gov",
        "enabled": False,  # disabled by default so sync attempts don't fire
        "service_token": "phase2-test-bearer-token",
        "signing_secret": "phase2-test-signing-secret-32-chars-min",
    }
    body.update(overrides)
    return {"federation_peer": body}


def _create(client: httpx.Client) -> dict[str, Any]:
    response = client.post(PATH, json=_new_payload())
    assert response.status_code in (200, 201), response.text
    return response.json()["data"]


def _delete(client: httpx.Client, peer_id: int) -> None:
    response = client.delete(f"{PATH}/{peer_id}")
    assert response.status_code in (200, 404), response.text


@pytest.fixture
def peer(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    p = _create(admin_client)
    try:
        yield p
    finally:
        _delete(admin_client, p["id"])


class TestIndex:
    @pytest.mark.happy
    def test_admin_lists_peers(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH)
        assert response.status_code == 200, response.text
        body = response.json()
        assert "data" in body and isinstance(body["data"], list)
        assert "meta" in body and "count" in body["meta"]
        # #562 was fixed in v1.7.3 — federation_peers now uses the
        # shared paginate() helper, so the standard envelope applies.
        validate_index_response(response, FederationPeerIndex)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(PATH), expected_status=401)


class TestShow:
    @pytest.mark.happy
    def test_admin_shows_peer(
        self, admin_client: httpx.Client, peer: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{peer['id']}")
        # #433 slice 2 — content-style validation (also enforces that the
        # schema declares no `service_token` / `signing_secret` field, so a
        # future serializer regression that leaks them would fail loudly).
        envelope = validate_show_response(response, FederationPeerShow)
        assert envelope.data.id == peer["id"]
        assert envelope.data.service_token_set is True
        assert envelope.data.signing_secret_set is True

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(f"{PATH}/0"), expected_status=401)

    def test_unknown_id_returns_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/99999999")
        assert_error_envelope(response, expected_status=404)


class TestCreate:
    @pytest.mark.happy
    def test_admin_creates_peer(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json=_new_payload())
        assert response.status_code in (200, 201)
        peer_id = response.json()["data"]["id"]
        _delete(admin_client, peer_id)

    @pytest.mark.happy
    def test_create_round_trip(self, admin_client: httpx.Client) -> None:
        """#433 slice 4 — fields sent on Create must come back from Show.

        Sensitive fields (service_token, signing_secret) are exposed as
        boolean ``*_set`` indicators only — the values themselves never
        come back. They live in ignore_fields.
        """
        assert_create_round_trip(
            admin_client,
            PATH,
            _new_payload(),
            "federation_peer",
            FederationPeerShow,
            identifier="id",
            ignore_fields={"service_token", "signing_secret"},
        )

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(PATH, json=_new_payload()), expected_status=401
        )

    @pytest.mark.authz
    def test_non_admin_returns_403(self, user_client: httpx.Client) -> None:
        response = user_client.post(PATH, json=_new_payload())
        assert response.status_code in (401, 403)


class TestUpdate:
    @pytest.mark.happy
    def test_admin_updates_peer(
        self, admin_client: httpx.Client, peer: dict[str, Any]
    ) -> None:
        new_url = f"https://updated-{uuid.uuid4().hex[:6]}.example.gov"
        response = admin_client.patch(
            f"{PATH}/{peer['id']}",
            json={"federation_peer": {"base_url": new_url}},
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["base_url"] == new_url

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.patch(f"{PATH}/0", json={}), expected_status=401
        )


class TestDestroy:
    @pytest.mark.happy
    def test_admin_destroys_peer(self, admin_client: httpx.Client) -> None:
        p = _create(admin_client)
        response = admin_client.delete(f"{PATH}/{p['id']}")
        assert response.status_code == 200
        body = response.json()["data"]
        assert body["deleted"] is True

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.delete(f"{PATH}/0"), expected_status=401)


class TestSync:
    def test_admin_sync_to_unreachable_peer_returns_502(
        self, admin_client: httpx.Client, peer: dict[str, Any]
    ) -> None:
        # Peer base_url is a phase2-*.example.gov hostname that does not
        # resolve, so the upstream call will fail. Controller returns
        # 502 in that case (or 422 if the peer is disabled per fixture
        # default — both are documented).
        response = admin_client.post(f"{PATH}/{peer['id']}/sync")
        assert response.status_code in (422, 502), response.text
        assert_error_envelope(response, expected_status=response.status_code)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(f"{PATH}/0/sync"), expected_status=401
        )
