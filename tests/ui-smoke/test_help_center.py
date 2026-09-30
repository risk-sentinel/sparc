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


# #1154 bundle — the three guides that gained screenshots of new screens must
# render in-app WITH those screenshots (issue_rules step 8). Both directions:
# each named image loads, and an unknown guide or image is refused, not served.
GUIDES_WITH_NEW_SCREENS = [
    ("authorization-boundaries",
     ["boundary-decision-dates.png", "boundary-multiple-ssp-warning.png"], "Next decision date"),
    ("poam", ["poam-risk-decision-fields.png"], "Reopen trigger"),
    ("system-security-plans", ["ssp-repair-banner.png"], "Link to a boundary"),
]


@pytest.mark.parametrize(("slug", "images", "text"), GUIDES_WITH_NEW_SCREENS,
                         ids=[g[0] for g in GUIDES_WITH_NEW_SCREENS])
def test_updated_guide_renders_its_new_screenshots(authed_page, slug, images, text):
    record_csp(authed_page)
    resp = authed_page.goto(f"/help/{slug}")
    assert resp is not None and resp.status < 400, f"/help/{slug} returned {resp and resp.status}"
    authed_page.wait_for_load_state("networkidle")

    content = authed_page.locator(".sparc-guide-content")
    assert text in content.inner_text(), f"/help/{slug} does not carry the new text {text!r}"
    for name in images:
        img = content.locator(f"img[src*='{name}']")
        assert img.count() == 1, f"/help/{slug} does not embed {name}"
        src = img.get_attribute("src") or ""
        assert "/help/images/" in src
        # Guide images are loading="lazy" (UserGuideLibrary): one far down the
        # page is not fetched until a reader scrolls to it, so look at it the way
        # a reader does before judging whether it loaded.
        img.scroll_into_view_if_needed()
        img.evaluate("el => el.decode ? el.decode().catch(() => null) : null")
        assert img.evaluate("el => el.complete && el.naturalWidth") > 0, (
            f"{name} failed to load on /help/{slug}"
        )
        served = authed_page.request.get(src)
        content_type = served.headers.get("content-type", "")
        assert served.status == 200 and content_type.startswith("image/png"), (
            f"{src} served {served.status} {content_type}"
        )
    assert_no_csp_violations(authed_page, during=f"guide {slug}")


def test_an_unknown_guide_and_an_unknown_image_are_refused(authed_page):
    guide = authed_page.goto("/help/no-such-guide-1154")
    assert guide is not None and guide.status == 404, (
        f"unknown guide answered {guide and guide.status}"
    )
    image = authed_page.request.get("/help/images/no-such-image-1154.png")
    assert image.status == 404, f"unknown image answered {image.status}"
