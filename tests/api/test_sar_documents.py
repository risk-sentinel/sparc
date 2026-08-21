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

from _crud_contract import CrudContract
from _document_helpers import create_doc, delete_doc, make_payload
from _export_contract import ExportContract
from _field_import_contract import FieldImportContract
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

def _new_payload(boundary_id: int) -> dict[str, Any]:
    return make_payload(PARAM_KEY, {"authorization_boundary_id": boundary_id})


# ── Fixtures ───────────────────────────────────────────────────────────────

@pytest.fixture
def sar_doc(admin_client: httpx.Client, seeded_boundary_id: int) -> Iterator[dict[str, Any]]:
    doc = create_doc(admin_client, PATH, _new_payload(seeded_boundary_id))
    try:
        yield doc
    finally:
        delete_doc(admin_client, PATH, doc["slug"])


# ── index ──────────────────────────────────────────────────────────────────

# #995 — the shared matrix for this group: documented status, an INDEPENDENT
# read after every write, gone-from-show-and-index after delete, and a refused
# caller changing nothing.
# #995 — the shared export contract: JSON not an error page, and the export
# actually CONTAINS the record it claims to export.
# #995 — the shared field-import contract.
class TestFieldImportContract(FieldImportContract):
    PATH = PATH

    def _document_slug(self, admin_client):
        if getattr(self, "_imp_slug", None):
            return self._imp_slug
        docs = admin_client.get(PATH, params={"items": 20}).json()["data"]
        for row in docs:
            export = admin_client.get(f"{PATH}/{row['slug']}/export")
            if export.status_code != 200:
                continue
            controls = export.json().get("controls") or []
            if controls:
                self._imp_slug = row["slug"]
                self._imp_control = controls[0]["control_id"]
                return self._imp_slug
        raise AssertionError("no document on this instance has controls to import into")

    def _control_and_field(self, admin_client):
        self._document_slug(admin_client)
        return (self._imp_control, "notes_weakness")


class TestExportContract(ExportContract):
    def _export_path(self, admin_client):
        docs = admin_client.get(PATH, params={"items": 1})
        self._doc = docs.json()["data"][0]
        return f"{PATH}/{self._doc['slug']}/export"

    def _expected_content(self, admin_client):
        self._export_path(admin_client)
        return self._doc["name"]


class TestCrudContract(CrudContract):
    PATH = PATH
    PARAM_KEY = PARAM_KEY
    IDENTIFIER = "slug"

    def _payload(self, admin_client):
        boundaries = admin_client.get("/api/v1/authorization_boundaries", params={"items": 1})
        rows = boundaries.json()["data"]
        assert rows, "no authorization boundary on this instance"
        return _new_payload(rows[0]["id"])[PARAM_KEY]


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
    def test_admin_creates_document(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        payload = _new_payload(seeded_boundary_id)
        response = admin_client.post(PATH, json=payload)
        assert response.status_code in (200, 201), response.text
        slug = response.json()["data"]["slug"]
        delete_doc(admin_client, PATH, slug)

    @pytest.mark.happy
    def test_create_round_trip(self, admin_client: httpx.Client, seeded_boundary_id: int) -> None:
        """#433 slice 3 — fields sent on Create must come back from Show."""
        assert_create_round_trip(
            admin_client, PATH, _new_payload(seeded_boundary_id), PARAM_KEY, SarDocumentShow
        )

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client, seeded_boundary_id: int) -> None:
        assert_error_envelope(
            anon_client.post(PATH, json=_new_payload(seeded_boundary_id)), expected_status=401
        )

    @pytest.mark.authz
    def test_non_admin_without_write_returns_403(
        self, user_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        response = user_client.post(PATH, json=_new_payload(seeded_boundary_id))
        assert response.status_code in (401, 403), response.text

    @pytest.mark.validation
    def test_missing_name_returns_422(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        payload = {PARAM_KEY: {"authorization_boundary_id": seeded_boundary_id}}
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
    def test_admin_destroys_document(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        doc = create_doc(admin_client, PATH, _new_payload(seeded_boundary_id))
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
