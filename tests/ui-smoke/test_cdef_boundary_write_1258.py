"""UI smoke: a System Owner writes their boundary's component definitions (#1258).

Every built-in role holding `cdef.write` holds it on a boundary, and every CDEF
write checked it at instance level only, so a System Owner could create and edit
no component definition at all. Now a boundary-scoped grant writes the CDEFs
scoped to that boundary, and nothing scoped elsewhere or wider.

Driven as the harness's second identity (SPARC_SMOKE_USER_TOKEN), a genuine
non-administrator. The administrator session creates two boundaries and a CDEF
on the second, then grants that identity the built-in System Owner / ISO role on
the first through Admin -> Users -> Edit; teardown removes the grant and deletes
what was made. As that user this authors a CDEF in the browser into its
boundary, opens it with Edit offered, and is refused the other boundary's.

Both directions for every action, on both surfaces, are at the request layer:
spec/requests/cdef_boundary_write_1258_spec.rb.

Selectors verified against app/views/admin/users/edit.html.erb and
app/views/cdef_documents/{new,show,_component_fields,_scope_picker}.html.erb.
"""

from __future__ import annotations

import uuid

import pytest

from _api_setup import _client, create_boundary, delete_doc, get_json
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

SUBMIT = "[data-testid='author-cdef-submit']"
EDIT = "[data-testid='edit-cdef']"
AUTHOR_BOUNDARY = "#cdef_author_authorization_boundary_id"
AUTHOR_SCOPE_BOUNDARY = "#cdef_author_scope_boundary"


def _second_identity_id(user_page) -> int:
    user_page.goto("/profile/edit")
    user_page.wait_for_load_state("domcontentloaded")
    email = user_page.locator(".sparc-avatar + div .text-body-secondary").first.inner_text().strip()
    assert "@" in email, f"could not read the second identity's email: {email!r}"
    match = next((u for u in get_json(f"/api/v1/users?email={email}") if u["email"] == email), None)
    assert match, f"no user found for {email}"
    assert not match["admin"], "SPARC_SMOKE_USER_TOKEN must be a non-administrator for this check"
    return match["id"]


def _system_owner_role_id() -> int:
    roles = get_json("/api/v1/roles?scope=authorization_boundary&items=100")
    match = next((r for r in roles if r["name"] == "so_iso"), None)
    if match is None:
        pytest.skip("the built-in System Owner / ISO role is not present on this instance")
    if "cdef.write" not in get_json(f"/api/v1/roles/{match['id']}")["permissions"]:
        pytest.skip("System Owner / ISO does not hold cdef.write here")
    return match["id"]


def _grant(admin_page, user_id: int, boundary_id: int, role_id: int) -> None:
    admin_page.goto(f"/admin/users/{user_id}/edit")
    admin_page.wait_for_load_state("networkidle")
    field = "select[name='user[authorization_boundary_roles][][{}]']"
    admin_page.select_option(field.format("authorization_boundary_id"), str(boundary_id))
    admin_page.select_option(field.format("role_id"), str(role_id))
    with admin_page.expect_navigation(wait_until="networkidle"):
        admin_page.get_by_role("button", name="Save Changes").click()


def _revoke(admin_page, user_id: int, boundary_name: str) -> None:
    admin_page.goto(f"/admin/users/{user_id}/edit")
    admin_page.wait_for_load_state("networkidle")
    keep = admin_page.locator(f"input[aria-label^='Keep '][aria-label$=' on {boundary_name}']")
    if keep.count() == 0:
        return
    for i in range(keep.count()):
        keep.nth(i).set_checked(False)
    with admin_page.expect_navigation(wait_until="networkidle"):
        admin_page.get_by_role("button", name="Save Changes").click()


def _cdef_on(boundary_id: int) -> dict:
    with _client() as c:
        r = c.post("/api/v1/cdef_documents", json={"cdef_document": {
            "name": f"phase2-ui-cdef1258-other-{uuid.uuid4().hex[:8]}", "component_type": "service",
            "component_title": "Other boundary component", "scope": "boundary",
            "authorization_boundary_id": boundary_id,
        }})
        assert r.status_code == 201, r.text[:300]
        return r.json()["data"]


def test_system_owner_writes_its_boundarys_cdefs_only(authed_page, user_authed_page):
    admin, user = authed_page, user_authed_page
    role_id = _system_owner_role_id()
    user_id = _second_identity_id(user)
    mine, theirs = create_boundary(), create_boundary()
    other = _cdef_on(theirs["id"])
    slug = None

    try:
        _grant(admin, user_id, mine["id"], role_id)

        record_csp(user)
        user.goto("/cdef_documents/new#author")
        user.wait_for_load_state("networkidle")
        assert user.locator(SUBMIT).count() == 1, "a System Owner should be offered authoring"
        offered = user.locator(f"{AUTHOR_BOUNDARY} option").all_text_contents()
        assert mine["name"] in offered, f"its own boundary is not offered: {offered}"
        assert theirs["name"] not in offered, "a boundary it holds no cdef.write on is offered"

        name = f"phase2-ui-cdef1258-{uuid.uuid4().hex[:8]}"
        user.fill("input[name='cdef_document[name]']", name)
        user.select_option("select[name='cdef_document[component_type]']", "service")
        user.fill("input[name='cdef_document[component_title]']", "Smoke System Owner Component")
        user.locator(AUTHOR_SCOPE_BOUNDARY).check()
        user.select_option(AUTHOR_BOUNDARY, str(mine["id"]))
        with user.expect_navigation(wait_until="networkidle"):
            user.click(SUBMIT)

        assert "/cdef_documents/" in user.url and "/new" not in user.url, (
            f"the System Owner's create did not land on the new document: {user.url}"
        )
        slug = user.url.rstrip("/").split("/")[-1]
        assert user.locator(EDIT).count() == 1, "Edit is not offered on its own boundary's CDEF"
        page_text = " ".join(user.locator("body").inner_text().split())
        assert f"Boundary-specific — {mine['name']}" in page_text, (
            "the authored CDEF is not scoped to the System Owner's boundary"
        )

        user.goto(f"/cdef_documents/{other['slug']}")
        user.wait_for_load_state("networkidle")
        assert user.locator(EDIT).count() == 0, "Edit is offered on another boundary's CDEF"

        user.goto(f"/cdef_documents/{other['slug']}/edit")
        user.wait_for_load_state("networkidle")
        assert f"/cdef_documents/{other['slug']}/edit" not in user.url, (
            "the other boundary's editor opened"
        )
        assert "not authorized" in user.locator("body").inner_text().lower()
        assert_no_csp_violations(user, during="a System Owner authoring a CDEF for its boundary")
    finally:
        _revoke(admin, user_id, mine["name"])
        if slug:
            delete_doc("cdef_documents", slug)
        delete_doc("cdef_documents", other["slug"])
        for b in (mine, theirs):
            delete_doc("authorization_boundaries", b.get("slug") or b["id"])
