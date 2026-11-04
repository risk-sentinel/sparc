"""UI smoke: the homepage's count badges (v1.17.2, #1243).

The thin inventory tiles above the layer cards are shown (restored after #1243
removed them by mistake), each a link to its list, and each card carries a
count that links to the same page as its title, scoped to what the user may
see. Every count is clicked here, in Chrome, with zero CSP violations.

Since 1.18.0-rf the cards are the Overview's boxes. Selectors verified against
app/views/home/_org_overview.html.erb and app/views/home/_inventory.html.erb
(`[data-home-inventory]`, `a[data-home-tile]`, `.sparc-inventory-name`,
`a[data-home-count]`, `[data-testid=org-box]`).
"""

from __future__ import annotations

from urllib.parse import urlparse

import pytest
from playwright.sync_api import expect

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


def _badges(page) -> list[tuple[str, str]]:
    return page.locator("a[data-home-count]").evaluate_all(
        "els => els.map(e => [e.dataset.homeCount, e.getAttribute('href')])"
    )


def _tiles(page) -> list[tuple[str, str]]:
    return page.locator("[data-home-inventory] a[data-home-tile]").evaluate_all(
        "els => els.map(e => [e.dataset.homeTile, e.getAttribute('href')])"
    )


def test_inventory_shows_and_each_badge_opens_its_list(authed_page, base_url):
    page = authed_page
    record_csp(page)
    page.goto(f"{base_url}/")
    page.wait_for_load_state("domcontentloaded")

    inventory = page.locator("[data-home-inventory]")
    expect(inventory).to_be_visible()
    labels = inventory.locator(".sparc-inventory-name").all_text_contents()
    for label in (
        "Catalogs",
        "Baselines",
        "Mappings",
        "SSPs",
        "CDEFs",
        "Converters",
        "SAPs",
        "Evidence",
        "SARs",
        "POA&Ms",
        "Auth Boundaries",
    ):
        assert label in labels, f"inventory tile {label!r} missing; found {labels}"
    # #1339 — the strip fits one row; the catalog list keeps these totals.
    for gone in ("Families", "Controls"):
        assert gone not in labels, f"inventory tile {gone!r} should be gone; found {labels}"
    badges = _badges(page)
    assert len(badges) >= 11, f"expected a badge on every layer card, found {badges}"

    for key, href in badges:
        # The Overview box's title link (1.18.0-rf): the box's own way in.
        card = page.locator("[data-testid=org-box]").filter(
            has=page.locator(f"a[data-home-count='{key}']")
        )
        view = card.locator(".sparc-lane-box__title")
        assert view.get_attribute("href") == href, f"{key}: badge and View lead to different pages"

    for key, href in badges:
        page.goto(f"{base_url}/")
        page.wait_for_load_state("domcontentloaded")
        badge = page.locator(f"a[data-home-count='{key}']")
        expect(badge).to_be_visible()
        badge.click()
        # A list may add its own query (a remembered view), so match the path.
        page.wait_for_url(lambda url, target=href: urlparse(url).path == target, timeout=10000)
        assert_no_csp_violations(page, during=f"clicking the {key} count badge")


def test_each_inventory_tile_opens_its_list(authed_page, base_url):
    page = authed_page
    record_csp(page)
    page.goto(f"{base_url}/")
    page.wait_for_load_state("domcontentloaded")

    tiles = _tiles(page)
    assert len(tiles) >= 11, f"expected a tile per inventory count, found {tiles}"
    badges = dict(_badges(page))
    for key, href in tiles:
        if key in badges:
            assert href == badges[key], f"{key}: tile and card badge lead to different pages"

    for key, href in tiles:
        page.goto(f"{base_url}/")
        page.wait_for_load_state("domcontentloaded")
        tile = page.locator(f"[data-home-inventory] a[data-home-tile='{key}']")
        expect(tile).to_be_visible()
        tile.click()
        page.wait_for_url(lambda url, target=href: urlparse(url).path == target, timeout=10000)
        assert_no_csp_violations(page, during=f"clicking the {key} inventory tile")


def test_non_admin_sees_no_organizations_card(user_authed_page, base_url):
    page = user_authed_page
    record_csp(page)
    page.goto(f"{base_url}/")
    page.wait_for_load_state("domcontentloaded")

    assert page.locator("a[data-home-count='organizations']").count() == 0
    labels = page.locator("[data-home-inventory] .sparc-inventory-name").all_text_contents()
    assert "Auth Boundaries" in labels and "Organizations" not in labels, labels
    assert page.locator("[data-testid=org-box] a[href^='/admin/organizations']").count() == 0
    assert page.locator("a[data-home-count='authorization_boundaries']").count() == 1
    assert_no_csp_violations(page, during="the homepage as a non-administrator")


def test_inventory_strip_is_one_row_at_1280(authed_page, base_url):
    """#1339 — the four layer cards sit on one row, and no card's numbers wrap."""
    page = authed_page
    record_csp(page)
    page.set_viewport_size({"width": 1280, "height": 900})
    page.goto(f"{base_url}/")
    page.wait_for_load_state("domcontentloaded")

    layout = page.locator("[data-home-inventory]").evaluate(
        """strip => [...strip.querySelectorAll('.sparc-home-strip__card')].map(card => {
             const tiles = [...card.querySelectorAll('a[data-home-tile]')];
             const tops = new Set(tiles.map(t => Math.round(t.getBoundingClientRect().top)));
             const counts = tiles.map(t => {
               const n = t.querySelector('.sparc-inventory-count').getBoundingClientRect();
               const l = t.querySelector('.sparc-inventory-name').getBoundingClientRect();
               return Math.abs((n.left + n.right) / 2 - (l.left + l.right) / 2);
             });
             return { label: card.getAttribute('aria-label'),
                      top: Math.round(card.getBoundingClientRect().top),
                      rows: tops.size, offCentre: Math.max(0, ...counts) };
           })"""
    )
    assert len(layout) == 4, layout
    tops = {card["top"] for card in layout}
    assert len(tops) == 1, f"layer cards wrap to more than one row: {layout}"
    for card in layout:
        assert card["rows"] == 1, f"{card['label']}: its numbers wrap onto a second line: {layout}"
        assert card["offCentre"] <= 1, (
            f"{card['label']}: a number is not centred over its label: {layout}"
        )
    assert_no_csp_violations(page, during="the homepage inventory strip at 1280px")
