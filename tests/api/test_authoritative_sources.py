"""Tests for /api/v1/authoritative_sources — export, import and create (#372, #396, #646).

Three endpoints:

  GET  /api/v1/authoritative_sources/export   signed envelope of this instance's
                                              authoritative resources, for a named peer
  POST /api/v1/authoritative_sources/import   verify a peer's envelope and import it
  POST /api/v1/authoritative_sources          add a library source (#646)

Export and import are BOTH endpoints on this instance, so the round trip needs
no second SPARC: registering a peer and exporting for it produces an envelope
this same instance can be asked to import. Only `federation_peers#sync`, which
makes an outbound call, needs a second instance.

That matters, because this module previously said the happy path was "exercised
by the sync flow tested in test_federation_peers.py against a self-loop
configuration" — and that module's own docstring says sync is exercised against
an UNREACHABLE peer, the test being `test_admin_sync_to_unreachable_peer_returns_502`.
Neither export nor import had ever been run successfully by this suite.

Import dedupes on `(federated_from_instance, original_uuid)` and takes
`federated_from_instance` from the EXPORTING instance's url, not the peer's, so
the rows a round trip creates are created once and skipped by every later run.
Nothing below may assume it is the first run on this instance.
"""

from __future__ import annotations

import base64
import json
import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.federation, pytest.mark.phase2]


EXPORT_PATH = "/api/v1/authoritative_sources/export"
IMPORT_PATH = "/api/v1/authoritative_sources/import"
CREATE_PATH = "/api/v1/authoritative_sources"
PEERS_PATH = "/api/v1/federation_peers"


def _decode_payload(envelope: dict[str, Any]) -> dict[str, Any]:
    """The envelope payload is base64url with the padding stripped."""
    raw = envelope["payload"]
    return json.loads(base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)))


@pytest.fixture(scope="module")
def peer(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    """A peer registered against this instance, so export has someone to sign for.

    The same record is used for both directions, which is what makes the
    round trip verifiable: one signing secret signs the export and checks the
    import.
    """
    suffix = uuid.uuid4().hex[:8]
    response = admin_client.post(
        PEERS_PATH,
        json={
            "federation_peer": {
                "name": f"phase2-selfloop-{suffix}",
                "base_url": f"https://phase2-selfloop-{suffix}.example.gov",
                # Disabled so no background sync fires at this fabricated URL.
                "enabled": False,
                "service_token": "phase2-selfloop-token",
                "signing_secret": "phase2-selfloop-signing-secret-32-chars",
            }
        },
    )
    assert response.status_code in (200, 201), response.text
    created = response.json()["data"]
    try:
        yield created
    finally:
        admin_client.delete(f"{PEERS_PATH}/{created['id']}")


@pytest.fixture(scope="module")
def envelope(admin_client: httpx.Client, peer: dict[str, Any]) -> dict[str, Any]:
    response = admin_client.get(EXPORT_PATH, params={"peer": peer["name"]})
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.happy
class TestExport:
    def test_returns_a_signed_envelope_addressed_to_the_peer(
        self, envelope: dict[str, Any], peer: dict[str, Any]
    ) -> None:
        assert set(envelope) >= {"alg", "key_id", "payload", "signature"}, envelope
        assert envelope["key_id"] == peer["name"], (
            "the envelope is keyed to a different peer than it was exported for"
        )
        assert envelope["signature"], "envelope carries no signature"

    def test_the_payload_is_a_bundle_naming_the_exporting_instance(
        self, envelope: dict[str, Any]
    ) -> None:
        payload = _decode_payload(envelope)

        assert payload["metadata"]["instance_url"], payload["metadata"]
        assert payload["metadata"]["bundle_uuid"], payload["metadata"]
        assert isinstance(payload.get("resources"), list), payload.keys()


@pytest.mark.happy
class TestRoundTrip:
    def test_this_instance_imports_the_envelope_it_exported(
        self, admin_client: httpx.Client, peer: dict[str, Any], envelope: dict[str, Any]
    ) -> None:
        """The property the pair exists for: a signed export verifies on import.

        Counted rather than asserted at a fixed number — the dedup key comes
        from the exporting instance, so a second run of this suite legitimately
        skips what the first imported.
        """
        entries = len(_decode_payload(envelope)["resources"])
        assert entries, "the export carried no resources, so importing it proves nothing"

        response = admin_client.post(IMPORT_PATH, json={"peer": peer["name"], "envelope": envelope})

        assert response.status_code == 200, response.text
        data = response.json()["data"]
        assert data["errors"] == [], data["errors"]
        assert len(data["imported"]) + len(data["skipped"]) == entries, (
            f"{entries} resources sent, {len(data['imported'])} imported and "
            f"{len(data['skipped'])} skipped — the rest were silently dropped"
        )

    def test_importing_the_same_envelope_again_adds_nothing(
        self, admin_client: httpx.Client, peer: dict[str, Any], envelope: dict[str, Any]
    ) -> None:
        """Federation is re-run on a schedule; a repeat must not duplicate rows."""
        body = {"peer": peer["name"], "envelope": envelope}
        first = admin_client.post(IMPORT_PATH, json=body)
        assert first.status_code == 200, first.text

        again = admin_client.post(IMPORT_PATH, json=body)

        assert again.status_code == 200, again.text
        data = again.json()["data"]
        assert data["imported"] == [], f"a repeated import created {data['imported']}"
        assert data["skipped"], "nothing was skipped, so nothing was recognized as already held"


@pytest.mark.validation
class TestSignatureVerification:
    def test_a_tampered_payload_is_refused_by_name(
        self, admin_client: httpx.Client, peer: dict[str, Any], envelope: dict[str, Any]
    ) -> None:
        """The whole point of signing. Payload edited, signature left intact.

        NIST SC-12 / SC-13 / AU-10 — a peer bundle that can be edited in flight
        and still import would let anyone with the network path write
        authoritative back-matter into this instance.
        """
        payload = _decode_payload(envelope)
        payload["metadata"]["instance_url"] = "https://not-the-real-peer.example.gov"
        forged = dict(envelope)
        forged["payload"] = (
            base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
        )

        response = admin_client.post(IMPORT_PATH, json={"peer": peer["name"], "envelope": forged})

        assert_error_envelope(response, expected_status=422)
        assert "ignature" in response.json()["error"], (
            f"refused, but not as a signature failure: {response.json()['error']}"
        )

    def test_unknown_peer_returns_422(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(
            EXPORT_PATH, params={"peer": "phase2-this-peer-name-should-never-exist"}
        )
        assert_error_envelope(response, expected_status=422)

    def test_import_from_unknown_peer_returns_422(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(
            IMPORT_PATH,
            json={
                "peer": "phase2-this-peer-name-should-never-exist",
                "envelope": {
                    "alg": "HS256",
                    "payload": "",
                    "signature": "",
                    "key_id": "phase2-this-peer-name-should-never-exist",
                },
            },
        )
        assert_error_envelope(response, expected_status=422)


@pytest.mark.happy
class TestCreate:
    """#646 — a normal authenticated write, deliberately NOT behind `federate`."""

    def test_creates_a_source_and_an_independent_read_confirms_it(
        self, admin_client: httpx.Client
    ) -> None:
        title = f"phase2-authoritative-{uuid.uuid4().hex[:8]}"

        created = admin_client.post(
            CREATE_PATH,
            json={
                "back_matter_resource": {
                    "title": title,
                    "description": "#995 sweep",
                    "href": "https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final",
                    "rel": "reference",
                    "media_type": "text/html",
                }
            },
        )

        assert created.status_code == 201, created.text
        resource = created.json()["data"]
        assert resource["title"] == title

        read_back = admin_client.get(f"/api/v1/back_matter_resources/{resource['id']}")
        assert read_back.status_code == 200, read_back.text
        assert read_back.json()["data"]["title"] == title

    def test_an_unrecognized_field_is_refused(self, admin_client: httpx.Client) -> None:
        """#1021 — this endpoint silently dropped unknown fields until the
        strict-params conversion reached it."""
        response = admin_client.post(
            CREATE_PATH,
            json={
                "back_matter_resource": {
                    "title": f"phase2-strict-{uuid.uuid4().hex[:8]}",
                    "href": "https://example.gov/doc",
                    "not_a_real_field": "should be refused",
                }
            },
        )

        assert_error_envelope(response, expected_status=422)
        # Named, so this cannot pass on some unrelated 422 — a missing required
        # field would also be a 422 and would prove nothing about strictness.
        assert "not_a_real_field" in json.dumps(response.json()), response.text


@pytest.mark.authz
class TestAuthorization:
    def test_non_admin_without_federate_is_refused_the_export(
        self, user_client: httpx.Client, peer: dict[str, Any]
    ) -> None:
        """Exactly 403, not "one of several plausible refusals".

        This previously accepted 401, 403 or 422, which cannot distinguish a
        working permission gate from a broken token or a bad peer name.
        """
        response = user_client.get(EXPORT_PATH, params={"peer": peer["name"]})

        assert_error_envelope(response, expected_status=403)

    def test_non_admin_without_federate_is_refused_the_import(
        self, user_client: httpx.Client, peer: dict[str, Any], envelope: dict[str, Any]
    ) -> None:
        response = user_client.post(IMPORT_PATH, json={"peer": peer["name"], "envelope": envelope})

        assert_error_envelope(response, expected_status=403)


@pytest.mark.auth
class TestAuthentication:
    def test_export_refuses_an_anonymous_caller(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(EXPORT_PATH, params={"peer": "anything"}), expected_status=401
        )

    def test_import_refuses_an_anonymous_caller(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(IMPORT_PATH, json={"peer": "anything", "envelope": {}}),
            expected_status=401,
        )

    def test_create_refuses_an_anonymous_caller(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(CREATE_PATH, json={"back_matter_resource": {"title": "nope"}}),
            expected_status=401,
        )
