"""The Boundary filter beside the document lists, in a real browser (1.18.0-rf #1292).

The filter exists only with SPARC_NAV_SHELL on, so this is posture-gated
("nav_shell") and reported as UNPROVEN when the stack has the switch off.

Each option is clicked and followed by a CSP check, and each must change what
the page shows, not just render: choosing a boundary puts it in the URL and
marks it current; "All boundaries" takes it out again; and a fresh visit
remembers nothing (the URL is the only source, owner's revised phase 2 plan).

Requires SPARC_SMOKE_SA_TOKEN, on an instance where the smoke user can reach at
least one boundary that holds an SSP.
"""

from __future__ import annotations

from urllib.parse import parse_qs, urlparse

import pytest

from helpers import assert_no_csp_violations, click_and_assert_clean, record_csp

pytestmark = pytest.mark.authenticated

FILTER = "[data-testid=boundary-filter]"
CURRENT = f"{FILTER} [aria-current=true]"
OPTION = f"{FILTER} [data-testid=boundary-filter-option]"
ALL = f"{FILTER} [data-testid=boundary-filter-all]"
PARAM = "authorization_boundary_id"


def _open(page, path):
    response = page.goto(path)
    status = response and response.status
    assert response is not None and response.ok, f"{path} returned {status}"
    page.wait_for_load_state("networkidle")


def _param(page):
    return parse_qs(urlparse(page.url).query).get(PARAM)


@pytest.mark.posture("nav_shell")
def test_choose_a_boundary_and_back_to_all(authed_page):
    page = authed_page
    record_csp(page)

    # Arrive with a page size and a view mode: choosing a boundary must keep
    # both and drop the page number, as the filter row does (#908).
    _open(page, "/ssp_documents?per_page=50&view=list&page=1")
    if page.locator(FILTER).count() == 0:
        pytest.skip("SPARC_NAV_SHELL is off on this stack, so there is no Boundary filter")
    assert page.locator(CURRENT).get_attribute("data-testid") == "boundary-filter-all"

    options = page.locator(OPTION)
    if options.count() == 0:
        pytest.skip("the smoke user cannot reach a boundary that holds an SSP")
    first = options.first
    boundary_id = first.get_attribute("data-boundary-id")
    name = first.locator(".sparc-filter-link__label").inner_text().strip()

    click_and_assert_clean(page, first, during="choose a boundary")
    page.wait_for_url(lambda u: f"{PARAM}={boundary_id}" in u)
    page.wait_for_load_state("networkidle")
    assert _param(page) == [boundary_id], page.url
    query = parse_qs(urlparse(page.url).query)
    assert query.get("per_page") == ["50"] and query.get("view") == ["list"], page.url
    assert "page" not in query, f"choosing a boundary kept the old page number: {page.url}"
    assert page.locator(CURRENT).get_attribute("data-boundary-id") == boundary_id
    assert page.locator(CURRENT).inner_text().strip().startswith(name)

    click_and_assert_clean(page, ALL, during="back to all boundaries")
    page.wait_for_url(lambda u: f"{PARAM}=" not in u)
    page.wait_for_load_state("networkidle")
    assert _param(page) is None, page.url
    assert page.locator(CURRENT).get_attribute("data-testid") == "boundary-filter-all"

    # Nothing is remembered: a later visit with no parameter shows everything.
    _open(page, f"/ssp_documents?{PARAM}={boundary_id}")
    _open(page, "/poam_documents")
    assert page.locator(CURRENT).get_attribute("data-testid") == "boundary-filter-all"
    assert_no_csp_violations(page, during="boundary filter")


@pytest.mark.posture("nav_shell")
def test_shared_library_list_has_no_boundary_filter(authed_page):
    page = authed_page
    record_csp(page)
    _open(page, "/ssp_documents")
    if page.locator(FILTER).count() == 0:
        pytest.skip("SPARC_NAV_SHELL is off on this stack, so there is no Boundary filter")

    _open(page, "/control_catalogs")
    assert page.locator(FILTER).count() == 0
    assert_no_csp_violations(page, during="shared-library list")
