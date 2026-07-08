"""UI smoke: content-completeness badge + Populate-from-Profile (#627/#628).

An empty CDEF/SSP shows an "Incomplete — needs content" badge and a
"Populate from Profile" card; choosing a published profile imports its controls
and clears the badge. Empty documents are provisioned via the API (SA token),
then the flow is driven in the browser. Selectors verified against
app/views/{cdef,ssp}_documents/{show,attach_profile}.html.erb.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import pytest

from _api_setup import (
    create_boundary,
    create_cdef,
    create_ssp,
    delete_doc,
    published_profile_slug,
)
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

# Exact badge text (em dash) from the show templates.
INCOMPLETE_BADGE = "Incomplete — needs content"


@pytest.fixture
def empty_cdef(session_cookie) -> Iterator[dict[str, Any]]:
    doc = create_cdef()
    try:
        yield doc
    finally:
        delete_doc("cdef_documents", doc["slug"])


@pytest.fixture
def empty_ssp(session_cookie) -> Iterator[dict[str, Any]]:
    boundary = create_boundary()
    doc = create_ssp(boundary["id"])
    try:
        yield doc
    finally:
        delete_doc("ssp_documents", doc["slug"])
        delete_doc("authorization_boundaries", boundary["id"])


def _assert_incomplete_and_populate(page, show_path: str, during: str) -> None:
    record_csp(page)
    resp = page.goto(show_path)
    assert resp and resp.status < 400, f"{during}: {resp.status if resp else 'no response'}"
    page.get_by_text(INCOMPLETE_BADGE).first.wait_for(state="visible", timeout=10_000)
    assert page.get_by_role("link", name="Populate from Profile").is_visible(), (
        f"{during}: 'Populate from Profile' card link missing on empty document"
    )
    assert_no_csp_violations(page, during=during)


class TestPopulateFlow:
    def test_empty_cdef_shows_badge_and_populate_card(self, authed_page, empty_cdef):
        _assert_incomplete_and_populate(
            authed_page, f"/cdef_documents/{empty_cdef['slug']}", "cdef show (empty)"
        )

    def test_empty_ssp_shows_badge_and_populate_card(self, authed_page, empty_ssp):
        _assert_incomplete_and_populate(
            authed_page, f"/ssp_documents/{empty_ssp['slug']}", "ssp show (empty)"
        )

    def test_cdef_attach_profile_page_loads_clean(self, authed_page, empty_cdef):
        record_csp(authed_page)
        authed_page.goto(f"/cdef_documents/{empty_cdef['slug']}")
        authed_page.get_by_role("link", name="Populate from Profile").click()
        authed_page.wait_for_load_state("networkidle")
        assert "/attach_profile" in authed_page.url, (
            f"expected attach_profile page, got {authed_page.url}"
        )
        assert_no_csp_violations(authed_page, during="attach_profile navigation")

    def test_populate_cdef_clears_badge(self, authed_page, empty_cdef):
        if published_profile_slug() is None:
            pytest.skip("no published profile on this instance to populate from")
        record_csp(authed_page)
        authed_page.goto(f"/cdef_documents/{empty_cdef['slug']}/attach_profile")
        authed_page.get_by_role(
            "button", name="Populate from this Profile"
        ).first.click()
        authed_page.wait_for_load_state("networkidle")
        assert_no_csp_violations(authed_page, during="populate submit")
        # Controls imported -> the incomplete badge is gone.
        assert authed_page.get_by_text(INCOMPLETE_BADGE).count() == 0, (
            "incomplete badge still present after populate"
        )
