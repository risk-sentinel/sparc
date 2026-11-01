"""The organization layout in a real browser (1.18.0-rf).

Every control is clicked, followed by a CSP check, and must change what
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


def test_overview_boundaries_and_inside_a_boundary(authed_page):
    page = authed_page
    record_csp(page)

    _open(page, "/")
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


def test_overview_numbers_open_what_they_count(authed_page):
    """#1302 — the header's counts, Waiting on you and every lane count are links."""
    page = authed_page
    record_csp(page)
    _open(page, "/")

    targets = [("[data-testid=org-meta-boundaries]", "/authorization_boundaries")]
    people = page.locator("a[data-testid=org-meta-people]")
    if people.count():
        people_path = urlparse(people.get_attribute("href")).path
        targets.append(("a[data-testid=org-meta-people]", people_path))
    if page.locator("[data-testid=org-waiting-queue]").count():
        targets.append(("[data-testid=org-waiting-queue]", "/review_queue"))
    for box in page.locator("[data-testid=org-box] .sparc-lane-box__count").evaluate_all(
        "els => els.map(e => e.getAttribute('href'))"
    ):
        targets.append((f"[data-testid=org-box] .sparc-lane-box__count[href='{box}']", box))

    for selector, path in targets:
        _open(page, "/")
        click_and_assert_clean(page, page.locator(selector).first, during=f"Overview: {selector}")
        page.wait_for_url(lambda u, path=path: urlparse(u).path == urlparse(path).path)
    assert_no_csp_violations(page, during="Overview numbers")


def test_command_center_controls_open_what_they_name(authed_page):
    """The command-center home (owner, 2026-10-31): a strip count, a layer
    row's title, every quick action and a boundary in the rail each open the
    page they name, with zero CSP violations; the page fits at 1280px and on a
    phone, and is held to zero new WCAG 2.1 AA violations."""
    page = authed_page
    record_csp(page)
    _open(page, "/")
    assert page.locator("[data-home-inventory] .sparc-home-strip__card").count() == 4
    assert_no_new_a11y_violations(page, "command_center_home")

    tile = "[data-home-inventory] a[data-home-tile='ssp_documents']"
    title = "[data-testid=org-box][data-box='cdef_documents'] .sparc-lane-box__title"
    targets = [(sel, page.locator(sel).get_attribute("href")) for sel in (tile, title)]
    quick = page.locator("[data-testid=org-quick-action]").evaluate_all(
        "els => els.map(e => [e.dataset.item, e.getAttribute('href')])"
    )
    for item, href in quick:
        targets.append((f"[data-testid=org-quick-action][data-item='{item}']", href))
    rail = "[data-testid=org-recent-boundaries]"
    boundary = page.locator(f"{rail} li a").first
    if boundary.count():
        assert page.locator(f"{rail} [data-testid=boundary-sparkline]").count() > 0
        targets.append((f"{rail} li a >> nth=0", boundary.get_attribute("href")))

    for selector, path in targets:
        _open(page, "/")
        click_and_assert_clean(page, page.locator(selector).first, during=f"home: {selector}")
        page.wait_for_url(lambda u, path=path: urlparse(u).path == urlparse(path).path)

    for width in (1280, 390):
        page.set_viewport_size({"width": width, "height": 900})
        _open(page, "/")
        overflow = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
        assert overflow <= 0, f"{width}px: the home page scrolls sideways by {overflow}px"
    assert_no_csp_violations(page, during="command center")
