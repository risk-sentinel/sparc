"""UI smoke: the boundary page (v1.17.2, #1251).

Clicked in Chrome, each with zero CSP violations:
  - the "More" menu and each of its items (Findings Triage, CDEF Coverage, Edit,
    All Authorization Boundaries), and Delete through SPARC's confirm modal
    (`#sparc-confirm-modal-confirm`, not a native dialog);
  - a collapsible section, whose open/closed state survives a reload and
    carries to another boundary's page, while a Draft boundary always opens
    Boundary Completeness;
  - the Completeness row links, including "Add SSP first" and the same-page
    Back Matter link that opens its section.

Every boundary is created through the API and deleted afterwards (the one
deleted through the UI is checked gone through the API).

Selectors verified against app/views/authorization_boundaries/show.html.erb,
_readiness.html.erb and shared/_collapsible_section.html.erb.
"""

from __future__ import annotations

import re

import httpx
import pytest
from playwright.sync_api import expect

from _api_setup import create_boundary, delete_doc, get_json, patch_json
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


@pytest.fixture
def boundary():
    record = create_boundary()  # API-created boundaries start as Draft
    try:
        yield record
    finally:
        delete_doc("authorization_boundaries", record["slug"])


@pytest.fixture
def active_boundary():
    record = create_boundary()
    try:
        r = patch_json(
            f"/api/v1/authorization_boundaries/{record['id']}",
            {"authorization_boundary": {"status": "active"}},
        )
        assert r.status_code == 200, r.text
        yield record
    finally:
        delete_doc("authorization_boundaries", record["slug"])


def _open(page, base_url, slug):
    page.goto(f"{base_url}/authorization_boundaries/{slug}")
    page.wait_for_load_state("domcontentloaded")


def _open_more(page):
    page.locator("[data-boundary-action='more']").click()
    expect(page.locator("[aria-labelledby='boundary-more-menu']")).to_be_visible()


def _toggle(page, section):
    return page.locator(f"[aria-controls='boundary-{section}-body']")


def _body(page, section):
    return page.locator(f"#boundary-{section}-body")


class TestMoreMenu:
    # Patterns, not globs: the page itself is under /authorization_boundaries,
    # so a glob for the list would match before the click went anywhere.
    @pytest.mark.parametrize(
        "action,destination",
        [
            ("amendments", r"/triage$"),
            ("cdef_coverage", r"/cdef_coverage/new\?authorization_boundary_id="),
            ("edit", r"/edit$"),
            ("all_boundaries", r"/authorization_boundaries(\?.*)?$"),
        ],
    )
    def test_menu_item_navigates(self, authed_page, base_url, boundary, action, destination):
        page = authed_page
        record_csp(page)
        _open(page, base_url, boundary["slug"])

        _open_more(page)
        item = page.locator(f"[data-boundary-action='{action}']")
        expect(item).to_be_visible()
        item.click()
        page.wait_for_url(re.compile(destination), timeout=10000)
        assert_no_csp_violations(page, during=f"the More menu's {action}")

    def test_build_ato_package_stays_outside_the_menu(self, authed_page, base_url, boundary):
        page = authed_page
        record_csp(page)
        _open(page, base_url, boundary["slug"])

        build = page.locator("header [data-boundary-action='build_ato_package']")
        expect(build).to_be_visible()
        build.click()
        page.wait_for_url("**/ato_wizard", timeout=10000)
        assert_no_csp_violations(page, during="Build ATO Package")

    def test_delete_through_the_confirm_modal(self, authed_page, base_url):
        record = create_boundary()
        try:
            page = authed_page
            record_csp(page)
            _open(page, base_url, record["slug"])

            _open_more(page)
            page.locator("[data-boundary-action='delete']").click()
            confirm = page.locator("#sparc-confirm-modal-confirm")
            confirm.wait_for(state="visible", timeout=5000)
            confirm.click()
            page.wait_for_url(
                lambda url: url.rstrip("/").endswith("/authorization_boundaries"), timeout=10000
            )
            assert_no_csp_violations(page, during="deleting a boundary from its page")

            with pytest.raises(httpx.HTTPStatusError) as gone:
                get_json(f"/api/v1/authorization_boundaries/{record['id']}")
            assert gone.value.response.status_code == 404, "the boundary survived its delete"
        finally:
            delete_doc("authorization_boundaries", record["slug"])


def _settled(page):
    """Wait out Bootstrap's collapse transition (~350ms). It ignores a click made
    while a section is still animating, as a person's second click would be."""
    expect(page.locator(".collapsing")).to_have_count(0)


class TestCollapsibleSections:
    def test_choice_survives_reload_and_carries_to_another_boundary(
        self, authed_page, base_url, boundary, active_boundary
    ):
        page = authed_page
        record_csp(page)
        _open(page, base_url, boundary["slug"])

        toggle = _toggle(page, "personnel")
        expect(toggle).to_have_attribute("aria-expanded", "false")
        toggle.click()
        _settled(page)
        expect(toggle).to_have_attribute("aria-expanded", "true")

        page.reload()
        page.wait_for_load_state("domcontentloaded")
        expect(_toggle(page, "personnel")).to_have_attribute("aria-expanded", "true")
        assert "show" in (_body(page, "personnel").get_attribute("class") or "")

        _open(page, base_url, active_boundary["slug"])
        expect(_toggle(page, "personnel")).to_have_attribute("aria-expanded", "true")

        # Close it again, and the next page load remembers that too.
        _toggle(page, "personnel").click()
        _settled(page)
        expect(_toggle(page, "personnel")).to_have_attribute("aria-expanded", "false")
        page.reload()
        page.wait_for_load_state("domcontentloaded")
        expect(_toggle(page, "personnel")).to_have_attribute("aria-expanded", "false")
        assert_no_csp_violations(page, during="collapsing and expanding a boundary section")

    def test_draft_always_opens_completeness(
        self, authed_page, base_url, boundary, active_boundary
    ):
        page = authed_page
        record_csp(page)

        # Collapse Completeness where it is not pinned (an active boundary).
        _open(page, base_url, active_boundary["slug"])
        completeness = _toggle(page, "completeness")
        if completeness.get_attribute("aria-expanded") == "false":
            completeness.click()
            _settled(page)
            expect(completeness).to_have_attribute("aria-expanded", "true")
        completeness.click()
        _settled(page)
        expect(completeness).to_have_attribute("aria-expanded", "false")

        # A Draft boundary still opens it.
        _open(page, base_url, boundary["slug"])
        expect(_toggle(page, "completeness")).to_have_attribute("aria-expanded", "true")
        assert "show" in (_body(page, "completeness").get_attribute("class") or "")
        assert_no_csp_violations(page, during="a Draft boundary's Completeness")


class TestCompletenessLinks:
    def test_rows_lead_to_the_work(self, authed_page, base_url, boundary):
        page = authed_page
        record_csp(page)
        _open(page, base_url, boundary["slug"])

        # Draft: Completeness is open. Personnel leads to Add Member.
        page.locator("[data-readiness-row='personnel'] a[data-readiness-action]").click()
        page.wait_for_url(
            f"**/authorization_boundaries/{boundary['slug']}/memberships/new", timeout=10000
        )
        assert_no_csp_violations(page, during="the Personnel row link")

        # With no SSP, the categorization row leads to the prerequisite.
        _open(page, base_url, boundary["slug"])
        prerequisite = page.locator(
            "[data-readiness-row='classification'] a[data-readiness-action]"
        )
        expect(prerequisite).to_have_text("Add SSP first")
        prerequisite.click()
        page.wait_for_url("**/attach_document?type=ssp", timeout=10000)
        assert_no_csp_violations(page, during="the Add SSP first link")

    def test_back_matter_row_opens_its_section(self, authed_page, base_url, boundary):
        page = authed_page
        record_csp(page)
        _open(page, base_url, boundary["slug"])

        expect(_toggle(page, "back-matter")).to_have_attribute("aria-expanded", "false")
        page.locator("[data-readiness-row='back_matter'] a[data-readiness-action]").click()
        expect(_toggle(page, "back-matter")).to_have_attribute("aria-expanded", "true")
        assert "show" in (_body(page, "back-matter").get_attribute("class") or "")
        assert_no_csp_violations(page, during="the Back-matter documents row link")
