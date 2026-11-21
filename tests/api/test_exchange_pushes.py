"""Tests for a provider's signed push (#1354).

    POST /api/v1/exchange_connections/:exchange_connection_id/document_sources/:id/push

A push tells SPARC that one registered document of a connection changed. It
carries no API token: the credential is an Ed25519 signature (header
``SPARC-Push-Signature``, with ``SPARC-Push-Timestamp``) made with a key
pinned on the connection (``push_public_keys``). Every authentication
failure answers the same 401 ``{"error": "Push not accepted"}``, so the
response cannot be used to learn which connections or documents exist.

Python's standard library cannot make an Ed25519 signature and this suite
carries no crypto dependency, so these tests cover the REFUSAL paths only.
The accepted push (202 and its pending receipt), its confirmation by a fresh
pull, the 409 replay and the 413 size cap are covered by the request specs
(spec/requests/api/v1/exchange_pushes_spec.rb), which sign with a real key.

The connections here are created with no IP ranges, so a refusal is the
signature's and not the address check's. Each is removed afterwards.
"""

from __future__ import annotations

import base64
import os
import time
import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.exchange, pytest.mark.phase2]

CONNECTIONS = "/api/v1/exchange_connections"
HOST = "trust.provider.example"
# The public half of an Ed25519 key, base64 of the raw 32 bytes. Its private
# half was discarded: nothing here can sign with it, which is the point.
PUSH_KEY = "qFefWoEcrH8p8yNgYjmKWU+/qyYla7rB8bLSdB8i47o="
NOT_ACCEPTED = {"error": "Push not accepted"}
BODY = b'{"reportPeriod": {"from": "2026-10-01T00:00:00Z"}, "vulnerabilities": []}'


def _create_connection(client: httpx.Client, boundary_id: int, **overrides: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "name": f"phase2-push-connection-{uuid.uuid4().hex[:8]}",
        "authorization_boundary_id": boundary_id,
        "root_url": f"https://{HOST}/",
        "auth_scheme": "none",
        "fedramp_id": "FR2400000001",
        "certification_class": "B",
        "certification_type": "20x",
    }
    body.update(overrides)
    response = client.post(CONNECTIONS, json={"exchange_connection": body})
    assert response.status_code == 201, response.text
    connection = response.json()["data"]

    source = client.post(
        f"{CONNECTIONS}/{connection['id']}/document_sources",
        json={
            "exchange_document_source": {
                "url": f"https://{HOST}/package/vdr.json",
                "format": "fedramp",
                "document_type": "vulnerability-detail-report",
            }
        },
    )
    if source.status_code != 201:
        client.delete(f"{CONNECTIONS}/{connection['id']}")
    assert source.status_code == 201, source.text
    connection["source"] = source.json()["data"]
    return connection


@pytest.fixture
def pushable(admin_client: httpx.Client, seeded_boundary_id: int) -> Iterator[dict[str, Any]]:
    """An enabled connection with a push key pinned, and one document."""
    connection = _create_connection(
        admin_client, seeded_boundary_id, push_public_keys=[PUSH_KEY]
    )
    try:
        assert connection["push_enabled"] is True
        # No IP ranges (the default), so the address check admits any caller.
        assert connection["allowed_cidrs"] == []
        yield connection
    finally:
        admin_client.delete(f"{CONNECTIONS}/{connection['id']}")


@pytest.fixture
def keyless(admin_client: httpx.Client, seeded_boundary_id: int) -> Iterator[dict[str, Any]]:
    """A connection with no push key: it takes no pushes at all."""
    connection = _create_connection(admin_client, seeded_boundary_id)
    try:
        assert connection["push_enabled"] is False
        yield connection
    finally:
        admin_client.delete(f"{CONNECTIONS}/{connection['id']}")


def _push_path(connection_id: Any, source_id: Any) -> str:
    return f"{CONNECTIONS}/{connection_id}/document_sources/{source_id}/push"


def _path_for(connection: dict[str, Any]) -> str:
    return _push_path(connection["id"], connection["source"]["id"])


def _garbage_signature() -> str:
    # The right shape (base64 of 64 bytes) signed by no pinned key.
    return base64.b64encode(os.urandom(64)).decode()


def _signed_looking_headers(timestamp: int | None = None) -> dict[str, str]:
    return {
        "Content-Type": "application/json",
        "SPARC-Push-Timestamp": str(int(time.time()) if timestamp is None else timestamp),
        "SPARC-Push-Signature": _garbage_signature(),
    }


def _push(
    client: httpx.Client, path: str, *, body: bytes = BODY, headers: dict[str, str] | None = None
) -> httpx.Response:
    return client.post(path, content=body, headers=headers or {"Content-Type": "application/json"})


def _assert_not_accepted(response: httpx.Response) -> None:
    assert_error_envelope(response, expected_status=401)
    assert response.json() == NOT_ACCEPTED


def _receipts(client: httpx.Client, connection: dict[str, Any]) -> list[dict[str, Any]]:
    response = client.get(f"{CONNECTIONS}/{connection['id']}/push_receipts")
    assert response.status_code == 200, response.text
    return response.json()["data"]


class TestExchangePushRefusals:
    @pytest.mark.auth
    def test_unsigned_push_is_not_accepted(
        self, anon_client: httpx.Client, admin_client: httpx.Client, pushable: dict[str, Any]
    ) -> None:
        assert "Authorization" not in anon_client.headers
        _assert_not_accepted(_push(anon_client, _path_for(pushable)))
        assert _receipts(admin_client, pushable) == []

    @pytest.mark.auth
    def test_an_api_token_is_not_a_signature(
        self, admin_client: httpx.Client, pushable: dict[str, Any]
    ) -> None:
        # The suite's admin Bearer token, and no signature: the token is not
        # the credential here, whoever it belongs to.
        _assert_not_accepted(_push(admin_client, _path_for(pushable)))
        assert _receipts(admin_client, pushable) == []

    @pytest.mark.auth
    def test_a_signature_by_no_pinned_key_is_not_accepted(
        self, anon_client: httpx.Client, admin_client: httpx.Client, pushable: dict[str, Any]
    ) -> None:
        response = _push(anon_client, _path_for(pushable), headers=_signed_looking_headers())
        _assert_not_accepted(response)

        shown = admin_client.get(f"{CONNECTIONS}/{pushable['id']}")
        assert shown.status_code == 200, shown.text
        assert shown.json()["data"]["last_pushed_at"] is None
        assert shown.json()["data"]["last_push_status"] is None
        assert _receipts(admin_client, pushable) == []

    @pytest.mark.auth
    def test_a_malformed_signature_or_stale_timestamp_is_not_accepted(
        self, anon_client: httpx.Client, pushable: dict[str, Any]
    ) -> None:
        not_base64 = _signed_looking_headers()
        not_base64["SPARC-Push-Signature"] = "not a signature"
        _assert_not_accepted(_push(anon_client, _path_for(pushable), headers=not_base64))

        stale = _signed_looking_headers(timestamp=int(time.time()) - 3600)
        _assert_not_accepted(_push(anon_client, _path_for(pushable), headers=stale))

    @pytest.mark.auth
    def test_unknown_connection_or_document_answers_as_a_bad_signature(
        self, anon_client: httpx.Client, pushable: dict[str, Any]
    ) -> None:
        bad_signature = _push(anon_client, _path_for(pushable), headers=_signed_looking_headers())
        unknown_connection = _push(
            anon_client,
            _push_path(0, pushable["source"]["id"]),
            headers=_signed_looking_headers(),
        )
        unknown_document = _push(
            anon_client, _push_path(pushable["id"], 0), headers=_signed_looking_headers()
        )

        _assert_not_accepted(bad_signature)
        for response in (unknown_connection, unknown_document):
            assert (response.status_code, response.text) == (
                bad_signature.status_code,
                bad_signature.text,
            )

    @pytest.mark.auth
    def test_a_connection_with_no_push_key_takes_no_push(
        self, anon_client: httpx.Client, keyless: dict[str, Any]
    ) -> None:
        # The connection is located first, so with no key pinned even an
        # empty body is refused as not accepted rather than as empty.
        _assert_not_accepted(
            _push(anon_client, _path_for(keyless), headers=_signed_looking_headers())
        )
        _assert_not_accepted(
            _push(anon_client, _path_for(keyless), body=b"", headers=_signed_looking_headers())
        )

    @pytest.mark.validation
    def test_empty_push_to_a_pushable_connection_is_400(
        self, anon_client: httpx.Client, admin_client: httpx.Client, pushable: dict[str, Any]
    ) -> None:
        # The body is checked before the timestamp and signature, once the
        # connection, document and address have passed.
        response = _push(
            anon_client, _path_for(pushable), body=b"", headers=_signed_looking_headers()
        )
        assert_error_envelope(response, expected_status=400)
        assert response.json()["error"] == "The push carries no document"
        assert _receipts(admin_client, pushable) == []

    @pytest.mark.auth
    def test_a_disabled_connection_takes_no_push(
        self, anon_client: httpx.Client, admin_client: httpx.Client, pushable: dict[str, Any]
    ) -> None:
        disabled = admin_client.patch(
            f"{CONNECTIONS}/{pushable['id']}", json={"exchange_connection": {"enabled": False}}
        )
        assert disabled.status_code == 200, disabled.text
        assert disabled.json()["data"]["push_enabled"] is False

        # Refused at the connection, before the body: an empty push is 401 too.
        _assert_not_accepted(
            _push(anon_client, _path_for(pushable), body=b"", headers=_signed_looking_headers())
        )
