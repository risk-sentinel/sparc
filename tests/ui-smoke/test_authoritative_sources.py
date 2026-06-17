"""Authoritative source screens — full control-surface smoke (#646).

Exercises EVERY interactive control this PR adds/touches on the Authoritative
Sources index + add form, asserting behavior AND zero CSP violations on each
interaction (the new "all navigation gets a Playwright check" guardrail):

  - index: "+ Add source", filter form (query → Filter), Clear, per-row View
  - add form: fill + submit (org-scoped), instance-wide checkbox, Cancel

Requires SPARC_SMOKE_SA_TOKEN; runs against a local container first.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp


pytestmark = pytest.mark.authenticated

INDEX = "/authoritative_sources"
NEW = "/authoritative_sources/new"


def _open_add_form(page):
    page.goto(INDEX, wait_until="networkidle")
    add = page.locator(f'a[href="{NEW}"]')
    if add.count() == 0:
        pytest.skip("add control not present for this user")
    add.first.click()
    page.wait_for_url(f"**{NEW}", timeout=10000)
    page.wait_for_load_state("networkidle")


def test_index_loads_and_exposes_add(authed_page):
    record_csp(authed_page)
    authed_page.goto(INDEX, wait_until="networkidle")
    assert_no_csp_violations(authed_page, during="index load")
    assert authed_page.locator(f'a[href="{NEW}"]').count() >= 1


def test_filter_then_clear(authed_page):
    record_csp(authed_page)
    authed_page.goto(INDEX, wait_until="networkidle")

    authed_page.fill("#q", "Smoke")
    authed_page.locator('input[type="submit"][value="Filter"]').click()
    authed_page.wait_for_url(lambda u: "q=Smoke" in u, timeout=10000)
    authed_page.wait_for_load_state("networkidle")
    assert_no_csp_violations(authed_page, during="apply filter")

    authed_page.get_by_role("link", name="Clear").click()
    authed_page.wait_for_url(lambda u: "q=" not in u, timeout=10000)
    assert_no_csp_violations(authed_page, during="clear filter")


def test_view_opens_show_page(authed_page):
    record_csp(authed_page)
    authed_page.goto(INDEX, wait_until="networkidle")

    view = authed_page.get_by_role("link", name="View")
    if view.count() == 0:
        pytest.skip("no rows to view")
    view.first.click()
    authed_page.wait_for_url(lambda u: "/authoritative_sources/" in u and not u.endswith("/new"))
    authed_page.wait_for_load_state("networkidle")
    assert_no_csp_violations(authed_page, during="open show page")


def test_cancel_returns_to_index(authed_page):
    record_csp(authed_page)
    _open_add_form(authed_page)

    authed_page.get_by_role("link", name="Cancel").click()
    authed_page.wait_for_url(lambda u: u.split("?")[0].rstrip("/").endswith("/authoritative_sources"))
    assert_no_csp_violations(authed_page, during="cancel add")


def test_add_org_scoped(authed_page):
    record_csp(authed_page)
    _open_add_form(authed_page)

    title = "UI Smoke Org Source"
    authed_page.fill("#back_matter_resource_title", title)
    authed_page.locator('input[type="submit"][value="Add source"]').click()
    authed_page.wait_for_url(
        lambda u: u.split("?")[0].rstrip("/").endswith("/authoritative_sources"), timeout=10000
    )
    authed_page.wait_for_load_state("networkidle")
    assert authed_page.get_by_text(title).count() > 0, f"'{title}' not listed after create"
    assert_no_csp_violations(authed_page, during="submit org-scoped add")


def test_add_instance_wide_checkbox(authed_page):
    """Checking 'instance-wide' as an admin self-promotes to a Global entry."""
    record_csp(authed_page)
    _open_add_form(authed_page)

    title = "UI Smoke Global Source"
    authed_page.fill("#back_matter_resource_title", title)
    authed_page.check("#instance_wide")
    assert_no_csp_violations(authed_page, during="check instance-wide")

    authed_page.locator('input[type="submit"][value="Add source"]').click()
    authed_page.wait_for_url(
        lambda u: u.split("?")[0].rstrip("/").endswith("/authoritative_sources"), timeout=10000
    )
    authed_page.wait_for_load_state("networkidle")

    row = authed_page.locator("tr", has_text=title)
    assert row.count() > 0, f"'{title}' not listed after instance-wide create"
    # An admin self-approves → the row is globally available.
    assert row.first.get_by_text("Global").count() > 0, "instance-wide source not marked Global"
    assert_no_csp_violations(authed_page, during="submit instance-wide add")
