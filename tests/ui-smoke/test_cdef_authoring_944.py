"""A component definition must be authorable and editable in the UI (#944).

`CdefDocumentsController` had `new`/`create` but no `edit` and no `update`, and
`create` was unconditionally an upload handler — so the only way a CDEF entered
SPARC was as a file someone else had authored. Worse, `config/routes.rb`
declared a bare `resources :cdef_documents`, so `/cdef_documents/:id/edit`
existed as a route and resolved to an action that did not.

That is precisely the shape page-load coverage misses: the route was in the
routing table the whole time. Only requesting it shows there is nothing behind
it, and only submitting the form shows whether the OSCAL fields can actually be
entered.
"""

from __future__ import annotations

import os
import uuid

import pytest

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

INDEX = "/cdef_documents"
NEW = "/cdef_documents/new"
TYPE_SELECT = "select[name='cdef_document[component_type]']"
SUBMIT = "[data-testid='author-cdef-submit']"


def _first_editable_cdef(page):
    """Path of a CDEF that offers an Edit link, or None.

    AWS-Labs-sourced and published documents are read-only by design, so the
    link is absent on them and this returns None rather than a false failure.
    """
    page.goto(INDEX)
    page.wait_for_load_state("networkidle")
    return page.evaluate(
        """() => {
            const link = [...document.querySelectorAll("a[href*='/cdef_documents/']")]
                .map(a => a.getAttribute("href"))
                .find(h => h && !h.includes("/new") && !h.includes("/edit")
                             && h !== "/cdef_documents");
            return link || null;
        }"""
    )


def test_the_authoring_form_is_offered(authed_page):
    """The new page offers authoring, not only upload."""
    record_csp(authed_page)
    authed_page.goto(NEW)
    authed_page.wait_for_load_state("networkidle")

    body = authed_page.locator("body").inner_text()
    assert "Author a Component Definition" in body, (
        "the new-CDEF page offers no way to author one — it is still upload-only"
    )

    assert authed_page.locator(TYPE_SELECT).count() > 0, (
        "the component type field is missing, so OSCAL's required `type` still "
        "has nowhere to be entered"
    )

    assert_no_csp_violations(authed_page, during="CDEF authoring form render")


def test_authoring_a_component_definition_end_to_end(authed_page, base_url):
    """Create one with no file at all and land on its page.

    Cleans up after itself. An authored component definition starts with NO
    controls, and a CDEF with no controls cannot produce valid OSCAL — so
    leaving one behind puts it at the top of the index and makes
    `test_document_exports` fail on a document this test created. A smoke test
    that breaks three other tests is worse than no smoke test.
    """
    record_csp(authed_page)
    authed_page.goto(NEW)
    authed_page.wait_for_load_state("networkidle")

    if authed_page.locator(SUBMIT).count() == 0:
        pytest.skip("current user cannot author CDEFs on this deployment")

    # Unique per run. A fixed name collides on `slug` with anything a previous
    # run left behind, and the create then fails for a reason that has nothing
    # to do with what this test is checking — which is exactly how it failed
    # once cleanup did not fire.
    name = f"UI Smoke Authored Component {uuid.uuid4().hex[:8]}"
    authed_page.fill("input[name='cdef_document[name]']", name)
    authed_page.select_option(TYPE_SELECT, "service")
    authed_page.fill("input[name='cdef_document[component_title]']", "Smoke Component")

    # Wait for the NAVIGATION, not just the load state. `wait_for_load_state`
    # can return before the redirect lands, leaving `page.url` on /new and
    # making a create that actually succeeded look like it never happened.
    with authed_page.expect_navigation(wait_until="networkidle"):
        authed_page.click(SUBMIT)

    try:
        # Assert on the URL, not on body prose: the landing page's wording is
        # not what this test is about, and the slug is unambiguous.
        assert "/cdef_documents/" in authed_page.url and "/new" not in authed_page.url, (
            f"submit did not land on the authored document (url={authed_page.url!r}) — "
            "create still went down the upload path"
        )
        body = authed_page.locator("body").inner_text()
        assert name in body, (
            f"landed on {authed_page.url!r} but {name!r} is not on the page; a document "
            "left in a non-completed state renders the processing view instead"
        )
        assert_no_csp_violations(authed_page, during="CDEF authoring submit")
    finally:
        _delete_authored(authed_page, base_url)


def _delete_authored(page, base_url):
    """Remove the document this test created, whatever the assertions did.

    Deleted through the API rather than the web route: a non-GET to the web app
    needs an authenticity token this request context does not carry, whereas the
    bearer token needs no CSRF. Failures are ignored — cleanup must never turn
    into a second reported failure on top of a real one.
    """
    slug = page.url.rstrip("/").split("/")[-1]
    if not slug or slug in ("new", "cdef_documents"):
        return

    token = os.environ.get("SPARC_SMOKE_SA_TOKEN")
    if not token:
        return

    page.request.delete(
        f"{base_url}/api/v1/cdef_documents/{slug}",
        headers={"Authorization": f"Bearer {token}"},
        fail_on_status_code=False,
    )


def test_the_edit_route_resolves_to_a_real_screen(authed_page):
    """The route existed and resolved to an action that did not."""
    record_csp(authed_page)
    path = _first_editable_cdef(authed_page)
    if not path:
        pytest.skip("no component definition seeded on this deployment")

    authed_page.goto(path)
    authed_page.wait_for_load_state("networkidle")

    edit_link = authed_page.locator("[data-testid='edit-cdef']")
    if edit_link.count() == 0:
        pytest.skip("this CDEF is read-only (AWS Labs or published), so Edit is absent by design")

    edit_link.first.click()
    authed_page.wait_for_load_state("networkidle")

    assert "/edit" in authed_page.url, "the Edit control did not navigate to the edit screen"
    assert authed_page.locator(TYPE_SELECT).count() > 0, (
        "the edit screen rendered without the component fields it exists to edit"
    )

    assert_no_csp_violations(authed_page, during="CDEF edit navigation")
