"""#1134 — declaring an SSP's OSCAL roles from the boundary, not from a keyboard.

Before this there was no declare-a-role screen at all: the only route was
`POST /api/v1/ssp_documents/:id/roles` with a TYPED id. And importing boundary
members as system users wrote each member's raw membership role (`system_owner`,
underscored, never declared) into OSCAL `role-ids` — a reference to nothing.

The enrich page now lists the roles an SSP declares and offers the boundary's
membership vocabulary, by label, to declare from. These tests drive that on a
disposable SSP, because declaring a role changes the document and a seeded one
would run out of undeclared roles after a single pass.

The API is the oracle for what was actually declared, so a page that merely
LOOKS right cannot pass.
"""

from __future__ import annotations

import pytest

from _api_setup import add_boundary_member, create_boundary, create_ssp, delete_doc, ssp_roles
from helpers import assert_no_csp_violations, record_csp

SECTION = "details#ssp-declared-roles"
SELECT = "#ssp-declare-role-select"
DECLARED_IDS = "[data-testid='ssp-declared-roles-list'] code"

# Built-in membership values that name a level of ACCESS. Owner-decided: they
# are never offered as a role anyone is responsible for.
ACCESS_ONLY = {"view_only", "project_member"}


@pytest.fixture
def ssp():
    boundary = create_boundary()
    doc = create_ssp(boundary["id"])
    try:
        yield {"doc": doc, "boundary": boundary}
    finally:
        delete_doc("ssp_documents", doc["slug"])
        delete_doc("authorization_boundaries", boundary["slug"])


def _submit_and_wait(page, control, action):
    """Click a form control and wait for its POST to be ANSWERED.

    Turbo submits forms with fetch, so no navigation has started when `click()`
    returns and `wait_for_load_state("networkidle")` settles immediately. Asking
    the API what was declared at that point races the POST — measured: the
    oracle read the document before the request reached the server, which then
    answered 302 in 19 ms. Waiting on the response removes the race.
    """
    with page.expect_response(
        lambda r: r.request.method == "POST" and r.url.split("?")[0].endswith(f"/{action}")
    ) as info:
        control.click()
    assert info.value.status < 400, f"POST {action} answered {info.value.status}"
    page.wait_for_load_state("networkidle")


def _open_section(page, slug):
    page.goto(f"/ssp_documents/{slug}/enrich")
    page.wait_for_load_state("networkidle")
    section = page.locator(SECTION)
    assert section.count() == 1, "the enrich page has no Declared roles section"
    section.evaluate("el => { el.open = true }")
    return section


def test_roles_are_offered_by_label_and_never_typed(authed_page, ssp):
    page = authed_page
    record_csp(page)
    section = _open_section(page, ssp["doc"]["slug"])

    listed = set(section.locator(DECLARED_IDS).all_text_contents())
    declared_via_api = {r["id"] for r in ssp_roles(ssp["doc"]["slug"])["data"]}
    assert listed == declared_via_api, (
        f"the page lists {sorted(listed)} but the document declares {sorted(declared_via_api)}"
    )

    select = section.locator(SELECT)
    assert select.is_visible(), "no picker to declare a role from"

    # THE #1134 GUARANTEE on this screen: nothing to type an identifier into.
    assert section.locator("input[type='text']").count() == 0, (
        "the declare-a-role surface has a text input — an author can type a role id again"
    )

    values = select.locator("option").evaluate_all("opts => opts.map(o => o.value)")
    labels = [t.strip() for t in select.locator("option").all_text_contents()]
    assert values, "the picker offers nothing"
    offered_access_only = sorted(ACCESS_ONLY & set(values))
    assert not offered_access_only, (
        f"access-only membership roles are offered as responsibilities: {offered_access_only}"
    )
    # `isso` and `system_owner` resolve to roles every SSP declares by default,
    # so offering them would only produce a duplicate.
    assert not {"isso", "system_owner"} & set(values), (
        f"already-declared roles are offered: {values}"
    )
    assert all(label not in values for label in labels), (
        f"roles are offered by raw membership value rather than by label: {labels}"
    )
    assert_no_csp_violations(page, during="rendering the declare-a-role section")


def test_declaring_a_role_persists_and_is_organization_defined(authed_page, ssp):
    page = authed_page
    record_csp(page)
    slug = ssp["doc"]["slug"]
    section = _open_section(page, slug)

    choices = {c["membership_role"]: c for c in ssp_roles(slug)["meta"]["membership_roles"]}
    undeclared_org = [
        c for c in choices.values() if c["organization_defined"] and not c["declared"]
    ]
    if not undeclared_org:
        pytest.skip(
            "this instance's boundary vocabulary has no undeclared organization-defined role"
        )
    target = undeclared_org[0]

    section.locator(SELECT).select_option(target["membership_role"])
    _submit_and_wait(
        page, section.locator("input[type='submit'][value='Declare role']"), "declare_role"
    )

    declared = {r["id"]: r for r in ssp_roles(slug)["data"]}
    assert target["role_id"] in declared, (
        f"picking {target['label']!r} declared nothing — the document declares {sorted(declared)}"
    )
    assert declared[target["role_id"]]["organization_defined"] is True, (
        "a role NIST does not name was declared without the organization-defined marker"
    )

    section = _open_section(page, slug)
    assert target["role_id"] in section.locator(DECLARED_IDS).all_text_contents(), (
        "the declared role does not appear in the page's list after the save"
    )
    offered = section.locator(f"{SELECT} option").evaluate_all("opts => opts.map(o => o.value)")
    assert target["membership_role"] not in offered, "a role just declared is still offered"
    assert_no_csp_violations(page, during="declaring a role")


def test_importing_boundary_members_declares_what_it_references(authed_page, ssp):
    """The measured break: imported users carried undeclared, underscored role-ids."""
    page = authed_page
    record_csp(page)
    slug = ssp["doc"]["slug"]
    add_boundary_member(ssp["boundary"]["id"], "Smoke CISO", "ciso")
    add_boundary_member(ssp["boundary"]["id"], "Smoke Viewer", "view_only")

    page.goto(f"/ssp_documents/{slug}/enrich")
    page.wait_for_load_state("networkidle")
    _submit_and_wait(
        page,
        page.get_by_role("button", name="boundary member(s) as system users"),
        "import_boundary_users",
    )

    declared = {r["id"] for r in ssp_roles(slug)["data"]}
    # `view_only` is not offered as a responsibility, but a viewer is still a
    # system user, so the import must still DECLARE the role it references.
    for role_id in ("ciso", "view-only"):
        assert role_id in declared, (
            f"the import referenced {role_id!r} without declaring it — declared: {sorted(declared)}"
        )
    assert "view_only" not in declared, "the underscored membership value was declared verbatim"
    assert_no_csp_violations(page, during="importing boundary members")
