"""SSP roles — the declarations a `role-id` must resolve to (#1116).

An SSP declared three roles hardcoded in the exporter, and the statement editor
accepted responsible roles as free text, so an author could type `isso` and
produce a document whose reference resolved to nothing. That is a REFERENTIAL
break, not a schema one: the document validates cleanly and a consuming tool
finds nothing, which is why schema validation never caught it.

These run against a live instance, so they assert the behaviours that only a
real server can show: that NIST's suggested vocabulary is offered, that a URI is
refused as an id, and that a role still referenced by a statement cannot be
undeclared.
"""

from __future__ import annotations

import uuid

import pytest

pytestmark = [pytest.mark.documents, pytest.mark.phase2]


@pytest.fixture
def ssp_slug(admin_client):
    """An SSP the caller can write to. Skips rather than failing on an instance
    with none — 'no SSP here' is a property of the instance, not a defect."""
    r = admin_client.get("/api/v1/ssp_documents", params={"per_page": 5})
    r.raise_for_status()
    rows = r.json().get("data", [])
    if not rows:
        pytest.skip("no SSP documents on this instance to declare roles on")
    return rows[0]["slug"]


@pytest.fixture
def declared_role(admin_client, ssp_slug):
    role_id = f"api-suite-role-{uuid.uuid4().hex[:8]}"
    r = admin_client.post(
        f"/api/v1/ssp_documents/{ssp_slug}/roles",
        json={"role": {"id": role_id, "title": "API Suite Role", "organization_defined": True}},
    )
    r.raise_for_status()
    yield r.json()["data"]
    # Clean up by id, not by name — the id is what addresses the resource.
    admin_client.delete(f"/api/v1/ssp_documents/{ssp_slug}/roles/{role_id}")


def test_index_lists_declared_and_offers_nist_suggestions(admin_client, ssp_slug):
    r = admin_client.get(f"/api/v1/ssp_documents/{ssp_slug}/roles")
    assert r.status_code == 200

    body = r.json()
    declared = {row["id"] for row in body["data"]}
    suggested = {row["id"] for row in body["meta"]["suggested"]}

    assert declared, "a plan declares its defaults even when none are authored"
    # NIST's canonical id for the ISSO. An author typing `isso` mints a private
    # id for a role NIST already defines.
    assert "information-system-security-officer" in declared | suggested
    assert not (declared & suggested), "a declared role must not also be offered as a suggestion"


def test_declares_an_organization_defined_role(admin_client, ssp_slug, declared_role):
    assert declared_role["organization_defined"] is True

    r = admin_client.get(f"/api/v1/ssp_documents/{ssp_slug}/roles")
    ids = {row["id"] for row in r.json()["data"]}
    assert declared_role["id"] in ids


def test_refuses_a_uri_as_a_role_id(admin_client, ssp_slug):
    """A role-id is a plain NCName token. The deployment's namespace belongs on a
    PROP of the role — putting it in the id is a category error."""
    r = admin_client.post(
        f"/api/v1/ssp_documents/{ssp_slug}/roles",
        json={"role": {"id": "https://att.example/ns/policy"}},
    )
    assert r.status_code == 422
    assert "NCName" in r.json()["error"]


def test_refuses_a_duplicate_declaration(admin_client, ssp_slug, declared_role):
    r = admin_client.post(
        f"/api/v1/ssp_documents/{ssp_slug}/roles",
        json={"role": {"id": declared_role["id"]}},
    )
    assert r.status_code == 422


def test_retitles_a_declared_role(admin_client, ssp_slug, declared_role):
    new_title = f"Renamed {uuid.uuid4().hex[:6]}"
    r = admin_client.patch(
        f"/api/v1/ssp_documents/{ssp_slug}/roles/{declared_role['id']}",
        json={"role": {"title": new_title}},
    )
    assert r.status_code == 200
    assert r.json()["data"]["title"] == new_title


def test_404_on_a_role_this_document_has_not_declared(admin_client, ssp_slug):
    r = admin_client.patch(
        f"/api/v1/ssp_documents/{ssp_slug}/roles/not-declared-anywhere",
        json={"role": {"title": "x"}},
    )
    assert r.status_code == 404


def test_undeclares_an_unreferenced_role(admin_client, ssp_slug):
    role_id = f"api-suite-temp-{uuid.uuid4().hex[:8]}"
    created = admin_client.post(
        f"/api/v1/ssp_documents/{ssp_slug}/roles",
        json={"role": {"id": role_id, "organization_defined": True}},
    )
    assert created.status_code == 201

    deleted = admin_client.delete(f"/api/v1/ssp_documents/{ssp_slug}/roles/{role_id}")
    assert deleted.status_code == 204

    listed = admin_client.get(f"/api/v1/ssp_documents/{ssp_slug}/roles").json()["data"]
    assert role_id not in {row["id"] for row in listed}


def test_unauthenticated_is_refused(anon_client, ssp_slug):
    """AC-3 — the endpoint is not readable without a token."""
    r = anon_client.get(f"/api/v1/ssp_documents/{ssp_slug}/roles")
    assert r.status_code in (401, 403)
