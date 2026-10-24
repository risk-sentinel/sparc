"""UI smoke: a CDEF is approved at the tier it asks to reach (#1275).

Instance > Organization > Boundary. Nearly anyone authors a CDEF on their
boundary; making it available more widely is asked for at Submit for review and
approved at the tier it reaches: the boundary's own ISSO, ISSM or System Owner
approve it for the boundary or organization-wide in the boundary's
organization; instance-wide is Policy Manager's (or the instance
administrator's). Nobody approves their own submission.

Driven as the harness's second identity (SPARC_SMOKE_USER_TOKEN), a genuine
non-administrator. The administrator session creates two boundaries, puts them
both in an existing organization, and grants that identity the built-in ISSO
role on the first through Admin -> Users -> Edit. The administrator authors and
submits the CDEFs, so the ISSO is never the submitter. As the ISSO this opens a
CDEF asking for organization-wide availability, sees what approving grants,
approves it from the CDEF page and sees it organization-wide; then sees no
Approve on a CDEF asking for instance-wide, nor on the sibling boundary's.
Teardown removes the grant and deletes what was made.

Every tier in both directions, the submitter rule and the form as rendered are
at the request layer: spec/requests/cdef_boundary_approve_1275_spec.rb.

Selectors verified against app/views/cdef_documents/_approval.html.erb,
app/views/review_queue/_item_actions.html.erb and app/views/admin/users/edit.html.erb.
"""

from __future__ import annotations

import uuid

import pytest

from _api_setup import _client, create_boundary, delete_doc, get_json
from helpers import assert_no_csp_violations, record_csp
from test_cdef_boundary_write_1258 import _grant, _revoke, _second_identity_id

pytestmark = pytest.mark.authenticated

APPROVAL = "[data-testid='cdef-approval']"
STATUS = "[data-testid='cdef-approval-status']"
REQUESTED = "[data-testid='cdef-requested-scope']"
CONFIRM_MODAL_OK = "#sparc-confirm-modal-confirm"


def _isso_role_id() -> int:
    roles = get_json("/api/v1/roles?scope=authorization_boundary&items=100")
    match = next((r for r in roles if r["name"] == "isso"), None)
    if match is None:
        pytest.skip("the built-in ISSO role is not present on this instance")
    if "cdef.approve" not in get_json(f"/api/v1/roles/{match['id']}")["permissions"]:
        pytest.skip("ISSO does not hold cdef.approve here")
    return match["id"]


def _an_organization() -> dict:
    orgs = [o for o in get_json("/api/v1/organizations") if o.get("active", True)]
    if not orgs:
        pytest.skip("no organization on this instance — run the demo seed")
    return orgs[0]


def _place_in(boundary: dict, organization: dict) -> None:
    with _client() as c:
        r = c.patch(f"/api/v1/authorization_boundaries/{boundary['id']}/organization",
                    json={"organization_id": organization["id"]})
        assert r.status_code == 200, r.text[:300]


def _submitted_cdef(boundary_id: int, requested_scope: str, made: list[dict]) -> dict:
    """A CDEF on this boundary with a control basis, submitted by the administrator.

    Recorded in `made` as soon as it exists, so teardown deletes it even when a
    later step fails."""
    with _client() as c:
        r = c.post("/api/v1/cdef_documents", json={"cdef_document": {
            "name": f"phase2-ui-cdef1275-{requested_scope}-{uuid.uuid4().hex[:8]}",
            "component_type": "service",
            "component_title": "Approval tier component", "scope": "boundary",
            "authorization_boundary_id": boundary_id,
        }})
        assert r.status_code == 201, r.text[:300]
        cdef = r.json()["data"]
        made.append(cdef)
        listed = c.get("/api/v1/profile_documents", params={"lifecycle_status": "published"})
        profiles = listed.json().get("data", [])
        profile = next((p for p in profiles if p.get("lifecycle_status") == "published"), None)
        if profile is None:
            pytest.skip("no published profile to give the CDEF a control basis")
        populated = c.post(f"/api/v1/cdef_documents/{cdef['slug']}/source_from_profile",
                           json={"source_profile_id": profile["id"]})
        assert populated.status_code == 200, populated.text[:300]
        submitted = c.post(f"/api/v1/cdef_documents/{cdef['slug']}/submit_for_review",
                           json={"requested_scope": requested_scope})
        assert submitted.status_code == 200, submitted.text[:300]
        assert submitted.json()["data"]["requested_scope"] == requested_scope
        return cdef


def _open(page, slug: str) -> None:
    page.goto(f"/cdef_documents/{slug}")
    page.wait_for_load_state("networkidle")


def test_boundary_isso_approves_up_to_organization_wide_only(authed_page, user_authed_page):
    admin, user = authed_page, user_authed_page
    role_id = _isso_role_id()
    user_id = _second_identity_id(user)
    organization = _an_organization()
    mine, theirs = create_boundary(), create_boundary()
    made: list[dict] = []

    try:
        # Both boundaries in one organization: holding ISSO on one approves
        # nothing on its sibling, even organization-wide in the same org.
        _place_in(mine, organization)
        _place_in(theirs, organization)
        org_wide = _submitted_cdef(mine["id"], "global", made)
        instance_wide = _submitted_cdef(mine["id"], "instance", made)
        other = _submitted_cdef(theirs["id"], "global", made)
        _grant(admin, user_id, mine["id"], role_id)

        record_csp(user)
        _open(user, org_wide["slug"])
        approval = user.locator(APPROVAL)
        assert approval.locator(STATUS).inner_text().strip() == "Pending Review"
        expected = f"organization-wide ({organization['name']})"
        assert approval.locator(REQUESTED).inner_text().strip() == expected
        user.locator(APPROVAL).get_by_role("button", name="Approve").click()
        user.locator(CONFIRM_MODAL_OK).wait_for(state="visible", timeout=5_000)
        with user.expect_navigation(wait_until="networkidle"):
            user.click(CONFIRM_MODAL_OK)

        status = user.locator(STATUS).inner_text().strip()
        assert status == "Approved", f"the ISSO's approval did not land: {status!r}"
        page_text = " ".join(user.locator("body").inner_text().split())
        assert "Organization-wide — any boundary's SSP within" in page_text, (
            "approving did not make the CDEF organization-wide"
        )
        approved = get_json(f"/api/v1/cdef_documents/{org_wide['slug']}")
        assert approved["scope_tier"] == "organization"

        refused = (
            (instance_wide, "an instance-wide request"),
            (other, "its sibling boundary's CDEF"),
        )
        for cdef, why in refused:
            _open(user, cdef["slug"])
            offered = user.locator(APPROVAL).get_by_role("button", name="Approve").count()
            assert offered == 0, (
                f"the boundary ISSO is offered Approve on {why}"
            )

        _open(admin, instance_wide["slug"])
        assert admin.locator(APPROVAL).get_by_role("button", name="Approve").count() == 1, (
            "the instance administrator is not offered Approve on an instance-wide request"
        )
        assert_no_csp_violations(user, during="a boundary ISSO approving a CDEF from its page")
    finally:
        _revoke(admin, user_id, mine["name"])
        for cdef in made:
            delete_doc("cdef_documents", cdef["slug"])
        for b in (mine, theirs):
            delete_doc("authorization_boundaries", b.get("slug") or b["id"])
