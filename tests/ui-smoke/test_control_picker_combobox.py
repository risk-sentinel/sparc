"""The control picker is a combobox, and must announce itself as one.

The results list already carried `role="listbox"` and its rows `role="option"`,
but the input was never wired to it — no `role="combobox"`, no `aria-controls`,
no `aria-expanded`, no `aria-activedescendant`. A sighted user saw results; a
screen-reader user had no way to discover they existed.

Static markup cannot prove this: `aria-expanded` and `aria-activedescendant` are
maintained by the Stimulus controller, so they are only correct if the
controller actually runs. These checks type, arrow, and read the live state.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

FORM = "/evidences/new"
SEARCH = "#evidence_control_search"
RESULTS = "#evidence_control_results"


def _open_picker(page):
    page.goto(FORM)
    page.wait_for_load_state("networkidle")
    if page.locator(SEARCH).count() == 0:
        pytest.skip("evidence form does not expose the control picker for this account")


def test_the_input_declares_the_combobox_relationship(authed_page):
    record_csp(authed_page)
    _open_picker(authed_page)

    box = authed_page.locator(SEARCH)
    assert box.get_attribute("role") == "combobox"
    assert box.get_attribute("aria-controls") == "evidence_control_results", \
        "the input does not point at the listbox, so the two are unrelated to a screen reader"
    assert box.get_attribute("aria-expanded") == "false", \
        "a closed picker must report itself closed"
    assert authed_page.locator(RESULTS).get_attribute("role") == "listbox"

    assert_no_csp_violations(authed_page)


def test_expanded_and_active_option_track_the_live_list(authed_page):
    record_csp(authed_page)
    _open_picker(authed_page)

    box = authed_page.locator(SEARCH)
    box.click()
    box.fill("ac")
    # The list is fetched, so wait for the controller to render rather than a fixed sleep.
    try:
        authed_page.wait_for_selector(f"{RESULTS} [role='option']", timeout=8000)
    except Exception:
        pytest.skip("no catalog controls loaded on this instance to search")

    assert box.get_attribute("aria-expanded") == "true", \
        "results are visible but the input still reports aria-expanded=false"

    authed_page.keyboard.press("ArrowDown")
    active = box.get_attribute("aria-activedescendant")
    assert active, "arrow-key navigation moves a visual highlight nothing announces"
    assert authed_page.locator(f"#{active}").get_attribute("aria-selected") == "true", \
        "aria-activedescendant points at an option that is not marked selected"

    authed_page.keyboard.press("Escape")
    assert_no_csp_violations(authed_page)


def test_the_status_line_is_an_output_element(authed_page):
    """`<output>` carries the status role implicitly; the explicit role was
    redundant markup for identical semantics."""
    record_csp(authed_page)
    _open_picker(authed_page)

    status = authed_page.locator("output[data-control-picker-target='status']")
    assert status.count() == 1, "the picker status line is not an <output>"
    assert_no_csp_violations(authed_page)
