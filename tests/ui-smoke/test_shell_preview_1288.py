"""Shell building blocks and icons in a real browser (1.18.0-rf #1288 / #1289).

Two parts:

* The theme toggle now carries a sun and a moon icon and CSS shows the one for
  the current theme. It always runs: the toggle is in every header.
* /shell_preview shows every building block and icon. It exists only with
  SPARC_NAV_SHELL on, so it is posture-gated ("nav_shell") and reported as
  UNPROVEN when the stack has the switch off, never as a quiet pass. On it:
  every icon actually draws (its <use> resolves to a sprite symbol with a
  size), there are zero CSP violations, and axe finds no WCAG 2.1 AA
  violation in either theme. It is a new page, so it has no baseline to hide
  behind.

Requires SPARC_SMOKE_SA_TOKEN.
"""

from __future__ import annotations

import pytest
from axe_playwright_python.sync_playwright import Axe

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

WCAG = {"runOnly": {"type": "tag", "values": ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]}}
TOGGLE = ".sparc-nav-theme-btn"

VISIBLE_THEME_ICON_JS = """
() => [...document.querySelectorAll('.sparc-nav-theme-btn svg.sparc-icon')]
  .filter((s) => getComputedStyle(s).display !== 'none')
  .map((s) => s.querySelector('use').getAttribute('href'))
"""


SETTLED_JS = "() => document.getAnimations().every((a) => a.playState !== 'running')"


def _theme(page) -> str:
    return page.evaluate("document.documentElement.dataset.bsTheme")


def test_theme_toggle_shows_one_icon_and_swaps_it(authed_page):
    record_csp(authed_page)
    authed_page.goto("/")
    authed_page.wait_for_load_state("networkidle")

    before_theme = _theme(authed_page)
    before = authed_page.evaluate(VISIBLE_THEME_ICON_JS)
    expected = "#i-sun" if before_theme == "dark" else "#i-moon"
    assert before == [expected], f"{before_theme} theme shows {before}, expected [{expected}]"

    authed_page.locator(TOGGLE).click()
    assert_no_csp_violations(authed_page, during="theme toggle")
    after_theme = _theme(authed_page)
    after = authed_page.evaluate(VISIBLE_THEME_ICON_JS)

    assert after_theme != before_theme, "the toggle did not change the theme"
    assert after == ["#i-moon" if after_theme == "light" else "#i-sun"], after
    title = authed_page.locator(TOGGLE).get_attribute("title")
    assert title == f"Switch to {'light' if after_theme == 'dark' else 'dark'} mode", title

    authed_page.locator(TOGGLE).click()  # leave the stored theme as it was
    assert _theme(authed_page) == before_theme


@pytest.mark.posture("nav_shell")
def test_shell_preview_draws_every_icon_cleanly_in_both_themes(authed_page):
    record_csp(authed_page)
    response = authed_page.goto("/shell_preview")
    if response is not None and response.status == 404:
        pytest.skip("SPARC_NAV_SHELL is off on this stack, so /shell_preview does not exist")
    assert response is not None and response.ok, (
        f"/shell_preview returned {response and response.status}"
    )
    authed_page.wait_for_load_state("networkidle")

    # Every icon draws: its <use> points at a symbol in the sprite, and the
    # drawn shape has a size. A missing symbol renders an empty box.
    undrawn = authed_page.evaluate(
        """() => [...document.querySelectorAll('[data-testid=shell-preview-icons] svg use')]
             .filter((u) => {
               const id = u.getAttribute('href').slice(1);
               const box = u.getBBox();
               return !document.getElementById(id) || box.width === 0 || box.height === 0;
             })
             .map((u) => u.getAttribute('href'))"""
    )
    count = authed_page.locator("[data-testid=shell-preview-icons] svg").count()
    assert count >= 40, f"only {count} icons on the preview"
    assert undrawn == [], f"icons that do not draw: {undrawn}"
    assert_no_csp_violations(authed_page, during="shell preview render")

    for _ in range(2):  # the current theme, then the other one
        # The theme fades over 0.2-0.3s. Axe run mid-fade measures colours that
        # belong to neither theme (greys like #bdbec0), so wait until every
        # transition has finished.
        authed_page.wait_for_function(SETTLED_JS)
        theme = _theme(authed_page)
        violations = Axe().run(authed_page, options=WCAG).response.get("violations", [])
        found = [
            f"{v['id']}: {' '.join(str(t) for t in n.get('target', []))}"
            for v in violations
            for n in v.get("nodes", [])
        ]
        assert found == [], f"axe, {theme} theme, /shell_preview:\n" + "\n".join(found)
        authed_page.locator(TOGGLE).click()
        assert_no_csp_violations(authed_page, during="theme toggle on the preview")
