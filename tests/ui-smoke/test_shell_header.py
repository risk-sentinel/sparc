"""The shell header in a real browser (1.18.0-rf #1295, #1291, SPARC_NAV_SHELL).

Posture-gated ("nav_shell"): reported as UNPROVEN when the stack has the switch
off. Every menu entry is clicked, each click followed by a CSP check, and must
open the page it names:
  - Create, Library and Help;
  - the review-queue indicator;
  - the boundary switcher, by mouse and by keyboard (type to filter, arrow
    keys, Esc returns focus to the trigger).
The header must not overflow the viewport from 1440px down to 320px, and the
open switcher is held to zero new WCAG 2.1 AA violations.

Requires SPARC_SMOKE_SA_TOKEN, on an instance where the smoke user can reach at
least one boundary.
"""

from __future__ import annotations

from urllib.parse import urlparse

import pytest
from playwright.sync_api import expect

from a11y import assert_no_new_a11y_violations
from helpers import (
    SHELL_HEADER,
    assert_no_csp_violations,
    click_and_assert_clean,
    nav_shell_on,
    record_csp,
)

pytestmark = [pytest.mark.authenticated, pytest.mark.posture("nav_shell")]

TRIGGER = "[data-testid=shell-switcher]"
PANEL = "[data-testid=shell-switcher-panel]"
ITEM = f"{PANEL} [data-testid=shell-switcher-item]"


def _home(page):
    response = page.goto("/")
    assert response is not None and response.ok, f"/ returned {response and response.status}"
    page.wait_for_load_state("networkidle")
    if not nav_shell_on(page):
        pytest.skip("SPARC_NAV_SHELL is off on this stack, so there is no shell header")


def _menu_entries(page, menu_testid, item_selector):
    toggle = page.locator(f"[data-testid={menu_testid}] > .dropdown-toggle")
    if toggle.count() == 0:
        return []
    toggle.click()
    entries = page.locator(f"[data-testid={menu_testid}] {item_selector}").evaluate_all(
        "els => els.map(e => ({href: e.getAttribute('href'), target: e.getAttribute('target')}))"
    )
    toggle.click()
    return entries


def _click_every_entry(page, menu_testid, item_selector):
    offered = _menu_entries(page, menu_testid, item_selector)
    entries = [e for e in offered if e["target"] != "_blank"]
    assert entries, f"the {menu_testid} menu offered nothing to click"
    for entry in entries:
        _home(page)
        page.locator(f"[data-testid={menu_testid}] > .dropdown-toggle").click()
        link = page.locator(f"[data-testid={menu_testid}] {item_selector}[href='{entry['href']}']")
        want = urlparse(entry["href"]).path
        click_and_assert_clean(page, link.first, during=f"{menu_testid}: {entry['href']}")
        # A Turbo visit: the URL changes after the click returns.
        page.wait_for_url(lambda url, want=want: urlparse(url).path == want, timeout=15000)


def test_create_and_library_entries_open_their_screens(authed_page):
    page = authed_page
    record_csp(page)
    _home(page)
    if page.locator("[data-testid=shell-create]").count():
        _click_every_entry(page, "shell-create", "[data-testid=shell-create-item]")
    _click_every_entry(page, "shell-library", "[data-testid=shell-library-item]")
    assert_no_csp_violations(page, during="shell header menus")


def test_help_menu_entries_open_in_place_or_in_a_new_tab(authed_page):
    page = authed_page
    record_csp(page)
    _home(page)
    entries = _menu_entries(page, "shell-help", "a.dropdown-item")
    # Guides open in a new tab (#870) and "Help for this page" in the drawer
    # (test_help_drawer_880); the rest navigate here.
    assert any(e["target"] == "_blank" for e in entries), "no guide link in the Help menu"
    _click_every_entry(page, "shell-help", "a.dropdown-item")


def test_review_queue_indicator_opens_the_queue(authed_page):
    page = authed_page
    record_csp(page)
    _home(page)
    indicator = page.locator("[data-testid=shell-review-queue]")
    if indicator.count() == 0:
        pytest.skip("the smoke user approves no reviewable type, so there is no review queue")
    click_and_assert_clean(page, indicator, during="review queue indicator")
    page.wait_for_url("**/review_queue")


def test_switcher_by_mouse_opens_the_chosen_boundary(authed_page):
    page = authed_page
    record_csp(page)
    _home(page)
    if page.locator(ITEM).count() == 0:
        pytest.skip("the smoke user can reach no boundary")

    click_and_assert_clean(page, TRIGGER, during="open the switcher")
    expect(page.locator(PANEL)).to_be_visible()
    expect(page.locator(TRIGGER)).to_have_attribute("aria-expanded", "true")
    assert_no_new_a11y_violations(page, "shell_switcher_open")

    first = page.locator(ITEM).first
    href = first.get_attribute("href")
    click_and_assert_clean(page, first, during="choose a boundary")
    page.wait_for_url(f"**{href}")
    expect(page.locator("[data-testid=shell-boundary]")).to_be_visible()


def test_switcher_by_keyboard_filters_moves_and_closes(authed_page):
    page = authed_page
    record_csp(page)
    _home(page)
    items = page.locator(ITEM)
    if items.count() == 0:
        pytest.skip("the smoke user can reach no boundary")
    name = items.first.locator(".sparc-switcher__name").inner_text().strip()

    page.locator(TRIGGER).focus()
    page.keyboard.press("Enter")
    expect(page.locator(PANEL)).to_be_visible()
    expect(page.locator(f"{PANEL} input[type=search]")).to_be_focused()

    page.keyboard.type(name)
    visible = [
        n.strip().lower()
        for n in page.locator(f"{ITEM}:visible .sparc-switcher__name").all_inner_texts()
    ]
    assert visible, f"filtering by {name!r} hid every boundary"
    assert all(name.lower() in n for n in visible), visible

    page.keyboard.press("ArrowDown")
    focused = page.evaluate("document.activeElement?.dataset.testid")
    assert focused == "shell-switcher-item", f"ArrowDown focused {focused!r}"

    page.keyboard.press("Escape")
    expect(page.locator(PANEL)).to_be_hidden()
    expect(page.locator(TRIGGER)).to_be_focused()
    assert_no_csp_violations(page, during="switcher by keyboard")


@pytest.mark.parametrize("menu", ["shell-create", "shell-library", "shell-help"])
def test_an_open_menu_floats_over_the_page(authed_page, menu):
    """A menu must open over the page, not inside the header's flow.

    Without `navbar-expand`, Bootstrap leaves navbar dropdowns `position:
    static`, so opening one stretched the header to the menu's height (found by
    the owner walking phase 3; no check opened a menu before).
    """
    page = authed_page
    _home(page)
    toggle = page.locator(f"[data-testid={menu}] > .dropdown-toggle")
    if toggle.count() == 0:
        pytest.skip(f"the smoke user is offered no {menu} menu")
    before = page.locator(SHELL_HEADER).bounding_box()["height"]
    toggle.click()
    expect(page.locator(f"[data-testid={menu}] .dropdown-menu")).to_be_visible()
    position = page.locator(f"[data-testid={menu}] .dropdown-menu").evaluate(
        "el => getComputedStyle(el).position"
    )
    after = page.locator(SHELL_HEADER).bounding_box()["height"]
    assert position == "absolute", f"{menu} opens with position {position}"
    assert after == before, f"opening {menu} stretched the header from {before}px to {after}px"


@pytest.mark.parametrize("width", [1440, 1024, 768, 414, 360, 320])
def test_the_header_fits_from_1440_to_320(authed_page, width):
    page = authed_page
    page.set_viewport_size({"width": width, "height": 800})
    _home(page)
    header = page.locator(SHELL_HEADER).bounding_box()
    overflow = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
    assert overflow <= 0, f"{width}px: the page scrolls sideways by {overflow}px"
    assert header and header["height"] < 90, f"{width}px: the header wrapped ({header})"
    help_toggle = page.locator(f"{SHELL_HEADER} [data-testid=shell-help] > .dropdown-toggle")
    expect(help_toggle).to_be_visible()
