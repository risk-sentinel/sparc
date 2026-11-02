"""Keyboard-only use and reduced motion, in a real browser (1.18.0-rf #1306).

Everything here is done with the Tab, Enter and Escape keys; the mouse is never
used. At every stop focus must be on screen and drawn (an outline or a ring).
  - The first Tab reaches the skip link; Enter moves focus to the page's <main>.
  - Every stop in the header, between the skip link and the page, shows focus.
  - Open the SSP tab, switch to the Table view, open a document, open and close
    its Export menu (Escape returns focus to the button).
  - Switch the theme and back.
With the system set to reduce motion, nothing on the page animates except the
progress spinners; with it unset, something does (so the check has teeth).

Signing in by keyboard is not covered: the harness starts signed in.
Requires SPARC_SMOKE_SA_TOKEN.
"""

from __future__ import annotations

import re

import pytest
from playwright.sync_api import expect

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

# What the focused element is, and whether a sighted keyboard user can see it.
_FOCUS_JS = """() => {
  const e = document.activeElement;
  if (!e || e === document.body) return null;
  const r = e.getBoundingClientRect();
  const cs = getComputedStyle(e);
  const outline = cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) > 0;
  const ring = !!cs.boxShadow && cs.boxShadow !== 'none';
  return {
    testid: e.dataset.testid || null,
    tag: e.tagName.toLowerCase(),
    id: e.id || null,
    name: (e.getAttribute('aria-label') || e.innerText || e.title || '').trim().slice(0, 40),
    on_screen: r.width > 0 && r.height > 0 && r.bottom > 0 && r.right > 0
               && r.top < innerHeight && r.left < innerWidth,
    drawn: outline || ring,
    in_main: !!e.closest('main'),
  };
}"""

# Elements still moving: any running transition or animation longer than 1ms,
# progress spinners aside.
_MOVING_JS = """() => {
  const one = s => parseFloat(s) * (s.trim().endsWith('ms') ? 1 : 1000);
  const ms = v => Math.max(...v.split(',').map(one));
  const spin = '.sparc-spinner, .spinner-border, .spinner-grow';
  const out = [];
  for (const e of document.querySelectorAll('*')) {
    if (e.matches(spin)) continue;
    const cs = getComputedStyle(e);
    const anim = cs.animationName !== 'none' && ms(cs.animationDuration) > 1;
    const trans = ms(cs.transitionDuration) > 1;
    const cls = typeof e.className === 'string' ? e.className.trim().replace(/\\s+/g, '.') : '';
    if (anim || trans) out.push(e.tagName.toLowerCase() + (cls ? '.' + cls : ''));
  }
  return out;
}"""

MAX_STOPS = 150


def _focused(page):
    return page.evaluate(_FOCUS_JS)


def _describe(stop):
    return f"{stop['tag']}#{stop['id'] or ''}[{stop['testid'] or ''}] {stop['name']!r}"


def _tab_to(page, selector):
    """Press Tab until focus is on an element matching `selector`."""
    for _ in range(MAX_STOPS):
        page.keyboard.press("Tab")
        if page.evaluate("s => !!document.activeElement?.matches(s)", selector):
            stop = _focused(page)
            assert stop["on_screen"], f"{_describe(stop)} has focus but is off screen"
            assert stop["drawn"], f"{_describe(stop)} has focus but shows no focus ring"
            return
    raise AssertionError(f"{MAX_STOPS} presses of Tab never reached {selector}")


def _home(page):
    response = page.goto("/")
    assert response is not None and response.ok, f"/ returned {response and response.status}"
    page.wait_for_load_state("networkidle")


def test_the_first_tab_is_the_skip_link_and_enter_moves_to_the_page(authed_page):
    page = authed_page
    _home(page)

    page.keyboard.press("Tab")
    stop = _focused(page)
    assert stop and stop["testid"] == "skip-link", f"the first Tab reached {stop}"
    assert stop["on_screen"] and stop["drawn"], f"the skip link is not shown on focus: {stop}"
    expect(page.get_by_test_id("skip-link")).to_have_text("Jump to page content")

    page.keyboard.press("Enter")
    # Focus moves once the browser has handled the jump, a moment after Enter.
    expect(page.locator("#main-content")).to_be_focused()
    page.keyboard.press("Tab")
    assert _focused(page)["in_main"], f"after the skip link, Tab reached {_focused(page)}"


def test_every_stop_before_the_page_shows_where_focus_is(authed_page):
    page = authed_page
    _home(page)

    stops = []
    for _ in range(MAX_STOPS):
        page.keyboard.press("Tab")
        stop = _focused(page)
        if stop is None or stop["in_main"]:
            break
        stops.append(stop)
    else:
        raise AssertionError(f"{MAX_STOPS} presses of Tab never reached the page")

    assert len(stops) >= 5, f"only {len(stops)} stops before the page: {stops}"
    hidden = [_describe(s) for s in stops if not (s["on_screen"] and s["drawn"])]
    assert not hidden, "focus is not visible on:\n  " + "\n  ".join(hidden)


def test_a_list_and_a_document_by_keyboard(authed_page):
    page = authed_page
    record_csp(page)
    _home(page)

    _tab_to(page, "[data-testid=org-tabs] [data-testid=shell-tab][data-tab=ssp]")
    page.keyboard.press("Enter")
    page.wait_for_url(re.compile(r"/ssp_documents(\?|$)"))
    page.wait_for_load_state("networkidle")

    _tab_to(page, ".sparc-view-toggle__option[href*='view=table']")
    page.keyboard.press("Enter")
    page.wait_for_url(re.compile(r"view=table"))
    page.wait_for_load_state("networkidle")

    if page.locator("main table a[href^='/ssp_documents/']").count() == 0:
        pytest.skip("no SSP to open on this instance")
    _tab_to(page, "main table a[href^='/ssp_documents/']")
    page.keyboard.press("Enter")
    # A document's address is its slug, e.g. /ssp_documents/acme-hr-portal-ssp-...
    page.wait_for_url(re.compile(r"/ssp_documents/(?!new\b)[^/?#]+$"))
    page.wait_for_load_state("networkidle")

    toggle = "[data-controller=oscal-export] > .dropdown-toggle"
    _tab_to(page, toggle)
    page.keyboard.press("Enter")
    menu = page.locator("[data-controller=oscal-export] .dropdown-menu")
    expect(menu).to_be_visible()
    page.keyboard.press("Escape")
    expect(menu).to_be_hidden()
    expect(page.locator(toggle)).to_be_focused()
    assert_no_csp_violations(page, during="a list and a document by keyboard")


def test_the_theme_switches_by_keyboard(authed_page):
    page = authed_page
    _home(page)
    theme = "document.documentElement.getAttribute('data-bs-theme')"
    before = page.evaluate(theme)

    _tab_to(page, ".sparc-nav-theme-btn")
    page.keyboard.press("Enter")
    assert page.evaluate(theme) != before
    page.keyboard.press("Enter")
    assert page.evaluate(theme) == before


@pytest.mark.parametrize("path", ["/", "/ssp_documents"])
def test_nothing_moves_when_the_system_asks_for_less_motion(authed_page, path):
    page = authed_page

    page.emulate_media(reduced_motion="no-preference")
    page.goto(path)
    page.wait_for_load_state("networkidle")
    assert page.evaluate(_MOVING_JS), f"nothing on {path} animates even with motion allowed"

    page.emulate_media(reduced_motion="reduce")
    page.goto(path)
    page.wait_for_load_state("networkidle")
    moving = page.evaluate(_MOVING_JS)
    page.emulate_media(reduced_motion="no-preference")
    assert not moving, f"{len(moving)} element(s) still animate on {path}: {moving[:10]}"
