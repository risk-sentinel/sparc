"""#1371 — a parameter saved on a draft baseline reaches Export > JSON (Resolved).

The download served the resolved catalog stored at publish or import, so a
value saved on a draft was on screen and in the plain JSON export and missing
from the resolved one. rspec covers the controller
(spec/requests/profile_resolved_catalog_1371_spec.rb); this drives the menu a
person uses: save the value in the form, open Export, take the download.
"""

from __future__ import annotations

import json

import pytest

from _api_setup import create_tailorable_profile, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

PARAM = "ac-01_odp.05"
FIELD = f"input[name='param_values[{PARAM}]']"
SAVE = "input[value='Save parameters'], button:has-text('Save parameters')"


@pytest.fixture
def profile():
    p = create_tailorable_profile()
    try:
        yield p
    finally:
        delete_doc("profile_documents", p["slug"])


def _reveal(page, selector: str):
    """Open each closed <details> around the element, outermost first."""
    field = page.locator(selector).first
    field.wait_for(state="attached", timeout=5000)
    for _ in range(6):
        if field.is_visible():
            return field
        closed = field.locator("xpath=ancestor::details[not(@open)]")
        if closed.count() == 0:
            break
        closed.first.locator("xpath=./summary").first.click()
        page.wait_for_timeout(100)
    assert field.is_visible(), f"{selector} never became visible"
    return field


def _resolved_values(document: dict) -> list[str] | None:
    def walk(node):
        if isinstance(node, dict):
            if node.get("id") == PARAM and "label" in node:
                return node.get("values")
            for child in node.values():
                found = walk(child)
                if found is not None:
                    return found
        elif isinstance(node, list):
            for child in node:
                found = walk(child)
                if found is not None:
                    return found
        return None

    return walk(document)


def test_a_saved_parameter_is_in_the_resolved_download(authed_page, profile, tmp_path):
    page = authed_page
    record_csp(page)
    page.goto(f"/profile_documents/{profile['slug']}")
    page.wait_for_load_state("networkidle")

    value = "at least annually (ui-smoke #1371)"
    field = _reveal(page, FIELD)
    field.fill(value)
    with page.expect_navigation(wait_until="load"):
        field.locator("xpath=ancestor::form[1]").locator(SAVE).first.click()
    page.wait_for_load_state("networkidle")

    page.locator("button.dropdown-toggle:has-text('Export')").first.click()
    with page.expect_download() as download:
        page.locator("a:has-text('JSON (Resolved)')").first.click()
    path = tmp_path / "resolved.json"
    download.value.save_as(path)

    assert _resolved_values(json.loads(path.read_text())) == [value], (
        "the value saved on the draft is missing from JSON (Resolved) — #1371"
    )
    assert_no_csp_violations(page, during="saving a parameter and exporting JSON (Resolved)")
