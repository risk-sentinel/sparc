"""The heatmap family filter, verified where it actually breaks: in the browser.

Three defects on the stimulus-mode heatmap (SSP / SAP / Profile show pages).
None of them is visible to rspec, and none to the pixel gate, because none of
them exists until a filter is applied:

  1. `applyFilter()` hid the family groups with no match but never OPENED the
     ones that matched. Those groups render collapsed, so a deep link such as
     ?family=CM&status=Deferred landed on a page whose matching rows were all
     sealed inside a closed <details>. The filter was arithmetically right and
     the screen looked empty.

  2. The family summary badge is server-rendered with the group's UNFILTERED
     total and nothing ever updated it, so a group narrowed to 2 rows kept a
     header reading 12. Clearing made it "correct" again, which is what made a
     static number read as stale state.

  3. The filter banner — and with it the only Clear Filter button — could not
     appear at all. `ae934727` (#1047) converted its `style="display: none;"`
     to `.sparc-d-none`, which is `display: none !important`; the controller
     still showed it by writing `style.display = "flex"`, and an inline
     declaration cannot outrank `!important`. This is the exact trap
     `controllers/visibility` was written for.

There is no JS test runner in this repo (importmap, no bundler), so a browser
assertion is the only way to prove the Stimulus wiring.
"""

from __future__ import annotations

from urllib.parse import quote

import pytest

from helpers import assert_no_csp_violations, record_csp, show_hrefs

GROUP = "details.sparc-family-group"
HEATMAP_CARD = ".sparc-heatmap-card"
BANNER = "[data-heatmap-target='banner']"
CLEAR = "[data-action='heatmap#clear']"

# A family/status cell that covers only PART of its family. Both count
# assertions below are vacuous on a cell whose count equals the family total
# (2 of 2 renders as the bare total, exactly like the unfiltered header), so the
# pick is the thing that gives this file teeth.
_PICK_PARTIAL_CELL = """
() => {
  for (const card of document.querySelectorAll('.sparc-heatmap-card')) {
    const totalEl = Array.from(card.querySelectorAll('div'))
      .find(d => /^\\s*\\d+\\s+controls\\s*$/.test(d.textContent))
    if (!totalEl) continue
    const total = parseInt(totalEl.textContent, 10)
    for (const badge of card.querySelectorAll('[data-heatmap-target="badge"]')) {
      const count = parseInt(badge.textContent, 10)
      if (Number.isFinite(count) && count > 0 && count < total) {
        return { family: badge.dataset.family, status: badge.dataset.status,
                 count: count, total: total }
      }
    }
  }
  return null
}
"""


def _ssp_show_with_heatmap(page) -> str:
    """Path of the first SSP whose show page has both a heatmap and family groups."""
    candidates = show_hrefs(page, "/ssp_documents", "/ssp_documents")
    if not candidates:
        pytest.skip("no SSP document — run the demo seed (SPARC_SEED_DEMO=true)")

    for href in candidates:
        page.goto(href)
        page.wait_for_load_state("networkidle")
        if page.locator(HEATMAP_CARD).count() and page.locator(GROUP).count():
            return href

    pytest.skip(
        f"none of {len(candidates)} seeded SSP(s) render both a heatmap and "
        "family groups — cannot exercise the filter"
    )


def _filtered(page, href: str):
    """Load `href` under a partial family/status filter. Returns the pick."""
    pick = page.evaluate(_PICK_PARTIAL_CELL)
    if not pick:
        pytest.skip(
            "no family/status cell covers only part of its family on this "
            "instance — every count assertion here would be vacuous"
        )
    page.goto(f"{href}?family={quote(pick['family'])}&status={quote(pick['status'])}")
    page.wait_for_load_state("networkidle")
    return pick


def _group(page, family: str):
    return page.locator(f"{GROUP}[data-family-group='{family}']")


def test_deep_link_filter_opens_the_matching_family_group(authed_page):
    """The matching rows must be ON SCREEN, not sealed in a collapsed group."""
    record_csp(authed_page)
    href = _ssp_show_with_heatmap(authed_page)
    pick = _filtered(authed_page, href)

    group = _group(authed_page, pick["family"])
    assert group.count() == 1, f"expected one {pick['family']} group, got {group.count()}"
    assert group.evaluate("el => el.open") is True, (
        f"the {pick['family']} group stayed collapsed under "
        f"?family={pick['family']}&status={pick['status']} — its "
        f"{pick['count']} matching row(s) are in the DOM but not on the screen"
    )

    visible = authed_page.locator(
        f"{GROUP}[data-family-group='{pick['family']}'] .control-card:visible"
    )
    assert visible.count() == pick["count"], (
        f"heatmap says {pick['count']} {pick['family']}/{pick['status']} control(s); "
        f"{visible.count()} are actually visible"
    )
    assert_no_csp_violations(authed_page, during="heatmap deep-link filter")


def test_family_header_count_follows_the_filter(authed_page):
    """The group header must not contradict the rows underneath it."""
    href = _ssp_show_with_heatmap(authed_page)
    pick = _filtered(authed_page, href)

    badge = _group(authed_page, pick["family"]).locator("[data-heatmap-count]")
    assert badge.count() == 1, "family summary badge lost its data-heatmap-count"
    # text_content(), not inner_text() — browser-independent (see the ui-smoke
    # rules on Firefox/Chromium rendering differences).
    assert badge.text_content().strip() == f"{pick['count']} / {pick['total']}", (
        f"header reads {badge.text_content().strip()!r} while the filter shows "
        f"{pick['count']} of {pick['total']} {pick['family']} control(s)"
    )


def test_filter_banner_and_clear_button_are_visible_under_a_filter(authed_page):
    """Regression net for the `.sparc-d-none` !important trap (#1047).

    An inline `style.display = "flex"` cannot outrank `display: none !important`,
    so the banner — and the only Clear Filter control on the page — was
    unreachable on every stimulus-mode heatmap.
    """
    href = _ssp_show_with_heatmap(authed_page)
    pick = _filtered(authed_page, href)

    banner = authed_page.locator(BANNER).first
    assert banner.is_visible(), (
        "the heatmap filter banner is hidden while a filter is active — "
        "Clear Filter is unreachable"
    )
    assert f"{pick['count']} control(s)" in banner.text_content(), (
        f"banner does not report the {pick['count']} matching control(s): "
        f"{banner.text_content()!r}"
    )
    assert authed_page.locator(CLEAR).first.is_visible(), "Clear Filter button is hidden"


def test_clearing_restores_the_counts_and_the_collapsed_groups(authed_page):
    """Clear must put the screen back, not leave every group forced open."""
    record_csp(authed_page)
    href = _ssp_show_with_heatmap(authed_page)
    pick = _filtered(authed_page, href)

    group = _group(authed_page, pick["family"])
    assert group.evaluate("el => el.open") is True, "precondition: filter did not open the group"

    authed_page.locator(CLEAR).first.click()
    authed_page.wait_for_timeout(300)

    badge = group.locator("[data-heatmap-count]")
    assert badge.text_content().strip() == str(pick["total"]), (
        f"after Clear the {pick['family']} header reads "
        f"{badge.text_content().strip()!r}, not its unfiltered total {pick['total']}"
    )
    assert group.evaluate("el => el.open") is False, (
        "Clear left the group forced open instead of restoring how it was found"
    )
    assert not authed_page.locator(BANNER).first.is_visible(), "Clear left the banner up"
    assert_no_csp_violations(authed_page, during="heatmap clear")
