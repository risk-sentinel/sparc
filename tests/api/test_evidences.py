"""Tests for the Evidence API (#756).

Endpoints:
  - /api/v1/evidences                              index, show, create, update, destroy
  - /api/v1/evidences/:id/control_links            index, create, destroy

Evidence create accepts multipart (file + metadata) or plain JSON for
metadata-only records. Provenance (collected_at / collected_by) is
server-stamped and must never reflect client-supplied values (#738, AU-10).

Document-scoped control links drive OSCAL back-matter emission — a link
carrying document_type + document_id creates a managed BackMatterResource
on that document. This suite asserts the link round-trip; the
back-matter emission itself is covered by the Rails request spec.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.evidence, pytest.mark.phase2]

_EVIDENCES = "/api/v1/evidences"
_MISSING_EVIDENCE = "99999999"


def _new_evidence_payload(**overrides: Any) -> dict[str, Any]:
    payload = {
        "title": "Contract-suite evidence",
        "description": "Created by the API contract suite.",
        "evidence_type": "artifact",
        "status": "draft",
        "source": "https://example.com/contract-suite",
    }
    payload.update(overrides)
    return {"evidence": payload}


@pytest.fixture
def evidence(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    """Create a throwaway evidence record and clean it up afterwards."""
    response = admin_client.post(_EVIDENCES, json=_new_evidence_payload())
    assert response.status_code == 201, response.text
    record = response.json()["data"]
    try:
        yield record
    finally:
        admin_client.delete(f"{_EVIDENCES}/{record['id']}")


# ── Auth ──────────────────────────────────────────────────────────────────

class TestAuth:
    @pytest.mark.auth
    def test_index_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(_EVIDENCES), expected_status=401)

    @pytest.mark.auth
    def test_show_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(f"{_EVIDENCES}/1"), expected_status=401)

    @pytest.mark.auth
    def test_create_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(_EVIDENCES, json=_new_evidence_payload()), expected_status=401
        )

    @pytest.mark.auth
    def test_destroy_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.delete(f"{_EVIDENCES}/1"), expected_status=401)

    @pytest.mark.auth
    def test_control_links_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{_EVIDENCES}/1/control_links"), expected_status=401
        )


class TestNotFound:
    def test_show_unknown_returns_404(self, admin_client: httpx.Client) -> None:
        assert_error_envelope(
            admin_client.get(f"{_EVIDENCES}/{_MISSING_EVIDENCE}"), expected_status=404
        )

    def test_control_links_unknown_evidence_returns_404(
        self, admin_client: httpx.Client
    ) -> None:
        assert_error_envelope(
            admin_client.get(f"{_EVIDENCES}/{_MISSING_EVIDENCE}/control_links"),
            expected_status=404,
        )


class TestAuthz:
    @pytest.mark.authz
    def test_non_privileged_create_rejected(self, user_client: httpx.Client) -> None:
        response = user_client.post(_EVIDENCES, json=_new_evidence_payload())
        assert response.status_code in (401, 403), response.text

    @pytest.mark.authz
    def test_non_privileged_destroy_rejected(self, user_client: httpx.Client) -> None:
        response = user_client.delete(f"{_EVIDENCES}/{_MISSING_EVIDENCE}")
        assert response.status_code in (401, 403, 404), response.text


# ── Index ─────────────────────────────────────────────────────────────────

class TestIndex:
    @pytest.mark.happy
    @pytest.mark.pagination
    def test_index_returns_paginated_envelope(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(_EVIDENCES, params={"items": 5})
        assert response.status_code == 200, response.text
        body = response.json()
        assert isinstance(body["data"], list)
        assert {"page", "count", "items"} <= set(body["meta"])
        assert len(body["data"]) <= 5

    @pytest.mark.pagination
    def test_index_filters_by_type(self, admin_client: httpx.Client, evidence: dict) -> None:
        response = admin_client.get(_EVIDENCES, params={"type": "artifact"})
        assert response.status_code == 200, response.text
        assert all(e["evidence_type"] == "artifact" for e in response.json()["data"])

    @pytest.mark.pagination
    def test_index_filters_by_status(self, admin_client: httpx.Client, evidence: dict) -> None:
        response = admin_client.get(_EVIDENCES, params={"status": "draft"})
        assert response.status_code == 200, response.text
        assert all(e["status"] == "draft" for e in response.json()["data"])


# ── Lifecycle ─────────────────────────────────────────────────────────────

class TestLifecycle:
    @pytest.mark.happy
    def test_create_show_update_destroy(self, admin_client: httpx.Client) -> None:
        created = admin_client.post(_EVIDENCES, json=_new_evidence_payload())
        assert created.status_code == 201, created.text
        record = created.json()["data"]
        evidence_id = record["id"]

        try:
            assert record["title"] == "Contract-suite evidence"
            assert record["has_file"] is False
            assert record["uuid"]
            # Detailed shape on create.
            assert "oscal_resolver_url" in record
            assert record["oscal_resolver_url"].endswith(record["uuid"])

            shown = admin_client.get(f"{_EVIDENCES}/{evidence_id}")
            assert shown.status_code == 200, shown.text
            assert shown.json()["data"]["id"] == evidence_id

            # Slug is an accepted route key.
            by_slug = admin_client.get(f"{_EVIDENCES}/{record['slug']}")
            assert by_slug.status_code == 200, by_slug.text

            updated = admin_client.patch(
                f"{_EVIDENCES}/{evidence_id}", json={"evidence": {"status": "collected"}}
            )
            assert updated.status_code == 200, updated.text
            assert updated.json()["data"]["status"] == "collected"
        finally:
            deleted = admin_client.delete(f"{_EVIDENCES}/{evidence_id}")
            assert deleted.status_code == 200, deleted.text

        assert admin_client.get(f"{_EVIDENCES}/{evidence_id}").status_code == 404

    @pytest.mark.happy
    def test_create_multipart_with_file(self, admin_client: httpx.Client) -> None:
        files = {"evidence[file]": ("evidence.txt", b"contract suite artifact", "text/plain")}
        data = {
            "evidence[title]": "Contract-suite upload",
            "evidence[description]": "Uploaded by the API contract suite.",
            "evidence[evidence_type]": "artifact",
            "evidence[status]": "draft",
            "evidence[source]": "https://example.com/contract-suite",
        }
        created = admin_client.post(_EVIDENCES, data=data, files=files)
        assert created.status_code == 201, created.text
        record = created.json()["data"]

        try:
            assert record["has_file"] is True
            assert record["original_filename"] == "evidence.txt"
            assert record["file_hash"], "expected a SHA-256 file_hash to be computed"
            assert record["file_size"] > 0
        finally:
            admin_client.delete(f"{_EVIDENCES}/{record['id']}")

    @pytest.mark.validation
    def test_create_missing_required_fields_returns_422(
        self, admin_client: httpx.Client
    ) -> None:
        response = admin_client.post(_EVIDENCES, json={"evidence": {"title": "No source"}})
        assert response.status_code == 422, response.text
        body = response.json()
        assert body["error"] == "Validation failed"
        assert isinstance(body["details"], list) and body["details"]

    @staticmethod
    def _upload_payload() -> dict[str, str]:
        return {
            "evidence[title]": "Should not persist",
            "evidence[description]": "Executable upload attempt.",
            "evidence[evidence_type]": "artifact",
            "evidence[status]": "draft",
            "evidence[source]": "https://example.com/contract-suite",
        }

    @pytest.mark.validation
    def test_unaccepted_extension_rejected(self, admin_client: httpx.Client) -> None:
        """#868 layer 1: .bin is not an accepted evidence type, so it never
        reaches content sniffing at all.

        This used to assert the #509 executable-signature message. #868 added an
        extension allowlist in front of that check, so the same ELF payload named
        .bin is now refused one layer earlier and cheaper. Still a 422 and still
        not stored — the guarantee is unchanged, the reason is stricter. The
        signature check itself is asserted below, where it is the layer that
        actually has to do the work.
        """
        files = {
            "evidence[file]": ("payload.bin", b"\x7fELF\x02\x01\x01" + b"A" * 64,
                               "application/octet-stream")
        }
        response = admin_client.post(_EVIDENCES, data=self._upload_payload(), files=files)
        assert response.status_code == 422, response.text
        assert "not an accepted evidence type" in response.json()["error"]

    @pytest.mark.validation
    def test_executable_upload_rejected(self, admin_client: httpx.Client) -> None:
        """#509 deny-list: ELF magic bytes refused even under an accepted name.

        Named .txt, so the extension allowlist passes it through and the
        executable-signature check is the only thing standing between this
        payload and storage. That makes this the case that proves renaming an
        executable to an accepted extension does not get it stored — the
        property the allowlist alone cannot provide.
        """
        files = {
            "evidence[file]": ("payload.txt", b"\x7fELF\x02\x01\x01" + b"A" * 64,
                               "text/plain")
        }
        response = admin_client.post(_EVIDENCES, data=self._upload_payload(), files=files)
        assert response.status_code == 422, response.text
        assert "Executable content is not permitted" in response.json()["error"]

    def test_provenance_is_server_stamped(self, admin_client: httpx.Client) -> None:
        """collected_at / collected_by are system-recorded (#738, AU-10)."""
        created = admin_client.post(
            _EVIDENCES,
            json=_new_evidence_payload(
                collected_by="spoofed@example.com", collected_at="1999-01-01T00:00:00Z"
            ),
        )
        assert created.status_code == 201, created.text
        record = created.json()["data"]
        try:
            assert record["collected_by"] != "spoofed@example.com"
            assert not record["collected_at"].startswith("1999")
        finally:
            admin_client.delete(f"{_EVIDENCES}/{record['id']}")


# ── Control links ─────────────────────────────────────────────────────────

class TestControlLinks:
    @pytest.mark.happy
    def test_link_list_unlink(self, admin_client: httpx.Client, evidence: dict) -> None:
        path = f"{_EVIDENCES}/{evidence['id']}/control_links"

        # #911 — BREAKING, and deliberate: control identifiers are stored and
        # returned in the OSCAL canonical form, so the API no longer echoes back
        # whatever spelling the caller sent. Posting "AC-2" yields "ac-2".
        #
        # The input side is unchanged on purpose — any legitimate spelling is
        # still accepted ("AC-2", "AC-02", "ac-2", "AC-2 (1)"), which is the
        # whole point: they name one control and now resolve to one identifier.
        created = admin_client.post(path, json={"control_link": {"control_id": "AC-2"}})
        assert created.status_code == 201, created.text
        link = created.json()["data"]
        assert link["control_id"] == "ac-2", (
            "control ids are returned canonically since #911; see the release notes"
        )

        listed = admin_client.get(path)
        assert listed.status_code == 200, listed.text
        assert any(item["id"] == link["id"] for item in listed.json()["data"])

        removed = admin_client.delete(f"{path}/{link['id']}")
        assert removed.status_code == 204, removed.text

    @pytest.mark.validation
    def test_missing_control_id_returns_422(
        self, admin_client: httpx.Client, evidence: dict
    ) -> None:
        response = admin_client.post(
            f"{_EVIDENCES}/{evidence['id']}/control_links",
            json={"control_link": {"control_id": ""}},
        )
        assert response.status_code == 422, response.text

    @pytest.mark.validation
    def test_unknown_document_type_returns_422(
        self, admin_client: httpx.Client, evidence: dict
    ) -> None:
        """document_type is constantized model-side — it must be allowlisted."""
        response = admin_client.post(
            f"{_EVIDENCES}/{evidence['id']}/control_links",
            json={"control_link": {"control_id": "AC-2", "document_type": "Kernel",
                                   "document_id": 1}},
        )
        assert response.status_code == 422, response.text
        assert "document_type must be one of" in " ".join(response.json()["details"])

    @pytest.mark.idempotency
    def test_duplicate_link_rejected(
        self, admin_client: httpx.Client, evidence: dict
    ) -> None:
        path = f"{_EVIDENCES}/{evidence['id']}/control_links"
        first = admin_client.post(path, json={"control_link": {"control_id": "AU-12"}})
        assert first.status_code == 201, first.text

        try:
            duplicate = admin_client.post(path, json={"control_link": {"control_id": "AU-12"}})
            assert duplicate.status_code == 422, duplicate.text
        finally:
            admin_client.delete(f"{path}/{first.json()['data']['id']}")
