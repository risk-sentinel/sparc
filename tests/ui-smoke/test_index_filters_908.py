"""Index-screen filter controls (#908).

Catalogs, baselines, POA&Ms and evidence gained dropdown/date filters above
their lists, rendered by app/views/shared/_collection_filter_form from
CollectionBrowseQuery#filter_fields.

The request specs cover which fields render and what they narrow. What only a
real browser proves is the part that made this worth a shared partial:

  - the filter form is a GET form, so applying a filter must PRESERVE the page
    size, the search term and the view mode. The screen this replaced dropped
    `per_page`, silently resetting the user's page size on every filter.
  - the applied filter shows a removable chip, and removing it restores the
    unfiltered list without losing the other state
  - ZERO CSP violations during the interaction. These are plain form controls
    with no JavaScript by design; a violation here would mean someone reached
    for an inline handler, which the app's CSP forbids outright.

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise. Run both browsers:
    uv run pytest test_index_filters_908.py --browser chromium --browser firefox
"""

from __future__ import annotations

import pytest

from helpers import csp_violations, record_csp

pytestmark = pytest.mark.authenticated

# Screens that gained filters, with the facet each is most likely to be able to
# offer against seeded demo data. The test SKIPS a screen whose corpus does not
# distinguish that facet rather than asserting the dropdown exists — the
# cardinality-1 rule deliberately hides a filter with one value, so demanding it
# be present would make this test a hostage to the seed data.
FILTERED_PAGES = [
    ("control_catalogs", "/control_catalogs"),
    ("profile", "/profile_documents"),
    ("poam", "/poam_documents"),
    ("evidence", "/evidences"),
]


def _first_filter_select(page):
    """The first real filter dropdown on the page, or None.

    Scoped to the filter form so it cannot accidentally grab a select belonging
    to some other control on the screen.
    """
    selects = page.locator("form select.form-select-sm")
    return selects.first if selects.count() > 0 else None


@pytest.mark.parametrize(
    "name,path", FILTERED_PAGES, ids=[p[0] for p in FILTERED_PAGES]
)
def test_filter_preserves_per_page_and_search(authed_page, name, path):
    record_csp(authed_page)

    # Arrive with a non-default page size AND a view mode, which is the state
    # the old hand-written form destroyed.
    resp = authed_page.goto(f"{path}?per_page=50&view=list")
    assert resp is not None and resp.status < 400, (
        f"{name}: {path} returned {resp.status if resp else 'none'}"
    )
    authed_page.wait_for_load_state("networkidle")

    select = _first_filter_select(authed_page)
    if select is None:
        pytest.skip(f"{name}: no filter dropdown offered for this corpus")

    # Every facet's value set has >= 2 entries or it would not be drawn, so
    # there is always a real option after the blank "All".
    options = select.locator("option")
    assert options.count() >= 2, f"{name}: filter dropdown drawn with no choices"
    value = options.nth(1).get_attribute("value")

    select.select_option(value)
    authed_page.locator("input[type='submit'][value='Filter']").first.click()
    authed_page.wait_for_load_state("networkidle")

    url = authed_page.url
    assert "per_page=50" in url, (
        f"{name}: filtering dropped per_page — the user's page size was reset. URL: {url}"
    )
    assert "view=list" in url, (
        f"{name}: filtering dropped the view mode. URL: {url}"
    )
    assert "page=" not in url.replace("per_page=", ""), (
        f"{name}: filtering carried the old page number, which means nothing "
        f"against a different result set. URL: {url}"
    )

    assert not csp_violations(authed_page), (
        f"{name}: CSP violations during filter interaction: {csp_violations(authed_page)}"
    )


@pytest.mark.parametrize(
    "name,path", FILTERED_PAGES, ids=[p[0] for p in FILTERED_PAGES]
)
def test_applied_filter_shows_a_removable_chip(authed_page, name, path):
    record_csp(authed_page)

    resp = authed_page.goto(path)
    assert resp is not None and resp.status < 400
    authed_page.wait_for_load_state("networkidle")

    select = _first_filter_select(authed_page)
    if select is None:
        pytest.skip(f"{name}: no filter dropdown offered for this corpus")

    value = select.locator("option").nth(1).get_attribute("value")
    select.select_option(value)
    authed_page.locator("input[type='submit'][value='Filter']").first.click()
    authed_page.wait_for_load_state("networkidle")

    chips = authed_page.locator("a.sparc-chip")
    assert chips.count() >= 1, (
        f"{name}: an applied filter must show a removable chip, or a user cannot "
        f"tell why the list is short"
    )
    assert "filter active" in authed_page.content()

    # Removing the chip is a plain link, not JavaScript — filter state lives in
    # the URL so it stays shareable and works without a mouse.
    chips.first.click()
    authed_page.wait_for_load_state("networkidle")
    assert authed_page.locator("a.sparc-chip").count() < chips.count() or (
        "filter active" not in authed_page.content()
    ), f"{name}: removing the chip did not clear the filter"

    assert not csp_violations(authed_page), (
        f"{name}: CSP violations during chip interaction: {csp_violations(authed_page)}"
    )
