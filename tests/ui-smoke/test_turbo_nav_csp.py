"""Turbo-navigation CSP smoke (#528 / #712).

The rest of the suite navigates with ``page.goto()`` — a FULL document load,
whose inline <script>s carry that page's fresh CSP nonce and never violate. But
real users navigate via **Turbo Drive** (link clicks / form submits): Turbo
fetches + swaps the <body> WITHOUT reloading the document, and re-executes the
new body's inline <script>s by *cloning* them — and clones lose their
per-request CSP nonce, tripping a ``script-src-elem`` violation under the
enforced CSP (no 'unsafe-inline').

That entire class shipped undetected until #712, precisely because the suite
only did full loads. This module drives Turbo navigation to the pages that
carried body inline scripts (now refactored to Stimulus, #528) and asserts zero
CSP violations — the regression guard for the class.
"""

from __future__ import annotations

import pytest

from helpers import (
    assert_no_csp_violations,
    csp_violations,
    first_show_href,
    record_csp,
    turbo_visit,
)

pytestmark = pytest.mark.authenticated

# Form pages that carried body inline <script>s (static paths, no record needed):
# sap_documents/new (ssp→profile autofill) and cdef_documents/new (scope picker).
FORM_PAGES = ["/sap_documents/new", "/cdef_documents/new"]

# Show pages that carried body inline <script>s (arrow toggles / data-quality
# card / heatmap) — discovered from their index at runtime.
SHOW_INDEXES = [
    ("profile_show", "/profile_documents"),
    ("cdef_show", "/cdef_documents"),
    ("sar_show", "/sar_documents"),
    ("ssp_show", "/ssp_documents"),
    ("sap_show", "/sap_documents"),
    ("control_catalog_show", "/control_catalogs"),
]


class TestTurboNavCSP:
    @pytest.mark.parametrize("path", FORM_PAGES)
    def test_turbo_visit_form_page_is_csp_clean(self, authed_page, path):
        record_csp(authed_page)
        authed_page.goto("/")  # one full load; Turbo Drive owns navigation after
        authed_page.wait_for_load_state("networkidle")
        turbo_visit(authed_page, path)
        assert_no_csp_violations(authed_page, during=f"Turbo nav to {path}")

    @pytest.mark.parametrize(
        "name,index", SHOW_INDEXES, ids=[n for n, _ in SHOW_INDEXES]
    )
    def test_turbo_visit_show_page_is_csp_clean(self, authed_page, name, index):
        record_csp(authed_page)
        href = first_show_href(authed_page, index, index)  # lands on the index
        if not href:
            pytest.skip(f"no {name} record to Turbo-navigate to")
        turbo_visit(authed_page, href)  # index -> show, via Turbo
        assert_no_csp_violations(authed_page, during=f"Turbo nav to {href}")

    def test_turbo_link_click_is_csp_clean(self, authed_page):
        """A real <a> click (Turbo intercepts same-origin links) is CSP-clean —
        the most user-realistic navigation."""
        record_csp(authed_page)
        resp = authed_page.goto("/cdef_documents")
        assert resp and resp.status < 400
        authed_page.wait_for_load_state("networkidle")
        link = authed_page.locator(
            "a[href^='/cdef_documents/']:not([href$='/new'])"
        ).first
        if link.count() == 0:
            pytest.skip("no cdef link to click")
        href = link.get_attribute("href")
        link.click()
        authed_page.wait_for_url(f"**{href}", timeout=10_000)
        authed_page.wait_for_load_state("networkidle")
        assert not csp_violations(authed_page), (
            f"CSP violations after link-click to {href}: "
            f"{csp_violations(authed_page)}"
        )
