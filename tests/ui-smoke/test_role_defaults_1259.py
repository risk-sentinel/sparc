"""UI smoke: a built-in role marks what differs from its shipped default (#1259).

An administrator's change to a built-in role is now kept when SPARC is
upgraded, so the role editor has to show which values are the administrator's
and offer to put one back. This grants a key the View Only role does not ship
with, reads the "Differs from default" marker on the edit and show screens,
then uses "Reset to default" and saves, and reads the marker gone.

The rules (what the seeds keep, what they audit, the upgrade) are covered at
the request and service layers: spec/requests/role_admin_overrides_1259_spec.rb,
spec/services/built_in_role_seeder_spec.rb.

Selectors verified against app/views/admin/roles/{_form,_default_marker,show}.html.erb.
The role is put back through the API in teardown whatever the assertions did.
"""

from __future__ import annotations

import re

import pytest

from _api_setup import get_json, patch_json
from helpers import assert_no_csp_violations, click_and_assert_clean, record_csp

pytestmark = pytest.mark.authenticated

ROLE_NAME = "view_only"
KEY = "sap.write"  # not granted to View Only by default
CHECKBOX = "#perm_sap_write"
MARKER = f"[data-testid='role-default-marker-{KEY}']"
RESET = f"[data-testid='role-default-reset-{KEY}']"


def _built_in_role() -> dict:
    roles = get_json("/api/v1/roles?scope=authorization_boundary&items=100")
    match = next((r for r in roles if r["name"] == ROLE_NAME), None)
    if match is None:
        pytest.skip(f"built-in role {ROLE_NAME!r} not present on this instance")
    return get_json(f"/api/v1/roles/{match['id']}")


def _restore(role: dict) -> None:
    granted = set(role["permissions"])
    patch_json(
        f"/api/v1/roles/{role['id']}",
        {"role": {"permissions": {k: k in granted for k in role["available_permissions"]}}},
    )


def test_admin_sees_and_resets_a_value_that_differs_from_default(authed_page):
    page = authed_page
    record_csp(page)
    role = _built_in_role()
    if not role.get("built_in"):
        pytest.skip("this instance predates #1259 (no shipped defaults reported)")
    if KEY in role["admin_overrides"] or KEY in role["permissions"]:
        pytest.skip(f"{ROLE_NAME} already carries {KEY} here; nothing to toggle safely")

    try:
        page.goto(f"/admin/roles/{role['id']}/edit")
        page.wait_for_load_state("networkidle")
        assert page.locator(MARKER).is_hidden(), "a value at its default must not be marked"

        page.locator(CHECKBOX).check()
        assert page.locator(MARKER).is_visible(), (
            "ticking a key the role does not ship with should mark it as differing at once"
        )
        assert_no_csp_violations(page, during="toggling a permission on a built-in role")

        with page.expect_navigation(wait_until="networkidle"):
            page.get_by_role("button", name="Save Changes").click()
        assert re.search(rf"/admin/roles/{role['id']}$", page.url), page.url
        assert page.locator(MARKER).is_visible(), "the role page should mark the overridden key"
        summary = page.get_by_test_id("role-defaults-summary").inner_text()
        assert KEY in summary, summary

        page.goto(f"/admin/roles/{role['id']}/edit")
        page.wait_for_load_state("networkidle")
        assert page.locator(MARKER).is_visible(), "the edit screen should mark the saved override"

        click_and_assert_clean(page, RESET, during="Reset to default")
        assert not page.locator(CHECKBOX).is_checked(), "Reset should put the shipped default back"
        assert page.locator(MARKER).is_hidden(), "the marker should clear once the default is back"

        with page.expect_navigation(wait_until="networkidle"):
            page.get_by_role("button", name="Save Changes").click()
        assert page.locator(MARKER).count() == 0, "a reset and saved key must not be marked"

        after = get_json(f"/api/v1/roles/{role['id']}")
        assert KEY not in after["admin_overrides"], after["admin_overrides"]
        assert KEY not in after["permissions"], after["permissions"]
        assert_no_csp_violations(page, during="saving a reset role")
    finally:
        _restore(role)
