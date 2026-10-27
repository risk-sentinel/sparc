"""#1100 — where an author answers a control's addressable parts.

Owner screen review: "This is not intuitive for where a user responds to each
part", and "it looks like only 1 response is stored for the entirety of the
control sub-parts".

Both were true, and neither was a data bug on the document under review — AC-2
had all 22 of its statements. The problems were where the table lived and what it
cost to use:

  * The Implementation Statements table rendered inside the control's EDIT form
    (`#edit-<id>`, which carries `.sparc-d-none`), below all nine editable
    fields. Answering a sub-part meant clicking Edit on the control, scrolling
    past status / application / coverage / type / roles, and finding a table at
    the bottom. It now renders in the VIEW, directly under the control language
    it answers.

  * Opening one statement's editor was a full page navigation to
    `?statement_id=N`, which reloaded every control on the document to show a
    modal. It is now inline.

  * Nothing on the screen said how much of a control was answered, so a control
    with 22 parts and one answer looked exactly like a finished one.

None of this is visible to rspec or to a pixel diff: the table was in the DOM
the whole time, just sealed inside a hidden edit form.

#1312 — one place to answer an item. Each row's inline editor was a second way
to write the same answer (and a deep-linked modal a third). The table is now
the read view; every item that takes a response is answered in the control's
Edit form, where it sets its own status, origination, responsible roles,
expected completion and remarks in one Save. A lead-in (AC-2 d. "Specify:")
takes no input.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp, show_hrefs

STATEMENTS_BLOCK = "text=Implementation Statements"
# Locate rows by an attribute BOTH the old and new partials carry, so a run
# against a build without this work FAILS on the assertions rather than
# skipping for want of a selector. A skip would be a vacuous green.
STMT_ROW = "tr[data-statement-id]"
ANSWERED_CHIP = "text=/\\d+ of \\d+ done/"  # #1242: counted in required responses


def _open_control_with_statements(page):
    """Expand the first control card that has more than one statement row.

    Returns (href, the control's <details> locator). Skips only when NO seeded
    SSP has a multi-statement control, so a thin estate cannot turn this file
    into silent no-ops.
    """
    for href in show_hrefs(page, "/ssp_documents", "/ssp_documents"):
        page.goto(href)
        page.wait_for_load_state("networkidle")

        # The control cards sit inside family groups that render COLLAPSED, so
        # nothing under them is visible until those are open. Without this every
        # assertion below fails on the wrapper rather than on what it is testing.
        page.evaluate(
            "() => document.querySelectorAll('details.sparc-family-group')"
            "        .forEach(d => { d.open = true })"
        )

        details = page.locator("details.card-details")
        for i in range(min(details.count(), 12)):
            card = details.nth(i)
            card.evaluate("el => { el.open = true }")
            if card.locator(STMT_ROW).count() > 1:
                card.scroll_into_view_if_needed()
                return href, card

    pytest.skip(
        "no seeded SSP has a control with more than one implementation "
        "statement — run the demo seed and the #1100 backfill"
    )


def test_statements_table_is_visible_without_entering_edit_mode(authed_page):
    """The authoring surface must be in the VIEW, not sealed in the edit form."""
    record_csp(authed_page)
    _href, card = _open_control_with_statements(authed_page)

    # The control's own edit form must still be hidden — proving the table is
    # visible because it moved, not because the card happens to be in edit mode.
    edit_form = card.locator("[id^='edit-']").first
    assert not edit_form.is_visible(), "precondition: the control edit form should be closed"

    assert card.locator(STATEMENTS_BLOCK).first.is_visible(), (
        "Implementation Statements is not visible with the control merely "
        "expanded — it is still behind the control's Edit button"
    )
    assert card.locator(STMT_ROW).first.is_visible(), "no statement row is on screen"

    # The structural fact behind the fix, independent of any open/closed state:
    # the block must not be a descendant of the control's edit form. It was one
    # before #1100, which is precisely why it could never be seen without
    # clicking Edit.
    inside_edit_form = card.locator(STMT_ROW).first.evaluate(
        "el => Boolean(el.closest(\"[id^='edit-']\"))"
    )
    assert not inside_edit_form, (
        "the statements table is still rendered inside the control's edit form"
    )
    assert_no_csp_violations(authed_page, during="ssp statements table")


def test_control_reports_how_much_of_it_is_answered(authed_page):
    """A 22-part control with one answer must not look like a finished one."""
    _href, card = _open_control_with_statements(authed_page)

    chip = card.locator(ANSWERED_CHIP).first
    assert chip.count() > 0 and chip.is_visible(), (
        "no 'N of M done' indicator on a control with multiple statements"
    )


ITEM_BLOCK = "[data-part-response]"
STATUSES = ["implemented", "partial", "planned", "alternative", "not-applicable"]
ORIGINATIONS = [
    "organization", "system-specific", "customer-configured", "customer-provided", "inherited",
]


def _open_edit_form(page, card):
    """Click the control's own Edit (in place, no navigation) and return its form."""
    control_card = card.locator("xpath=ancestor::div[contains(@class,'control-card')]").first
    control_card.locator("[id^='edit-btn-']").first.click()
    form = control_card.locator("[id^='edit-']").filter(has=page.locator(ITEM_BLOCK)).first
    form.wait_for(state="visible", timeout=5000)
    return form


def test_rows_are_read_only_now(authed_page):
    """#1312: the table is the read view; no row carries a second editor."""
    _href, card = _open_control_with_statements(authed_page)

    rows = card.locator(STMT_ROW)
    assert rows.count() > 1
    assert rows.locator("textarea, select, input[type='submit']").count() == 0, (
        "a statement row still carries its own editor — a second place to "
        "enter the same answer"
    )


def test_edit_form_sets_every_field_per_item(authed_page):
    """Each item that takes a response sets all of its own fields, in OSCAL's terms."""
    record_csp(authed_page)
    _href, card = _open_control_with_statements(authed_page)
    before_url = authed_page.url
    form = _open_edit_form(authed_page, card)
    assert authed_page.url == before_url, "opening Edit navigated"

    block = form.locator(ITEM_BLOCK).first
    status = block.locator("select[name$='[implementation_status]']")
    values = status.locator("option").evaluate_all("opts => opts.map(o => o.value)")
    assert [v for v in values if v] == STATUSES, values

    origin = block.locator("input[type='checkbox'][name$='[control_origination][]']")
    leveraged = block.locator("[data-testid='leveraged-origination']").count()
    if not leveraged:
        assert origin.evaluate_all("els => els.map(e => e.value)") == ORIGINATIONS

    roles = block.locator("select[name$='[responsible_role_ids][]']")
    assert roles.get_attribute("multiple") is not None
    role_values = roles.locator("option").evaluate_all("opts => opts.map(o => o.value)")
    assert "system-owner" in role_values, role_values
    # #1116: NIST's canonical id, never the abbreviation authors type.
    assert "isso" not in role_values
    # `all_text_contents()` on the options, NOT `inner_text()` on the select:
    # inner_text of a <select> is rendering-dependent across browsers.
    labels = roles.locator("option").all_text_contents()
    assert any(label.strip() == "System Owner" for label in labels), labels

    assert block.locator("input[type='date'][name$='[expected_completion]']").count() == 1
    assert block.locator("textarea[name$='[remarks]']").count() == 1
    assert block.locator("textarea[name$='[implementation_prose]']").count() == 1
    assert_no_csp_violations(authed_page, during="ssp control edit form")


def test_lead_ins_take_no_input(authed_page):
    """AC-2 d. 'Specify:' is answered by d.1-d.3, not by itself."""
    _href, card = _open_control_with_statements(authed_page)
    form = _open_edit_form(authed_page, card)
    lead_ins = form.locator("[data-lead-in]")
    if lead_ins.count() == 0:
        pytest.skip("this control has no lead-in item")
    assert lead_ins.locator("textarea, select, input").count() == 0


def test_saving_an_items_fields_persists_and_shows_in_the_read_view(authed_page):
    """Pick a status, origination and role, save once, and see them stick."""
    page = authed_page
    _href, card = _open_control_with_statements(page)
    form = _open_edit_form(page, card)
    block = form.locator(ITEM_BLOCK).first
    statement_id = block.get_attribute("data-part-response")
    prose_name = block.locator("textarea[name$='[implementation_prose]']").get_attribute("name")
    row_id = prose_name.split("[")[1].rstrip("]")

    block.locator("select[name$='[implementation_status]']").select_option("planned")
    if block.locator("[data-testid='leveraged-origination']").count() == 0:
        block.locator("input[type='checkbox'][value='inherited']").check()
        block.locator("input[type='checkbox'][value='system-specific']").check()
    block.locator("select[name$='[responsible_role_ids][]']").select_option(["system-owner"])
    block.locator("input[name$='[expected_completion]']").fill("2027-06-30")
    try:
        with page.expect_navigation(wait_until="load"):
            form.locator("input[type='submit'][value='Save Changes']").click()

        row = page.locator(f"tr[data-statement-id='{statement_id}']").first
        text = row.text_content()
        assert "Planned" in text, text[:400]
        assert "system-owner" in text, text[:400]
        assert "Expected 2027-06-30" in text, text[:400]
    finally:
        from _api_setup import _client
        with _client() as c:
            c.patch(f"/api/v1/ssp_control_statements/{row_id}",
                    json={"ssp_control_statement": {"implementation_status": None,
                                                    "control_origination": [],
                                                    "responsible_roles_data": [],
                                                    "expected_completion": None}})
