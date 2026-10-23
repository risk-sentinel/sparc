"""UI smoke: a boundary's own back-matter, managed from its page (v1.17.2, #1249).

Before #1249 nothing could create back-matter owned by a boundary, so the
Completeness row "Back-matter documents" stayed "Not started". The boundary
page's Back Matter section now adds, edits and deletes it, in any boundary
status. Driven in Chrome, each step with zero CSP violations; the delete goes
through SPARC's confirm modal (`#sparc-confirm-modal-confirm`, not a native
dialog). The boundary is created through the API (and made Active, to prove
the section is not draft-only) and deleted afterwards.

Selectors verified against app/views/authorization_boundaries/show.html.erb
and app/views/shared/_oscal_back_matter_section.html.erb.
"""

from __future__ import annotations

import uuid

import pytest
from playwright.sync_api import expect

from _api_setup import create_boundary, delete_doc, get_json, patch_json
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


@pytest.fixture
def active_boundary():
    record = create_boundary()
    try:
        r = patch_json(
            f"/api/v1/authorization_boundaries/{record['id']}",
            {"authorization_boundary": {"status": "active"}},
        )
        assert r.status_code == 200, r.text
        yield record
    finally:
        delete_doc("authorization_boundaries", record["slug"])


def _section(page):
    return page.locator("#boundary-back-matter")


def _expand(page):
    toggle = page.locator("[aria-controls='boundary-back-matter-body']")
    if toggle.get_attribute("aria-expanded") != "true":
        toggle.click()
    expect(toggle).to_have_attribute("aria-expanded", "true")


def _resources(boundary_id) -> list[dict]:
    return get_json(f"/api/v1/authorization_boundaries/{boundary_id}/back_matter_resources")


def test_create_edit_delete_back_matter_on_an_active_boundary(
    authed_page, base_url, active_boundary
):
    page = authed_page
    record_csp(page)
    title = f"phase2-ui-diagram-{uuid.uuid4().hex[:8]}"
    renamed = f"{title}-rev2"

    page.goto(f"{base_url}/authorization_boundaries/{active_boundary['slug']}")
    page.wait_for_load_state("domcontentloaded")
    _expand(page)

    # Create.
    form = _section(page).locator("#add-resource-section form")
    form.locator("[name='back_matter_resource[title]']").fill(title)
    form.locator("[name='back_matter_resource[href]']").fill(
        "https://example.gov/docs/boundary-diagram.pdf"
    )
    form.locator("[name='back_matter_resource[rel]']").select_option("diagram")
    form.get_by_role("button", name="Add Resource").click()
    # Wait for the redirected page (it carries the new title), THEN expand it.
    expect(_section(page)).to_contain_text(title)
    _expand(page)
    assert [r["title"] for r in _resources(active_boundary["id"])] == [title]
    assert_no_csp_violations(page, during="adding boundary back-matter")

    # The Completeness row turns Complete.
    row = page.locator("[data-readiness-row='back_matter']")
    expect(row).to_contain_text("Complete")

    # Edit.
    resource_row = _section(page).locator("tr", has_text=title).first
    resource_row.get_by_role("button", name="Edit").click()
    edit_form = _section(page).locator("tr[id^='edit-resource-'] form").first
    expect(edit_form).to_be_visible()
    edit_form.locator("[name='back_matter_resource[title]']").fill(renamed)
    edit_form.get_by_role("button", name="Save").click()
    expect(_section(page)).to_contain_text(renamed)
    _expand(page)
    assert [r["title"] for r in _resources(active_boundary["id"])] == [renamed]
    assert_no_csp_violations(page, during="editing boundary back-matter")

    # Delete, through the confirm modal.
    _section(page).locator("tr", has_text=renamed).first.get_by_role(
        "button", name="Delete"
    ).click()
    confirm = page.locator("#sparc-confirm-modal-confirm")
    confirm.wait_for(state="visible", timeout=5000)
    confirm.click()
    expect(page.locator("#boundary-back-matter")).not_to_contain_text(renamed)
    assert _resources(active_boundary["id"]) == []
    assert_no_csp_violations(page, during="deleting boundary back-matter")
