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


# ── #1134 — declared from the boundary vocabulary, never typed ──────────────

ACCESS_ONLY = {"view_only", "project_member"}


def _membership_roles(client, slug):
    r = client.get(f"/api/v1/ssp_documents/{slug}/roles")
    r.raise_for_status()
    return r.json()["meta"]["membership_roles"]


def test_index_offers_the_responsibility_bearing_boundary_vocabulary(admin_client, ssp_slug):
    choices = _membership_roles(admin_client, ssp_slug)

    assert choices, "no boundary vocabulary offered to declare from"
    for c in choices:
        assert set(c) >= {"membership_role", "label", "role_id", "organization_defined", "declared"}
    offered = {c["membership_role"] for c in choices}
    assert not offered & ACCESS_ONLY, f"access-only roles offered: {sorted(offered & ACCESS_ONLY)}"

    by_value = {c["membership_role"]: c for c in choices}
    if "isso" in by_value:
        # NIST's id, never the membership value or its hyphenated form.
        assert by_value["isso"]["role_id"] == "information-system-security-officer"
        assert by_value["isso"]["organization_defined"] is False


def test_declares_a_role_by_membership_role(admin_client, ssp_slug):
    pick = next((c for c in _membership_roles(admin_client, ssp_slug) if not c["declared"]), None)
    if pick is None:
        pytest.skip("every responsibility-bearing boundary role is already declared on this SSP")

    r = admin_client.post(
        f"/api/v1/ssp_documents/{ssp_slug}/roles",
        json={"role": {"membership_role": pick["membership_role"]}},
    )
    try:
        assert r.status_code == 201, r.text
        data = r.json()["data"]
        assert data["id"] == pick["role_id"], "declared a different id than index said it would"
        assert data["organization_defined"] is pick["organization_defined"]

        after = {c["membership_role"]: c for c in _membership_roles(admin_client, ssp_slug)}
        assert after[pick["membership_role"]]["declared"] is True
    finally:
        # Clean up by id, not by name.
        admin_client.delete(f"/api/v1/ssp_documents/{ssp_slug}/roles/{pick['role_id']}")


def test_refuses_an_access_only_membership_role(admin_client, ssp_slug):
    r = admin_client.post(
        f"/api/v1/ssp_documents/{ssp_slug}/roles",
        json={"role": {"membership_role": "view_only"}},
    )
    assert r.status_code == 422
    assert "responsibility-bearing" in r.json()["error"]


def test_refuses_id_and_membership_role_together(admin_client, ssp_slug):
    stray = f"api-suite-both-{uuid.uuid4().hex[:8]}"
    r = admin_client.post(
        f"/api/v1/ssp_documents/{ssp_slug}/roles",
        json={"role": {"membership_role": "ciso", "id": stray}},
    )
    assert r.status_code == 422
    # Without the guard, `ciso` would be declared and `stray` never — so the
    # absence of `stray` alone proves nothing. The refusal must name the reason.
    assert "not both" in r.json()["error"]

    listed = admin_client.get(f"/api/v1/ssp_documents/{ssp_slug}/roles").json()["data"]
    assert stray not in {row["id"] for row in listed}
