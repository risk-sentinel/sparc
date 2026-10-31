"""The document pages' shared header in a real browser (1.18.0-rf #1304).

Posture-gated ("nav_shell"). On an SSP and a CDEF created through the API (and
deleted afterwards), each clicked with zero CSP violations:
  - every section link jumps to its section, and the row stays just below
    the (sticky) top bar after the jump;
  - Rename opens the name form in place and Cancel closes it;
  - the breadcrumb's list link opens the list;
and at 360px the page does not scroll sideways (the section row scrolls
inside itself).

Selectors verified against app/views/shared/_document_header.html.erb,
_page_header.html.erb and _section_links.html.erb.
"""

from __future__ import annotations

import pytest
from playwright.sync_api import expect

from _api_setup import create_boundary, create_cdef, create_ssp, delete_doc
from helpers import assert_no_csp_violations, nav_shell_on, record_csp

pytestmark = [pytest.mark.authenticated, pytest.mark.posture("nav_shell")]


@pytest.fixture
def documents():
    boundary = create_boundary()
    ssp = create_ssp(boundary["id"])
    cdef = create_cdef()
    try:
        yield {"ssp": f"/ssp_documents/{ssp['slug']}", "cdef": f"/cdef_documents/{cdef['slug']}"}
    finally:
        delete_doc("ssp_documents", ssp["slug"])
        delete_doc("cdef_documents", cdef["slug"])
        delete_doc("authorization_boundaries", boundary["slug"])


def _open(page, base_url, path, width=1280):
    page.set_viewport_size({"width": width, "height": 800})
    record_csp(page)
    resp = page.goto(f"{base_url}{path}")
    assert resp is not None and resp.ok, f"{path} returned {resp and resp.status}"
    page.wait_for_load_state("domcontentloaded")
    if not nav_shell_on(page):
        pytest.skip("SPARC_NAV_SHELL is off on this stack")


@pytest.mark.parametrize("kind", ["ssp", "cdef"])
def test_section_links_jump_and_stay(authed_page, base_url, documents, kind):
    page = authed_page
    _open(page, base_url, documents[kind])
    links = page.get_by_test_id("section-links").locator("a")
    hrefs = links.evaluate_all("els => els.map(e => e.getAttribute('href'))")
    assert hrefs, f"{kind}: no section links"

    row = page.get_by_test_id("section-links")
    # Where the row sits before any scroll: once the page scrolls past it, a
    # sticky row stays at the top of the window.
    natural = row.evaluate("e => e.getBoundingClientRect().top + window.scrollY")
    for href in reversed(hrefs):
        row.locator(f"a[href='{href}']").click()
        page.wait_for_url(f"**{href}")
        expect(page.locator(href)).to_be_in_viewport()
        if page.evaluate("window.scrollY") > natural:
            # Stuck just below the top bar, which is sticky too.
            bar = page.locator("nav.sticky-top").bounding_box()
            top = row.bounding_box()["y"]
            below = bar["y"] + bar["height"]
            assert abs(top - below) <= 1, f"{kind}: row at {top:.0f}px, bar ends at {below:.0f}px"
    assert_no_csp_violations(page, during=f"{kind} section links")


@pytest.mark.parametrize("kind", ["ssp", "cdef"])
def test_rename_opens_in_place(authed_page, base_url, documents, kind):
    page = authed_page
    _open(page, base_url, documents[kind])
    header = page.get_by_test_id("page-header")
    header.get_by_role("button", name="Rename").click()
    form = page.locator("#doc-meta-edit [data-testid=document-name-form]")
    expect(form).to_be_visible()
    expect(header.locator("h1")).to_be_hidden()
    form.get_by_role("button", name="Cancel").click()
    expect(form).to_be_hidden()
    expect(header.locator("h1")).to_be_visible()
    assert_no_csp_violations(page, during=f"{kind} rename toggle")


def test_breadcrumb_opens_the_boundary_list(authed_page, base_url, documents):
    page = authed_page
    _open(page, base_url, documents["ssp"])
    page.get_by_test_id("page-header").get_by_role("navigation", name="Breadcrumb").get_by_role(
        "link", name="SSPs"
    ).click()
    page.wait_for_url("**/ssp_documents?authorization_boundary_id=*")
    assert_no_csp_violations(page, during="the SSP breadcrumb")


@pytest.mark.parametrize("kind", ["ssp", "cdef"])
def test_nothing_scrolls_sideways_on_a_phone(authed_page, base_url, documents, kind):
    page = authed_page
    _open(page, base_url, documents[kind], width=360)
    overflow = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
    assert overflow <= 0, f"{kind} at 360px scrolls sideways by {overflow}px"
