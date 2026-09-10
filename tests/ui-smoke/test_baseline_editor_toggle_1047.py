"""UI smoke: the control-family baseline editor still reveals on click (#1047).

WHY THIS EXISTS, AND WHY IT IS AN INTERACTION TEST.

`baseline_editor` used to reveal its elements with

    el.style.display = this.editing ? "" : "none"

Writing an EMPTY string clears an inline `display`, which works only while the
markup hides the element with `style="display: none"`. The #1047 sweep moves
exactly those attributes into `.sparc-d-none` — and an empty inline value cannot
override a class. The toggle would have gone on flipping its label while
revealing nothing, so the whole baseline editing mode would have died silently,
on click, on a screen the visual gate does not even capture.

That is strictly worse than the toggle INVERSIONS #1047 already shipped: those
showed the wrong panel, this shows none. A pixel diff cannot see either, because
neither defect exists until someone clicks.

The controller now goes through `setVisible()`, which toggles the class and
strips any legacy inline `display` on the way past. This asserts the behaviour
that migration exists to protect, in both directions.

Selectors verified against app/views/control_families/show.html.erb.
"""

from __future__ import annotations

import pytest
from playwright.sync_api import expect

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

TOGGLE = "[data-baseline-editor-target='editToggle']"
BULK_TOOLBAR = "[data-baseline-editor-target='bulkToolbar']"
CHECKBOX_CELL = "[data-baseline-checkbox-cell]"


def _family_with_toggle(page, base_url):
    """A control-family page that actually renders the editor toggle.

    Two reasons this searches instead of taking the first thing it finds:

    * families hang off a catalog, so there is no `/control_families` index to
      discover from — this walks catalog -> family, which is also why the screen
      is absent from the visual gate's one-hop inventory; and
    * the toggle is gated on `can_write_catalogs? && !published_lifecycle?`, so
      a PUBLISHED catalog renders no button at all. Taking the first catalog
      lands on the seeded NIST one, which is published, and the test would fail
      on a screen that is behaving correctly.
    """
    page.goto(f"{base_url}/control_catalogs", wait_until="domcontentloaded", timeout=30000)
    catalogs = [
        h for h in page.eval_on_selector_all(
            "a[href]", "els => els.map(e => e.getAttribute('href'))")
        if h and h.startswith("/control_catalogs/") and "/new" not in h and "/edit" not in h
    ]
    if not catalogs:
        pytest.skip("no control catalog on this deployment — nothing to exercise")

    for catalog in dict.fromkeys(catalogs):
        page.goto(f"{base_url}{catalog}", wait_until="domcontentloaded", timeout=30000)
        families = [
            h for h in page.eval_on_selector_all(
                "a[href]", "els => els.map(e => e.getAttribute('href'))")
            if h and "/control_families/" in h and "/edit" not in h and "/new" not in h
        ]
        for family in dict.fromkeys(families):
            page.goto(f"{base_url}{family}", wait_until="domcontentloaded", timeout=30000)
            if page.locator(TOGGLE).count() and page.locator(CHECKBOX_CELL).count():
                return family

    pytest.skip("no editable (unpublished) catalog with a populated family — "
                "the toggle is gated on can_write_catalogs? && !published_lifecycle?")


def test_baseline_editor_reveals_and_hides_on_click(authed_page, base_url):
    page = authed_page
    record_csp(page)  # before goto — it installs an init script

    # Already navigated by the search; it returns a page that HAS the toggle.
    _family_with_toggle(page, base_url)

    toggle = page.locator(TOGGLE)
    expect(toggle).to_be_visible()

    cell = page.locator(CHECKBOX_CELL).first
    if cell.count() == 0:
        pytest.skip("family has no controls — nothing to reveal")

    # Hidden to start. `to_be_hidden` asks the browser, not the attribute, so it
    # holds whether the markup uses an inline style or `.sparc-d-none`.
    expect(cell).to_be_hidden()

    toggle.click()
    # THE ASSERTION THIS FILE EXISTS FOR: the reveal must actually reveal.
    expect(cell).to_be_visible()
    expect(page.locator(BULK_TOOLBAR)).to_be_visible()

    toggle.click()
    expect(cell).to_be_hidden()
    expect(page.locator(BULK_TOOLBAR)).to_be_hidden()

    assert_no_csp_violations(page, during="toggling the baseline editor")
