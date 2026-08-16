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


def test_authoring_a_component_definition_end_to_end(authed_page):
    """Create one with no file at all and land on its page."""
    record_csp(authed_page)
    authed_page.goto(NEW)
    authed_page.wait_for_load_state("networkidle")

    if authed_page.locator(SUBMIT).count() == 0:
        pytest.skip("current user cannot author CDEFs on this deployment")

    name = "UI Smoke Authored Component"
    authed_page.fill("input[name='cdef_document[name]']", name)
    authed_page.select_option(TYPE_SELECT, "service")
    authed_page.fill("input[name='cdef_document[component_title]']", "Smoke Component")

    authed_page.click(SUBMIT)
    authed_page.wait_for_load_state("networkidle")

    body = authed_page.locator("body").inner_text()
    assert name in body, (
        f"authored component definition {name!r} did not appear after submit — "
        "create still went down the upload path"
    )

    assert_no_csp_violations(authed_page, during="CDEF authoring submit")


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
