"""Tests for /api/v1/converters and its entries (#1011).

Converters ingest external framework mappings. Before #1011 every refresh and
import was browser-only — found by the missing-endpoint axis of #995.

The refresh endpoint is asynchronous, so the property that matters is that it
does NOT claim the work is done: 202, not 200.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.catalogs, pytest.mark.phase2]

PATH = "/api/v1/converters"


def _payload(**overrides: Any) -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    body = {
        "name": f"phase2-converter-{suffix}",
        "converter_type": "cci_to_nist",
        "status": "draft",
        "source_framework": "DISA CCI",
        "target_framework": "NIST SP 800-53",
        "description": "Created by the API contract suite.",
    }
    body.update(overrides)
    return {"converter": body}


@pytest.fixture
def converter(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(PATH, json=_payload())
    assert response.status_code == 201, response.text
    record = response.json()["data"]
    try:
        yield record
    finally:
        admin_client.delete(f"{PATH}/{record['id']}")


class TestCreate:
    @pytest.mark.happy
    def test_create_persists_and_reads_back(
        self, admin_client: httpx.Client, converter: dict[str, Any]
    ) -> None:
        shown = admin_client.get(f"{PATH}/{converter['id']}")
        assert shown.status_code == 200, shown.text

        data = shown.json()["data"]
        assert data["name"] == converter["name"]
        assert data["converter_type"] == "cci_to_nist"
        assert data["refreshable"] is True, "a cci_to_nist converter should be refreshable"

    @pytest.mark.validation
    def test_unknown_converter_type_is_refused(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json=_payload(converter_type="invented"))
        assert response.status_code == 422, response.text

    @pytest.mark.validation
    def test_unrecognized_field_is_refused(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json=_payload(uuid=str(uuid.uuid4())))
        assert response.status_code == 422, response.text
        assert "uuid" in " ".join(response.json()["details"])

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.post(PATH, json=_payload()), expected_status=401)

    @pytest.mark.authz
    def test_caller_without_write_is_refused(self, user_client: httpx.Client) -> None:
        response = user_client.post(PATH, json=_payload())
        assert response.status_code in (401, 403), response.text


class TestReadsAreOpen:
    """#919 removed converters.read: any authenticated caller may read them.

    Pinned so a later "tightening" is a failing test rather than a silent
    narrowing of behaviour that was decided on purpose.
    """

    @pytest.mark.happy
    def test_a_non_privileged_user_can_read(
        self, user_client: httpx.Client, converter: dict[str, Any]
    ) -> None:
        listing = user_client.get(PATH)
        assert listing.status_code == 200, listing.text

        shown = user_client.get(f"{PATH}/{converter['id']}")
        assert shown.status_code == 200, shown.text

    @pytest.mark.auth
    def test_but_not_anonymously(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(PATH), expected_status=401)


class TestRefresh:
    @pytest.mark.happy
    def test_refresh_answers_202_and_does_not_claim_completion(
        self, admin_client: httpx.Client, converter: dict[str, Any]
    ) -> None:
        response = admin_client.post(f"{PATH}/{converter['id']}/refresh")
        assert response.status_code == 202, (
            f"an asynchronous refresh must not answer {response.status_code}: {response.text[:200]}"
        )

        data = response.json()["data"]
        assert data["status"] == "processing"
        assert data["refresh"]["enqueued"] is True

    @pytest.mark.validation
    def test_a_type_with_no_refresh_service_is_refused_by_name(
        self, admin_client: httpx.Client
    ) -> None:
        created = admin_client.post(PATH, json=_payload(converter_type="custom"))
        assert created.status_code == 201, created.text
        record = created.json()["data"]

        try:
            assert record["refreshable"] is False

            response = admin_client.post(f"{PATH}/{record['id']}/refresh")
            assert response.status_code == 422, response.text
            assert "cci_to_nist" in response.json()["expected"]
        finally:
            admin_client.delete(f"{PATH}/{record['id']}")

    @pytest.mark.authz
    def test_caller_without_write_cannot_refresh(
        self, admin_client: httpx.Client, user_client: httpx.Client,
        converter: dict[str, Any]
    ) -> None:
        response = user_client.post(f"{PATH}/{converter['id']}/refresh")
        assert response.status_code in (401, 403), response.text

        shown = admin_client.get(f"{PATH}/{converter['id']}").json()["data"]
        assert shown["status"] != "processing", "a refused refresh started one anyway"


class TestEntries:
    @pytest.mark.happy
    def test_create_list_and_delete_an_entry(
        self, admin_client: httpx.Client, converter: dict[str, Any]
    ) -> None:
        entries_path = f"{PATH}/{converter['id']}/entries"

        created = admin_client.post(
            entries_path,
            json={"converter_entry": {"source_id": "CCI-000123", "target_id": "AC-2",
                                      "relationship": "equal"}},
        )
        assert created.status_code == 201, created.text
        entry_id = created.json()["data"]["id"]

        listing = admin_client.get(entries_path)
        assert entry_id in [row["id"] for row in listing.json()["data"]]

        deleted = admin_client.delete(f"{entries_path}/{entry_id}")
        assert deleted.status_code == 200, deleted.text

        after = admin_client.get(entries_path).json()["data"]
        assert entry_id not in [row["id"] for row in after], (
            "the entry was deleted but still lists"
        )

    @pytest.mark.pagination
    def test_source_id_filter_narrows_truthfully(
        self, admin_client: httpx.Client, converter: dict[str, Any]
    ) -> None:
        entries_path = f"{PATH}/{converter['id']}/entries"
        for source, target in (("CCI-000001", "AC-1"), ("CCI-000002", "AU-2")):
            admin_client.post(
                entries_path,
                json={"converter_entry": {"source_id": source, "target_id": target,
                                          "relationship": "equal"}},
            )

        filtered = admin_client.get(entries_path, params={"source_id": "CCI-000001"})
        assert filtered.status_code == 200, filtered.text

        sources = [row["source_id"] for row in filtered.json()["data"]]
        assert sources == ["CCI-000001"], f"the filter did not narrow: {sources}"

    @pytest.mark.validation
    def test_duplicate_source_target_pair_is_refused(
        self, admin_client: httpx.Client, converter: dict[str, Any]
    ) -> None:
        entries_path = f"{PATH}/{converter['id']}/entries"
        body = {"converter_entry": {"source_id": "CCI-000777", "target_id": "AC-7",
                                    "relationship": "equal"}}

        assert admin_client.post(entries_path, json=body).status_code == 201
        assert admin_client.post(entries_path, json=body).status_code == 422

    @pytest.mark.validation
    def test_unknown_relationship_is_refused(
        self, admin_client: httpx.Client, converter: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            f"{PATH}/{converter['id']}/entries",
            json={"converter_entry": {"source_id": "CCI-000999", "target_id": "AC-9",
                                      "relationship": "vaguely_related"}},
        )
        assert response.status_code == 422, response.text

    @pytest.mark.authz
    def test_caller_without_write_cannot_add_an_entry(
        self, admin_client: httpx.Client, user_client: httpx.Client,
        converter: dict[str, Any]
    ) -> None:
        entries_path = f"{PATH}/{converter['id']}/entries"
        before = admin_client.get(entries_path).json()["meta"]["count"]

        response = user_client.post(
            entries_path,
            json={"converter_entry": {"source_id": "CCI-000404", "target_id": "AC-4",
                                      "relationship": "equal"}},
        )
        assert response.status_code in (401, 403), response.text

        after = admin_client.get(entries_path).json()["meta"]["count"]
        assert after == before, "a refused request added an entry anyway"


class TestExport:
    @pytest.mark.happy
    def test_export_includes_every_entry(
        self, admin_client: httpx.Client, converter: dict[str, Any]
    ) -> None:
        admin_client.post(
            f"{PATH}/{converter['id']}/entries",
            json={"converter_entry": {"source_id": "CCI-000010", "target_id": "AC-1",
                                      "relationship": "equal"}},
        )

        response = admin_client.get(f"{PATH}/{converter['id']}/export")
        assert response.status_code == 200, response.text

        entries = response.json()["data"]["entries"]
        assert "CCI-000010" in [row["source_id"] for row in entries]
