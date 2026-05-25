"""Tests for /api/v1/cdef_documents.

5 logical endpoints — CRUD + export. CDEF (component definition)
documents differ from SSP/SAR/etc in that they are not boundary-scoped
— they describe a component (image, package, hardware) that can be
linked to multiple boundaries via leveraged authorizations.
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
    CdefDocumentIndex,
    CdefDocumentShow,
    assert_create_round_trip,
    validate_index_response,
    validate_show_response,
)


pytestmark = [pytest.mark.documents, pytest.mark.phase1]


PATH = "/api/v1/cdef_documents"
PARAM_KEY = "cdef_document"


def _new_payload() -> dict[str, Any]:
    return make_payload(PARAM_KEY)


@pytest.fixture
def cdef_doc(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    doc = create_doc(admin_client, PATH, _new_payload())
    try:
        yield doc
    finally:
        delete_doc(admin_client, PATH, doc["slug"])


class TestIndex:
    @pytest.mark.happy
    def test_admin_lists_documents(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH)
        assert response.status_code == 200, response.text
        assert_paginated_envelope(response.json())
        # #433 slice 1 — content-style validation: every item in the list
        # must conform to the CdefDocumentIndex schema (strict, extra=forbid).
        validate_index_response(response, CdefDocumentIndex)

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
        self, admin_client: httpx.Client, cdef_doc: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{cdef_doc['slug']}")
        # #433 slice 1 — content-style validation: the show response is the
        # detailed CdefDocumentShow shape (adds description / oscal_version /
        # controls_count / oscal_metadata / back_matter_resources beyond what
        # the index returns).
        envelope = validate_show_response(response, CdefDocumentShow)
        assert envelope.data.slug == cdef_doc["slug"]

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(f"{PATH}/anything"), expected_status=401)

    def test_unknown_slug_returns_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/missing-{uuid.uuid4().hex}")
        assert_error_envelope(response, expected_status=404)


class TestCreate:
    @pytest.mark.happy
    def test_admin_creates_document(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json=_new_payload())
        assert response.status_code in (200, 201), response.text
        delete_doc(admin_client, PATH, response.json()["data"]["slug"])

    @pytest.mark.happy
    def test_create_round_trip(self, admin_client: httpx.Client) -> None:
        """#433 slice 3 — fields sent on Create must come back from Show.

        Catches persistence drops and show-serializer omissions that the
        index/show schema validation alone can't surface.
        """
        assert_create_round_trip(
            admin_client, PATH, _new_payload(), PARAM_KEY, CdefDocumentShow
        )

    @pytest.mark.happy
    def test_create_round_trip_rich_payload(self, admin_client: httpx.Client) -> None:
        """#433 slice 3 — exercise more than just name+description.

        Sets every type-specific field permitted by the CDEF create
        params (cdef_type, cdef_version, file_type, benchmark_id) and
        confirms every one survives Create → Show.
        """
        from _document_helpers import make_payload

        suffix = uuid.uuid4().hex[:8]
        payload = make_payload(
            PARAM_KEY,
            {
                "cdef_type": "custom",
                "cdef_version": "1.2.3",
                "file_type": "json",
                "benchmark_id": f"BENCH-{suffix}",
            },
        )
        assert_create_round_trip(
            admin_client, PATH, payload, PARAM_KEY, CdefDocumentShow
        )

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(PATH, json=_new_payload()), expected_status=401
        )

    @pytest.mark.authz
    def test_non_admin_without_write_returns_403(self, user_client: httpx.Client) -> None:
        response = user_client.post(PATH, json=_new_payload())
        assert response.status_code in (401, 403)

    @pytest.mark.validation
    def test_missing_name_returns_422(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json={PARAM_KEY: {"description": "no name"}})
        assert_error_envelope(response, expected_status=422)


class TestUpdate:
    @pytest.mark.happy
    @pytest.mark.xfail(
        reason="#555 — Update returns compact (index) shape instead of detailed "
        "(show), so `description` is absent from the response even though the "
        "update persists. Remove this xfail once the controller passes "
        "detailed: true on update.",
        strict=False,
    )
    def test_admin_updates_via_put(
        self, admin_client: httpx.Client, cdef_doc: dict[str, Any]
    ) -> None:
        new_desc = f"updated {uuid.uuid4().hex[:6]}"
        response = admin_client.put(
            f"{PATH}/{cdef_doc['slug']}",
            json={PARAM_KEY: {"description": new_desc}},
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["description"] == new_desc

    @pytest.mark.happy
    def test_admin_updates_via_patch(
        self, admin_client: httpx.Client, cdef_doc: dict[str, Any]
    ) -> None:
        response = admin_client.patch(
            f"{PATH}/{cdef_doc['slug']}",
            json={PARAM_KEY: {"description": "patched"}},
        )
        assert response.status_code == 200

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.put(f"{PATH}/anything", json={}), expected_status=401
        )


class TestDestroy:
    @pytest.mark.happy
    def test_admin_destroys_document(self, admin_client: httpx.Client) -> None:
        doc = create_doc(admin_client, PATH, _new_payload())
        response = admin_client.delete(f"{PATH}/{doc['slug']}")
        assert response.status_code == 200
        assert response.json()["data"]["deleted"] is True

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.delete(f"{PATH}/anything"), expected_status=401)
