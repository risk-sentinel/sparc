"""OSCAL metadata + back-matter edit interaction smoke (#645, epic #650).

The #645 blocker: on Profile and Control Catalog show pages, the OSCAL metadata
and back-matter panels could not be edited because their controls relied on
inline on* handlers that strict CSP (script-src :self, no 'unsafe-inline')
silently blocks. The panels rendered, but every button was inert.

These tests drive the actual interactions — expand the panel, add a metadata
row, toggle a back-matter edit row — and assert BOTH that the DOM reacts AND
that zero CSP violations fire on the click. Render-time checks can't catch this
class of bug; only clicking can.

Discovers a Profile / Catalog show page at runtime from its index and skips
when the deployment has no draft record with editable panels.

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, first_show_href, record_csp

pytestmark = pytest.mark.authenticated

# (label, index_path, show_prefix). Document URLs are slug-based (FriendlyId),
# e.g. /profile_documents/test or /control_catalogs/<slug> — NOT numeric ids.
EDITABLE_DOCS = [
    ("profile", "/profile_documents", "/profile_documents"),
    ("control_catalog", "/control_catalogs", "/control_catalogs"),
]


def _first_show_href(page, index_path, prefix):
    return first_show_href(page, index_path, prefix)


@pytest.mark.parametrize(
    "label,index_path,pattern", EDITABLE_DOCS, ids=[d[0] for d in EDITABLE_DOCS]
)
def test_oscal_metadata_panel_interacts_without_csp_violation(
    authed_page, label, index_path, pattern
):
    record_csp(authed_page)
    href = _first_show_href(authed_page, index_path, pattern)
    if not href:
        pytest.skip(f"no {label} record to exercise")

    authed_page.goto(href)
    authed_page.wait_for_load_state("networkidle")

    card = authed_page.locator('[data-controller="oscal-metadata"]')
    if card.count() == 0:
        pytest.skip(f"{label}: no OSCAL metadata panel rendered")

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
    add_role = authed_page.locator('[data-action="oscal-metadata#addRole"]')
    if add_role.count() == 0:
        pytest.skip(f"{label}: metadata not editable (non-draft) — expand-only check")

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
    "label,index_path,pattern", EDITABLE_DOCS, ids=[d[0] for d in EDITABLE_DOCS]
)
def test_oscal_back_matter_panel_interacts_without_csp_violation(
    authed_page, label, index_path, pattern
):
    record_csp(authed_page)
    href = _first_show_href(authed_page, index_path, pattern)
    if not href:
        pytest.skip(f"no {label} record to exercise")

    authed_page.goto(href)
    authed_page.wait_for_load_state("networkidle")

    card = authed_page.locator('[data-controller="oscal-back-matter"]')
    if card.count() == 0:
        pytest.skip(f"{label}: no OSCAL back-matter panel rendered")

    body = authed_page.locator("#oscal-back-matter-body")
    card.locator(".card-header").first.click()
    authed_page.wait_for_timeout(150)
    assert "d-none" not in (body.get_attribute("class") or ""), (
        f"{label}: back-matter panel did not expand on header click"
    )
    assert_no_csp_violations(authed_page, during=f"{label} back-matter expand")

    # Per-resource Edit toggle only exists when a draft has a managed resource.
    edit_btn = authed_page.locator('[data-action="oscal-back-matter#toggleEdit"]')
    if edit_btn.count() == 0:
        pytest.skip(f"{label}: no editable managed resource — expand-only check")

    rid = edit_btn.first.get_attribute("data-oscal-back-matter-resource-id-param")
    edit_row = authed_page.locator(f"#edit-resource-{rid}")
    edit_btn.first.click()
    authed_page.wait_for_timeout(150)
    assert "d-none" not in (edit_row.get_attribute("class") or ""), (
        f"{label}: Edit did not reveal the back-matter edit row"
    )
    assert_no_csp_violations(authed_page, during=f"{label} back-matter edit toggle")
