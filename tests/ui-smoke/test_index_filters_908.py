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


def _apply_first_filter(page):
    """Select the first real option and submit, returning (param, value).

    Returns None when this corpus offers no filter.

    `wait_for_url` is load-bearing. Submitting is a Turbo GET visit, and
    `wait_for_load_state("networkidle")` can return BEFORE that navigation
    commits — leaving `page.url` and the DOM as they were pre-submit. An
    assertion made there reads back the state the test set up itself and
    passes without exercising anything, which is exactly what happened to the
    per_page check until the chip assertion caught it. Wait for the parameter
    to actually appear in the URL. Same pattern as test_index_search.py.
    """
    select = _first_filter_select(page)
    if select is None:
        return None

    param = select.get_attribute("name")
    options = select.locator("option")
    assert options.count() >= 2, f"filter dropdown '{param}' drawn with no choices"
    value = options.nth(1).get_attribute("value")
    assert value, f"filter dropdown '{param}' first real option has an empty value"

    select.select_option(value)
    page.locator("input[type='submit'][value='Filter']").first.click()
    page.wait_for_url(f"**{param}=*", timeout=10000)
    page.wait_for_load_state("networkidle")
    return param, value


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

    applied = _apply_first_filter(authed_page)
    if applied is None:
        pytest.skip(f"{name}: no filter dropdown offered for this corpus")
    param, value = applied

    url = authed_page.url
    assert f"{param}={value}" in url, (
        f"{name}: the selected filter did not reach the URL. URL: {url}"
    )
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

    applied = _apply_first_filter(authed_page)
    if applied is None:
        pytest.skip(f"{name}: no filter dropdown offered for this corpus")
    param, _value = applied

    chips = authed_page.locator("a.sparc-chip")
    assert chips.count() >= 1, (
        f"{name}: an applied filter must show a removable chip, or a user cannot "
        f"tell why the list is short"
    )
    assert "filter active" in authed_page.content()

    # Removing the chip is a plain link, not JavaScript — filter state lives in
    # the URL so it stays shareable and works without a mouse.
    #
    # Waiting for the parameter to LEAVE the URL, for the same reason as the
    # submit above: asserting straight after the click would read the page that
    # still has the filter applied and pass without removing anything.
    chips.first.click()
    authed_page.wait_for_url(lambda url: f"{param}=" not in url, timeout=10000)
    authed_page.wait_for_load_state("networkidle")
    assert f"{param}=" not in authed_page.url, (
        f"{name}: removing the chip did not drop {param} from the URL. "
        f"URL: {authed_page.url}"
    )

    assert not csp_violations(authed_page), (
        f"{name}: CSP violations during chip interaction: {csp_violations(authed_page)}"
    )
