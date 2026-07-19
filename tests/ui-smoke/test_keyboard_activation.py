"""#762 — keyboard activation for div-based controls, verified in a real browser.

Sonar flagged ten `Web:MouseEventWithoutKeyboardEquivalentCheck` findings;
eight were false positives (Sonar cannot parse Stimulus `data-action`, so it
cannot see `keydown.enter->` / `keydown.space->` bindings that are already
present). Two were genuine:

  - shared/_heatmap.html.erb          heatmap cell badge, click-only
  - ssp_documents/show.html.erb       summary chip, bare action (defaults to click)

Both are `<div role="button">`. A div never receives `click` from the keyboard,
so those controls were mouse-only despite carrying `tabindex="0"`.

This file is the regression net for that fix. There is no JS test runner in
this repo (importmap, no bundler), so browser-level assertions are the only
way to prove the Stimulus wiring actually responds to a key press — a unit
test could not have caught the `preventDefault` bug below.

Also covers `heatmap_chip_controller#apply` gaining `preventDefault()`. The
CDEF/Profile/SAP chips already bound `keydown.space` while the controller
never suppressed the default, so pressing Space activated the filter AND
scrolled the page. That was live on three templates before #762.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp

HEATMAP_CELL = "[data-action*='heatmap#filterByCell']"
SUMMARY_CHIP = "[data-action*='heatmap-chip#apply']"


# Collection routes that sit at the same depth as a document slug. Without
# this the naive "one path segment under the index" rule picks
# /ssp_documents/wizard, lands on a page with no heatmap, and every test in
# this file skips green — a silently vacuous suite.
NON_SLUG_SEGMENTS = {
    "new", "wizard", "select_profile", "import", "upload", "search", "bulk",
}


def _doc_hrefs(page, index_path: str) -> list[str]:
    """Candidate document show-page hrefs from an index, best-effort ordered."""
    page.goto(index_path)
    page.wait_for_load_state("networkidle")
    links = page.locator(f"a[href^='{index_path}/']")

    seen: list[str] = []
    for i in range(links.count()):
        href = links.nth(i).get_attribute("href")
        if not href or href.count("/") != 2:
            continue
        if href.rsplit("/", 1)[-1] in NON_SLUG_SEGMENTS:
            continue
        if href not in seen:
            seen.append(href)
    return seen


def _open_page_with(page, index_path: str, selector: str, what: str):
    """Open the first document whose show page actually contains `selector`.

    Returns the located control. Skips only when NO document has it, so a
    routing quirk can't quietly turn the whole file into no-ops.
    """
    candidates = _doc_hrefs(page, index_path)
    if not candidates:
        pytest.skip(f"no document under {index_path} — run the demo seed (SPARC_SEED_DEMO=true)")

    for href in candidates:
        page.goto(href)
        page.wait_for_load_state("networkidle")
        if page.locator(selector).count() > 0:
            return page.locator(selector).first

    pytest.skip(
        f"no {what} found on any of {len(candidates)} document(s) under "
        f"{index_path} — seeded documents may have no controls"
    )


def _focus(control):
    control.scroll_into_view_if_needed()
    control.focus()
    return control


@pytest.mark.parametrize("key", ["Enter", "Space"])
def test_heatmap_cell_activates_by_keyboard(authed_page, key):
    """A heatmap cell badge must apply its filter from the keyboard (#762)."""
    record_csp(authed_page)
    cell = _focus(_open_page_with(authed_page, "/ssp_documents", HEATMAP_CELL, "heatmap cell"))
    assert cell.evaluate("el => el === document.activeElement"), (
        "cell did not take focus; tabindex regression"
    )

    cell.press(key)
    authed_page.wait_for_timeout(300)

    # filterByCell sets aria-pressed on activation.
    assert cell.get_attribute("aria-pressed") == "true", (
        f"{key} did not activate the heatmap cell — keyboard binding regression"
    )
    assert_no_csp_violations(authed_page, during=f"heatmap cell {key}")


@pytest.mark.parametrize("key", ["Enter", "Space"])
def test_summary_chip_activates_by_keyboard(authed_page, key):
    """An SSP summary chip must apply its filter from the keyboard (#762)."""
    record_csp(authed_page)
    chip = _focus(_open_page_with(authed_page, "/ssp_documents", SUMMARY_CHIP, "summary chip"))

    # The chip dispatches heatmap:chip to #heatmapSection; observe the event
    # rather than a DOM side effect so the assertion stays independent of how
    # the heatmap chooses to render the filter.
    authed_page.evaluate(
        "() => { window.__chipEvents = [];"
        "  const s = document.getElementById('heatmapSection');"
        "  if (s) s.addEventListener('heatmap:chip',"
        "    e => window.__chipEvents.push(e.detail && e.detail.filter)); }"
    )

    chip.press(key)
    authed_page.wait_for_timeout(300)

    events = authed_page.evaluate("window.__chipEvents || []")
    assert events, f"{key} did not dispatch heatmap:chip — keyboard binding regression"
    assert_no_csp_violations(authed_page, during=f"summary chip {key}")


def test_space_on_chip_does_not_scroll_page(authed_page):
    """Space must activate the chip WITHOUT scrolling (#762 preventDefault fix).

    Regression net for the bug that predated #762: the chips bound
    keydown.space but heatmap_chip_controller#apply never called
    preventDefault, so Space both filtered and paged down.
    """
    chip = _focus(_open_page_with(authed_page, "/ssp_documents", SUMMARY_CHIP, "summary chip"))
    # Ensure the document is actually scrollable, else the assertion is vacuous.
    scrollable = authed_page.evaluate(
        "() => document.documentElement.scrollHeight > window.innerHeight + 50"
    )
    if not scrollable:
        pytest.skip("page is not scrollable at this viewport — cannot observe scroll")

    before = authed_page.evaluate("window.scrollY")
    chip.press("Space")
    authed_page.wait_for_timeout(300)
    after = authed_page.evaluate("window.scrollY")

    assert after == before, (
        f"Space scrolled the page ({before} -> {after}); "
        "heatmap_chip_controller#apply is missing preventDefault()"
    )


def test_cdef_field_table_uses_row_headers(authed_page):
    """CDEF key/value tables expose the field name as <th scope='row'> (Web:S5256)."""
    _open_page_with(
        authed_page, "/cdef_documents", "table.sparc-field-table", "CDEF field table"
    )
    headers = authed_page.locator("table.sparc-field-table th[scope='row']")
    assert headers.count() > 0, (
        "field tables have no <th scope='row'> — Web:S5256 regression"
    )
    # The semantic change must stay visually invisible: <th> defaults to bold
    # + centered, and .sparc-field-label resets both.
    style = headers.first.evaluate(
        "el => { const s = getComputedStyle(el);"
        " return { weight: s.fontWeight, align: s.textAlign }; }"
    )
    assert style["align"] == "left", f"row header is not left-aligned: {style}"
    assert str(style["weight"]) in ("400", "normal"), (
        f"row header rendered bold, CSS reset regressed: {style}"
    )
