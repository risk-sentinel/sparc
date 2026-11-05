"""UI smoke: the Settings lists fit beside the menu, and the overview is colour-coded (#1349).

At 1024px the users, roles, remediation timelines and audit log lists ran past
their card beside the settings menu. Each now fits at 1024px; narrower than
that a table may scroll in its own box, but the page never scrolls sideways.

The Settings overview's sections carry the home page's group colours: a bar
beside each heading, and each card's border in the same colour.

Selectors verified against app/views/admin/_settings_frame.html.erb,
app/views/admin/settings/index.html.erb and each admin index view.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

MENU = "[data-testid=admin-settings-menu]"

LISTS = [
    "/admin/users",
    "/admin/roles",
    "/admin/service_accounts",
    "/admin/idp_grants",
    "/admin/organizations",
    "/admin/authorization_boundaries",
    "/admin/remediation_timelines",
    "/admin/audit_logs",
    "/admin/reconciliation",
    "/admin/data_migrations",
]

# How far the box that scrolls the list's table is wider than it shows.
TABLE_OVER_JS = """() => {
  const t = document.querySelector('.sparc-list-card table, main table');
  if (!t) return null;
  let box = t.parentElement;
  while (box && getComputedStyle(box).overflowX === 'visible') box = box.parentElement;
  return box ? box.scrollWidth - box.clientWidth : 0;
}"""


def _open(page, path):
    record_csp(page)
    resp = page.goto(path)
    assert resp is not None and resp.ok, f"{path} returned {resp and resp.status}"
    page.wait_for_load_state("networkidle")
    if page.locator(MENU).count() == 0:
        pytest.skip("no settings menu here: the smoke user is not an administrator")


@pytest.mark.parametrize("path", LISTS)
def test_a_settings_list_fits_beside_the_menu_at_1024(authed_page, path):
    page = authed_page
    page.set_viewport_size({"width": 1024, "height": 900})
    _open(page, path)
    menu = page.locator(MENU).bounding_box()
    main = page.locator(".sparc-filtered-collection__main").bounding_box()
    beside = main["x"] > menu["x"] + menu["width"]
    assert beside, f"{path}: the menu is not beside the list at 1024px"

    over = page.evaluate(TABLE_OVER_JS)
    if over is None:
        pytest.skip(f"{path}: no table on this deployment")
    assert over <= 0, f"{path}: the table scrolls sideways by {over}px at 1024px"
    sideways = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
    assert sideways <= 0, f"{path}: the page scrolls sideways by {sideways}px"
    assert_no_csp_violations(page, during=f"{path} at 1024px")


@pytest.mark.parametrize("path", LISTS)
def test_a_settings_list_never_scrolls_the_page_on_a_phone(authed_page, path):
    page = authed_page
    page.set_viewport_size({"width": 360, "height": 800})
    _open(page, path)
    sideways = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
    assert sideways <= 0, f"{path} at 360px: the page scrolls sideways by {sideways}px"


def test_the_overview_sections_carry_the_home_colours(authed_page):
    page = authed_page
    page.set_viewport_size({"width": 1280, "height": 900})
    _open(page, "/admin")
    sections = page.locator("[data-testid=admin-settings-section]")
    assert sections.count() == 3

    seen = []
    for i in range(sections.count()):
        sec = sections.nth(i)
        bar = sec.locator("h2 .sparc-group-bar").evaluate(
            "e => getComputedStyle(e).backgroundColor"
        )
        borders = sec.locator("[data-testid=admin-settings-item]").evaluate_all(
            "els => els.map(e => getComputedStyle(e).borderTopColor)"
        )
        assert borders, f"section {i}: no cards"
        assert set(borders) == {bar}, f"section {i}: borders {set(borders)} differ from bar {bar}"
        seen.append(bar)
    # Access blue (#3498db), Organization purple (#9b59b6), Records carrot (#e67e22).
    assert seen == ["rgb(52, 152, 219)", "rgb(155, 89, 182)", "rgb(230, 126, 34)"], seen
    assert_no_csp_violations(page, during="settings overview")
