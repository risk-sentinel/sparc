"""Tests for /api/v1/sar_documents.

8 logical endpoints — same shape as SSP. See test_ssp_documents.py for
the reference implementation; this module mirrors it with
SAR-controller-specific tweaks.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _document_helpers import create_doc, delete_doc, make_payload
from conftest import assert_error_envelope, assert_paginated_envelope
from schemas import (
    SarDocumentIndex,
    SarDocumentShow,
    assert_create_round_trip,
    validate_index_response,
    validate_show_response,
)

pytestmark = [pytest.mark.documents, pytest.mark.phase1]


PATH = "/api/v1/sar_documents"
PARAM_KEY = "sar_document"


# ── Helpers ────────────────────────────────────────────────────────────────

def _new_payload(boundary_id: int = 1) -> dict[str, Any]:
    return make_payload(PARAM_KEY, {"authorization_boundary_id": boundary_id})


# ── Fixtures ───────────────────────────────────────────────────────────────

@pytest.fixture
def sar_doc(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    doc = create_doc(admin_client, PATH, _new_payload())
    try:
        yield doc
    finally:
        delete_doc(admin_client, PATH, doc["slug"])


# ── index ──────────────────────────────────────────────────────────────────

class TestIndex:
    @pytest.mark.happy
    def test_admin_lists_documents(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH)
        assert response.status_code == 200, response.text
        assert_paginated_envelope(response.json())
        # #433 slice 2 — content-style validation
        validate_index_response(response, SarDocumentIndex)

    @pytest.mark.pagination
    def test_pagination_query_params_respected(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH, params={"page": 1, "items": 5})
        assert response.status_code == 200
        meta = response.json()["meta"]
        assert meta["page"] == 1
        assert meta["items"] == 5

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(PATH), expected_status=401)


# ── show ───────────────────────────────────────────────────────────────────

class TestShow:
    @pytest.mark.happy
    def test_admin_shows_document(
        self, admin_client: httpx.Client, sar_doc: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{sar_doc['slug']}")
        # #433 slice 2 — content-style validation (detailed Show shape)
        envelope = validate_show_response(response, SarDocumentShow)
        assert envelope.data.slug == sar_doc["slug"]

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(f"{PATH}/anything"), expected_status=401)

    def test_unknown_slug_returns_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/this-does-not-exist-{uuid.uuid4().hex}")
        assert_error_envelope(response, expected_status=404)


# ── create ─────────────────────────────────────────────────────────────────

class TestCreate:
    @pytest.mark.happy
    def test_admin_creates_document(self, admin_client: httpx.Client) -> None:
        payload = _new_payload()
        response = admin_client.post(PATH, json=payload)
        assert response.status_code in (200, 201), response.text
        slug = response.json()["data"]["slug"]
        delete_doc(admin_client, PATH, slug)

    @pytest.mark.happy
    def test_create_round_trip(self, admin_client: httpx.Client) -> None:
        """#433 slice 3 — fields sent on Create must come back from Show."""
        assert_create_round_trip(
            admin_client, PATH, _new_payload(), PARAM_KEY, SarDocumentShow
        )

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(PATH, json=_new_payload()), expected_status=401
        )

    @pytest.mark.authz
    def test_non_admin_without_write_returns_403(self, user_client: httpx.Client) -> None:
        response = user_client.post(PATH, json=_new_payload())
        assert response.status_code in (401, 403), response.text

    @pytest.mark.validation
    def test_missing_name_returns_422(self, admin_client: httpx.Client) -> None:
        payload = {PARAM_KEY: {"authorization_boundary_id": 1}}
        response = admin_client.post(PATH, json=payload)
        assert_error_envelope(response, expected_status=422)


# ── update ─────────────────────────────────────────────────────────────────

class TestUpdate:
    @pytest.mark.happy
    def test_admin_updates_document_via_put(
        self, admin_client: httpx.Client, sar_doc: dict[str, Any]
    ) -> None:
        new_description = f"updated by phase2 {uuid.uuid4().hex[:6]}"
        response = admin_client.put(
            f"{PATH}/{sar_doc['slug']}",
            json={PARAM_KEY: {"description": new_description}},
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["description"] == new_description

    @pytest.mark.happy
    def test_admin_updates_document_via_patch(
        self, admin_client: httpx.Client, sar_doc: dict[str, Any]
    ) -> None:
        new_description = f"patched {uuid.uuid4().hex[:6]}"
        response = admin_client.patch(
            f"{PATH}/{sar_doc['slug']}",
            json={PARAM_KEY: {"description": new_description}},
        )
        assert response.status_code == 200
        assert response.json()["data"]["description"] == new_description

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.put(f"{PATH}/anything", json={}), expected_status=401
        )


# ── destroy ────────────────────────────────────────────────────────────────

class TestDestroy:
    @pytest.mark.happy
    def test_admin_destroys_document(self, admin_client: httpx.Client) -> None:
        doc = create_doc(admin_client, PATH, _new_payload())
        response = admin_client.delete(f"{PATH}/{doc['slug']}")
        assert response.status_code == 200, response.text
        assert response.json()["data"]["deleted"] is True

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.delete(f"{PATH}/anything"), expected_status=401)


# ── update_fields (bulk) ───────────────────────────────────────────────────

class TestUpdateFields:
    @pytest.mark.happy
    def test_admin_updates_fields(
        self, admin_client: httpx.Client, sar_doc: dict[str, Any]
    ) -> None:
        response = admin_client.put(
            f"{PATH}/{sar_doc['slug']}/update_fields",
            json={"controls": {}},
        )
        assert response.status_code == 200, response.text
        assert response.json()["success"] is True

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.put(f"{PATH}/anything/update_fields", json={"controls": {}}),
            expected_status=401,
        )


# ── export ─────────────────────────────────────────────────────────────────

class TestExport:
    @pytest.mark.happy
    def test_admin_exports_document(
        self, admin_client: httpx.Client, sar_doc: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{sar_doc['slug']}/export")
        assert response.status_code == 200, response.text
        assert isinstance(response.json(), dict)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{PATH}/anything/export"), expected_status=401
        )


# ── convert ────────────────────────────────────────────────────────────────

class TestConvert:
    @pytest.mark.happy
    def test_no_file_returns_400(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(f"{PATH}/convert")
        assert_error_envelope(response, expected_status=400)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.post(f"{PATH}/convert"), expected_status=401)
