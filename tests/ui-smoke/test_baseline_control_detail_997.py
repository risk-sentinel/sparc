"""#997 — a tailoring decision the user can actually see.

A parameter update could succeed and leave no trace on any screen: there was no
web UI for baseline parameters at all, so the only way to observe one was to
call the API back. And nothing on the Profile or SSP screens said what was
legitimately part of the profile — the Profile screen listed control
identifiers grouped by family with priority counts and stopped.

rspec covers what the screens render (spec/requests/baseline_control_visibility_997_spec.rb).
What only a browser can prove is the part that is an INTERACTION: the panel is
behind a disclosure, the editor is a form inside it, and the round trip
"change a value, come back, see the new value" is the defect this issue opens
with. A CSP regression or a partial that renders but cannot submit would look
exactly like the original bug — nothing visibly wrong, and nothing applied.
"""

from __future__ import annotations

import pytest

from _api_setup import create_tailorable_profile, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

DISCLOSURE = "summary:has-text('What this baseline requires')"
SAVE = "input[value='Save parameters'], button:has-text('Save parameters')"


@pytest.fixture
def profile():
    p = create_tailorable_profile()
    try:
        yield p
    finally:
        delete_doc("profile_documents", p["slug"])


def _ensure_open(page, summary_selector: str) -> None:
    """Open a <details> and CONFIRM it opened — never toggle it blindly.

    Two failures made the original one-line click unreliable, both measured
    against the running app rather than guessed at:

      * it clicked unconditionally, so after a save — where the family group
        comes back already open — the click CLOSED it and every later
        assertion read an empty panel;
      * the panel it waited on was not necessarily the panel the click drove.
        `details.card-details` also matches the OSCAL Metadata and Back Matter
        disclosures, so a wait keyed on the selector could be satisfied by an
        unrelated open section while the control's panel stayed shut, and the
        assertion then failed for a reason that had nothing to do with what it
        was testing.

    So: derive the <details> FROM the summary being clicked, and poll that same
    element until it actually reports open.
    """
    summary = page.locator(summary_selector).first
    summary.wait_for(state="attached", timeout=5000)
    panel = summary.locator("xpath=..")          # the <details> this summary drives
    for _ in range(20):                          # ~2s, re-reading the SAME element
        if panel.evaluate("e => e.open"):
            return
        summary.click()
        page.wait_for_timeout(100)
    raise AssertionError(f"{summary_selector} never opened its panel")


def _open_first_control(page, profile) -> None:
    page.goto(f"/profile_documents/{profile['slug']}")
    page.wait_for_load_state("networkidle")
    _ensure_open(page, "details.sparc-family-group > summary")
    _ensure_open(page, DISCLOSURE)


class TestTheBaselineIsVisible:
    def test_the_panel_shows_the_control_language(self, authed_page, profile):
        page = authed_page
        record_csp(page)
        _open_first_control(page, profile)

        panel = page.locator(".sparc-baseline-detail").first
        assert panel.is_visible(), "the baseline detail panel did not open"
        # Case-insensitive: the label is styled `text-transform: uppercase`, so
        # inner_text() returns "CONTROL STATEMENT". Asserting the CSS-rendered
        # casing would tie this test to a stylesheet; asserting the label is
        # present is what the test actually means.
        assert "control statement" in panel.inner_text().lower(), (
            "the panel opened without the control language, which is what it exists to show"
        )
        assert_no_csp_violations(page, during="opening the baseline detail panel")

    def test_no_raw_insert_markup_reaches_the_screen(self, authed_page, profile):
        """Showing `{{ insert: param, ac-1_prm_1 }}` is worse than showing nothing.

        Checked against the whole rendered page rather than one element: the
        markup travels through statements, parameter labels and selection
        choices, and #942 fixed it in the exporters while the views still had it.
        """
        page = authed_page
        _open_first_control(page, profile)

        body = page.locator("body").inner_text()
        assert "insert: param" not in body, (
            "raw OSCAL insert markup reached the screen"
        )
        assert "{{" not in body, "unsubstituted template markup reached the screen"


class TestTailoringRoundTrip:
    def test_a_saved_parameter_value_is_visible_afterwards(self, authed_page, profile):
        """The defect the issue opens with, end to end in the browser."""
        page = authed_page
        record_csp(page)
        _open_first_control(page, profile)

        text_input = page.locator(".sparc-param-form input[type='text']").first
        if text_input.count() == 0:
            pytest.skip(
                "no free-text ODP on the first control of this catalog — "
                "the selection-only path is covered by the request spec"
            )

        value = "ui-smoke tailored value"
        text_input.fill(value)
        # Wait for the SAVE ITSELF, not for the network to go quiet. The
        # original `click(); wait_for_load_state("networkidle")` returns as soon
        # as nothing is in flight, which can be before the POST has been handled
        # — the next navigation then renders pre-save state while the write
        # lands behind it. Confirmed against the running app: the value was in
        # the database and in the raw HTML of a later request, and absent only
        # from the page this test had already read. A race in the test, not a
        # defect in the screen.
        with page.expect_navigation(wait_until="load"):
            page.locator(SAVE).first.click()
        page.wait_for_load_state("networkidle")

        # Back on the profile screen: the value must be readable without
        # calling the API to find out what happened.
        _open_first_control(page, profile)
        # Look in BOTH places a value can legitimately be on this screen.
        # `inner_text()` alone was the original assertion and it cannot pass
        # here: the Profile screen is editable, so the saved value comes back
        # in the parameter form field, and inner_text() does not include input
        # values. Verified against the running app — the value was saved and on
        # screen the whole time, in an <input value="...">.
        body_text = page.locator("body").inner_text()
        input_values = page.eval_on_selector_all(
            "input, textarea", "els => els.map(e => e.value).filter(Boolean)"
        )
        assert value in body_text or any(value in v for v in input_values), (
            "the tailored value was accepted and is not visible on the screen — "
            "which is the whole of #997"
        )
        assert_no_csp_violations(page, during="saving a baseline parameter")
