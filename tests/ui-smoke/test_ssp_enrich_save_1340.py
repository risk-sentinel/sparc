"""UI smoke: saving the SSP Enrich page keeps the author's place (#1340).

A tester added a component, left it blank, and saved. The page reloaded with
"Validation failed: Title can't be blank, Description can't be blank" at the
top. Their input was gone, every section had collapsed, nothing said which
row was wrong, and a blank added row could only be cleared by reloading.

Here, on a disposable SSP, in Chrome:
- the failed save answers 422 without reloading the page;
- the added row's Title is outlined, flagged invalid and has its message
  under it;
- the error list names the row;
- the section holding it is open and can't be collapsed, and a section the
  author had open stays open;
- typing into the field clears its mark, and Remove row takes the added row
  off;
- the next save succeeds in place, still on the Enrich page with its
  confirmation;
- a fresh load of the page shows what was saved.

Selectors verified against app/views/ssp_documents/enrich.html.erb and
app/views/ssp_documents/_enrich_remove_row.html.erb.
"""

from __future__ import annotations

import re
import uuid

import pytest
from playwright.sync_api import expect

from _api_setup import create_boundary, create_ssp, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

COMPONENTS = "details#enrich-components"
SECURITY = "details#enrich-security-levels"
SAVE = "input[type=submit][value='Save Enrichment Data']"
TITLE_FIELD = "input[name='ssp_document[components][][title]']"


@pytest.fixture
def ssp():
    boundary = create_boundary()
    doc = create_ssp(boundary["id"])
    try:
        yield doc
    finally:
        delete_doc("ssp_documents", doc["slug"])
        delete_doc("authorization_boundaries", boundary["slug"])


def _save(page, expected_status):
    with page.expect_response(
        lambda r: r.request.method in ("PATCH", "POST") and "/update_enrich" in r.url
    ) as info:
        page.locator(SAVE).click()
    assert info.value.status == expected_status, f"save answered {info.value.status}"
    page.wait_for_load_state("networkidle")


def test_failed_save_keeps_place_and_marks_the_field(authed_page, ssp):
    page = authed_page
    record_csp(page)
    resp = page.goto(f"/ssp_documents/{ssp['slug']}/enrich")
    assert resp and resp.status < 400, f"enrich page: {resp.status if resp else 'no response'}"

    # A marker that only a full page load would clear.
    page.evaluate("window.__sparcNoReload = true")
    page.locator(f"{SECURITY} > summary").click()
    page.locator(f"{COMPONENTS} > summary").click()
    page.get_by_role("button", name="+ Add Component").click()
    added = page.locator(".component-entry").last
    expect(added.get_by_test_id("enrich-remove-row")).to_be_visible()

    _save(page, 422)
    assert page.evaluate("window.__sparcNoReload === true"), "the failed save reloaded the page"
    assert page.url.rstrip("/").endswith("/enrich"), page.url
    errors = page.get_by_test_id("enrich-errors")
    expect(errors).to_be_visible()
    expect(errors).to_contain_text("Component 1: Title is empty")

    title = page.locator(".component-entry").last.locator(TITLE_FIELD)
    expect(title).to_have_class(re.compile(r"\bis-invalid\b"))
    assert title.get_attribute("aria-invalid") == "true"
    described_by = title.get_attribute("aria-describedby")
    expect(page.locator(f"#{described_by}")).to_contain_text("Title is empty")

    # The section holding the field is open and stays open; the one the author
    # had open is still open.
    assert page.locator(COMPONENTS).evaluate("d => d.open"), "the section with the error is closed"
    assert page.locator(SECURITY).evaluate("d => d.open"), "a section the author had open collapsed"
    page.locator(f"{COMPONENTS} > summary").click()
    assert page.locator(COMPONENTS).evaluate("d => d.open"), "the section with an error collapsed"

    # Typing clears the mark; then the row can be taken off.
    title.fill("x")
    assert "is-invalid" not in (title.get_attribute("class") or "")
    page.locator(".component-entry").last.get_by_test_id("enrich-remove-row").click()

    description = f"ui-smoke-1340-{uuid.uuid4().hex[:8]}"
    page.locator("#ssp_document_description").fill(description)
    _save(page, 200)
    assert page.evaluate("window.__sparcNoReload === true"), "the successful save reloaded the page"
    assert page.url.rstrip("/").endswith("/enrich"), f"a save left the Enrich page: {page.url}"
    expect(page.get_by_test_id("enrich-saved")).to_be_visible()
    assert page.locator(SECURITY).evaluate("d => d.open"), "an open section collapsed on save"
    assert_no_csp_violations(page, during="saving the SSP Enrich page")

    page.goto(f"/ssp_documents/{ssp['slug']}/enrich")
    expect(page.locator("#ssp_document_description")).to_have_value(description)
