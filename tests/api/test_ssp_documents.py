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

# Coverage declared for bin/api_inventory_check.rb. These endpoints are
# exercised through shared contract mixins, which express an endpoint as a
# URL path rather than by action name, so the inventory's string match
# cannot see them.
# api-inventory: covers ssp_documents#import_fields_preview
# api-inventory: covers ssp_documents#import_fields_confirm
# POST change_baseline routes to apply_baseline_change (#1330); TestChangeBaseline.
# api-inventory: covers ssp_documents#apply_baseline_change
# api-inventory: covers ssp_documents#bring_up_to_baseline
# api-inventory: covers ssp_documents#apply_bring_up_to_baseline

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
from _oscal_export_contract import OscalExportContract
from _populate_from_profile import PopulateFromProfileContract
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

def _new_payload(boundary_id: int) -> dict[str, Any]:
    """Boundary id 1 is the standard seed value in dev/test SPARC instances."""
    return make_payload(PARAM_KEY, {"authorization_boundary_id": boundary_id})


def _create_ssp(client: httpx.Client, seeded_boundary_id: int) -> dict[str, Any]:
    return create_doc(client, PATH, _new_payload(seeded_boundary_id))


def _delete_ssp(client: httpx.Client, slug: str) -> None:
    delete_doc(client, PATH, slug)


# ── Fixtures ───────────────────────────────────────────────────────────────

@pytest.fixture
def ssp_doc(admin_client: httpx.Client, seeded_boundary_id: int) -> Iterator[dict[str, Any]]:
    """Create an SSP, hand it to the test, delete on teardown."""
    doc = _create_ssp(admin_client, seeded_boundary_id)
    try:
        yield doc
    finally:
        _delete_ssp(admin_client, doc["slug"])


# ── populate from profile (#628) ────────────────────────────────────────────

# #995 — the shared export contract: JSON not an error page, and the export
# actually CONTAINS the record it claims to export.
# #995 — the shared field-import contract: a preview must write NOTHING, and
# confirm must actually apply, both confirmed by an independent read.
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
                self._imp_control = controls[0]
                self._imp_uuid = controls[0]["uuid"]
                return self._imp_slug
        raise AssertionError("no SSP on this instance has controls to import fields into")

    def _target(self, admin_client):
        self._document_slug(admin_client)
        # This type keys directly on NIST controls and has no duplicates, so the
        # `control_id` is a valid address — which is the common path worth
        # covering here. CDEF exercises uuid addressing (#1028).
        return {
            "uuid": self._imp_uuid,
            "key": self._imp_control["control_id"],
            "field": "notes",
        }


class TestExportContract(ExportContract):
    def _export_path(self, admin_client):
        docs = admin_client.get(PATH, params={"items": 1})
        self._doc = docs.json()["data"][0]
        return f"{PATH}/{self._doc['slug']}/export"

    def _expected_content(self, admin_client):
        self._export_path(admin_client)
        return self._doc["name"]


class TestPopulateFromProfile(PopulateFromProfileContract):
    """Populate an SSP from a published profile (#628). Contract lives in
    _populate_from_profile; SSPs are slug-addressed."""

    PATH = PATH

    @pytest.fixture
    def populate_doc(self, ssp_doc: dict[str, Any]) -> dict[str, Any]:
        return ssp_doc


# ── change baseline (#1330) ────────────────────────────────────────────────

def _published_profile_ids(client: httpx.Client) -> list[int]:
    resp = client.get("/api/v1/profile_documents", params={"items": 100})
    assert resp.status_code == 200, resp.text
    return [
        row["id"] for row in resp.json()["data"]
        if (row.get("lifecycle_status") or row.get("status")) == "published"
    ]


class TestChangeBaseline:
    """GET previews the delta and changes nothing; POST applies it. Both go
    through SspBaselineChange, so a refusal reads the same on each."""

    @pytest.fixture
    def on_baseline(
        self, admin_client: httpx.Client, ssp_doc: dict[str, Any]
    ) -> tuple[dict[str, Any], int, int]:
        """An SSP populated from one published baseline, and another baseline
        it may change to. Skips when the instance has no such pair."""
        ids = _published_profile_ids(admin_client)
        if len(ids) < 2:
            pytest.skip("needs two published baselines to change between")
        slug = ssp_doc["slug"]
        resp = admin_client.post(f"{PATH}/{slug}/populate_from_profile",
                                 json={"source_profile_id": ids[0]})
        assert resp.status_code == 200, resp.text
        for target in ids[1:]:
            preview = admin_client.get(f"{PATH}/{slug}/change_baseline",
                                       params={"profile_document_id": target})
            if preview.status_code == 200 and preview.json()["data"]["refusal"] is None:
                return ssp_doc, ids[0], target
        pytest.skip("no other published baseline with a resolved catalog")

    def _baseline_of(self, client: httpx.Client, slug: str) -> int | None:
        resp = client.get(f"{PATH}/{slug}")
        assert resp.status_code == 200, resp.text
        return resp.json()["data"]["profile_document_id"]

    @pytest.mark.happy
    def test_preview_shows_the_delta_and_changes_nothing(
        self, admin_client: httpx.Client, on_baseline: tuple[dict[str, Any], int, int]
    ) -> None:
        ssp, current, target = on_baseline
        resp = admin_client.get(f"{PATH}/{ssp['slug']}/change_baseline",
                                params={"profile_document_id": target})
        assert resp.status_code == 200, resp.text
        data = resp.json()["data"]
        assert data["profile_document_id"] == target
        for key in ("added", "unchanged", "kept", "removed"):
            assert isinstance(data[key], list), f"{key} missing from the delta: {data}"
        assert data["refusal"] is None
        assert self._baseline_of(admin_client, ssp["slug"]) == current

    @pytest.mark.happy
    def test_apply_changes_the_baseline_and_returns_the_delta(
        self, admin_client: httpx.Client, on_baseline: tuple[dict[str, Any], int, int]
    ) -> None:
        ssp, _current, target = on_baseline
        resp = admin_client.post(f"{PATH}/{ssp['slug']}/change_baseline",
                                 json={"profile_document_id": target})
        assert resp.status_code == 200, resp.text
        data = resp.json()["data"]
        assert data["profile_document_id"] == target
        for key in ("added", "unchanged", "kept", "removed"):
            assert isinstance(data[key], list), f"{key} missing from the delta: {data}"
        assert self._baseline_of(admin_client, ssp["slug"]) == target

    def test_apply_refuses_the_baseline_already_in_use_with_422(
        self, admin_client: httpx.Client, on_baseline: tuple[dict[str, Any], int, int]
    ) -> None:
        ssp, current, _target = on_baseline
        preview = admin_client.get(f"{PATH}/{ssp['slug']}/change_baseline",
                                   params={"profile_document_id": current})
        assert preview.status_code == 200, preview.text
        assert preview.json()["data"]["refusal"] == "This SSP already uses that baseline."

        resp = admin_client.post(f"{PATH}/{ssp['slug']}/change_baseline",
                                 json={"profile_document_id": current})
        assert_error_envelope(resp, expected_status=422)
        assert resp.json()["error"] == "This SSP already uses that baseline."

    @pytest.mark.validation
    def test_no_baseline_named_returns_422(
        self, admin_client: httpx.Client, ssp_doc: dict[str, Any]
    ) -> None:
        for method in ("get", "post"):
            resp = getattr(admin_client, method)(f"{PATH}/{ssp_doc['slug']}/change_baseline")
            assert_error_envelope(resp, expected_status=422)

    @pytest.mark.auth
    def test_apply_is_refused_to_a_read_only_user(
        self, admin_client: httpx.Client, user_client: httpx.Client,
        on_baseline: tuple[dict[str, Any], int, int],
    ) -> None:
        ssp, current, target = on_baseline
        resp = user_client.post(f"{PATH}/{ssp['slug']}/change_baseline",
                                json={"profile_document_id": target})
        # 403 for a user who may read the boundary; 404 when it is not even
        # visible to them. Either way nothing changes.
        assert resp.status_code in (403, 404), resp.text
        assert self._baseline_of(admin_client, ssp["slug"]) == current

    @pytest.mark.auth
    def test_change_baseline_requires_token(
        self, anon_client: httpx.Client, ssp_doc: dict[str, Any]
    ) -> None:
        for method in ("get", "post"):
            resp = getattr(anon_client, method)(f"{PATH}/{ssp_doc['slug']}/change_baseline",
                                                params={"profile_document_id": 1})
            assert resp.status_code == 401, resp.text


def _missing_controls(client: httpx.Client, slug: str) -> list[str]:
    resp = client.get(f"{PATH}/{slug}/bring_up_to_baseline")
    assert resp.status_code == 200, resp.text
    return resp.json()["data"]["controls_added"]


class TestBringUpToBaseline:
    """#1337 — GET previews what an SSP lacks of its own baseline and changes
    nothing; POST adds it and changes nothing that exists. A second POST adds
    nothing. Both go through SspBaselineChange.fill."""

    @pytest.fixture
    def short_of_baseline(
        self, admin_client: httpx.Client, ssp_doc: dict[str, Any]
    ) -> dict[str, Any]:
        """An SSP that names a published baseline but holds none of its
        controls, as an import that declared its baseline can."""
        for profile_id in _published_profile_ids(admin_client):
            resp = admin_client.patch(f"{PATH}/{ssp_doc['slug']}",
                                      json={PARAM_KEY: {"profile_document_id": profile_id}})
            assert resp.status_code == 200, resp.text
            preview = admin_client.get(f"{PATH}/{ssp_doc['slug']}/bring_up_to_baseline")
            if preview.status_code == 200 and preview.json()["data"]["controls_added"]:
                return ssp_doc
        pytest.skip("needs a published baseline with a resolved catalog")

    @pytest.mark.happy
    def test_preview_lists_what_is_missing_and_changes_nothing(
        self, admin_client: httpx.Client, short_of_baseline: dict[str, Any]
    ) -> None:
        slug = short_of_baseline["slug"]
        first = admin_client.get(f"{PATH}/{slug}/bring_up_to_baseline")
        second = admin_client.get(f"{PATH}/{slug}/bring_up_to_baseline")
        assert first.status_code == 200, first.text
        data = first.json()["data"]
        assert isinstance(data["controls_added"], list) and data["controls_added"], data
        assert isinstance(data["items_added"], int), data
        again = second.json()["data"]["controls_added"]
        assert again == data["controls_added"], "the preview changed the SSP"

    @pytest.mark.happy
    def test_apply_adds_what_the_preview_listed_and_a_second_call_adds_nothing(
        self, admin_client: httpx.Client, short_of_baseline: dict[str, Any]
    ) -> None:
        slug = short_of_baseline["slug"]
        expected = _missing_controls(admin_client, slug)

        resp = admin_client.post(f"{PATH}/{slug}/bring_up_to_baseline")
        assert resp.status_code == 200, resp.text
        assert resp.json()["data"]["controls_added"] == expected

        again = admin_client.post(f"{PATH}/{slug}/bring_up_to_baseline")
        assert again.status_code == 200, again.text
        assert again.json()["data"]["controls_added"] == []
        assert again.json()["data"]["items_added"] == 0

    @pytest.mark.validation
    def test_an_ssp_with_no_baseline_is_refused_with_422(
        self, admin_client: httpx.Client, ssp_doc: dict[str, Any]
    ) -> None:
        for method in ("get", "post"):
            resp = getattr(admin_client, method)(f"{PATH}/{ssp_doc['slug']}/bring_up_to_baseline")
            assert_error_envelope(resp, expected_status=422)
            assert "no baseline" in resp.json()["error"]

    @pytest.mark.auth
    def test_apply_is_refused_to_a_read_only_user(
        self, admin_client: httpx.Client, user_client: httpx.Client,
        short_of_baseline: dict[str, Any],
    ) -> None:
        slug = short_of_baseline["slug"]
        before = _missing_controls(admin_client, slug)
        resp = user_client.post(f"{PATH}/{slug}/bring_up_to_baseline")
        # 403 for a user who may read the boundary; 404 when it is not even
        # visible to them. Either way nothing is added.
        assert resp.status_code in (403, 404), resp.text
        assert _missing_controls(admin_client, slug) == before

    @pytest.mark.auth
    def test_bring_up_to_baseline_requires_token(
        self, anon_client: httpx.Client, ssp_doc: dict[str, Any]
    ) -> None:
        for method in ("get", "post"):
            resp = getattr(anon_client, method)(f"{PATH}/{ssp_doc['slug']}/bring_up_to_baseline")
            assert resp.status_code == 401, resp.text


# ── index ──────────────────────────────────────────────────────────────────

# #995 — the shared matrix for this group.
class TestCrudContract(CrudContract):
    PATH = PATH
    PARAM_KEY = PARAM_KEY
    IDENTIFIER = "slug"

    def _payload(self, admin_client):
        boundaries = admin_client.get("/api/v1/authorization_boundaries", params={"items": 1})
        rows = boundaries.json()["data"]
        assert rows, "no authorization boundary on this instance to hang an SSP off"
        return _new_payload(rows[0]["id"])[PARAM_KEY]


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
        response = admin_client.get(
            f"{PATH}/this-slug-definitely-does-not-exist-{uuid.uuid4().hex}"
        )
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
        body = response.json()
        assert "slug" in body["data"]
        assert body["data"]["name"] == payload["ssp_document"]["name"]

        _delete_ssp(admin_client, body["data"]["slug"])

    @pytest.mark.happy
    def test_create_round_trip(self, admin_client: httpx.Client, seeded_boundary_id: int) -> None:
        """#433 slice 3 — fields sent on Create must come back from Show."""
        assert_create_round_trip(
            admin_client, PATH, _new_payload(seeded_boundary_id), PARAM_KEY, SspDocumentShow
        )

    @pytest.mark.happy
    def test_create_round_trip_rich_payload(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        """#433 slice 3 — exercise type-specific SSP fields beyond name/description."""
        payload = make_payload(
            PARAM_KEY,
            {
                "authorization_boundary_id": seeded_boundary_id,
                "ssp_version": "2.1.0",
                "system_status": "operational",
                "security_sensitivity_level": "moderate",
            },
        )
        assert_create_round_trip(
            admin_client, PATH, payload, PARAM_KEY, SspDocumentShow
        )

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client, seeded_boundary_id: int) -> None:
        response = anon_client.post(PATH, json=_new_payload(seeded_boundary_id))
        assert_error_envelope(response, expected_status=401)

    @pytest.mark.authz
    def test_non_admin_without_write_returns_403(
        self, user_client: httpx.Client
    , seeded_boundary_id: int) -> None:
        response = user_client.post(PATH, json=_new_payload(seeded_boundary_id))
        # 403 expected; some configurations may also return 401 if the
        # test user has zero permissions at all. Both are valid signals
        # that the unauthorized create was rejected.
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
    def test_admin_destroys_document(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        # Don't use the ssp_doc fixture because we want to assert the
        # delete actually happened (fixture would also try to delete on
        # teardown and produce a confusing 404).
        doc = _create_ssp(admin_client, seeded_boundary_id)

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


# #1181 — the OSCAL formats of `export`, through the shared contract.
class TestOscalExportContract(OscalExportContract):
    PATH = PATH
    ROOT_KEY = "system-security-plan"
