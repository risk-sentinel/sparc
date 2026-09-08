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
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp, show_hrefs

STATEMENTS_BLOCK = "text=Implementation Statements"
# Locate rows by an attribute BOTH the old and new partials carry, so a run
# against a build without this work FAILS on the assertions rather than
# skipping for want of a selector. A skip would be a vacuous green.
STMT_ROW = "tr[data-statement-id]"
ANSWERED_CHIP = "text=/\\d+ of \\d+ answered/"


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
        "no 'N of M answered' indicator on a control with multiple statements"
    )


def test_editing_one_statement_does_not_navigate(authed_page):
    """Opening a statement editor was a whole-page reload, 22 times per control."""
    record_csp(authed_page)
    href, card = _open_control_with_statements(authed_page)
    before_url = authed_page.url

    row = card.locator(STMT_ROW).first
    form = row.locator("[data-statement-edit-target='form']")
    assert not form.is_visible(), "precondition: the row editor should start closed"

    row.locator("[data-statement-edit-target='toggle']").click()
    authed_page.wait_for_timeout(250)

    assert authed_page.url == before_url, (
        f"editing a statement navigated: {before_url} -> {authed_page.url}"
    )
    assert form.is_visible(), "the inline statement editor did not open"
    assert row.locator("[data-statement-edit-target='prose']").is_visible(), (
        "the implementation textarea is not on screen"
    )
    assert_no_csp_violations(authed_page, during="statement inline edit")


def test_cancelling_closes_the_editor_and_restores_the_read_view(authed_page):
    href, card = _open_control_with_statements(authed_page)
    row = card.locator(STMT_ROW).first
    toggle = row.locator("[data-statement-edit-target='toggle']")
    form = row.locator("[data-statement-edit-target='form']")
    read = row.locator("[data-statement-edit-target='read']")

    toggle.click()
    authed_page.wait_for_timeout(250)
    assert form.is_visible()
    assert not read.is_visible(), "the read view should give way to the editor"

    row.locator("[data-action='statement-edit#cancel']").click()
    authed_page.wait_for_timeout(250)

    assert not form.is_visible(), "Cancel left the editor open"
    assert read.is_visible(), "Cancel did not restore the read view"
