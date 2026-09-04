"""UI smoke: the ATO wizard's step panels still toggle (#1047 slice 3).

The wizard had NO Playwright coverage at all before this — only the visual
harness reached it, and a screenshot proves the initial render, not that
anything works. That mattered for slice 3, which moved the panels' `display:
none` out of an inline `style=` and into `.sparc-wizard-step-panel`.

The toggle survives that move, and this asserts it rather than assuming it:
`ato_wizard_controller` sets `element.style.display` directly, and an inline
style beats a class, so the class supplies the initial hidden state and the
controller overrides it. That is also why the toggle survives the eventual
removal of `style-src 'unsafe-inline'` — CSP governs `style=` attributes in
MARKUP and `<style>` blocks, not CSSOM assignment.

The click check is the point. #650 replaced `onclick="toggleMode(...)"` and a
nonce'd <script> here precisely because strict CSP silently blocked them, and a
render-time assertion would not have noticed.

Selectors verified against app/views/authorization_boundaries/ato_wizard.html.erb.
"""

from __future__ import annotations

import pytest
from playwright.sync_api import expect

import helpers
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


def _open_step_containing(page, selector):
    """Reveal the <details> step holding `selector`.

    Only the first two steps render `open`; the SSP step is collapsed, so the
    radio resolves in the DOM but is "not visible" and the click times out.

    `.open = true` rather than clicking the <summary>: the summary is itself a
    control, and clicking it to reach a different control is the kind of setup
    that quietly starts testing the wrong thing. Same reason the visual harness
    expands disclosures this way.
    """
    page.eval_on_selector(
        selector,
        "el => { let n = el; while (n) { if (n.tagName === 'DETAILS') n.open = true;"
        "        n = n.parentElement; } }",
    )
    page.wait_for_timeout(200)


def _wizard_url(page, base_url):
    href = helpers.first_show_href(
        page, "/authorization_boundaries", "/authorization_boundaries"
    )
    if not href:
        pytest.skip("no authorization boundary on this deployment — nothing to exercise")
    return f"{base_url}{href}/ato_wizard"


def test_step_panel_starts_hidden_and_opens_on_select(authed_page, base_url):
    page = authed_page
    record_csp(page)
    page.goto(_wizard_url(page, base_url))
    page.wait_for_load_state("domcontentloaded")

    _open_step_containing(page, "#ssp_create_new_panel")

    panel = page.locator("#ssp_create_new_panel")
    expect(panel).to_be_attached()
    # Hidden by the CLASS now, not by an inline style — the state slice 3 moved.
    expect(panel).to_be_hidden()

    helpers.click_and_assert_clean(
        page, "input[name='ssp_radio'][value='create_new']",
        during="selecting the SSP create-new mode",
    )
    expect(panel).to_be_visible()

    # ...and the hidden field the form actually submits was written.
    expect(page.locator("#ssp_mode")).to_have_value("create_new")


def test_selecting_another_mode_hides_the_first_panel(authed_page, base_url):
    page = authed_page
    record_csp(page)
    page.goto(_wizard_url(page, base_url))
    page.wait_for_load_state("domcontentloaded")

    _open_step_containing(page, "#ssp_create_new_panel")

    create_panel = page.locator("#ssp_create_new_panel")
    select_panel = page.locator("#ssp_select_existing_panel")

    page.locator("input[name='ssp_radio'][value='create_new']").click()
    expect(create_panel).to_be_visible()

    # The other direction: choosing a different mode must CLOSE the first panel,
    # not merely open the second. Leaving both open is the failure a
    # "does it open?" test would pass straight through.
    helpers.click_and_assert_clean(
        page, "input[name='ssp_radio'][value='select_existing']",
        during="switching the SSP mode",
    )
    expect(select_panel).to_be_visible()
    expect(create_panel).to_be_hidden()

    assert_no_csp_violations(page, during="the ATO wizard after switching modes")
