"""The administration settings in a real browser (1.18.0-rf #1303).

Posture-gated ("nav_shell"): reported as UNPROVEN when the stack has the switch
off (then /admin does not exist). As an administrator: the organization's
Settings tab opens the settings page; every screen it lists is clicked (each
click followed by a CSP check) and must open with the settings menu beside it,
naming itself as the current page. The settings page is held to zero new WCAG
2.1 AA violations.

Requires SPARC_SMOKE_SA_TOKEN for an instance administrator.
"""

from __future__ import annotations

from urllib.parse import urlparse

import pytest
from playwright.sync_api import expect

from a11y import assert_no_new_a11y_violations
from helpers import assert_no_csp_violations, click_and_assert_clean, nav_shell_on, record_csp

pytestmark = [pytest.mark.authenticated, pytest.mark.posture("nav_shell")]

SETTINGS_TAB = "[data-testid=org-tabs] [data-tab=settings]"
ITEM = "[data-testid=admin-settings-item]"
MENU = "[data-testid=admin-settings-menu]"


def _open(page, path):
    resp = page.goto(path)
    assert resp is not None and resp.status < 500, f"{path} returned {resp and resp.status}"
    page.wait_for_load_state("networkidle")


def test_settings_tab_lists_and_opens_every_admin_screen(authed_page):
    page = authed_page
    record_csp(page)
    _open(page, "/")
    if not nav_shell_on(page):
        pytest.skip("SPARC_NAV_SHELL is off on this stack, so there is no settings page")
    if page.locator(SETTINGS_TAB).count() == 0:
        pytest.skip("the smoke user is not an administrator, so there is no Settings tab")

    click_and_assert_clean(page, SETTINGS_TAB, during="open Settings")
    page.wait_for_url(lambda u: urlparse(u).path == "/admin", timeout=15000)
    page.wait_for_load_state("networkidle")
    assert_no_new_a11y_violations(page, "admin_settings")

    items = page.locator(ITEM).evaluate_all(
        "els => els.map(e => ({href: e.getAttribute('href'), item: e.dataset.item}))"
    )
    assert len(items) == 10, f"the settings page lists {len(items)} screens"
    for entry in items:
        _open(page, "/admin")
        click_and_assert_clean(
            page, f"{ITEM}[data-item='{entry['item']}']", during=f"settings: {entry['item']}"
        )
        page.wait_for_url(lambda u, p=entry["href"]: urlparse(u).path == p, timeout=15000)
        page.wait_for_load_state("networkidle")
        current = page.locator(f"{MENU} [aria-current=page]")
        expect(current).to_have_attribute("data-item", entry["item"])
        expect(page.locator("[data-testid=page-header] h1")).to_have_count(1)
    assert_no_csp_violations(page, during="admin settings")


@pytest.mark.parametrize("width", [1280, 360])
def test_an_admin_screen_with_its_menu_fits(authed_page, width):
    page = authed_page
    page.set_viewport_size({"width": width, "height": 900})
    _open(page, "/admin/users")
    if page.locator(MENU).count() == 0:
        pytest.skip("no settings menu here (switch off, or not an administrator)")
    overflow = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
    assert overflow <= 0, f"{width}px: the page scrolls sideways by {overflow}px"
