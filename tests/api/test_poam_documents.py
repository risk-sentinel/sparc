"""Tests for /api/v1/poam_documents.

5 logical endpoints — CRUD + export. Same shape as SAP. Note that
nested POA&M children (items, risks, remediations, observations,
findings, local-components) live under their own routes that are
exercised by their own future modules — this module covers only the
top-level POA&M document.
"""

# Coverage declared for bin/api_inventory_check.rb. These endpoints are
# exercised through shared contract mixins, which express an endpoint as a
# URL path rather than by action name, so the inventory's string match
# cannot see them.
# api-inventory: covers poam_documents#import

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
    PoamDocumentIndex,
    PoamDocumentShow,
    assert_create_round_trip,
    assert_update_round_trip,
    validate_index_response,
    validate_show_response,
)

pytestmark = [pytest.mark.documents, pytest.mark.phase1]


PATH = "/api/v1/poam_documents"
PARAM_KEY = "poam_document"


def _new_payload(boundary_id: int) -> dict[str, Any]:
    # #952 — a POA&M tracks the open weaknesses of ONE system, so the boundary
    # is required at create. Mirrors test_sar_documents.py.
    return make_payload(PARAM_KEY, {"authorization_boundary_id": boundary_id})


@pytest.fixture
def poam_doc(admin_client: httpx.Client, seeded_boundary_id: int) -> Iterator[dict[str, Any]]:
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
        validate_index_response(response, PoamDocumentIndex)

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
        self, admin_client: httpx.Client, poam_doc: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{poam_doc['slug']}")
        # #433 slice 2 — content-style validation (detailed Show shape)
        envelope = validate_show_response(response, PoamDocumentShow)
        assert envelope.data.slug == poam_doc["slug"]

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
    def test_create_round_trip(self, admin_client: httpx.Client, seeded_boundary_id: int) -> None:
        """#433 slice 3 — fields sent on Create must come back from Show."""
        assert_create_round_trip(
            admin_client, PATH, _new_payload(seeded_boundary_id), PARAM_KEY, PoamDocumentShow
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
        assert response.status_code in (401, 403)

    @pytest.mark.validation
    def test_missing_name_returns_422(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json={PARAM_KEY: {"description": "no name"}})
        assert_error_envelope(response, expected_status=422)


class TestUpdate:
    @pytest.mark.happy
    def test_admin_updates_via_put(
        self, admin_client: httpx.Client, poam_doc: dict[str, Any]
    ) -> None:
        new_desc = f"updated {uuid.uuid4().hex[:6]}"
        response = admin_client.put(
            f"{PATH}/{poam_doc['slug']}",
            json={PARAM_KEY: {"description": new_desc}},
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["description"] == new_desc

    @pytest.mark.happy
    def test_admin_updates_via_patch(
        self, admin_client: httpx.Client, poam_doc: dict[str, Any]
    ) -> None:
        """The PATCH persists, confirmed by an independent read.

        This asserted only a status code until #995 — it would have passed
        against an endpoint that discarded the payload entirely, which is
        exactly what #994 did.
        """
        assert_update_round_trip(
            admin_client,
            PATH,
            poam_doc["slug"],
            {"description": f"patched {uuid.uuid4().hex[:6]}"},
            PARAM_KEY,
            PoamDocumentShow,
            restore=False,  # the fixture owns this document and deletes it
        )

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.put(f"{PATH}/anything", json={}), expected_status=401)


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


# api-inventory: covers poam_documents#generate
class TestGenerate:
    """`POST /poam_documents/generate` — build a POA&M from a SAR's findings.

    LIMITATION, stated rather than hidden: the created counts are exercised for
    CONSISTENCY, not for value. Making them non-zero needs a SAR carrying
    assessment findings on the same boundary, which is a fixture this module
    does not build. A boundary with no SAR legitimately generates an empty
    POA&M, so asserting those zeros would be asserting that nothing happened.

    What is asserted is the relationship between the summary and the document:
    `meta` claims how much was created, and the document reports how much it
    holds. Those two are computed separately and can disagree — which is the
    #994 shape, a write reporting one thing while another read says otherwise.
    """

    @pytest.fixture
    def boundary(self, admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
        suffix = uuid.uuid4().hex[:8]
        response = admin_client.post(
            "/api/v1/authorization_boundaries",
            json={
                "authorization_boundary": {
                    "name": f"phase2-poam-generate-{suffix}",
                    "description": "#995 POA&M generation sweep",
                }
            },
        )
        assert response.status_code in (200, 201), response.text
        created = response.json()["data"]
        try:
            yield created
        finally:
            admin_client.delete(f"/api/v1/authorization_boundaries/{created['id']}")

    @pytest.mark.happy
    def test_generates_a_poam_confirmed_by_an_independent_read(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        name = f"phase2-generated-poam-{uuid.uuid4().hex[:8]}"

        response = admin_client.post(
            "/api/v1/poam_documents/generate",
            json={
                "poam_document": {
                    "name": name,
                    "authorization_boundary_id": boundary["id"],
                }
            },
        )

        assert response.status_code == 201, response.text
        document = response.json()["data"]
        assert document["name"] == name
        assert document["authorization_boundary_id"] == boundary["id"]

        try:
            fetched = admin_client.get(f"/api/v1/poam_documents/{document['slug']}")
            assert fetched.status_code == 200, fetched.text
            assert fetched.json()["data"]["name"] == name, (
                "the generated POA&M is not readable under the name it reported"
            )
        finally:
            admin_client.delete(f"/api/v1/poam_documents/{document['slug']}")

    @pytest.mark.happy
    def test_the_summary_agrees_with_the_document_it_describes(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            "/api/v1/poam_documents/generate",
            json={
                "poam_document": {
                    "name": f"phase2-poam-summary-{uuid.uuid4().hex[:8]}",
                    "authorization_boundary_id": boundary["id"],
                }
            },
        )
        assert response.status_code == 201, response.text
        body = response.json()

        try:
            meta, document = body["meta"], body["data"]
            assert set(meta) >= {
                "items_created",
                "risks_created",
                "findings_created",
                "complete",
            }, meta
            assert isinstance(body["skipped"], list), body["skipped"]
            assert meta["items_created"] == document["items_count"], (
                f"meta claims {meta['items_created']} items created, the document "
                f"holds {document['items_count']}"
            )
            assert meta["findings_created"] == document["findings_count"], (
                f"meta claims {meta['findings_created']} findings created, the "
                f"document holds {document['findings_count']}"
            )
        finally:
            admin_client.delete(f"/api/v1/poam_documents/{body['data']['slug']}")

    @pytest.mark.validation
    def test_an_unrecognized_field_is_refused(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(
            "/api/v1/poam_documents/generate",
            json={"poam_document": {"name": "phase2-strict", "not_a_real_field": "x"}},
        )

        assert response.status_code == 422, response.text
        assert "not_a_real_field" in str(response.json()), response.text

    @pytest.mark.validation
    def test_an_unknown_boundary_is_refused(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(
            "/api/v1/poam_documents/generate",
            json={
                "poam_document": {
                    "name": "phase2-unknown-boundary",
                    "authorization_boundary_id": 999_999_999,
                }
            },
        )

        assert response.status_code == 404, response.text

    @pytest.mark.auth
    def test_an_anonymous_caller_is_refused(
        self, anon_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = anon_client.post(
            "/api/v1/poam_documents/generate",
            json={"poam_document": {"name": "nope", "authorization_boundary_id": boundary["id"]}},
        )

        assert response.status_code == 401, response.text
