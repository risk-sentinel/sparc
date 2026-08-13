"""Contextual help must not cost the operator their work (#870).

Operators open help BECAUSE they are mid-task. Same-tab navigation turns a
support aid into a context switch that discards a part-filled form, so the two
properties worth driving a real browser for are:

  - opening help does NOT replace the current page, and unsaved input survives
  - field-level help is reachable by KEYBOARD, not hover alone

The second is the one a request spec cannot prove. Markup can look correct
while the tooltip never initialises — Bootstrap is set up on `turbo:load`, so a
Turbo navigation that failed to re-instantiate it would leave a control that
renders but does nothing. Only a browser shows that.

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise.
    uv run pytest test_contextual_help.py --browser chromium
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, first_show_href, record_csp

pytestmark = pytest.mark.authenticated

BOUNDARY_FORM = "/authorization_boundaries/new"


def test_help_control_keeps_its_new_tab_fallback(authed_page):
    """The navbar ? is still target=_blank, now as the no-JS fallback.

    #880 moved the click to an in-page drawer but deliberately left the anchor
    intact: if help_drawer_controller never connects, the "?" degrades to
    #870's new tab rather than becoming a dead control. Either way it cannot
    replace the current page, which is the property #870 exists to protect.
    """
    record_csp(authed_page)
    authed_page.goto(BOUNDARY_FORM)

    help_link = authed_page.locator("a.sparc-nav-btn[href*='/help']").first
    assert help_link.count() > 0, "navbar help control not found"
    assert help_link.get_attribute("target") == "_blank"

    rel = help_link.get_attribute("rel") or ""
    assert "noopener" in rel, f"rel={rel!r} must include noopener"

    assert_no_csp_violations(authed_page, during="boundary form load")


def test_opening_help_does_not_discard_typed_input(authed_page):
    """The failure this issue exists to prevent, driven end to end.

    #870 delivered this with a new tab; #880 delivers it with a drawer. The
    guarantee is unchanged and is what this test pins — clicking the "?" must
    leave the part-filled form exactly as it was. Only the mechanism moved, so
    this now drives the drawer instead of waiting for a tab that no longer
    opens. The drawer's own behaviour is covered in test_help_drawer_880.py.
    """
    authed_page.goto(BOUNDARY_FORM)

    typed = "Half-finished boundary name"
    authed_page.fill("#authorization_boundary_name", typed)
    url_before = authed_page.url

    authed_page.click("a.sparc-nav-btn[href*='/help']")
    authed_page.wait_for_selector("#sparc-help-drawer.show", timeout=5000)

    # The point of the drawer: help arrived without going anywhere.
    assert authed_page.url == url_before, (
        f"opening help navigated to {authed_page.url} — it must not leave the screen"
    )

    authed_page.keyboard.press("Escape")
    authed_page.wait_for_selector("#sparc-help-drawer.show", state="detached", timeout=5000)

    assert authed_page.locator("#authorization_boundary_name").input_value() == typed, (
        "typed input was lost when help opened — help must not disturb the form"
    )


def test_field_help_is_reachable_by_keyboard(authed_page):
    """Hover-only help is invisible to keyboard and touch users."""
    record_csp(authed_page)
    authed_page.goto(BOUNDARY_FORM)

    help_button = authed_page.locator("button.sparc-field-help").first
    assert help_button.count() > 0, "no field-help control rendered"

    # Focus, not hover. Bootstrap's default trigger is "hover focus", so this
    # proves the tooltip is genuinely instantiated rather than merely marked up.
    help_button.focus()
    authed_page.wait_for_selector(".tooltip", state="visible", timeout=3000)

    tooltip_text = authed_page.locator(".tooltip").inner_text().strip()
    assert tooltip_text, "tooltip appeared but carried no text"

    assert_no_csp_violations(authed_page, during="field help focus")


def test_field_help_never_submits_the_form(authed_page):
    """A bare <button> inside a form defaults to type=submit."""
    authed_page.goto(BOUNDARY_FORM)

    for button in authed_page.locator("button.sparc-field-help").all():
        assert button.get_attribute("type") == "button", (
            "field help must be type=button or clicking it submits the form"
        )


def test_field_help_survives_a_turbo_navigation(authed_page):
    """Bootstrap widgets are wired on turbo:load; a Turbo visit must re-wire them."""
    authed_page.goto("/authorization_boundaries")
    authed_page.goto(BOUNDARY_FORM)  # second visit exercises the turbo:load path

    help_button = authed_page.locator("button.sparc-field-help").first
    help_button.focus()
    authed_page.wait_for_selector(".tooltip", state="visible", timeout=3000)


def test_autofocus_does_not_fire_the_help_tooltip(authed_page):
    """#869's autofocus and #870's focus-triggered tooltip share a form.

    The help control sits between the label and the input, so autofocus should
    land on the field itself. If it ever landed on the `?` instead, every visit
    to Add Member would pop a tooltip nobody asked for. Cheap to assert, and
    only observable with both changes in one tree.
    """
    # Discover a real boundary rather than guessing a slug — /authorization_boundaries/new
    # is the *new* form, and requesting .../new/memberships/new is a 404 that would
    # make this assertion vacuously pass.
    # No trailing slash — the helper appends one (it matches `prefix + "/"`).
    href = first_show_href(authed_page, "/authorization_boundaries", "/authorization_boundaries")
    if not href:
        pytest.skip("no authorization boundary exists in this deployment")

    authed_page.goto(f"{href}/memberships/new")
    authed_page.wait_for_load_state("networkidle")

    # Guard against the vacuous pass: the form must actually be here.
    assert authed_page.locator("button.sparc-field-help").count() > 0, (
        f"expected the membership form at {authed_page.url}"
    )

    focused_name = authed_page.evaluate(
        "document.activeElement?.getAttribute('name') || ''"
    )
    assert "user_name" in focused_name, (
        f"autofocus landed on {focused_name!r}, not the name field"
    )
    assert authed_page.locator(".tooltip").count() == 0, (
        "a tooltip was visible on page load — autofocus must not trigger field help"
    )
