"""#1312 — a SAP control's 800-53A objectives are planned in its Edit.

Each objective used to be planned one at a time, through a per-row Edit and its
own modal. What only a browser proves: on a seeded SAP the control's Edit opens
with every objective to plan, the objectives table carries no second editor,
and nothing trips CSP.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp, show_hrefs

BLOCK = "[data-objective-plan]"


def test_edit_offers_every_objective(authed_page, base_url):
    page = authed_page
    record_csp(page)
    for href in show_hrefs(page, "/sap_documents", "/sap_documents"):
        page.goto(href)
        page.wait_for_load_state("domcontentloaded")
        rows = page.locator("tr[data-objective-id]")
        if rows.count():
            break
    else:
        pytest.skip("no seeded SAP has assessment objectives — run the demo seed")

    assert rows.locator("a, button").count() == 0, "an objective row still carries its own editor"

    # Family groups render collapsed; open them so the card's Edit is clickable.
    page.evaluate("() => document.querySelectorAll('details').forEach(d => { d.open = true })")
    card = rows.first.locator("xpath=ancestor::div[contains(@class,'control-card')]").first
    with page.expect_navigation(wait_until="load"):
        card.get_by_role("link", name="Edit").first.click()
    modal = page.locator("#editModal")
    blocks = modal.locator(BLOCK)
    assert blocks.count() > 0, "the control's Edit offers no objective to plan"
    statuses = blocks.first.locator("select[name$='[status]'] option").evaluate_all(
        "opts => opts.map(o => o.value)"
    )
    assert statuses == ["pending", "in-progress", "passing", "failed", "not_applicable"], statuses
    assert blocks.first.locator("textarea[name$='[assessor_notes]']").is_visible()
    assert_no_csp_violations(page, during="SAP control edit with objectives")
