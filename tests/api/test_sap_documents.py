"""Tests for /api/v1/sap_documents.

5 logical endpoints — CRUD + export. Same shape as SSP without convert
or update_fields. See test_ssp_documents.py for the reference
implementation.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _crud_contract import CrudContract
from _document_helpers import create_doc, delete_doc, make_payload
from conftest import assert_error_envelope, assert_paginated_envelope
from schemas import (
    SapDocumentIndex,
    SapDocumentShow,
    assert_create_round_trip,
    assert_update_round_trip,
    validate_index_response,
    validate_show_response,
)

pytestmark = [pytest.mark.documents, pytest.mark.phase1]


PATH = "/api/v1/sap_documents"
PARAM_KEY = "sap_document"


def _new_payload(boundary_id: int) -> dict[str, Any]:
    # #952 — an assessment plan plans the assessment of ONE system, so the
    # boundary is required at create. Mirrors test_sar_documents.py.
    return make_payload(PARAM_KEY, {"authorization_boundary_id": boundary_id})


@pytest.fixture
def sap_doc(admin_client: httpx.Client, seeded_boundary_id: int) -> Iterator[dict[str, Any]]:
    doc = create_doc(admin_client, PATH, _new_payload(seeded_boundary_id))
    try:
        yield doc
    finally:
        delete_doc(admin_client, PATH, doc["slug"])


# #995 — the shared matrix for this group: documented status, an INDEPENDENT
# read after every write, gone-from-show-and-index after delete, and a refused
# caller changing nothing.
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
        validate_index_response(response, SapDocumentIndex)

    @pytest.mark.pagination
    def test_pagination_query_params_respected(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH, params={"page": 1, "items": 5})
        assert response.status_code == 200
        meta = response.json()["meta"]
        assert meta["page"] == 1 and meta["items"] == 5

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(PATH), expected_status=401)


class TestShow:
    @pytest.mark.happy
    def test_admin_shows_document(
        self, admin_client: httpx.Client, sap_doc: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{sap_doc['slug']}")
        # #433 slice 2 — content-style validation (detailed Show shape)
        envelope = validate_show_response(response, SapDocumentShow)
        assert envelope.data.slug == sap_doc["slug"]

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(f"{PATH}/anything"), expected_status=401)

    def test_unknown_slug_returns_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/missing-{uuid.uuid4().hex}")
        assert_error_envelope(response, expected_status=404)


class TestCreate:
    @pytest.mark.happy
    def test_admin_creates_document(

        self, admin_client: httpx.Client, seeded_boundary_id: int

    ) -> None:
        response = admin_client.post(PATH, json=_new_payload(seeded_boundary_id))
        assert response.status_code in (200, 201), response.text
        delete_doc(admin_client, PATH, response.json()["data"]["slug"])

    @pytest.mark.happy
    def test_create_round_trip(

        self, admin_client: httpx.Client, seeded_boundary_id: int

    ) -> None:
        """#433 slice 3 — fields sent on Create must come back from Show."""
        assert_create_round_trip(
            admin_client, PATH, _new_payload(seeded_boundary_id), PARAM_KEY, SapDocumentShow
        )

    @pytest.mark.auth
    def test_no_token_returns_401(

        self, anon_client: httpx.Client, seeded_boundary_id: int

    ) -> None:
        assert_error_envelope(
            anon_client.post(PATH, json=_new_payload(seeded_boundary_id)), expected_status=401
        )

    @pytest.mark.authz
    def test_non_admin_without_write_returns_403(

        self, user_client: httpx.Client, seeded_boundary_id: int

    ) -> None:
        response = user_client.post(PATH, json=_new_payload(seeded_boundary_id))
        assert response.status_code in (401, 403)

    @pytest.mark.validation
    def test_missing_name_returns_422(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json={PARAM_KEY: {"description": "no name"}})
        assert_error_envelope(response, expected_status=422)


class TestUpdate:
    @pytest.mark.happy
    def test_admin_updates_via_put(
        self, admin_client: httpx.Client, sap_doc: dict[str, Any]
    ) -> None:
        new_desc = f"updated {uuid.uuid4().hex[:6]}"
        response = admin_client.put(
            f"{PATH}/{sap_doc['slug']}",
            json={PARAM_KEY: {"description": new_desc}},
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["description"] == new_desc

    @pytest.mark.happy
    def test_admin_updates_via_patch(
        self, admin_client: httpx.Client, sap_doc: dict[str, Any]
    ) -> None:
        """The PATCH persists, confirmed by an independent read.

        This asserted only a status code until #995 — it would have passed
        against an endpoint that discarded the payload entirely, which is
        exactly what #994 did.
        """
        assert_update_round_trip(
            admin_client,
            PATH,
            sap_doc["slug"],
            {"description": f"patched {uuid.uuid4().hex[:6]}"},
            PARAM_KEY,
            SapDocumentShow,
            restore=False,  # the fixture owns this document and deletes it
        )

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.put(f"{PATH}/anything", json={}), expected_status=401
        )


class TestDestroy:
    @pytest.mark.happy
    def test_admin_destroys_document(

        self, admin_client: httpx.Client, seeded_boundary_id: int

    ) -> None:
        doc = create_doc(admin_client, PATH, _new_payload(seeded_boundary_id))
        response = admin_client.delete(f"{PATH}/{doc['slug']}")
        assert response.status_code == 200
        assert response.json()["data"]["deleted"] is True

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.delete(f"{PATH}/anything"), expected_status=401)
