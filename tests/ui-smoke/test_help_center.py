"""In-app Help Center / User Guides smoke (#784).

The Help Center (`/help`) renders the bundled wiki User Guides in-app. This
exercises the new navigation + the client-side search control end to end:
  - /help loads (authenticated) and lists guide cards
  - typing in the search box filters cards client-side (no reload, no /login)
  - a guide page (/help/:slug) renders with its screenshot served in-app
  - ZERO CSP violations throughout (the non-negotiable DoD for new interactive
    controls — the search is a Stimulus controller, no inline handlers)

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


def test_help_index_search_filters_clean(authed_page):
    record_csp(authed_page)

    resp = authed_page.goto("/help")
    assert resp is not None and resp.status < 400, (
        f"/help returned {resp.status if resp else 'none'}"
    )
    authed_page.wait_for_load_state("networkidle")

    cards = authed_page.locator("[data-guide-search-target='card']")
    total = cards.count()
    assert total >= 13, f"expected >= 13 guide cards, saw {total}"

    box = authed_page.locator("[data-guide-search-target='query']")
    assert box.count() == 1, "expected the guide search box"

    # Client-side filter: an unlikely query hides every card.
    box.fill("zzq-unlikely-xyz")
    authed_page.wait_for_timeout(300)
    visible = authed_page.locator(
        "[data-guide-search-target='card']:not(.d-none)"
    ).count()
    assert visible == 0, f"unlikely query left {visible} cards visible"

    # A real query narrows to a subset without navigating away.
    box.fill("assessment")
    authed_page.wait_for_timeout(300)
    narrowed = authed_page.locator(
        "[data-guide-search-target='card']:not(.d-none)"
    ).count()
    assert 0 < narrowed < total, f"'assessment' matched {narrowed} of {total}"
    assert "/login" not in authed_page.url

    assert_no_csp_violations(authed_page, during="help search")


def test_help_guide_renders_with_screenshot(authed_page):
    record_csp(authed_page)

    resp = authed_page.goto("/help/getting-oriented")
    assert resp is not None and resp.status < 400, (
        f"/help/getting-oriented returned {resp.status if resp else 'none'}"
    )
    authed_page.wait_for_load_state("networkidle")

    assert authed_page.locator(".sparc-guide-content").count() == 1

    # The embedded screenshot is served in-app from /help/images/… and loads.
    img = authed_page.locator(".sparc-guide-content img").first
    assert img.count() == 1, "expected at least one screenshot in the guide"
    src = img.get_attribute("src") or ""
    assert "/help/images/" in src, f"image not rewritten to in-app route: {src}"
    natural_width = img.evaluate("el => el.naturalWidth")
    assert natural_width > 0, "guide screenshot failed to load (naturalWidth 0)"

    assert_no_csp_violations(authed_page, during="guide render")
