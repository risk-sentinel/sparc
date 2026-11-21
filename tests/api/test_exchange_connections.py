"""Tests for /api/v1/exchange_connections and their document sources (#1354).

A connection is another system SPARC pulls FedRAMP, OSCAL, HDF or XCCDF
documents from. These tests stay off the network: they register, read,
update and remove connections and their document addresses. Pull, discover
and test_connection are exercised only where they reach nothing (a
connection with no address answers 422; a caller without the permission,
403). Fetching from a real trust center is covered by the request specs,
with ExchangeFetcher stubbed.

The credential SPARC sends there is write-only: no response may carry it.

Push and Class A (#1354): a connection pins the Ed25519 public keys a
provider signs its pushes with (``push_public_keys``, at most two) and lists
the pushes received (``push_receipts``); a Class A connection records the
framework its certification rests on and the date, which expires 12 months
later. The push itself is tested in test_exchange_pushes.py.
"""

from __future__ import annotations

import base64
import calendar
import datetime
import hashlib
import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope, assert_paginated_envelope

pytestmark = [pytest.mark.exchange, pytest.mark.phase2]

PATH = "/api/v1/exchange_connections"
SECRET = "phase2-credential-never-echoed"
HOST = "trust.provider.example"
# Public halves of three Ed25519 keys (base64 of the raw 32 bytes, and the same
# first key as PEM). Their private halves were discarded.
PUSH_KEY = "qFefWoEcrH8p8yNgYjmKWU+/qyYla7rB8bLSdB8i47o="
PUSH_KEY_PEM = (
    "-----BEGIN PUBLIC KEY-----\n"
    "MCowBQYDK2VwAyEAqFefWoEcrH8p8yNgYjmKWU+/qyYla7rB8bLSdB8i47o=\n"
    "-----END PUBLIC KEY-----\n"
)
NEXT_PUSH_KEY = "uWhxBteD/Eh0qu0ua2crDexSK4FZI9OGm+G/DiYWFq0="
THIRD_PUSH_KEY = "WzaX78xTTkiYAip39aUhdVJfft8Eg5LR8VjGretUpbs="


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


def _fingerprint(base64_key: str) -> str:
    return hashlib.sha256(base64.b64decode(base64_key)).hexdigest()[:16]


def _twelve_months_after(day: datetime.date) -> datetime.date:
    # Rails' `date + 12.months`: the same day next year, or the month's last
    # day when that day does not exist (29 February).
    year = day.year + 1
    return day.replace(year=year, day=min(day.day, calendar.monthrange(year, day.month)[1]))


def _patch(client: httpx.Client, connection: dict[str, Any], **fields: Any) -> httpx.Response:
    return client.patch(f"{PATH}/{connection['id']}", json={"exchange_connection": fields})


class TestPushSettings:
    @pytest.mark.happy
    def test_a_new_connection_takes_no_pushes(self, connection: dict[str, Any]) -> None:
        assert connection["push_public_keys"] == []
        assert connection["push_key_fingerprints"] == []
        assert connection["push_enabled"] is False
        assert connection["last_pushed_at"] is None
        assert connection["last_push_status"] is None
        assert connection["class_a"] is None

    @pytest.mark.happy
    def test_push_keys_are_pinned_and_fingerprinted(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        response = _patch(admin_client, connection, push_public_keys=[PUSH_KEY, NEXT_PUSH_KEY])
        assert response.status_code == 200, response.text
        data = response.json()["data"]
        assert data["push_public_keys"] == [PUSH_KEY, NEXT_PUSH_KEY]
        assert data["push_key_fingerprints"] == [
            _fingerprint(PUSH_KEY),
            _fingerprint(NEXT_PUSH_KEY),
        ]
        assert data["push_enabled"] is True

        shown = admin_client.get(f"{PATH}/{connection['id']}")
        assert shown.json()["data"]["push_public_keys"] == [PUSH_KEY, NEXT_PUSH_KEY]

        # A disabled connection takes no pushes, whatever keys it holds.
        disabled = _patch(admin_client, connection, enabled=False)
        assert disabled.status_code == 200, disabled.text
        assert disabled.json()["data"]["push_enabled"] is False

        cleared = _patch(admin_client, connection, enabled=True, push_public_keys=[])
        assert cleared.status_code == 200, cleared.text
        assert cleared.json()["data"]["push_public_keys"] == []
        assert cleared.json()["data"]["push_enabled"] is False

    @pytest.mark.happy
    def test_a_pem_key_is_stored_as_its_raw_base64(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        response = _patch(admin_client, connection, push_public_keys=[PUSH_KEY_PEM])
        assert response.status_code == 200, response.text
        assert response.json()["data"]["push_public_keys"] == [PUSH_KEY]
        assert response.json()["data"]["push_key_fingerprints"] == [_fingerprint(PUSH_KEY)]

    @pytest.mark.validation
    def test_a_key_that_is_not_ed25519_is_refused(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        # Base64, but not 32 bytes.
        response = _patch(admin_client, connection, push_public_keys=["bm90IGEga2V5"])
        assert_error_envelope(response, expected_status=422)
        shown = admin_client.get(f"{PATH}/{connection['id']}")
        assert shown.json()["data"]["push_public_keys"] == []

    @pytest.mark.validation
    def test_more_than_two_keys_are_refused(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        # Three valid keys: one more than the current key and the next.
        response = _patch(
            admin_client, connection, push_public_keys=[PUSH_KEY, NEXT_PUSH_KEY, THIRD_PUSH_KEY]
        )
        assert_error_envelope(response, expected_status=422)
        assert any("at most 2" in d for d in response.json()["details"])


class TestPushReceipts:
    @pytest.mark.happy
    def test_push_receipts_are_empty_for_a_new_connection(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{connection['id']}/push_receipts")
        assert response.status_code == 200, response.text
        assert_paginated_envelope(response.json())
        assert response.json()["data"] == []
        assert response.json()["meta"]["count"] == 0

    @pytest.mark.validation
    def test_push_receipts_of_an_unknown_connection_are_404(
        self, admin_client: httpx.Client
    ) -> None:
        assert_error_envelope(admin_client.get(f"{PATH}/0/push_receipts"), expected_status=404)

    @pytest.mark.auth
    def test_push_receipts_require_a_token(
        self, anon_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        response = anon_client.get(f"{PATH}/{connection['id']}/push_receipts")
        assert_error_envelope(response, expected_status=401)

    @pytest.mark.authz
    def test_push_receipts_need_connections_manage(
        self, user_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        response = user_client.get(f"{PATH}/{connection['id']}/push_receipts")
        assert_error_envelope(response, expected_status=403)


class TestClassA:
    @pytest.mark.happy
    def test_class_a_framework_and_date_set_a_twelve_month_expiry(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        certified_on = datetime.date.today() - datetime.timedelta(days=30)
        expires_on = _twelve_months_after(certified_on)
        response = _patch(
            admin_client,
            connection,
            certification_class="A",
            class_a_framework="soc2_type2",
            class_a_certified_on=certified_on.isoformat(),
        )
        assert response.status_code == 200, response.text
        class_a = response.json()["data"]["class_a"]
        assert class_a["framework"] == "soc2_type2"
        assert class_a["framework_label"] == "SOC 2 Type II"
        assert class_a["certified_on"] == certified_on.isoformat()
        assert class_a["expires_on"] == expires_on.isoformat()
        assert class_a["expired"] is False
        assert isinstance(class_a["days_left"], int)
        assert class_a["days_left"] > 0

        shown = admin_client.get(f"{PATH}/{connection['id']}")
        assert shown.json()["data"]["class_a"] == class_a

    @pytest.mark.happy
    def test_class_a_without_a_framework_is_reported_empty(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        response = _patch(admin_client, connection, certification_class="A")
        assert response.status_code == 200, response.text
        assert response.json()["data"]["class_a"] == {
            "framework": None,
            "framework_label": None,
            "certified_on": None,
            "expires_on": None,
            "expired": False,
            "days_left": None,
        }

    @pytest.mark.validation
    def test_class_a_fields_are_refused_on_another_class(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        # The fixture's connection is Class B.
        response = _patch(
            admin_client,
            connection,
            class_a_framework="fedramp_rev5",
            class_a_certified_on=(datetime.date.today() - datetime.timedelta(days=1)).isoformat(),
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_a_future_date_an_unknown_framework_or_no_date_is_refused(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        future = (datetime.date.today() + datetime.timedelta(days=30)).isoformat()
        past = (datetime.date.today() - datetime.timedelta(days=30)).isoformat()
        for fields in (
            {"class_a_framework": "govramp", "class_a_certified_on": future},
            {"class_a_framework": "iso27001", "class_a_certified_on": past},
            {"class_a_framework": "fedramp_ready"},
        ):
            response = _patch(admin_client, connection, certification_class="A", **fields)
            assert_error_envelope(response, expected_status=422)
        shown = admin_client.get(f"{PATH}/{connection['id']}")
        assert shown.json()["data"]["certification_class"] == "B"

    @pytest.mark.validation
    def test_the_expiry_is_not_writable(
        self, admin_client: httpx.Client, connection: dict[str, Any]
    ) -> None:
        response = _patch(
            admin_client, connection, certification_class="A", class_a_expires_on="2099-01-01"
        )
        assert_error_envelope(response, expected_status=422)
        assert response.json()["details"] == ["Unrecognized field: class_a_expires_on"]
        shown = admin_client.get(f"{PATH}/{connection['id']}")
        assert shown.json()["data"]["certification_class"] == "B"
        assert shown.json()["data"]["class_a"] is None
