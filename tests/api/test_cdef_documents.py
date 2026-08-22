"""Tests for /api/v1/cdef_documents.

5 logical endpoints — CRUD + export. CDEF (component definition)
documents differ from SSP/SAR/etc in that they are not boundary-scoped
— they describe a component (image, package, hardware) that can be
linked to multiple boundaries via leveraged authorizations.
"""

# Coverage declared for bin/api_inventory_check.rb. These endpoints are
# exercised through shared contract mixins, which express an endpoint as a
# URL path rather than by action name, so the inventory's string match
# cannot see them.
# api-inventory: covers cdef_documents#import_fields_preview
# api-inventory: covers cdef_documents#import_fields_confirm
# api-inventory: covers cdef_documents#export
# api-inventory: covers cdef_documents#import

from __future__ import annotations

import json
import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _bulk_destroy import BulkDestroyContract
from _crud_contract import CrudContract
from _document_helpers import create_doc, delete_doc, make_payload
from _field_import_contract import FieldImportContract
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
# #995 — the shared field-import contract. Reachable only after #1026 added
# `GET /api/v1/cdef_documents/:slug/export`: before that, `confirm` wrote control
# fields and `show` carried only `controls_count`, so the contract's central
# assertion — an INDEPENDENT read confirms the write — had nothing to read.
#
# CDEF addresses by `uuid` rather than `control_id`, and that is the point of
# #1028 rather than a convenience here. On a CDEF `control_id` holds the NIST
# reference a Converter resolved at ingest (#912): it is non-unique by design,
# because two components can implement the same control, and NULL where nothing
# resolved. On this instance 67 of 68 populated CDEFs are the AWS Labs inventory,
# where EVERY control id is duplicated or NULL — so `control_id` addresses
# nothing reliably there, and `uuid` addresses everything.
class TestFieldImportContract(FieldImportContract):
    PATH = PATH

    def _document_slug(self, admin_client):
        if getattr(self, "_imp_slug", None):
            return self._imp_slug

        rows = admin_client.get(PATH, params={"items": 50}).json()["data"]
        for row in rows:
            export = admin_client.get(f"{PATH}/{row['slug']}/export")
            if export.status_code != 200:
                continue
            controls = export.json().get("controls") or []
            if controls:
                self._imp_slug = row["slug"]
                self._imp_uuid = controls[0]["uuid"]
                return self._imp_slug

        raise AssertionError(
            "no CDEF on this instance carries controls — the field-import "
            "contract cannot run without a populated document"
        )

    def _target(self, admin_client):
        self._document_slug(admin_client)
        # `notes` is in CdefControlField::EDITABLE_FIELDS and is not one of the
        # parsed fields, so the import CREATES the row rather than editing one.
        # The contract handles a field that reads back as None first time.
        return {"uuid": self._imp_uuid, "key": self._imp_uuid, "field": "notes"}


# #1028 — the refusal. A key naming more than one control must be refused and
# named, never resolved silently to whichever row the database returned first.
class TestAmbiguousControlAddressing:
    @pytest.fixture
    def duplicated(self, admin_client):
        """A CDEF holding two controls that share a control_id, and that id."""
        rows = admin_client.get(PATH, params={"items": 50}).json()["data"]
        for row in rows:
            export = admin_client.get(f"{PATH}/{row['slug']}/export")
            if export.status_code != 200:
                continue
            seen: dict[str, list] = {}
            for control in export.json().get("controls") or []:
                cid = control.get("control_id")
                if cid:
                    seen.setdefault(cid, []).append(control)
            for cid, controls in seen.items():
                if len(controls) > 1:
                    return {"slug": row["slug"], "control_id": cid, "controls": controls}

        raise AssertionError(
            "no CDEF on this instance has a duplicated control_id — the "
            "ambiguity this asserts cannot be reached"
        )

    def _import(self, admin_client, slug, key, action, value="ambiguity-probe"):
        body = {"controls": {key: {"notes": value}}}
        return admin_client.post(
            f"{PATH}/{slug}/fields/import/{action}",
            files={"file": ("i.json", json.dumps(body).encode(), "application/json")},
        )

    @pytest.mark.validation
    def test_an_ambiguous_control_id_is_refused_not_resolved(
        self, admin_client, duplicated
    ) -> None:
        response = self._import(
            admin_client, duplicated["slug"], duplicated["control_id"], "preview"
        )

        assert response.status_code == 200, response.text
        data = response.json()["data"]
        assert data["rows"][0]["status"] == "ambiguous", data["rows"][0]
        assert data["stats"]["ambiguous"] == 1

    @pytest.mark.validation
    def test_the_refusal_names_every_candidate_so_it_is_actionable(
        self, admin_client, duplicated
    ) -> None:
        message = self._import(
            admin_client, duplicated["slug"], duplicated["control_id"], "preview"
        ).json()["data"]["rows"][0]["message"]

        for control in duplicated["controls"]:
            assert control["uuid"] in message, (
                f"candidate {control['uuid']} not named in the refusal: {message}"
            )

    @pytest.mark.validation
    def test_confirm_writes_nothing_for_an_ambiguous_key(self, admin_client, duplicated) -> None:
        slug = duplicated["slug"]

        def notes_by_uuid():
            body = admin_client.get(f"{PATH}/{slug}/export").json()
            return {
                c["uuid"]: next(
                    (f["field_value"] for f in c.get("fields") or [] if f["field_name"] == "notes"),
                    None,
                )
                for c in body.get("controls") or []
            }

        before = notes_by_uuid()
        response = self._import(
            admin_client,
            slug,
            duplicated["control_id"],
            "confirm",
            value=f"must-not-be-written-{uuid.uuid4().hex[:8]}",
        )

        assert response.status_code == 200, response.text
        assert response.json()["data"]["applied"] == 0
        assert notes_by_uuid() == before, "an ambiguous key wrote to a control"


class TestCrudContract(CrudContract):
    PATH = PATH
    PARAM_KEY = PARAM_KEY
    IDENTIFIER = "slug"
    # #1032 — CDEF writes now require `cdef.write`, so the default posture
    # applies and no NON_ADMIN_MAY_WRITE_BECAUSE declaration is made.
    #
    # This declaration used to assert the opposite, on the strength of the
    # controller's design comment ("All CRUD operations are available to any
    # authenticated user") and a claim that the AWS Labs bulk-ingest flow
    # depended on it. That claim was wrong: AWS Labs ingest runs through
    # `AwsLabsCdefRefreshJob` -> `AwsLabsCdefImportService`, which never touches
    # a controller and so was never subject to this authorization either way.
    #
    # The old declaration did its job. Its comment said "asserted rather than
    # exempted, so gating it later is a failing test", and gating it later was
    # a failing test.

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
        response = admin_client.get(PATH, params={"partition": "aws-us-gov", "capability": "MFA"})
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

    def test_component_details_are_detail_only(self, admin_client: httpx.Client, cdef_doc) -> None:
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
        resp = user_client.post(f"{PATH}/{cdef_doc['slug']}/bulk_apply_converter/confirm", json={})
        assert resp.status_code in (401, 403), resp.text

    @pytest.mark.auth
    def test_preview_requires_token(
        self, anon_client: httpx.Client, cdef_doc: dict[str, Any]
    ) -> None:
        assert_error_envelope(
            anon_client.post(f"{PATH}/{cdef_doc['slug']}/bulk_apply_converter/preview", json={}),
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
        assert_create_round_trip(admin_client, PATH, _new_payload(), PARAM_KEY, CdefDocumentShow)

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
        assert_create_round_trip(admin_client, PATH, payload, PARAM_KEY, CdefDocumentShow)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.post(PATH, json=_new_payload()), expected_status=401)

    @pytest.mark.authz
    def test_non_admin_without_cdef_write_cannot_create(
        self, user_client: httpx.Client, admin_client: httpx.Client
    ) -> None:
        """#1032 — CDEF writes require `cdef.write`.

        This asserted the opposite until the gate landed: the API ran no
        permission check while the web controller gated the same operations, so
        `cdef.write` was not a permission a caller could be denied through the
        API, only one they could route around by using it.

        The count is checked as well as the status. A 403 that still created the
        document would be worse than either.
        """
        before = admin_client.get(PATH, params={"items": 1}).json()["meta"]["count"]

        response = user_client.post(PATH, json=_new_payload())

        assert response.status_code == 403, response.text
        after = admin_client.get(PATH, params={"items": 1}).json()["meta"]["count"]
        assert after == before, "a refused create still made a document"

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
        assert_error_envelope(anon_client.put(f"{PATH}/anything", json={}), expected_status=401)


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


# api-inventory: covers cdef_documents#update_scope
class TestUpdateScope:
    """`PATCH /cdef_documents/:slug/scope` — global, or pinned to one boundary.

    Every assertion here confirms the change through an INDEPENDENT read rather
    than the write's own body. That was impossible until #1038: the scope was
    not exposed anywhere in the API — not on the write, not on `show`, and the
    index ignores a `scope` parameter — so the only way to see it was a Rails
    console. Getting it wrong silently widens what every other boundary's
    composition includes, which is why it is worth reading back.
    """

    @pytest.fixture
    def scoped_cdef(self, admin_client: httpx.Client):
        suffix = uuid.uuid4().hex[:8]
        created = admin_client.post(
            "/api/v1/cdef_documents",
            json={"cdef_document": {"name": f"phase2-scope-{suffix}"}},
        )
        assert created.status_code == 201, created.text
        cdef = created.json()["data"]

        boundary = admin_client.post(
            "/api/v1/authorization_boundaries",
            json={
                "authorization_boundary": {
                    "name": f"phase2-scope-bnd-{suffix}",
                    "description": "#995 CDEF scope sweep",
                }
            },
        )
        assert boundary.status_code in (200, 201), boundary.text
        try:
            yield {"cdef": cdef, "boundary": boundary.json()["data"]}
        finally:
            admin_client.delete(f"/api/v1/cdef_documents/{cdef['slug']}")
            admin_client.delete(f"/api/v1/authorization_boundaries/{boundary.json()['data']['id']}")

    def _read_scope(self, admin_client: httpx.Client, slug: str) -> dict[str, Any]:
        response = admin_client.get(f"/api/v1/cdef_documents/{slug}")
        assert response.status_code == 200, response.text
        return response.json()["data"]

    @pytest.mark.happy
    def test_pinning_to_a_boundary_is_confirmed_by_an_independent_read(
        self, admin_client: httpx.Client, scoped_cdef
    ) -> None:
        slug = scoped_cdef["cdef"]["slug"]
        boundary_id = scoped_cdef["boundary"]["id"]

        written = admin_client.patch(
            f"/api/v1/cdef_documents/{slug}/scope",
            json={"scope": "boundary", "authorization_boundary_id": boundary_id},
        )
        assert written.status_code == 200, written.text

        data = self._read_scope(admin_client, slug)
        assert data["scope"] == "boundary", data
        assert data["authorization_boundary_id"] == boundary_id, data
        assert data["globally_available"] is False, (
            "a boundary-pinned CDEF is still offered to every other boundary"
        )

    @pytest.mark.happy
    def test_returning_to_global_is_confirmed_by_an_independent_read(
        self, admin_client: httpx.Client, scoped_cdef
    ) -> None:
        """Both directions. Only asserting the pin would pass against a service
        that pinned and could never unpin."""
        slug = scoped_cdef["cdef"]["slug"]
        admin_client.patch(
            f"/api/v1/cdef_documents/{slug}/scope",
            json={"scope": "boundary", "authorization_boundary_id": scoped_cdef["boundary"]["id"]},
        )

        written = admin_client.patch(
            f"/api/v1/cdef_documents/{slug}/scope", json={"scope": "global"}
        )
        assert written.status_code == 200, written.text

        data = self._read_scope(admin_client, slug)
        assert data["scope"] == "global", data
        assert data["authorization_boundary_id"] is None, (
            "the CDEF is global but still records a boundary"
        )
        assert data["globally_available"] is True, data

    @pytest.mark.validation
    def test_an_unknown_scope_is_refused_by_name(
        self, admin_client: httpx.Client, scoped_cdef
    ) -> None:
        response = admin_client.patch(
            f"/api/v1/cdef_documents/{scoped_cdef['cdef']['slug']}/scope",
            json={"scope": "nonsense"},
        )

        assert response.status_code == 422, response.text
        assert "nonsense" in response.json()["error"], response.text

    @pytest.mark.validation
    def test_boundary_scope_without_a_boundary_is_refused(
        self, admin_client: httpx.Client, scoped_cdef
    ) -> None:
        """`CdefScopeService` raises rather than half-applying: a
        boundary-scoped CDEF with no boundary would be visible to nobody."""
        response = admin_client.patch(
            f"/api/v1/cdef_documents/{scoped_cdef['cdef']['slug']}/scope",
            json={"scope": "boundary"},
        )

        assert response.status_code == 422, response.text
        assert self._read_scope(admin_client, scoped_cdef["cdef"]["slug"])["scope"] == "global", (
            "a refused scope change was applied anyway"
        )

    @pytest.mark.authz
    def test_a_non_admin_without_cdef_write_is_refused(
        self, admin_client: httpx.Client, user_client: httpx.Client, scoped_cdef
    ) -> None:
        """#1032 gated CDEF writes behind `cdef.write`; scope is a write."""
        slug = scoped_cdef["cdef"]["slug"]

        response = user_client.patch(
            f"/api/v1/cdef_documents/{slug}/scope",
            json={"scope": "boundary", "authorization_boundary_id": scoped_cdef["boundary"]["id"]},
        )

        assert response.status_code == 403, response.text
        assert self._read_scope(admin_client, slug)["scope"] == "global", (
            "a refused caller changed the scope anyway"
        )

    @pytest.mark.auth
    def test_an_anonymous_caller_is_refused(self, anon_client: httpx.Client, scoped_cdef) -> None:
        response = anon_client.patch(
            f"/api/v1/cdef_documents/{scoped_cdef['cdef']['slug']}/scope",
            json={"scope": "global"},
        )

        assert response.status_code == 401, response.text
