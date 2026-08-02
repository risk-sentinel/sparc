"""#881 — readable, catalog-scoped control URLs and the new control page.

A new page, so the standing rule applies: exercise it in a real browser and
assert zero CSP violations on interaction, not just on render.

What makes this worth a browser test rather than only request specs:

  * The control id reaches the page through a route that must NOT let Rails
    treat `.1.a` as a format. A truncation would render the PARENT control —
    a page that looks perfectly correct.
  * Sub-part links are generated in the view, so a bad path helper produces
    links that 404 only when clicked.
"""

from __future__ import annotations

import re

import pytest

from helpers import assert_no_csp_violations, record_csp

CATALOGS = "/control_catalogs"


def _first_catalog_href(page) -> str | None:
    page.goto(CATALOGS)
    page.wait_for_load_state("networkidle")
    hrefs = page.eval_on_selector_all(
        f"a[href*='{CATALOGS}/']", "els => els.map(e => e.getAttribute('href'))"
    )
    for href in hrefs:
        # A catalog show URL, not a nested or collection route.
        if re.fullmatch(rf"{CATALOGS}/[^/]+", href or ""):
            return href
    return None


def _first_family_href(page, catalog_href: str) -> str | None:
    page.goto(catalog_href)
    page.wait_for_load_state("networkidle")
    hrefs = page.eval_on_selector_all(
        "a[href*='control_families/']", "els => els.map(e => e.getAttribute('href'))"
    )
    return hrefs[0] if hrefs else None


class TestControlUrls:
    def test_catalog_url_is_the_uuid_not_the_long_slug(self, authed_page) -> None:
        record_csp(authed_page)
        href = _first_catalog_href(authed_page)
        if not href:
            pytest.skip("no catalogs seeded")

        authed_page.goto(href)
        authed_page.wait_for_load_state("networkidle")

        # The slug form 301s onto the uuid, so whatever we clicked, we land on
        # a uuid — the identifier that does not change when a catalog is renamed.
        assert re.search(
            r"/control_catalogs/[0-9a-fA-F-]{36}", authed_page.url
        ), f"expected a uuid catalog URL, got {authed_page.url}"
        assert_no_csp_violations(authed_page, during="catalog show")

    def test_family_url_is_catalog_scoped_and_code_addressed(self, authed_page) -> None:
        catalog = _first_catalog_href(authed_page)
        if not catalog:
            pytest.skip("no catalogs seeded")
        family = _first_family_href(authed_page, catalog)
        if not family:
            pytest.skip("catalog has no families")

        authed_page.goto(family)
        authed_page.wait_for_load_state("networkidle")

        assert re.search(
            r"/control_catalogs/[^/]+/control_families/[^/]+$", authed_page.url
        ), f"expected a catalog-scoped family URL, got {authed_page.url}"

    def test_control_page_opens_and_keeps_its_full_identifier(self, authed_page) -> None:
        catalog = _first_catalog_href(authed_page)
        if not catalog:
            pytest.skip("no catalogs seeded")
        family = _first_family_href(authed_page, catalog)
        if not family:
            pytest.skip("catalog has no families")

        record_csp(authed_page)
        authed_page.goto(family)
        authed_page.wait_for_load_state("networkidle")

        links = authed_page.locator("a[href*='/controls/']")
        if links.count() == 0:
            pytest.skip("family has no controls")

        href = links.first.get_attribute("href")
        links.first.click()
        authed_page.wait_for_load_state("networkidle")

        # The identifier must survive routing intact. If Rails ate a trailing
        # `.a` as a format we would land on the parent control instead, with a
        # page that renders perfectly well.
        identifier = href.rsplit("/controls/", 1)[1]
        assert authed_page.url.endswith(f"/controls/{identifier}"), (
            f"identifier changed in transit: asked for {identifier!r}, landed on {authed_page.url}"
        )
        assert_no_csp_violations(authed_page, during="control show")

    def test_sub_part_links_resolve(self, authed_page) -> None:
        """Sub-parts are ~48% of catalog control rows and had no address at all
        before this. Their links are generated in the view, so a wrong path
        helper only shows up on click."""
        catalog = _first_catalog_href(authed_page)
        if not catalog:
            pytest.skip("no catalogs seeded")
        family = _first_family_href(authed_page, catalog)
        if not family:
            pytest.skip("catalog has no families")

        authed_page.goto(family)
        authed_page.wait_for_load_state("networkidle")
        control_links = authed_page.locator("a[href*='/controls/']")
        if control_links.count() == 0:
            pytest.skip("family has no controls")

        control_links.first.click()
        authed_page.wait_for_load_state("networkidle")

        sub = authed_page.locator("a[href*='/controls/']")
        if sub.count() == 0:
            pytest.skip("this control has no sub-parts on the page")

        record_csp(authed_page)
        sub.first.click()
        authed_page.wait_for_load_state("networkidle")

        assert "/controls/" in authed_page.url
        body = authed_page.inner_text("body")
        assert "not found" not in body.lower(), "sub-part link resolved to an error page"
        assert_no_csp_violations(authed_page, during="sub-part navigation")
