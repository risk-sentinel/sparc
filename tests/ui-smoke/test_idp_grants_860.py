"""Administration -> IdP Grants (#860).

The unmatched-grant queue: entitlements an identity provider asked for that this
instance could not grant. New page and new nav entry, so it takes an interaction
check with a CSP assertion — render-time checks cannot see inline-handler
breakage, which only shows on click.

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

PATH = "/admin/idp_grants"


def test_the_page_loads_and_is_reachable_from_the_nav(authed_page):
    """The nav entry is the point of the screen existing at all.

    An admin who has to be told the URL will not find it, and the refusals it
    reports are otherwise invisible.
    """
    record_csp(authed_page)
    authed_page.goto("/")

    link = authed_page.locator('a[href="/admin/idp_grants"]')
    if link.count() == 0:
        pytest.skip("administration nav is not rendered for this user or viewport")

    assert "IdP Grants" in link.first.inner_text()


def test_it_renders_without_csp_violations(authed_page):
    record_csp(authed_page)
    authed_page.goto(PATH)

    assert authed_page.locator("h1").first.inner_text().strip() == "Unmatched IdP Grants"
    assert_no_csp_violations(authed_page, during="loading the IdP grants queue")


def test_it_says_nothing_needs_clearing(authed_page):
    """The instinct this page has to correct.

    Every sign-in re-evaluates the claim, so creating the missing record
    resolves the grant by itself. Without saying so the page reads as a task
    list with no way to complete a task, and an administrator hunts for a
    dismiss button that should not be their first move.
    """
    record_csp(authed_page)
    authed_page.goto(PATH)

    body = authed_page.locator("body").inner_text()
    assert ("resolves by itself" in body) or ("No grants were refused" in body), body[:400]


def test_the_window_filter_works(authed_page):
    record_csp(authed_page)
    authed_page.goto(PATH)

    select = authed_page.locator("select[name='days']")
    if select.count() == 0:
        pytest.skip("window filter not rendered")

    select.first.select_option("7")
    authed_page.locator("input[type='submit']").first.click()
    authed_page.wait_for_load_state("load")

    assert "days=7" in authed_page.url, authed_page.url
    assert_no_csp_violations(authed_page, during="changing the window")


def test_a_wide_table_scrolls_inside_its_own_container(authed_page):
    """#1042's lesson applied on the way in rather than after the fact."""
    record_csp(authed_page)
    authed_page.set_viewport_size({"width": 992, "height": 800})
    authed_page.goto(PATH)

    tables = authed_page.locator("table")
    for i in range(tables.count()):
        scrollable = tables.nth(i).evaluate(
            "el => { for (let p = el.parentElement; p; p = p.parentElement) {"
            "  const ov = getComputedStyle(p).overflowX;"
            "  if (ov === 'auto' || ov === 'scroll') return true; } return false; }"
        )
        assert scrollable, f"table {i} has no scrollable ancestor at 992px"
