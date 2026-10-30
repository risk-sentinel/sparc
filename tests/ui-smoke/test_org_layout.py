"""The organization layout in a real browser (1.18.0-rf, SPARC_NAV_SHELL).

Posture-gated ("nav_shell"): reported as UNPROVEN when the stack has the switch
off. Every control is clicked, followed by a CSP check, and must change what
the page shows: the Boundaries tab opens the repository-style list; a boundary
opens with its own tabs; its POA&Ms tab opens the list filtered to it, with the
Boundary filter on that boundary; the organization breadcrumb returns to the
Overview. The three screens are held to zero new WCAG 2.1 AA violations (their
baselines are empty).

Requires SPARC_SMOKE_SA_TOKEN, on an instance where the smoke user can reach at
least one boundary.
"""

from __future__ import annotations

from urllib.parse import parse_qs, urlparse

import pytest

from a11y import assert_no_new_a11y_violations
from helpers import assert_no_csp_violations, click_and_assert_clean, record_csp

pytestmark = pytest.mark.authenticated

ORG_TABS = "[data-testid=org-tabs]"
BOUNDARY_TABS = "[data-testid=boundary-tabs]"


def _open(page, path):
    response = page.goto(path)
    status = response and response.status
    assert response is not None and response.ok, f"{path} returned {status}"
    page.wait_for_load_state("networkidle")


def _current(page, bar):
    return page.locator(f"{bar} [aria-current=page]").get_attribute("data-tab")


@pytest.mark.posture("nav_shell")
def test_overview_boundaries_and_inside_a_boundary(authed_page):
    page = authed_page
    record_csp(page)

    _open(page, "/")
    if page.locator(ORG_TABS).count() == 0:
        pytest.skip("SPARC_NAV_SHELL is off on this stack, so there is no organization layout")
    assert _current(page, ORG_TABS) == "overview"
    assert page.locator("[data-testid=org-lane]").count() == 4
    assert page.locator("[data-home-inventory]").count() == 1
    assert_no_new_a11y_violations(page, "org_overview")

    click_and_assert_clean(
        page, f"{ORG_TABS} [data-tab=boundaries]", during="open the Boundaries tab"
    )
    page.wait_for_url(lambda u: urlparse(u).path == "/authorization_boundaries")
    page.wait_for_load_state("networkidle")
    assert _current(page, ORG_TABS) == "boundaries"
    rows = page.locator("[data-testid=boundary-row]")
    if rows.count() == 0:
        pytest.skip("the smoke user cannot reach any authorization boundary")
    assert rows.first.locator("[data-testid=boundary-sparkline]").count() == 1
    assert_no_new_a11y_violations(page, "org_boundaries_tab")

    row = rows.first
    boundary_id = row.get_attribute("data-boundary-id")
    name = row.locator(".sparc-repo-row__name").inner_text().strip()
    click_and_assert_clean(page, row.locator(".sparc-repo-row__name"), during="open a boundary")
    page.wait_for_url(lambda u: urlparse(u).path.startswith("/authorization_boundaries/"))
    page.wait_for_load_state("networkidle")
    assert page.locator("[data-testid=shell-boundary]").inner_text().strip() == name
    assert _current(page, BOUNDARY_TABS) == "overview"

    click_and_assert_clean(
        page, f"{BOUNDARY_TABS} [data-tab=poam]", during="open the boundary's POA&Ms"
    )
    page.wait_for_url(lambda u: "authorization_boundary_id=" in u)
    page.wait_for_load_state("networkidle")
    query = parse_qs(urlparse(page.url).query)
    assert query.get("authorization_boundary_id") == [boundary_id], page.url
    assert _current(page, BOUNDARY_TABS) == "poam"
    current_filter = page.locator("[data-testid=boundary-filter] [aria-current=true]")
    assert current_filter.get_attribute("data-boundary-id") == boundary_id
    assert_no_new_a11y_violations(page, "boundary_poams_tabs")

    click_and_assert_clean(page, "[data-testid=shell-org]", during="back to the organization")
    page.wait_for_url(lambda u: urlparse(u).path == "/")
    page.wait_for_load_state("networkidle")
    assert _current(page, ORG_TABS) == "overview"
    assert_no_csp_violations(page, during="organization layout")
