"""UI smoke: the homepage's count badges (v1.17.2, #1243).

The scoreboard above the layer cards is gone. Each card carries a count badge
that links to the same page as its View button, scoped to what the user may
see. Every badge is clicked here, in Chrome, with zero CSP violations.

Selectors verified against app/views/home/index.html.erb
(`a[data-home-count]`, `.sparc-section-card`).
"""

from __future__ import annotations

from urllib.parse import urlparse

import pytest
from playwright.sync_api import expect

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


def _badges(page) -> list[tuple[str, str]]:
    return page.locator("a[data-home-count]").evaluate_all(
        "els => els.map(e => [e.dataset.homeCount, e.getAttribute('href')])"
    )


def test_scoreboard_is_gone_and_each_badge_opens_its_list(authed_page, base_url):
    page = authed_page
    record_csp(page)
    page.goto(f"{base_url}/")
    page.wait_for_load_state("domcontentloaded")

    assert page.locator(".sparc-gradient-header").count() == 0, "the scoreboard is still rendered"
    badges = _badges(page)
    assert len(badges) >= 11, f"expected a badge on every layer card, found {badges}"

    for key, href in badges:
        card = page.locator(".sparc-section-card").filter(
            has=page.locator(f"a[data-home-count='{key}']")
        )
        view = card.get_by_role("link", name="View")
        assert view.get_attribute("href") == href, f"{key}: badge and View lead to different pages"

    for key, href in badges:
        page.goto(f"{base_url}/")
        page.wait_for_load_state("domcontentloaded")
        badge = page.locator(f"a[data-home-count='{key}']")
        expect(badge).to_be_visible()
        badge.click()
        # A list may add its own query (a remembered view), so match the path.
        page.wait_for_url(lambda url, target=href: urlparse(url).path == target, timeout=10000)
        assert_no_csp_violations(page, during=f"clicking the {key} count badge")


def test_non_admin_sees_no_organizations_card(user_authed_page, base_url):
    page = user_authed_page
    record_csp(page)
    page.goto(f"{base_url}/")
    page.wait_for_load_state("domcontentloaded")

    assert page.locator("a[data-home-count='organizations']").count() == 0
    assert page.locator(".sparc-section-card a[href^='/admin/organizations']").count() == 0
    assert page.locator("a[data-home-count='authorization_boundaries']").count() == 1
    assert_no_csp_violations(page, during="the homepage as a non-administrator")
