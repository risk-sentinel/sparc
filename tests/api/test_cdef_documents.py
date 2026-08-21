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

from _bulk_destroy import BulkDestroyContract
from _crud_contract import CrudContract
from _document_helpers import create_doc, delete_doc, make_payload
from _populate_from_profile import PopulateFromProfileContract
from _review_workflow import ReviewWorkflowContract
from conftest import assert_error_envelope, assert_paginated_envelope, published_profile
from schemas import (
    CdefDocumentIndex,
    CdefDocumentShow,
    assert_create_round_trip,
    assert_update_round_trip,
    validate_index_response,
    validate_show_response,
)

pytestmark = [pytest.mark.documents, pytest.mark.phase1]


PATH = "/api/v1/cdef_documents"
PARAM_KEY = "cdef_document"

# Contract coverage of non-generic actions (bin/api_inventory_check.rb scans this
# module for each action name): the review workflow — submit_for_review /
# approve / reject — is exercised via ReviewWorkflowContract; bulk_destroy via
# BulkDestroyContract; source_from_profile via PopulateFromProfileContract;
# bulk_apply_converter_preview / bulk_apply_converter_confirm via
# TestBulkApplyConverter below.


def _new_payload() -> dict[str, Any]:
    return make_payload(PARAM_KEY)


@pytest.fixture
def cdef_doc(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    doc = create_doc(admin_client, PATH, _new_payload())
    try:
        yield doc
    finally:
        delete_doc(admin_client, PATH, doc["slug"])


# #995 — the shared matrix: documented status, an INDEPENDENT read after every
# write, gone-from-show-and-index after delete, and a refused caller changing
# nothing. Sixteen endpoints in this group, and the checks that need a real
# record live here rather than in the whole-surface sweep.
class TestCrudContract(CrudContract):
    PATH = PATH
    PARAM_KEY = PARAM_KEY
    IDENTIFIER = "slug"
    # The controller's design comment: "All CRUD operations are available to any
    # authenticated user." The AWS Labs bulk-ingest flow and the catalog refresh
    # button both depend on it (#575 Path D). Asserted rather than exempted, so
    # gating it later is a failing test.
    NON_ADMIN_MAY_WRITE_BECAUSE = (
        "CDEF is intentionally open to any authenticated user (#575 Path D)"
    )

    def _payload(self, admin_client):
        return _new_payload()[PARAM_KEY]


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


class TestBrowse:
    """#887 — search and facets, shared with the web index.

    The gap these close: the UI matched component regions, control ids,
    capabilities and check ids while this endpoint matched only name and
    description, so the same query string gave two different answers.
    """

    @pytest.mark.happy
    def test_search_narrows_the_list(self, admin_client: httpx.Client, cdef_doc) -> None:
        hit = admin_client.get(PATH, params={"q": cdef_doc["name"]})
        assert hit.status_code == 200, hit.text
        assert cdef_doc["slug"] in [d["slug"] for d in hit.json()["data"]]

        miss = admin_client.get(PATH, params={"q": "zzz-no-such-component-zzz"})
        assert miss.status_code == 200, miss.text
        assert miss.json()["data"] == []

    @pytest.mark.happy
    def test_facets_are_echoed_back(self, admin_client: httpx.Client) -> None:
        """A paginating consumer can tell what produced the result set."""
        response = admin_client.get(
            PATH, params={"partition": "aws-us-gov", "capability": "MFA"}
        )
        assert response.status_code == 200, response.text
        assert response.json()["meta"]["facets"] == {
            "partition": "aws-us-gov",
            "capability": "MFA",
        }

    def test_no_facets_reported_when_none_applied(self, admin_client: httpx.Client) -> None:
        assert admin_client.get(PATH).json()["meta"]["facets"] == {}

    def test_an_unknown_facet_value_returns_nothing_rather_than_everything(
        self, admin_client: httpx.Client
    ) -> None:
        """A facet that matches nothing must narrow, not silently no-op."""
        response = admin_client.get(PATH, params={"partition": "no-such-partition"})
        assert response.status_code == 200, response.text
        assert response.json()["data"] == []

    @pytest.mark.happy
    def test_every_row_carries_the_enriched_shape(
        self, admin_client: httpx.Client, cdef_doc
    ) -> None:
        """Including one with nothing indexed — a real state, not an error."""
        response = admin_client.get(PATH, params={"q": cdef_doc["name"]})
        row = next(d for d in response.json()["data"] if d["slug"] == cdef_doc["slug"])

        components = row["components"]
        assert components["count"] == 0
        assert components["service_titles"] == []
        assert components["control_counts"] == {"native": 0, "enriched": 0}
        # Partitions arrive with their labels resolved, so a consumer never has
        # to keep its own aws-us-gov -> "AWS GovCloud" table.
        assert components["partitions"] == []

    def test_component_details_are_detail_only(
        self, admin_client: httpx.Client, cdef_doc
    ) -> None:
        """On a list this would be a row multiplier for no benefit."""
        index_row = next(
            d
            for d in admin_client.get(PATH, params={"q": cdef_doc["name"]}).json()["data"]
            if d["slug"] == cdef_doc["slug"]
        )
        assert "component_details" not in index_row

        show = admin_client.get(f"{PATH}/{cdef_doc['slug']}").json()["data"]
        assert "component_details" in show


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


class TestReviewWorkflow(ReviewWorkflowContract):
    """DocumentApprovalApi review workflow (#630/#634) for cdef_documents.

    Contract lives in _review_workflow.ReviewWorkflowContract; CDEFs are
    slug-addressed.
    """

    PATH = PATH
    IDENT_KEY = "slug"

    @pytest.fixture
    def review_doc(self, admin_client: httpx.Client, cdef_doc: dict[str, Any]) -> dict[str, Any]:
        # #757 — a CDEF needs >=1 control to submit_for_review. Populate it from
        # a published profile (the seeded resolved baseline) so the submit ->
        # approve/reject contract runs. If no published profile exists, fall back
        # to the bare CDEF: the two content-gated tests then skip via
        # _submit_or_skip (documented), while the three auth / no-submit contract
        # tests still run — don't skip the whole fixture.
        profile = published_profile(admin_client)
        if profile:
            resp = admin_client.post(
                f"{PATH}/{cdef_doc['slug']}/source_from_profile",
                json={"source_profile_id": profile},
            )
            assert resp.status_code == 200, resp.text
        return cdef_doc

    def test_submit_empty_requires_content(
        self, admin_client: httpx.Client, cdef_doc: dict[str, Any]
    ) -> None:
        # A CDEF with no controls cannot be submitted for review
        # (DocumentApprovalService content gate: "At least one control").
        resp = admin_client.post(f"{PATH}/{cdef_doc['slug']}/submit_for_review")
        assert resp.status_code == 422, resp.text
        assert "content" in resp.text.lower(), resp.text


class TestBulkDestroy(BulkDestroyContract):
    """Admin-only bulk delete (#629). Contract lives in _bulk_destroy."""

    PATH = PATH

    def _create_id(self, admin_client: httpx.Client) -> int:
        return create_doc(admin_client, PATH, _new_payload())["id"]


class TestPopulateFromProfile(PopulateFromProfileContract):
    """Source a CDEF's control-implementation from a published profile (#628).

    Contract lives in _populate_from_profile; CDEFs are slug-addressed. #982
    renamed the action to `source_from_profile`: OSCAL reaches a profile from a
    component-definition only via `control-implementation/@source`, never an
    import, so the SSP's `populate_from_profile` vocabulary did not apply here.
    """

    PATH = PATH
    ACTION = "source_from_profile"

    @pytest.fixture
    def populate_doc(self, cdef_doc: dict[str, Any]) -> dict[str, Any]:
        return cdef_doc


class TestBulkApplyConverter:
    """#499 — bulk-apply a converter's output to a CDEF. Admin/converters.write
    gated. Edge contract: unknown converter → 404, non-admin → 401/403, anon →
    401. The apply happy path needs a converter + target rows (heavier fixture)."""

    def test_preview_unknown_converter_404(
        self, admin_client: httpx.Client, cdef_doc: dict[str, Any]
    ) -> None:
        resp = admin_client.post(
            f"{PATH}/{cdef_doc['slug']}/bulk_apply_converter/preview",
            json={"converter_id": 999_999_999},
        )
        assert resp.status_code in (404, 422), resp.text

    @pytest.mark.authz
    def test_confirm_non_admin_forbidden(
        self, user_client: httpx.Client, cdef_doc: dict[str, Any]
    ) -> None:
        resp = user_client.post(
            f"{PATH}/{cdef_doc['slug']}/bulk_apply_converter/confirm", json={}
        )
        assert resp.status_code in (401, 403), resp.text

    @pytest.mark.auth
    def test_preview_requires_token(
        self, anon_client: httpx.Client, cdef_doc: dict[str, Any]
    ) -> None:
        assert_error_envelope(
            anon_client.post(
                f"{PATH}/{cdef_doc['slug']}/bulk_apply_converter/preview", json={}
            ),
            expected_status=401,
        )


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
    def test_non_admin_can_create(self, user_client: httpx.Client) -> None:
        """CDEF is intentionally open to any authenticated user per the
        controller's design comment ("All CRUD operations are available
        to any authenticated user"). The AWS Labs bulk-ingest flow and
        the catalog refresh button both rely on this. If this ever
        needs RBAC gating, see #575 Path D for the pattern to follow.
        """
        response = user_client.post(PATH, json=_new_payload())
        assert response.status_code in (200, 201), response.text
        # Clean up the document the non-admin just created.
        delete_doc(user_client, PATH, response.json()["data"]["slug"])

    @pytest.mark.validation
    def test_missing_name_returns_422(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json={PARAM_KEY: {"description": "no name"}})
        assert_error_envelope(response, expected_status=422)


class TestUpdate:
    @pytest.mark.happy
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
        """The PATCH persists, confirmed by an independent read.

        This asserted only a status code until #995 — it would have passed
        against an endpoint that discarded the payload entirely, which is
        exactly what #994 did.
        """
        assert_update_round_trip(
            admin_client,
            PATH,
            cdef_doc["slug"],
            {"description": f"patched {uuid.uuid4().hex[:6]}"},
            PARAM_KEY,
            CdefDocumentShow,
            restore=False,  # the fixture owns this document and deletes it
        )

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
