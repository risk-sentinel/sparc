"""Tests for /api/v1/ssp_documents.

8 logical endpoints — index, show, create, update (PATCH+PUT), destroy,
convert, update_fields, export. The shape is identical to the other
document controllers (SAR, SAP, POAM, CDEF, profile_documents); this
module is the reference implementation, the others mirror it with
controller-specific tweaks.

Per-test isolation: each create-test owns the resource it creates and
deletes it in teardown. Tests that need an existing document use the
``ssp_doc`` fixture which sets up + tears down once per test.
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
    SspDocumentIndex,
    SspDocumentShow,
    assert_create_round_trip,
    validate_index_response,
    validate_show_response,
)


pytestmark = [pytest.mark.documents, pytest.mark.phase1]


PATH = "/api/v1/ssp_documents"
PARAM_KEY = "ssp_document"


# ── Helpers ────────────────────────────────────────────────────────────────

def _new_payload(boundary_id: int = 1) -> dict[str, Any]:
    """Boundary id 1 is the standard seed value in dev/test SPARC instances."""
    return make_payload(PARAM_KEY, {"authorization_boundary_id": boundary_id})


def _create_ssp(client: httpx.Client) -> dict[str, Any]:
    return create_doc(client, PATH, _new_payload())


def _delete_ssp(client: httpx.Client, slug: str) -> None:
    delete_doc(client, PATH, slug)


# ── Fixtures ───────────────────────────────────────────────────────────────

@pytest.fixture
def ssp_doc(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    """Create an SSP, hand it to the test, delete on teardown."""
    doc = _create_ssp(admin_client)
    try:
        yield doc
    finally:
        _delete_ssp(admin_client, doc["slug"])


# ── index ──────────────────────────────────────────────────────────────────

class TestIndex:
    @pytest.mark.happy
    def test_admin_lists_documents(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH)
        assert response.status_code == 200, response.text
        assert_paginated_envelope(response.json())
        # #433 slice 2 — content-style validation
        validate_index_response(response, SspDocumentIndex)

    @pytest.mark.pagination
    def test_pagination_query_params_respected(
        self, admin_client: httpx.Client, ssp_doc: dict[str, Any]
    ) -> None:
        response = admin_client.get(PATH, params={"page": 1, "items": 5})
        assert response.status_code == 200
        meta = response.json()["meta"]
        assert meta["page"] == 1
        assert meta["items"] == 5

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        response = anon_client.get(PATH)
        assert_error_envelope(response, expected_status=401)


# ── show ───────────────────────────────────────────────────────────────────

class TestShow:
    @pytest.mark.happy
    def test_admin_shows_document(
        self, admin_client: httpx.Client, ssp_doc: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{ssp_doc['slug']}")
        # #433 slice 2 — content-style validation (detailed Show shape)
        envelope = validate_show_response(response, SspDocumentShow)
        assert envelope.data.slug == ssp_doc["slug"]
        assert envelope.data.name == ssp_doc["name"]

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        response = anon_client.get(f"{PATH}/does-not-matter")
        assert_error_envelope(response, expected_status=401)

    def test_unknown_slug_returns_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/this-slug-definitely-does-not-exist-{uuid.uuid4().hex}")
        assert_error_envelope(response, expected_status=404)


# ── create ─────────────────────────────────────────────────────────────────

class TestCreate:
    @pytest.mark.happy
    def test_admin_creates_document(self, admin_client: httpx.Client) -> None:
        payload = _new_payload()
        response = admin_client.post(PATH, json=payload)
        assert response.status_code in (200, 201), response.text
        body = response.json()
        assert "slug" in body["data"]
        assert body["data"]["name"] == payload["ssp_document"]["name"]

        _delete_ssp(admin_client, body["data"]["slug"])

    @pytest.mark.happy
    def test_create_round_trip(self, admin_client: httpx.Client) -> None:
        """#433 slice 3 — fields sent on Create must come back from Show."""
        assert_create_round_trip(
            admin_client, PATH, _new_payload(), PARAM_KEY, SspDocumentShow
        )

    @pytest.mark.happy
    def test_create_round_trip_rich_payload(self, admin_client: httpx.Client) -> None:
        """#433 slice 3 — exercise type-specific SSP fields beyond name/description."""
        suffix = uuid.uuid4().hex[:8]
        payload = make_payload(
            PARAM_KEY,
            {
                "authorization_boundary_id": 1,
                "ssp_version": "2.1.0",
                "system_status": "operational",
                "security_sensitivity_level": "moderate",
            },
        )
        assert_create_round_trip(
            admin_client, PATH, payload, PARAM_KEY, SspDocumentShow
        )

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        response = anon_client.post(PATH, json=_new_payload())
        assert_error_envelope(response, expected_status=401)

    @pytest.mark.authz
    def test_non_admin_without_write_returns_403(
        self, user_client: httpx.Client
    ) -> None:
        response = user_client.post(PATH, json=_new_payload())
        # 403 expected; some configurations may also return 401 if the
        # test user has zero permissions at all. Both are valid signals
        # that the unauthorized create was rejected.
        assert response.status_code in (401, 403), response.text

    @pytest.mark.validation
    def test_missing_name_returns_422(self, admin_client: httpx.Client) -> None:
        payload = {PARAM_KEY: {"authorization_boundary_id": 1}}
        response = admin_client.post(PATH, json=payload)
        assert_error_envelope(response, expected_status=422)


# ── update ─────────────────────────────────────────────────────────────────

_UPDATE_SHAPE_XFAIL = pytest.mark.xfail(
    reason="#555 — Update returns compact (index) shape instead of detailed; "
    "`description` is absent from the response. Drift caught by #433 slice 2.",
    strict=False,
)


class TestUpdate:
    @pytest.mark.happy
    @_UPDATE_SHAPE_XFAIL
    def test_admin_updates_document_via_put(
        self, admin_client: httpx.Client, ssp_doc: dict[str, Any]
    ) -> None:
        new_description = f"updated by phase2 {uuid.uuid4().hex[:6]}"
        response = admin_client.put(
            f"{PATH}/{ssp_doc['slug']}",
            json={PARAM_KEY: {"description": new_description}},
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["description"] == new_description

    @pytest.mark.happy
    @_UPDATE_SHAPE_XFAIL
    def test_admin_updates_document_via_patch(
        self, admin_client: httpx.Client, ssp_doc: dict[str, Any]
    ) -> None:
        new_description = f"patched by phase2 {uuid.uuid4().hex[:6]}"
        response = admin_client.patch(
            f"{PATH}/{ssp_doc['slug']}",
            json={PARAM_KEY: {"description": new_description}},
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["description"] == new_description

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        response = anon_client.put(f"{PATH}/anything", json={})
        assert_error_envelope(response, expected_status=401)


# ── destroy ────────────────────────────────────────────────────────────────

class TestDestroy:
    @pytest.mark.happy
    def test_admin_destroys_document(self, admin_client: httpx.Client) -> None:
        # Don't use the ssp_doc fixture because we want to assert the
        # delete actually happened (fixture would also try to delete on
        # teardown and produce a confusing 404).
        doc = _create_ssp(admin_client)

        response = admin_client.delete(f"{PATH}/{doc['slug']}")
        assert response.status_code == 200, response.text
        assert response.json()["data"]["deleted"] is True

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        response = anon_client.delete(f"{PATH}/anything")
        assert_error_envelope(response, expected_status=401)


# ── update_fields (bulk) ───────────────────────────────────────────────────

class TestUpdateFields:
    @pytest.mark.happy
    def test_admin_updates_fields(
        self, admin_client: httpx.Client, ssp_doc: dict[str, Any]
    ) -> None:
        # The bulk-edit endpoint accepts an arbitrary controls map.
        # An empty controls map is a degenerate-but-valid case that
        # exercises the request-shape contract without depending on
        # which specific control IDs the test instance has populated.
        response = admin_client.put(
            f"{PATH}/{ssp_doc['slug']}/update_fields",
            json={"controls": {}},
        )
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["success"] is True

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        response = anon_client.put(
            f"{PATH}/anything/update_fields",
            json={"controls": {}},
        )
        assert_error_envelope(response, expected_status=401)


# ── export ─────────────────────────────────────────────────────────────────

class TestExport:
    @pytest.mark.happy
    def test_admin_exports_document(
        self, admin_client: httpx.Client, ssp_doc: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{ssp_doc['slug']}/export")
        assert response.status_code == 200, response.text
        # Export returns OSCAL JSON; validating the full schema is out
        # of scope for the contract tests — assert minimal structure
        # only.
        payload = response.json()
        assert isinstance(payload, dict) and len(payload) > 0

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        response = anon_client.get(f"{PATH}/anything/export")
        assert_error_envelope(response, expected_status=401)


# ── convert (Excel parse) ──────────────────────────────────────────────────

class TestConvert:
    @pytest.mark.happy
    def test_no_file_returns_400(self, admin_client: httpx.Client) -> None:
        # The convert endpoint requires a multipart upload; sending an
        # empty body lets us assert the controller's "No file provided"
        # guard returns 400 rather than crashing.
        response = admin_client.post(f"{PATH}/convert")
        assert_error_envelope(response, expected_status=400)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        response = anon_client.post(f"{PATH}/convert")
        assert_error_envelope(response, expected_status=401)
