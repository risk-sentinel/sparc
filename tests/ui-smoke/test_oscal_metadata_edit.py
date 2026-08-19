"""OSCAL metadata + back-matter edit interaction smoke (#645, epic #650).

The #645 blocker: on Profile and Control Catalog show pages, the OSCAL metadata
and back-matter panels could not be edited because their controls relied on
inline on* handlers that strict CSP (script-src :self, no 'unsafe-inline')
silently blocks. The panels rendered, but every button was inert.

These tests drive the actual interactions — expand the panel, add a metadata
row, toggle a back-matter edit row — and assert BOTH that the DOM reacts AND
that zero CSP violations fire on the click. Render-time checks can't catch this
class of bug; only clicking can.

Each case creates its OWN draft record and deletes it afterwards. It used to
take whatever was first on the index, which on any real deployment is a
PUBLISHED document — so the interaction half of every test skipped itself
("non-draft — expand-only check") while the file still reported as passing, and
scanning a large index for a candidate is what made it time out under load. A
fixture the test owns is draft by construction, reachable by a known URL, and
never depends on what the deployment happens to contain.

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise.
"""

from __future__ import annotations

import pytest

from _api_setup import (
    create_back_matter_resource,
    create_catalog,
    create_profile,
    delete_doc,
)
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

# (label, resource, factory, resourceable_type). Document URLs are slug-based.
EDITABLE_DOCS = [
    ("profile", "profile_documents", create_profile, "ProfileDocument"),
    ("control_catalog", "control_catalogs", create_catalog, "ControlCatalog"),
]


@pytest.fixture
def draft_doc(request):
    """A draft record of the parametrized type, carrying one managed
    back-matter resource, removed afterwards.

    The resource is created deliberately: a fresh draft has none, so the
    per-resource Edit toggle never rendered and the back-matter test skipped the
    interaction it exists to exercise.
    """
    _label, resource, factory, resourceable_type = request.param
    doc = factory()
    try:
        create_back_matter_resource(resourceable_type, doc["id"])
        yield f"/{resource}/{doc['slug']}"
    finally:
        delete_doc(resource, doc["slug"])


@pytest.mark.parametrize(
    "draft_doc", EDITABLE_DOCS, ids=[d[0] for d in EDITABLE_DOCS], indirect=True
)
def test_oscal_metadata_panel_interacts_without_csp_violation(authed_page, draft_doc):
    label = draft_doc.split("/")[1]
    record_csp(authed_page)
    href = draft_doc

    authed_page.goto(href)
    authed_page.wait_for_load_state("networkidle")

    card = authed_page.locator('[data-controller="oscal-metadata"]')
    assert card.count() > 0, f"{label}: no OSCAL metadata panel on a draft this test created"

    # Expand the panel — the header toggle is the first inline handler that
    # CSP used to block.
    body = authed_page.locator("#oscal-meta-body")
    card.locator(".card-header").first.click()
    authed_page.wait_for_timeout(150)
    assert "d-none" not in (body.get_attribute("class") or ""), (
        f"{label}: metadata panel did not expand on header click"
    )
    assert_no_csp_violations(authed_page, during=f"{label} metadata expand")

    # Add Role only renders for draft docs the user can edit. Skip otherwise.
    # No skip here any more. The fixture is a DRAFT this test created, so the
    # editor must render; its absence is a regression, not a deployment state.
    add_role = authed_page.locator('[data-action="oscal-metadata#addRole"]')
    assert add_role.count() > 0, (
        f"{label}: '+ Add Role' is absent on a draft this test created — "
        "the metadata editor did not render for an editable document"
    )

    before = authed_page.locator("#roles-editor .role-row").count()
    add_role.first.click()
    authed_page.wait_for_timeout(150)
    after = authed_page.locator("#roles-editor .role-row").count()
    assert after == before + 1, (
        f"{label}: '+ Add Role' did not add a row ({before} -> {after})"
    )
    assert_no_csp_violations(authed_page, during=f"{label} add role")

    # Remove the row we just added.
    authed_page.locator("#roles-editor .role-row").last.locator(
        '[data-action="oscal-metadata#removeRow"]'
    ).click()
    authed_page.wait_for_timeout(150)
    assert authed_page.locator("#roles-editor .role-row").count() == before, (
        f"{label}: removeRow did not remove the added row"
    )
    assert_no_csp_violations(authed_page, during=f"{label} remove role")


@pytest.mark.parametrize(
    "draft_doc", EDITABLE_DOCS, ids=[d[0] for d in EDITABLE_DOCS], indirect=True
)
def test_oscal_back_matter_panel_interacts_without_csp_violation(authed_page, draft_doc):
    label = draft_doc.split("/")[1]
    record_csp(authed_page)
    href = draft_doc

    authed_page.goto(href)
    authed_page.wait_for_load_state("networkidle")

    card = authed_page.locator('[data-controller="oscal-back-matter"]')
    assert card.count() > 0, f"{label}: no OSCAL back-matter panel on a draft this test created"

    body = authed_page.locator("#oscal-back-matter-body")
    card.locator(".card-header").first.click()
    authed_page.wait_for_timeout(150)
    assert "d-none" not in (body.get_attribute("class") or ""), (
        f"{label}: back-matter panel did not expand on header click"
    )
    assert_no_csp_violations(authed_page, during=f"{label} back-matter expand")

    # The fixture created a managed resource on this draft, so the per-resource
    # Edit toggle must render. Skipping here is what let the interaction half of
    # this test stop running while the file still reported as passing.
    edit_btn = authed_page.locator('[data-action="oscal-back-matter#toggleEdit"]')
    assert edit_btn.count() > 0, (
        f"{label}: no Edit toggle for the managed back-matter resource this test created"
    )

    rid = edit_btn.first.get_attribute("data-oscal-back-matter-resource-id-param")
    edit_row = authed_page.locator(f"#edit-resource-{rid}")
    edit_btn.first.click()
    authed_page.wait_for_timeout(150)
    assert "d-none" not in (edit_row.get_attribute("class") or ""), (
        f"{label}: Edit did not reveal the back-matter edit row"
    )
    assert_no_csp_violations(authed_page, during=f"{label} back-matter edit toggle")
