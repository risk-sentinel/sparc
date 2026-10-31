"""The boundary home in a real browser (1.18.0-rf #1301).

Posture-gated ("nav_shell"). On a boundary created through the API (and
deleted afterwards), each clicked with zero CSP violations:
  - the page header's More menu opens;
  - each document row's link (the Add… links lead to the attach screen);
  - "Use from a pipeline" opens and shows the readiness API call;
  - "See each item" reaches Boundary Completeness, and People reaches the
    roster;
and the home lays out at 1280px (About beside the main column) and at 360px
(no sideways scroll).

Selectors verified against app/views/authorization_boundaries/_home.html.erb.
"""

from __future__ import annotations

import pytest
from playwright.sync_api import expect

from _api_setup import create_boundary, delete_doc
from helpers import assert_no_csp_violations, nav_shell_on, record_csp

pytestmark = [pytest.mark.authenticated, pytest.mark.posture("nav_shell")]


@pytest.fixture
def boundary():
    record = create_boundary()
    try:
        yield record
    finally:
        delete_doc("authorization_boundaries", record["slug"])


def _open(page, base_url, slug, width=1280):
    page.set_viewport_size({"width": width, "height": 900})
    record_csp(page)
    resp = page.goto(f"{base_url}/authorization_boundaries/{slug}")
    assert resp is not None and resp.ok
    page.wait_for_load_state("domcontentloaded")
    if not nav_shell_on(page):
        pytest.skip("SPARC_NAV_SHELL is off on this stack")
    expect(page.get_by_test_id("boundary-home")).to_be_visible()


def test_the_header_menu_opens(authed_page, base_url, boundary):
    page = authed_page
    _open(page, base_url, boundary["slug"])
    header = page.get_by_test_id("page-header")
    expect(header.locator("h1")).to_have_text(boundary["name"])
    header.locator("[data-boundary-action='more']").click()
    expect(page.locator("[aria-labelledby='boundary-more-menu']")).to_be_visible()
    assert_no_csp_violations(page, during="opening the boundary More menu")


@pytest.mark.parametrize("key", ["ssp", "sap", "sar", "poam"])
def test_an_empty_document_row_leads_to_attach(authed_page, base_url, boundary, key):
    page = authed_page
    _open(page, base_url, boundary["slug"])
    row = page.locator(f"[data-testid=boundary-documents] [data-document='{key}']")
    row.get_by_role("link", name="Add…").click()
    page.wait_for_url(f"**/authorization_boundaries/{boundary['slug']}/attach_document?type={key}")
    assert_no_csp_violations(page, during=f"Add… on the {key} row")


def test_pipeline_snippet_and_jumps(authed_page, base_url, boundary):
    page = authed_page
    _open(page, base_url, boundary["slug"])

    readiness = page.get_by_test_id("boundary-readiness-bar")
    readiness.get_by_text("Use from a pipeline").click()
    code = readiness.locator("code")
    expect(code).to_be_visible()
    expect(code).to_contain_text(f"/api/v1/authorization_boundaries/{boundary['id']}/readiness")

    readiness.get_by_role("link", name="See each item").click()
    page.wait_for_url("**#boundary-completeness")
    expect(page.locator("#boundary-completeness")).to_be_in_viewport()

    page.locator("[data-boundary-fact='people'] a").click()
    page.wait_for_url("**#boundary-personnel")
    expect(page.locator("#boundary-personnel")).to_be_in_viewport()
    assert_no_csp_violations(page, during="the readiness snippet and the page jumps")


def test_about_sits_beside_the_main_column(authed_page, base_url, boundary):
    page = authed_page
    _open(page, base_url, boundary["slug"])
    main = page.locator(".sparc-boundary-home__main").bounding_box()
    about = page.locator(".sparc-boundary-home__about").bounding_box()
    assert about["x"] >= main["x"] + main["width"], "About is not beside the main column at 1280px"
    assert abs(about["y"] - main["y"]) <= 4, "About does not start level with the main column"


def test_nothing_scrolls_sideways_on_a_phone(authed_page, base_url, boundary):
    page = authed_page
    _open(page, base_url, boundary["slug"], width=360)
    overflow = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
    assert overflow <= 0, f"the boundary page at 360px scrolls sideways by {overflow}px"
