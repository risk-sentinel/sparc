"""UI smoke: a Policy Manager creates a component definition (#1257).

Before #1257 only an instance administrator could author a CDEF: every CDEF
write is checked at instance level, and every other built-in role holding
`cdef.write` is boundary-scoped. Policy Manager now ships with the key, and
holding it across the instance curates which CDEFs every organization shares.

Driven as the harness's second identity (SPARC_SMOKE_USER_TOKEN), a genuine
non-administrator. The administrator session grants it the built-in Policy
Manager role on Admin -> Users -> Edit, and teardown takes the role away again
if it did not hold it before. As that user this authors a CDEF in the browser,
asks for organization-wide scope, then makes it instance-wide through the
offered tier. The CDEF is deleted through the API afterwards.

The authorization rules in both directions (web and API, a role without
cdef.write refused, an administrator's revoke kept) are covered
at the request layer: spec/requests/policy_manager_cdef_write_1257_spec.rb.

Selectors verified against app/views/admin/users/edit.html.erb,
app/views/profiles/edit.html.erb, app/views/cdef_documents/{new,show,
_component_fields,_scope_picker}.html.erb.
"""

from __future__ import annotations

import uuid

import pytest

from _api_setup import delete_doc, get_json
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

SUBMIT = "[data-testid='author-cdef-submit']"
TYPE_SELECT = "select[name='cdef_document[component_type]']"
SCOPE_GLOBAL = "#cdef_document_scope_global"
SCOPE_INSTANCE = "#cdef_document_scope_instance"


def _second_identity_id(user_page) -> int:
    user_page.goto("/profile/edit")
    user_page.wait_for_load_state("domcontentloaded")
    email = user_page.locator(".sparc-avatar + div .text-body-secondary").first.inner_text().strip()
    assert "@" in email, f"could not read the second identity's email: {email!r}"
    match = next((u for u in get_json(f"/api/v1/users?email={email}") if u["email"] == email), None)
    assert match, f"no user found for {email}"
    assert not match["admin"], "SPARC_SMOKE_USER_TOKEN must be a non-administrator for this check"
    return match["id"]


def _policy_manager_role_id() -> int:
    roles = get_json("/api/v1/roles?scope=instance&items=100")
    match = next((r for r in roles if r["name"] == "policy_manager"), None)
    if match is None:
        pytest.skip("the built-in Policy Manager role is not present on this instance")
    if "cdef.write" not in get_json(f"/api/v1/roles/{match['id']}")["permissions"]:
        pytest.skip("Policy Manager does not hold cdef.write here (revoked, or pre-#1257)")
    return match["id"]


def _set_policy_manager(admin_page, user_id: int, role_id: int, *, held: bool) -> None:
    admin_page.goto(f"/admin/users/{user_id}/edit")
    admin_page.wait_for_load_state("networkidle")
    box = admin_page.locator(f"#role_{role_id}")
    if box.is_checked() == held:
        return
    box.set_checked(held)
    with admin_page.expect_navigation(wait_until="networkidle"):
        admin_page.get_by_role("button", name="Save Changes").click()


def test_policy_manager_creates_a_cdef_and_makes_it_instance_wide(
    authed_page, user_authed_page
):
    admin, user = authed_page, user_authed_page
    role_id = _policy_manager_role_id()
    user_id = _second_identity_id(user)

    admin.goto(f"/admin/users/{user_id}/edit")
    admin.wait_for_load_state("networkidle")
    held_before = admin.locator(f"#role_{role_id}").is_checked()
    slug = None

    try:
        _set_policy_manager(admin, user_id, role_id, held=True)

        record_csp(user)
        user.goto("/cdef_documents/new")
        user.wait_for_load_state("networkidle")
        assert user.locator(SUBMIT).count() == 1, "a Policy Manager should be offered authoring"

        name = f"phase2-ui-cdef1257-{uuid.uuid4().hex[:8]}"
        user.fill("input[name='cdef_document[name]']", name)
        user.select_option(TYPE_SELECT, "service")
        user.fill("input[name='cdef_document[component_title]']", "Smoke Policy Component")
        with user.expect_navigation(wait_until="networkidle"):
            user.click(SUBMIT)

        assert "/cdef_documents/" in user.url and "/new" not in user.url, (
            f"a Policy Manager's create did not land on the new document: {user.url}"
        )
        slug = user.url.rstrip("/").split("/")[-1]
        assert name in user.locator("body").inner_text()

        assert user.locator(f"{SCOPE_INSTANCE}:not([disabled])").count() == 1, (
            "a Policy Manager should be offered the instance-wide tier"
        )

        user.locator(SCOPE_GLOBAL).check()
        with user.expect_navigation(wait_until="networkidle"):
            user.get_by_role("button", name="Update Scope").click()
        body = user.locator("body").inner_text()
        assert "Instance-wide — every organization" not in body, (
            "asking for organization-wide must never make the CDEF instance-wide"
        )
        assert ("Organization-wide —" in body) or ("needs an organization" in body), (
            "organization-wide should either apply (the user has an organization) or be "
            "refused naming the missing organization; got neither"
        )

        user.locator(SCOPE_INSTANCE).check()
        with user.expect_navigation(wait_until="networkidle"):
            user.get_by_role("button", name="Update Scope").click()
        assert "Component definition scope updated." in user.locator("body").inner_text(), (
            "a Policy Manager's instance-wide scope was not applied"
        )
        assert user.locator(f"{SCOPE_INSTANCE}:checked").count() == 1, (
            "the picker should show the CDEF as instance-wide"
        )
        assert_no_csp_violations(user, during="a Policy Manager authoring and scoping a CDEF")
    finally:
        if slug:
            delete_doc("cdef_documents", slug)
        if not held_before:
            _set_policy_manager(admin, user_id, role_id, held=False)
