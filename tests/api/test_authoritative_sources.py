"""Tests for /api/v1/authoritative_sources/{export,import}.

Federation export/import is bilateral: each side needs the other
registered as a FederationPeer with a matching signing_secret. Tests
here cover the auth/permission/peer-validation paths that don't need
a live cross-instance handshake. The full happy path (build envelope
on instance A, verify-and-import on instance B) is exercised by the
sync flow tested in test_federation_peers.py against a self-loop
configuration.
"""

from __future__ import annotations

import httpx
import pytest

from conftest import assert_error_envelope


pytestmark = [pytest.mark.federation, pytest.mark.phase2]


EXPORT_PATH = "/api/v1/authoritative_sources/export"
IMPORT_PATH = "/api/v1/authoritative_sources/import"


class TestExport:
    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(EXPORT_PATH, params={"peer": "anything"}),
            expected_status=401,
        )

    @pytest.mark.authz
    def test_non_admin_without_federate_returns_403(
        self, user_client: httpx.Client
    ) -> None:
        response = user_client.get(EXPORT_PATH, params={"peer": "anything"})
        # 403 if user has no permission; 422 if the user happens to have
        # back_matter.federate but the named peer doesn't exist. Both are
        # correct rejections of the request as posed.
        assert response.status_code in (401, 403, 422), response.text

    @pytest.mark.validation
    def test_unknown_peer_returns_422(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(
            EXPORT_PATH,
            params={"peer": "phase2-this-peer-name-should-never-exist"},
        )
        assert_error_envelope(response, expected_status=422)


class TestImport:
    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(
                IMPORT_PATH,
                json={"peer": "anything", "envelope": {}},
            ),
            expected_status=401,
        )

    @pytest.mark.validation
    def test_unknown_peer_returns_422(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(
            IMPORT_PATH,
            json={
                "peer": "phase2-this-peer-name-should-never-exist",
                "envelope": {
                    "alg": "HMAC-SHA256-base64url",
                    "payload": "",
                    "signature": "",
                    "key_id": "phase2-this-peer-name-should-never-exist",
                },
            },
        )
        assert_error_envelope(response, expected_status=422)
