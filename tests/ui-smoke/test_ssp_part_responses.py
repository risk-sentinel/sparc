"""Per-part SSP responses, checked in the browser (v1.17.2).

An SSP is answered part by part: every statement part (ac-1 a., a.1, a.1.(a))
and every enhancement (ac-2.1). On a deployed v1.17.1 an author could not:

  - the response rows rendered only in the card's VIEW mode; clicking Edit,
    the obvious place to answer, showed control-level boxes and no row to
    answer a part in;
  - each row was labelled "a." or "(b)" with no text, so the author could not
    see which requirement a box answered.

This checks both on a seeded SSP: every lettered part of ac-1 shows its
requirement text, the rows are still there in Edit mode, and an enhancement has
its own answerable row.

#1312 — the rows are the read view; every item that takes a response is
answered in the control's Edit form, one block per item with all its fields.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp, show_hrefs

ROW = "tr[data-statement-id]"
REQUIREMENT = "[data-statement-requirement]"


def _card(page, control_id: str):
    return page.locator(".control-card").filter(
        has=page.locator(f".sparc-ctrl-id:text-is('{control_id}')")
    ).first


def _open_card(page, control_id: str):
    card = _card(page, control_id)
    card.evaluate(
        "c => { const g = c.closest('details.sparc-family-group'); if (g) g.open = true;"
        " const d = c.querySelector('details.card-details'); if (d) d.open = true; }"
    )
    card.scroll_into_view_if_needed()
    return card


def _ssp_with_part_rows(page) -> str:
    for href in show_hrefs(page, "/ssp_documents", "/ssp_documents"):
        page.goto(href)
        card = _card(page, "ac-1")
        if card.count() and card.locator(ROW).count() > 1:
            return href
    pytest.skip("no seeded SSP shows ac-1 with statement-part rows")


def test_every_part_of_ac1_shows_the_requirement_it_answers(authed_page):
    record_csp(authed_page)
    authed_page.goto(_ssp_with_part_rows(authed_page))
    card = _open_card(authed_page, "ac-1")

    rows = card.locator(ROW)
    lettered = [
        rows.nth(i) for i in range(rows.count())
        if not rows.nth(i).get_attribute("data-statement-id").endswith("_smt")
    ]
    assert lettered, "ac-1 has no lettered statement parts"
    blank = [
        r.get_attribute("data-statement-id") for r in lettered
        if r.locator(REQUIREMENT).inner_text().strip() in ("", "The control as a whole")
    ]
    assert not blank, f"statement parts with no requirement text: {blank}"
    assert_no_csp_violations(authed_page, during="ssp part rows")


def test_the_part_rows_stay_answerable_in_edit_mode(authed_page):
    authed_page.goto(_ssp_with_part_rows(authed_page))
    card = _open_card(authed_page, "ac-1")
    visible_before = card.locator(f"{ROW}:visible").count()

    card.locator("[id^='edit-btn-']").first.click()

    assert card.locator(f"{ROW}:visible").count() == visible_before > 1
    blocks = card.locator("[data-part-response]:visible")
    assert blocks.count() > 1, "the Edit form offers no item to answer"
    first = blocks.first
    assert first.locator("textarea[name$='[implementation_prose]']").is_visible()
    assert first.locator("select[name$='[implementation_status]']").is_visible()


def test_an_enhancement_has_its_own_answerable_row(authed_page):
    authed_page.goto(_ssp_with_part_rows(authed_page))
    # Whichever enhancement the baseline includes (LOW has no ac-2.1).
    ids = authed_page.locator(".control-card .sparc-ctrl-id").all_text_contents()
    enhancement = next((i.strip() for i in ids if "." in i), None)
    assert enhancement, "this SSP shows no enhancement at all"
    card = _open_card(authed_page, enhancement)

    row = card.locator(ROW).first
    requirement = row.locator(REQUIREMENT).inner_text().strip()
    assert requirement, f"{enhancement}'s row shows no requirement"

    card.locator("[id^='edit-btn-']").first.click()
    block = card.locator("[data-part-response]").first
    assert block.locator("textarea[name$='[implementation_prose]']").is_visible(), (
        f"{enhancement} has no answerable item in its Edit form"
    )
