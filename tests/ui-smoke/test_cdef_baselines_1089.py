"""#1089 — a component definition is used under many baselines.

It belonged to at most one; reuse meant copying it. Its page now lists every
baseline it serves under "Used under:", with Add a baseline and Remove. What only
a browser proves: the panel renders on a real CDEF, adding one round-trips
through the form and shows, and Remove (behind a confirm) takes it away again,
all without a CSP violation.
"""

from __future__ import annotations

import pytest

from _api_setup import _client
from helpers import assert_no_csp_violations, record_csp, show_hrefs

pytestmark = pytest.mark.authenticated

PANEL = "[data-testid='cdef-baselines']"


def _cdef_with_baseline_picker(page):
    for href in show_hrefs(page, "/cdef_documents", "/cdef_documents"):
        page.goto(href)
        page.wait_for_load_state("domcontentloaded")
        if page.locator(f"{PANEL} select[name='profile_document_id']").count():
            return href
    pytest.skip("no CDEF this user may change with a baseline left to add — run the demo seed")


def test_adding_and_removing_a_baseline(authed_page):
    page = authed_page
    record_csp(page)
    href = _cdef_with_baseline_picker(page)
    slug = href.rstrip("/").rsplit("/", 1)[-1]

    picker = page.locator(f"{PANEL} select[name='profile_document_id']")
    options = picker.locator("option").evaluate_all(
        "opts => opts.filter(o => o.value).map(o => [o.value, o.textContent.trim()])"
    )
    assert options, "the picker offers no baseline"
    profile_id, profile_name = options[0]

    picker.select_option(profile_id)
    try:
        with page.expect_navigation(wait_until="load"):
            page.locator(f"{PANEL} input[type='submit'][value='Add']").click()

        linked = page.locator(f"{PANEL} [data-baseline-id='{profile_id}']")
        assert linked.count() == 1, f"{profile_name!r} is not listed after adding it"
        assert profile_name in linked.text_content()

        page.once("dialog", lambda dialog: dialog.accept())
        with page.expect_navigation(wait_until="load"):
            linked.locator("button, input[type='submit']").first.click()
        assert page.locator(f"{PANEL} [data-baseline-id='{profile_id}']").count() == 0, (
            "Remove left the baseline listed"
        )
        assert_no_csp_violations(page, during="adding and removing a CDEF baseline")
    finally:
        with _client() as c:
            c.delete(f"/api/v1/cdef_documents/{slug}/profiles/{profile_id}")
