"""The in-page help drawer (#880).

#870 established the rule these tests protect: opening help must never cost the
operator their work. The drawer keeps that rule while dropping the tab switch,
and everything interesting about it is only observable in a real browser.

A request spec can prove the drawer response is a bare Turbo Frame and the
markup carries the right attributes (spec/requests/help_drawer_spec.rb). It
cannot prove any of this:

  - the panel actually opens, rather than being marked up and inert
  - focus moves INTO it and returns to the "?" on close
  - Tab does not walk out of the dialog into the form underneath
  - Esc closes it
  - a part-filled form is untouched by the whole round trip
  - no CSP violation fires on open OR on close (interaction-time breakage)
  - it does not strand itself across a Turbo visit

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise.
    uv run pytest test_help_drawer_880.py --browser chromium
"""

from __future__ import annotations

import pytest

from a11y import assert_no_new_a11y_violations
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

BOUNDARY_FORM = "/authorization_boundaries/new"
NAME_FIELD = "#authorization_boundary_name"
TRIGGER = "a.sparc-nav-btn[href*='/help']"
DRAWER = "#sparc-help-drawer"


def open_drawer(page):
    """Click the navbar ? and wait for the panel to finish sliding in."""
    page.click(TRIGGER)
    page.wait_for_selector(f"{DRAWER}.show", timeout=5000)
    # The guide arrives in a Turbo Frame, separately from the panel animation.
    page.wait_for_selector(f"{DRAWER} .sparc-guide-content", timeout=5000)


def test_drawer_opens_over_the_screen_without_navigating(authed_page):
    """The whole point: help arrives without leaving the page."""
    record_csp(authed_page)
    authed_page.goto(BOUNDARY_FORM)
    url_before = authed_page.url

    open_drawer(authed_page)

    assert authed_page.url == url_before, (
        f"opening help navigated to {authed_page.url} — it must not leave the screen"
    )
    assert authed_page.locator(f"{DRAWER} .sparc-guide-content").inner_text().strip(), (
        "the drawer opened but loaded no guide content"
    )
    assert_no_csp_violations(authed_page, during="help drawer open")


def test_unsaved_input_survives_open_and_close(authed_page):
    """The #870 property, re-proven against the new mechanism.

    A drawer that quietly re-rendered the page would pass every other test here
    and still destroy the operator's work.
    """
    authed_page.goto(BOUNDARY_FORM)

    typed = "Half-finished boundary name"
    authed_page.fill(NAME_FIELD, typed)

    open_drawer(authed_page)
    authed_page.keyboard.press("Escape")
    authed_page.wait_for_selector(f"{DRAWER}.show", state="detached", timeout=5000)

    assert authed_page.locator(NAME_FIELD).input_value() == typed, (
        "typed input was lost across the drawer — help must never disturb the form"
    )


def test_escape_closes_the_drawer(authed_page):
    record_csp(authed_page)
    authed_page.goto(BOUNDARY_FORM)
    open_drawer(authed_page)

    authed_page.keyboard.press("Escape")
    authed_page.wait_for_selector(f"{DRAWER}.show", state="detached", timeout=5000)

    assert not authed_page.locator(f"{DRAWER}.show").count()
    assert_no_csp_violations(authed_page, during="help drawer close")


def test_focus_moves_into_the_drawer_and_returns_to_the_trigger(authed_page):
    """Bootstrap moves focus in; returning it to the trigger is ours (#880).

    Without the explicit restore, closing the drawer drops a keyboard user at
    the top of the document, several tab stops from where they were.
    """
    authed_page.goto(BOUNDARY_FORM)
    open_drawer(authed_page)

    inside = authed_page.evaluate(
        "document.activeElement?.closest('#sparc-help-drawer') !== null"
    )
    assert inside, "focus stayed outside the drawer — a keyboard user cannot reach it"

    authed_page.keyboard.press("Escape")
    authed_page.wait_for_selector(f"{DRAWER}.show", state="detached", timeout=5000)

    returned = authed_page.evaluate(
        "document.activeElement?.matches(\"a.sparc-nav-btn[href*='/help']\") === true"
    )
    assert returned, "focus did not return to the ? that opened the drawer"


def test_focus_is_trapped_while_the_drawer_is_open(authed_page):
    """Tab must not walk out of the dialog and into the form underneath.

    This is what `scroll: false` buys — Bootstrap only arms its focus trap when
    the body is locked, so a config change to `scroll: true` breaks exactly
    this and nothing else.
    """
    authed_page.goto(BOUNDARY_FORM)
    open_drawer(authed_page)

    # Enough hops to walk off the end of the panel's focusables and wrap.
    for _ in range(12):
        authed_page.keyboard.press("Tab")
        escaped = authed_page.evaluate(
            "document.activeElement?.closest('#sparc-help-drawer') === null"
            " && document.activeElement !== document.body"
        )
        assert not escaped, (
            "Tab escaped the open drawer — focus must stay inside a modal dialog"
        )


def test_drawer_is_announced_as_a_labelled_dialog(authed_page):
    """Screen readers must hear a layer, not the form behind it."""
    authed_page.goto(BOUNDARY_FORM)
    open_drawer(authed_page)

    role = authed_page.get_attribute(DRAWER, "role")
    modal = authed_page.get_attribute(DRAWER, "aria-modal")
    labelledby = authed_page.get_attribute(DRAWER, "aria-labelledby")

    assert role == "dialog", f"role={role!r} — the drawer must be a dialog"
    assert modal == "true", f"aria-modal={modal!r} — content behind must be inert"

    label = authed_page.locator(f"#{labelledby}").inner_text().strip()
    assert label, "the dialog has no accessible name"


def test_full_guide_stays_one_click_away_in_a_new_tab(authed_page):
    """#880 complements the new tab, it does not replace it."""
    authed_page.goto(BOUNDARY_FORM)
    open_drawer(authed_page)

    full = authed_page.locator(f"{DRAWER} [data-help-drawer-target='fullGuide']")
    assert full.count() > 0, "no full-guide escape hatch inside the drawer"
    assert full.get_attribute("target") == "_blank"

    # It must point at the guide being READ, not a generic index — otherwise
    # "open the whole thing" lands somewhere else.
    href = full.get_attribute("href") or ""
    assert href.startswith("/help/"), f"full-guide link points at {href!r}"

    with authed_page.context.expect_page() as new_tab_info:
        full.click()
    new_tab = new_tab_info.value
    new_tab.wait_for_load_state()
    assert "/help/" in new_tab.url
    new_tab.close()


def test_drawer_does_not_strand_across_a_turbo_visit(authed_page):
    """A plain Turbo visit made with the drawer open lands on a clean screen.

    Honest caveat: on a plain visit Turbo replaces <body>, and the panel, the
    backdrop and the body's inline scroll-lock all go with it — so this passes
    even with every teardown hook removed. It pins the user-visible property,
    not the mechanism that delivers it. The test that actually discriminates is
    the cached-snapshot one below.
    """
    record_csp(authed_page)
    authed_page.goto(BOUNDARY_FORM)
    open_drawer(authed_page)

    # A real Turbo Drive visit, driven directly rather than by clicking a nav
    # link: while the drawer is open its backdrop intercepts pointer events,
    # which is correct modal behaviour. The navigation this guards against is
    # the one that arrives WITHOUT a click — a Turbo redirect or stream.
    authed_page.evaluate("window.Turbo.visit('/authorization_boundaries')")
    authed_page.wait_for_url("**/authorization_boundaries", timeout=10000)
    authed_page.wait_for_load_state("networkidle")

    assert not authed_page.locator(".offcanvas-backdrop").count(), (
        "a backdrop was stranded on the next screen"
    )
    assert not authed_page.locator(f"{DRAWER}.show").count(), (
        "the drawer survived the navigation"
    )
    # Bootstrap locks body scroll while a modal layer is open; if teardown was
    # skipped the new page is unscrollable with nothing visible to blame.
    overflow = authed_page.evaluate("getComputedStyle(document.body).overflow")
    assert overflow != "hidden", "body scroll was left locked after navigating"

    assert_no_csp_violations(authed_page, during="turbo visit with drawer open")


def test_drawer_does_not_strand_into_a_cached_snapshot(authed_page):
    """Coming Back to a cached page must not restore a frozen-looking screen.

    SPARC sets `turbo-cache-control: no-cache` app-wide, so Turbo never
    snapshots a page and the drawer cannot strand on a normal visit at all —
    which is why the plain-visit test above passes even with every teardown
    hook removed. This one opts the page into the cache to get closer to the
    real failure.

    READ THIS BEFORE TRUSTING IT. It is an under-powered guard, not proof.
    While developing the teardown I did observe the failure — Turbo snapshots
    the body synchronously while Bootstrap's animated hide() is still running,
    and the restored page came back with the panel shown over a body stuck at
    `overflow: hidden`. But it is a RACE, and it could not be reproduced on
    demand: with the synchronous teardown deliberately removed, this test
    still passed on four consecutive clean runs. So a green result here does
    not mean the teardown works, and this test failing IS meaningful while it
    passing is not. The teardown is kept because making the closed state true
    immediately is correct by construction, not because this proves it.
    """
    authed_page.goto(BOUNDARY_FORM)

    # Opt this page into Turbo's cache, which the layout disables globally.
    assert authed_page.locator("meta[name='turbo-cache-control']").count() == 1, (
        "expected the app-wide no-cache meta — if it is gone, this test's setup "
        "no longer matches the app and the plain-visit test is the live one"
    )
    authed_page.evaluate(
        "document.querySelector(\"meta[name='turbo-cache-control']\")?.remove()"
    )

    open_drawer(authed_page)
    authed_page.evaluate("window.Turbo.visit('/authorization_boundaries')")
    authed_page.wait_for_url("**/authorization_boundaries", timeout=10000)

    authed_page.go_back()
    authed_page.wait_for_timeout(1500)

    assert not authed_page.locator(f"{DRAWER}.show").count(), (
        "the restored page came back with the drawer still open"
    )
    assert not authed_page.locator(".offcanvas-backdrop").count(), (
        "the restored page came back with a stranded backdrop"
    )
    overflow = authed_page.evaluate("getComputedStyle(document.body).overflow")
    assert overflow != "hidden", (
        "the restored page is scroll-locked — it looks frozen with nothing to click"
    )


def test_open_drawer_passes_the_a11y_bar(authed_page):
    """Audit the drawer OPEN, which no page baseline ever sees.

    test_accessibility.py sweeps pages as they load, and on every one of them
    this panel is hidden — axe skips hidden content, so the whole drawer would
    be invisible to Layer 3 despite being the most a11y-sensitive thing in
    #880. Opening it first is the only way it gets audited at all.
    """
    authed_page.goto(BOUNDARY_FORM)
    open_drawer(authed_page)
    authed_page.wait_for_load_state("networkidle")

    assert_no_new_a11y_violations(authed_page, "help_drawer_open")


def test_drawer_reopens_after_a_turbo_visit(authed_page):
    """Teardown must not leave the control dead on the next screen.

    Disposing the Bootstrap instance without re-creating it on the new page is
    an easy way to fix the stranding bug and break the feature.
    """
    authed_page.goto("/authorization_boundaries")
    authed_page.goto(BOUNDARY_FORM)  # second visit exercises the turbo:load path

    open_drawer(authed_page)
    assert authed_page.locator(f"{DRAWER}.show").count() == 1
