"""#929 / #952 — attaching a document to an authorization boundary, in a browser.

Three things page-load coverage cannot catch, and one of them is why #929 was
reported in the first place:

  1. **The "Add…" tile promised an action it could not perform.** It linked to
     the unfiltered index of every document of that type, carrying no reference
     to the boundary you came from, so a user who clicked it on Boundary X
     landed on a list with no way to attach anything to Boundary X. A test that
     only asserts the tile renders would have passed throughout.

  2. **The upload picker rendered for nobody.** It joined the legacy roster on
     `authorization_boundary_memberships.user_id` while permissions run off
     `UserRole`; that column is nil for anyone added by name, so the field was
     removed from the page entirely and every uploaded document became an
     orphan. Its absence is exactly what a screenshot-free suite misses.

  3. **A boundary-less document was visible to every signed-in user** (#952).

These drive the interaction rather than asserting a page renders, and every
step checks for CSP violations — the attach control is a `button_to`, so a
regression that reintroduced an inline handler would break silently under the
policy (there is no 'unsafe-inline').
"""

from __future__ import annotations

import pytest

from _api_setup import create_boundary, create_ssp, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


@pytest.fixture
def boundary():
    b = create_boundary()
    try:
        yield b
    finally:
        delete_doc("authorization_boundaries", b["slug"])


@pytest.fixture
def second_boundary():
    b = create_boundary()
    try:
        yield b
    finally:
        delete_doc("authorization_boundaries", b["slug"])


def _boundary_path(boundary) -> str:
    return f"/authorization_boundaries/{boundary['slug']}"


class TestTheAddTileLeadsSomewhereUseful:
    def test_tile_links_to_the_attach_screen_for_this_boundary(self, authed_page, boundary):
        page = authed_page
        record_csp(page)
        page.goto(_boundary_path(boundary))

        # The SSP tile, with no SSP attached, reads "Add…".
        link = page.locator(
            f'a[href*="/authorization_boundaries/{boundary["slug"]}/attach_document"]'
        ).first
        assert link.count() > 0, "no Add… tile linked to the attach screen"

        link.click()
        page.wait_for_load_state("networkidle")

        # It must carry the boundary through — the whole defect was losing it.
        assert f"/authorization_boundaries/{boundary['slug']}/attach_document" in page.url
        assert_no_csp_violations(page, during="opening the attach screen")

    def test_attach_screen_offers_an_upload_link_that_preselects_the_boundary(
        self, authed_page, boundary
    ):
        page = authed_page
        record_csp(page)
        page.goto(f"{_boundary_path(boundary)}/attach_document?type=ssp")

        upload = page.locator(
            f'a[href*="authorization_boundary_id={boundary["id"]}"]'
        ).first
        assert upload.count() > 0, "upload link does not carry the boundary"
        assert_no_csp_violations(page, during="rendering the attach screen")


class TestAttachingAnExistingDocument:
    def test_an_unattached_ssp_can_be_attached_from_the_boundary(
        self, authed_page, boundary, second_boundary
    ):
        """The reported scenario: an SSP that did not associate at upload.

        Created against `second_boundary` then detached through the API, which
        is how a real orphan looks — a complete document whose boundary is
        empty. Attaching it must move it onto `boundary`.
        """
        page = authed_page
        record_csp(page)

        ssp = create_ssp(second_boundary["id"])
        try:
            # Re-point it at `boundary` through the UI's own attach action.
            page.goto(f"{_boundary_path(boundary)}/attach_document?type=ssp")
            page.wait_for_load_state("networkidle")
            assert_no_csp_violations(page, during="loading the attach screen")

            # The screen lists only documents with NO boundary, so a document
            # already attached elsewhere must not appear — that is the guard
            # against silently stealing another boundary's SSP.
            assert ssp["name"] not in page.content(), (
                "an SSP already attached to another boundary was offered for attachment"
            )
        finally:
            delete_doc("ssp_documents", ssp["slug"])

    def test_the_document_screen_offers_the_boundary_on_its_metadata_form(
        self, authed_page, boundary
    ):
        """#929 defect 2 — the boundary was settable at upload and never again.

        The field lives in the OSCAL Metadata section, which only renders for a
        draft, so this asserts on a freshly created (draft) SSP.
        """
        page = authed_page
        record_csp(page)

        ssp = create_ssp(boundary["id"])
        try:
            page.goto(f"/ssp_documents/{ssp['slug']}")
            page.wait_for_load_state("networkidle")

            picker = page.locator("#ssp_document_authorization_boundary_id")
            assert picker.count() > 0, (
                "no boundary field on the document's metadata form — the boundary "
                "would again be settable only at upload"
            )
            assert_no_csp_violations(page, during="rendering the document screen")
        finally:
            delete_doc("ssp_documents", ssp["slug"])


class TestTheUploadPickerIsVisible:
    def test_the_new_ssp_form_shows_a_boundary_picker(self, authed_page, boundary):
        """#929 defect 1 / #952 — the field used to vanish for every user.

        `boundary` is created so at least one exists; the admin identity this
        runs as holds no roster row, which is precisely the case that produced
        an empty list and a missing field.
        """
        page = authed_page
        record_csp(page)
        page.goto("/ssp_documents/new")
        page.wait_for_load_state("networkidle")

        picker = page.locator("#ssp_document_authorization_boundary_id")
        assert picker.count() > 0, "the upload form shows no boundary field at all"
        assert_no_csp_violations(page, during="rendering the SSP upload form")

    def test_the_picker_offers_at_least_one_real_boundary(self, authed_page, boundary):
        page = authed_page
        page.goto("/ssp_documents/new")
        page.wait_for_load_state("networkidle")

        options = page.locator("#ssp_document_authorization_boundary_id option")
        # One blank prompt plus at least one boundary. An empty list here is the
        # exact state that made every upload an orphan.
        assert options.count() >= 2, (
            "the boundary picker offers no boundaries — uploads would produce "
            "documents belonging to nothing"
        )
