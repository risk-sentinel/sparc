"""Status tabs, list rows and side filters in a real browser (1.18.0-rf #1299, #1300).

Posture-gated ("nav_shell"): reported as UNPROVEN when the stack has the switch
off. On each list with tabs, every tab is clicked (each click followed by a CSP
check) and must:
  - select itself (aria-current) and put its filter in the URL;
  - keep the view mode and page size;
  - show exactly as many records as its count says.
The filter form in the left column is submitted and must keep the view mode.

Requires SPARC_SMOKE_SA_TOKEN.
"""

from __future__ import annotations

from urllib.parse import parse_qs, urlparse

import pytest
from playwright.sync_api import expect

from helpers import assert_no_csp_violations, click_and_assert_clean, nav_shell_on, record_csp

pytestmark = [pytest.mark.authenticated, pytest.mark.posture("nav_shell")]

TABS = "[data-testid=status-tabs] [data-testid=status-tab]"
ROW = "[data-testid=collection-row]"

# Lists with status tabs (CDEFs by source, #1300).
TABBED = [
    ("cdef", "/cdef_documents"),
    ("ssp", "/ssp_documents"),
    ("sap", "/sap_documents"),
    ("sar", "/sar_documents"),
    ("poam", "/poam_documents"),
    ("profile", "/profile_documents"),
    ("control_catalogs", "/control_catalogs"),
    ("evidences", "/evidences"),
    ("control_mappings", "/control_mappings"),
    ("converters", "/converters"),
]


def _open(page, path):
    resp = page.goto(path)
    assert resp is not None and resp.ok, f"{path} returned {resp and resp.status}"
    page.wait_for_load_state("networkidle")
    if not nav_shell_on(page):
        pytest.skip("SPARC_NAV_SHELL is off on this stack")


@pytest.mark.parametrize(("label", "path"), TABBED, ids=[t[0] for t in TABBED])
def test_every_tab_selects_itself_and_shows_its_count(authed_page, label, path):
    page = authed_page
    record_csp(page)
    _open(page, f"{path}?view=list&per_page=200")

    tabs = page.locator(TABS)
    assert tabs.count() >= 2, f"{label}: no status tabs"
    expect(tabs.first).to_have_attribute("aria-current", "true")
    targets = tabs.evaluate_all(
        "els => els.map(e => ({slug: e.dataset.tab, count: +e.dataset.count}))"
    )

    for target in targets:
        _open(page, f"{path}?view=list&per_page=200")
        before = page.url
        tab = page.locator(f"{TABS}[data-tab='{target['slug']}']")
        click_and_assert_clean(page, tab, during=f"{label}: tab {target['slug']}")
        if target["slug"] != "all":
            # A Turbo visit: the URL changes after the click returns.
            page.wait_for_url(lambda url, before=before: url != before, timeout=15000)
        page.wait_for_load_state("networkidle")

        query = parse_qs(urlparse(page.url).query)
        assert query.get("view") == ["list"] and query.get("per_page") == ["200"], page.url
        current = page.locator(f"{TABS}[aria-current=true]")
        expect(current).to_have_attribute("data-tab", target["slug"])
        shown = page.locator(ROW).count()
        # The tiered views (#948) still draw one row per record.
        assert shown == min(target["count"], 200), (
            f"{label}: tab {target['slug']} says {target['count']}, shows {shown}"
        )
    assert_no_csp_violations(page, during=f"{label} status tabs")


def test_the_side_filter_form_keeps_the_view(authed_page):
    """The filter form moved into the left column still carries the view mode."""
    page = authed_page
    record_csp(page)
    _open(page, "/profile_documents?view=table&per_page=50")
    side = page.locator(".sparc-filtered-collection__side")
    form = side.locator("[data-testid=collection-filter-form] form")
    if form.count() == 0:
        pytest.skip("this instance has too few baselines for any filter to be offered")

    select = form.locator("select").first
    values = select.locator("option").evaluate_all("os => os.map(o => o.value).filter(Boolean)")
    select.select_option(values[0])
    click_and_assert_clean(page, form.locator("input[type=submit]"), during="side filter")
    page.wait_for_url(lambda url: values[0] in url, timeout=15000)

    query = parse_qs(urlparse(page.url).query)
    assert query.get("view") == ["table"] and query.get("per_page") == ["50"], page.url
    tokens = page.locator("[data-testid=filter-token]").count()
    assert tokens >= 1, "the applied filter shows no token"


@pytest.mark.parametrize("width", [1280, 360])
def test_rows_fit_the_viewport(authed_page, width):
    page = authed_page
    page.set_viewport_size({"width": width, "height": 900})
    _open(page, "/ssp_documents?view=list")
    if page.locator(ROW).count() == 0:
        pytest.skip("no SSPs on this deployment")
    overflow = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
    assert overflow <= 0, f"{width}px: the list scrolls sideways by {overflow}px"


def test_cdef_coverage_sorts_a_boundary_list(authed_page):
    """#1300 — inside a boundary with a baseline, CDEFs sort by coverage."""
    page = authed_page
    record_csp(page)
    _open(page, "/cdef_documents?view=list")
    options = page.locator("[data-testid=boundary-filter-option]").evaluate_all(
        "els => els.map(e => e.getAttribute('href'))"
    )
    for href in options:
        _open(page, href)
        if page.locator("[data-testid=cdef-sort-coverage]").count():
            break
    else:
        pytest.skip("no boundary here has CDEFs and a resolved baseline")

    before = page.url
    click_and_assert_clean(page, "[data-testid=cdef-sort-coverage]", during="sort by coverage")
    page.wait_for_url(lambda url: url != before and "sort=coverage" in url, timeout=15000)
    page.wait_for_load_state("networkidle")
    values = [
        float(v)
        for v in page.locator(f"{ROW} [data-testid=coverage-meter]").evaluate_all(
            "els => els.map(e => e.getAttribute('value'))"
        )
    ]
    assert values, "a boundary list sorted by coverage shows no coverage"
    assert values == sorted(values, reverse=True), f"not sorted by coverage: {values}"
    assert_no_csp_violations(page, during="cdef coverage sort")
