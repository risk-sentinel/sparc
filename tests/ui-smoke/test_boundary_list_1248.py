"""UI smoke: the boundary list's Next decision column and its sort (v1.17.2, #1248).

Two boundaries are created through the API with next decision dates, the list
is opened in table view, and the sortable header is clicked both ways. Rows
offer View only. Everything created is deleted.

Selectors verified against app/views/authorization_boundaries/index.html.erb
(`a[data-sort-column='next_decision']`, `tr[data-boundary-row]`,
`[data-next-decision]`).

With SPARC_NAV_SHELL on (1.18.0-rf) the list is the Boundaries tab and this
table is the classic list at `?classic=1`; the parameter is ignored with the
switch off, so these tests always open the table they are about.
"""

from __future__ import annotations

from datetime import date, timedelta

import pytest
from playwright.sync_api import expect

from _api_setup import create_boundary, delete_doc, patch_json
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


@pytest.fixture
def dated_boundaries():
    soon = create_boundary()
    later = create_boundary()
    try:
        for record, when in (
            (soon, date.today() + timedelta(days=10)),
            (later, date.today() + timedelta(days=400)),
        ):
            r = patch_json(
                f"/api/v1/authorization_boundaries/{record['id']}",
                {"authorization_boundary": {"next_decision_date": when.isoformat()}},
            )
            assert r.status_code == 200, r.text
        yield soon, later
    finally:
        delete_doc("authorization_boundaries", soon["slug"])
        delete_doc("authorization_boundaries", later["slug"])


def _row_order(page, slugs: list[str]) -> list[str]:
    rows = page.locator("tr[data-boundary-row]").evaluate_all(
        "els => els.map(e => e.dataset.boundaryRow)"
    )
    return [slug for slug in rows if slug in slugs]


def test_next_decision_sorts_both_ways(authed_page, base_url, dated_boundaries):
    soon, later = dated_boundaries
    slugs = [soon["slug"], later["slug"]]
    page = authed_page
    record_csp(page)
    page.goto(f"{base_url}/authorization_boundaries?view=list&per_page=100&classic=1")
    page.wait_for_load_state("domcontentloaded")

    header = page.locator("a[data-sort-column='next_decision']")
    header.click()
    page.wait_for_url("**sort=next_decision**")
    expect(page.locator("th[aria-sort='ascending']")).to_have_count(1)
    assert _row_order(page, slugs) == slugs, "ascending put the later decision first"

    page.locator("a[data-sort-column='next_decision']").click()
    page.wait_for_url("**sort=-next_decision**")
    expect(page.locator("th[aria-sort='descending']")).to_have_count(1)
    assert _row_order(page, slugs) == list(reversed(slugs)), "descending kept the soonest first"

    soon_row = page.locator(f"tr[data-boundary-row='{soon['slug']}']")
    expect(soon_row.locator("[data-next-decision='due_soon']")).to_have_count(1)
    assert_no_csp_violations(page, during="sorting the boundary list by next decision")


def test_rows_offer_view_only(authed_page, base_url, dated_boundaries):
    soon, _later = dated_boundaries
    page = authed_page
    record_csp(page)
    page.goto(f"{base_url}/authorization_boundaries?view=list&per_page=100&classic=1")
    page.wait_for_load_state("domcontentloaded")

    row = page.locator(f"tr[data-boundary-row='{soon['slug']}']")
    expect(row.get_by_role("link", name="View", exact=True)).to_have_count(1)
    expect(row.get_by_role("link", name="Edit")).to_have_count(0)
    expect(row.get_by_role("button", name="Delete")).to_have_count(0)

    row.get_by_role("link", name="View", exact=True).click()
    page.wait_for_url(f"**/authorization_boundaries/{soon['slug']}")
    assert_no_csp_violations(page, during="View from the boundary list")
