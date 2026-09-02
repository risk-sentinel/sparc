"""UI smoke: the SAR show page keeps a route into the enrich screen (#1093).

The link to ``/sar_documents/:slug/enrich`` used to be wrapped in
``unless @sar_document.enriched?``, so it vanished the moment the document WAS
enriched — the screen was reachable exactly once, and after the first save the
only way back was to type the URL. That is backwards for a screen whose purpose
is iterative: #1090 had just added Statement, Impact and Likelihood to that form
and no already-enriched SAR could reach them.

This is the interaction check for that control. It is deliberately NOT a
render-only assertion: an inline-handler / CSP breakage on a link or its
surrounding action bar only manifests on click, which is the whole reason the
repo requires a click-through here.

The demo seed enriches its SARs (they carry results), so the seeded instance
exercises the state that used to hide the control — which is the case worth
covering. The label is asserted loosely (``Enrich`` is a substring of
``Edit Enrichment``) so this does not become a copy test.

Selectors verified against app/views/sar_documents/show.html.erb.
"""

from __future__ import annotations

import pytest
from playwright.sync_api import expect

import helpers
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

ENRICH_LINK = "a[href$='/enrich']"


def _first_sar(page):
    # index_path twice, and RELATIVE: hrefs on the page are relative, so an
    # absolute prefix never matches. Must be the AUTHENTICATED page — an
    # anonymous one redirects to /login, finds no document links, and the test
    # SKIPS while looking like it ran.
    href = helpers.first_show_href(page, "/sar_documents", "/sar_documents")
    if not href:
        pytest.skip("no SAR document on this deployment — nothing to exercise")
    return href


def test_sar_show_offers_a_route_into_enrich(authed_page, base_url):
    page = authed_page
    record_csp(page)
    href = _first_sar(page)
    page.goto(f"{base_url}{href}")
    page.wait_for_load_state("networkidle")

    link = page.locator(ENRICH_LINK).first
    expect(link).to_be_visible()

    # Either state is acceptable — what must NOT happen is the control being
    # absent. Before #1093 an enriched SAR rendered no enrich link at all.
    label = link.inner_text().strip()
    assert "Enrich" in label, f"expected an enrich route, got {label!r}"

    assert_no_csp_violations(page, during="loading the SAR show page")


def test_clicking_it_reaches_the_enrich_screen_cleanly(authed_page, base_url):
    page = authed_page
    record_csp(page)
    href = _first_sar(page)
    page.goto(f"{base_url}{href}")
    page.wait_for_load_state("networkidle")

    helpers.click_and_assert_clean(page, ENRICH_LINK, during="clicking the enrich link")

    # WAIT FOR THE URL, not for a load state. `click_and_assert_clean` clicks and
    # returns; it does not await navigation, so reading `page.url` straight after
    # reads the OLD page. The first version of this test failed exactly that way
    # and the #968 diagnostics named it: "1 request(s) still in flight ...
    # PENDING .../enrich".
    #
    # `networkidle` is the wrong wait here too. The enrich screen is ~31,000 css
    # px with 150 findings, and per #1087 every page's `load` waits on
    # cdn.jsdelivr.net, so idle may never arrive. The harness's own `_settle`
    # treats it as best-effort for the same reason.
    page.wait_for_url("**/enrich", timeout=60000)

    assert page.url.endswith("/enrich"), f"expected the enrich screen, landed on {page.url}"
    # The enrich screen keeps four of its five sections in a collapsed
    # <details>, so assert on something outside them rather than on a field.
    expect(page.locator("details").first).to_be_attached()
    assert_no_csp_violations(page, during="the enrich screen after navigation")
