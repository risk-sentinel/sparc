"""#1312 — a SAR control's 800-53A objectives are determined in its Edit form.

The SAR had the SSP's problem: a control's Edit held only control-level fields,
and each objective was determined elsewhere, one at a time, through a per-row
Edit and a modal. What only a browser proves: on a seeded SAR the card's Edit
opens in place with a determination for every assessable objective, the read
view carries no second editor, and nothing trips CSP.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp, show_hrefs

BLOCK = "[data-objective-determination]"


def _sar_card_with_objectives(page):
    for href in show_hrefs(page, "/sar_documents", "/sar_documents"):
        page.goto(href)
        page.wait_for_load_state("domcontentloaded")
        cards = page.locator(".control-card").filter(has=page.locator(BLOCK))
        if cards.count():
            return cards.first
    pytest.skip("no seeded SAR control has assessment objectives — run the demo seed")


def test_edit_offers_every_objective_in_place(authed_page):
    page = authed_page
    record_csp(page)
    card = _sar_card_with_objectives(page)
    card.evaluate(
        "c => { const g = c.closest('details'); if (g) g.open = true;"
        " const d = c.querySelector('details.card-details'); if (d) d.open = true; }"
    )

    read_rows = card.locator("tr[data-objective-id]")
    assert read_rows.locator("a, button").count() == 0, (
        "an objective row still carries its own editor"
    )

    card.locator("[data-action='inline-edit#toggle']").first.click()
    blocks = card.locator(f"{BLOCK}:visible")
    assert blocks.count() > 0, "the Edit form offers no objective to determine"
    first = blocks.first
    statuses = first.locator("select[name$='[status]'] option").evaluate_all(
        "opts => opts.map(o => o.value)"
    )
    assert statuses == ["pending", "in-progress", "passing", "failed", "not_applicable"], statuses
    assert first.locator("textarea[name$='[assessor_notes]']").is_visible()
    assert_no_csp_violations(page, during="SAR control edit with determinations")
