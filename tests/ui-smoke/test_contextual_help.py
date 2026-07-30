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

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

BOUNDARY_FORM = "/authorization_boundaries/new"


def test_help_control_opens_in_a_new_tab(authed_page):
    """The navbar ? is target=_blank — the whole point of #870."""
    record_csp(authed_page)
    authed_page.goto(BOUNDARY_FORM)

    help_link = authed_page.locator("a.sparc-nav-btn[href*='/help']").first
    assert help_link.count() > 0, "navbar help control not found"
    assert help_link.get_attribute("target") == "_blank"

    rel = help_link.get_attribute("rel") or ""
    assert "noopener" in rel, f"rel={rel!r} must include noopener"

    assert_no_csp_violations(authed_page, during="boundary form load")


def test_opening_help_does_not_discard_typed_input(authed_page):
    """The failure this issue exists to prevent, driven end to end."""
    authed_page.goto(BOUNDARY_FORM)

    typed = "Half-finished boundary name"
    authed_page.fill("#authorization_boundary_name", typed)

    # Real click. If the link were same-tab, Turbo would replace the page here
    # and the field would come back empty.
    with authed_page.context.expect_page() as new_tab_info:
        authed_page.click("a.sparc-nav-btn[href*='/help']")
    new_tab = new_tab_info.value
    new_tab.wait_for_load_state()

    assert "/help" in new_tab.url, f"help tab landed on {new_tab.url}"
    new_tab.close()

    assert authed_page.locator("#authorization_boundary_name").input_value() == typed, (
        "typed input was lost when help opened — help must not replace the page"
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
