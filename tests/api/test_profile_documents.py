"""Tests for /api/v1/profile_documents.

5 logical endpoints — CRUD + export. Profiles are baselines (FedRAMP
Low/Moderate/High, etc.) that select controls from a control catalog;
this module covers the top-level profile document. Nested baseline
parameters live under their own routes covered by
test_baseline_parameters.py.
"""

# Coverage declared for bin/api_inventory_check.rb. These endpoints are
# exercised through shared contract mixins, which express an endpoint as a
# URL path rather than by action name, so the inventory's string match
# cannot see them.
# api-inventory: covers profile_documents#import
# api-inventory: covers profile_documents#update_controls

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _crud_contract import CrudContract
from _document_helpers import create_doc, delete_doc, make_payload
from _review_workflow import ReviewWorkflowContract
from conftest import assert_error_envelope, assert_paginated_envelope, published_profile
from schemas import (
    ProfileDocumentIndex,
    ProfileDocumentShow,
    assert_create_round_trip,
    assert_update_round_trip,
    validate_index_response,
    validate_show_response,
)

pytestmark = [pytest.mark.documents, pytest.mark.phase1]


PATH = "/api/v1/profile_documents"
PARAM_KEY = "profile_document"

# Contract coverage of non-generic actions (bin/api_inventory_check.rb scans this
# module): submit_for_review / approve / reject via ReviewWorkflowContract;
# baseline_review via TestBaselineReview.


def _new_payload() -> dict[str, Any]:
    return make_payload(PARAM_KEY)


@pytest.fixture
def profile_doc(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    doc = create_doc(admin_client, PATH, _new_payload())
    try:
        yield doc
    finally:
        delete_doc(admin_client, PATH, doc["slug"])


class TestReviewWorkflow(ReviewWorkflowContract):
    """DocumentApprovalApi review workflow (#630/#634) for profile_documents.

    Contract lives in _review_workflow.ReviewWorkflowContract; profiles are
    slug-addressed.

    #757: profile baseline controls are now selectable via the API
    (PUT .../controls, ProfileControlSelectionService). The review_doc fixture
    links the seeded published baseline's catalog and selects a couple of its
    controls so the submit -> approve/reject contract runs. If no published
    profile exists to source a catalog + control ids, it falls back to the bare
    profile (the two content tests then skip; the three auth/no-submit tests
    still run).
    """

    PATH = PATH
    IDENT_KEY = "slug"

    @pytest.fixture
    def review_doc(self, admin_client: httpx.Client, profile_doc: dict[str, Any]) -> dict[str, Any]:
        source_slug = published_profile(admin_client)
        if source_slug is None:
            return profile_doc  # no catalog/control basis -> content tests skip

        source = admin_client.get(f"{PATH}/{source_slug}").json()["data"]
        catalog_id = source.get("control_catalog_id")
        control_ids = (source.get("control_ids") or [])[:2]
        if not catalog_id or not control_ids:
            return profile_doc

        admin_client.patch(
            f"{PATH}/{profile_doc['slug']}",
            json={"profile_document": {"control_catalog_id": catalog_id}},
        )
        resp = admin_client.put(
            f"{PATH}/{profile_doc['slug']}/controls", json={"control_ids": control_ids}
        )
        assert resp.status_code == 200, resp.text
        return profile_doc

    def test_submit_empty_requires_content(
        self, admin_client: httpx.Client, profile_doc: dict[str, Any]
    ) -> None:
        # A profile with no linked catalog / selected controls cannot be
        # submitted for review (DocumentApprovalService content gate).
        resp = admin_client.post(f"{PATH}/{profile_doc['slug']}/submit_for_review")
        assert resp.status_code == 422, resp.text
        assert "content" in resp.text.lower(), resp.text


class TestBaselineReview:
    """#633 — GET /api/v1/profile_documents/:id/baseline_review returns the
    selected-vs-expected control diff + ODP customization counts."""

    @pytest.mark.happy
    def test_returns_diff_shape(
        self, admin_client: httpx.Client, profile_doc: dict[str, Any]
    ) -> None:
        resp = admin_client.get(f"{PATH}/{profile_doc['slug']}/baseline_review")
        assert resp.status_code == 200, resp.text
        data = resp.json()["data"]
        for key in (
            "expected_count",
            "selected_count",
            "missing_controls",
            "extra_controls",
            "odp_customized_count",
            "odp_total_count",
        ):
            assert key in data, f"baseline_review missing {key!r}: {data}"

    @pytest.mark.auth
    def test_requires_token(
        self, anon_client: httpx.Client, profile_doc: dict[str, Any]
    ) -> None:
        assert_error_envelope(
            anon_client.get(f"{PATH}/{profile_doc['slug']}/baseline_review"),
            expected_status=401,
        )


# #995 — the shared matrix for this group: documented status, an INDEPENDENT
# read after every write, gone-from-show-and-index after delete, and a refused
# caller changing nothing.
class TestCrudContract(CrudContract):
    PATH = PATH
    PARAM_KEY = PARAM_KEY
    IDENTIFIER = "slug"

    def _payload(self, admin_client):
        return _new_payload()[PARAM_KEY]


class TestIndex:
    @pytest.mark.happy
    def test_admin_lists_documents(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH)
        assert response.status_code == 200, response.text
        assert_paginated_envelope(response.json())
        # #433 slice 2 — content-style validation
        validate_index_response(response, ProfileDocumentIndex)

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
        self, admin_client: httpx.Client, profile_doc: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{profile_doc['slug']}")
        # #433 slice 2 — content-style validation (detailed Show shape)
        envelope = validate_show_response(response, ProfileDocumentShow)
        assert envelope.data.slug == profile_doc["slug"]

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
        """#433 slice 3 — fields sent on Create must come back from Show."""
        assert_create_round_trip(
            admin_client, PATH, _new_payload(), PARAM_KEY, ProfileDocumentShow
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
    def test_admin_updates_via_put(
        self, admin_client: httpx.Client, profile_doc: dict[str, Any]
    ) -> None:
        new_desc = f"updated {uuid.uuid4().hex[:6]}"
        response = admin_client.put(
            f"{PATH}/{profile_doc['slug']}",
            json={PARAM_KEY: {"description": new_desc}},
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["description"] == new_desc

    @pytest.mark.happy
    def test_admin_updates_via_patch(
        self, admin_client: httpx.Client, profile_doc: dict[str, Any]
    ) -> None:
        """The PATCH persists, confirmed by an independent read.

        This asserted only a status code until #995 — it would have passed
        against an endpoint that discarded the payload entirely, which is
        exactly what #994 did.
        """
        assert_update_round_trip(
            admin_client,
            PATH,
            profile_doc["slug"],
            {"description": f"patched {uuid.uuid4().hex[:6]}"},
            PARAM_KEY,
            ProfileDocumentShow,
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


@pytest.mark.happy
class TestApprovalStatusIsVisible:
    """#1041 — `approval_status` is readable over the API.

    Whether a document is awaiting sign-off is a DIFFERENT question from its
    `lifecycle_status`, and it was exposed nowhere. The review queue lists
    profiles sitting at `lifecycle_status: "in_progress"` with
    `approval_status: "pending_review"`, so a client reading the API could not
    tell a document under review from any other in-progress one.

    That was not a cosmetic gap. `test_baseline_parameters.py` picked the first
    non-published profile with tailorable parameters, which was the seeded
    review-queue fixture, and editing it cleared the review state — emptying a
    screen that a ui-smoke check in another suite asserts on. The fixture could
    not avoid it, because the state it needed to see was invisible.
    """

    def test_the_index_reports_approval_status(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH, params={"items": 25})

        assert response.status_code == 200, response.text
        rows = response.json()["data"]
        assert rows, "no profiles on this instance"
        # On the INDEX, not just the detail — the review queue is a list.
        for row in rows:
            assert "approval_status" in row, sorted(row)

    def test_it_distinguishes_a_document_under_review(
        self, admin_client: httpx.Client
    ) -> None:
        """The property the field exists for, asserted end to end.

        A freshly created profile is not awaiting review; the same profile after
        `submit_for_review` is. Reading `lifecycle_status` alone cannot tell
        those apart.
        """
        suffix = uuid.uuid4().hex[:8]
        # Built with a catalog and a selected control, because submit_for_review
        # refuses a profile without them ("missing required content"). A bare
        # profile would make this SKIP, and a skipped test proves nothing.
        catalogs = admin_client.get("/api/v1/control_catalogs", params={"items": 50})
        catalog = next(
            (c for c in catalogs.json()["data"] if "800-53" in (c.get("name") or "")), None
        )
        assert catalog, "no NIST 800-53 catalog to base a submittable profile on"

        created = admin_client.post(
            PATH,
            json={
                "profile_document": {
                    "name": f"phase2-approval-{suffix}",
                    "control_catalog_id": catalog["id"],
                    "baseline_level": "moderate",
                }
            },
        )
        assert created.status_code == 201, created.text
        slug = created.json()["data"]["slug"]

        try:
            selected = admin_client.put(
                f"{PATH}/{slug}/controls", json={"control_ids": ["ac-1"]}
            )
            assert selected.status_code == 200, selected.text

            before = admin_client.get(f"{PATH}/{slug}").json()["data"]
            assert before["approval_status"] != "pending_review", before

            submitted = admin_client.post(f"{PATH}/{slug}/submit_for_review")
            assert submitted.status_code == 200, (
                f"could not submit for review, so the assertion below would not run: "
                f"{submitted.status_code} {submitted.text[:200]}"
            )

            after = admin_client.get(f"{PATH}/{slug}").json()["data"]
            assert after["approval_status"] == "pending_review", (
                f"submit_for_review did not surface in approval_status: {after}"
            )
            # The distinction that matters: lifecycle_status did NOT move, which
            # is exactly why it could not stand in for this.
            assert after["lifecycle_status"] == before["lifecycle_status"], (
                "lifecycle_status moved too, so this test is not showing what it claims"
            )
        finally:
            admin_client.delete(f"{PATH}/{slug}")
