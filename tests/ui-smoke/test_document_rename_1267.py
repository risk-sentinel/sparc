"""A document can be renamed and re-versioned from its page, and the OSCAL
Metadata form saves what it shows (#1267).

The name/version form on five document pages submitted its fields unwrapped,
so every rename was refused with a 400; the OSCAL Metadata form dropped OSCAL
Version, Published Date and Description while still saying "Document updated".
Nothing caught either: `test_oscal_metadata_edit.py` opens the panels but never
saves, and no check renamed anything.

Each test here saves through the page and then reads the value back from the
page the server renders afterwards.

  - The common route: open a published profile, Create Editable Copy, rename
    the copy and give it a new version before tailoring it.
  - Rename and version change on a draft CDEF, SSP, SAP and SAR.
  - OSCAL Version, Published Date and Description on a draft profile and a
    draft catalog.

POA&M's form always worked and has no API fixture; the request spec covers it.

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise.
"""

from __future__ import annotations

import re
import time
import uuid
from urllib.parse import urlparse

import pytest

from _api_setup import (
    create_boundary,
    create_catalog,
    create_cdef,
    create_profile,
    create_sap,
    create_sar,
    create_ssp,
    delete_doc,
    published_profile_slug,
)
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

DESCRIPTION = "phase2-ui metadata saved through the page"

# The forms are found by the containers the pages have always had, and the
# name/version inputs by position, so this check runs unchanged against a build
# from before the fix and fails there on the bug itself, not on a selector.
NAME_FORM = "#doc-meta-edit form"
METADATA_FORM = "#oscal-meta-edit-section form"


def _name_field(form):
    return form.locator('input[type="text"]').nth(0)


def _version_field(form):
    return form.locator('input[type="text"]').nth(1)


def _save_and_follow(page, button, label: str, *, follow: bool = True) -> None:
    """Click a metadata form's save button, and wait for the save itself.

    The forms submit through Turbo: the click returns at once, the PATCH and
    the redirect's page load happen after it. Reading the page straight after
    the click read the OLD page, on a fixed build and on a broken one alike.
    So wait for the update_metadata response, refuse an error status (a broken
    form answers 400), then wait for the page the redirect names.
    """
    with page.expect_response(
        lambda r: "/update_metadata" in r.url and r.request.method == "POST", timeout=15000
    ) as info:
        button.click()
    response = info.value
    assert response.status in (302, 303), (
        f"{label}: the save was answered {response.status}, not a redirect to the saved document"
    )
    if not follow:
        # The response is in, so the save is committed; the caller reloads.
        return
    target = urlparse(response.headers.get("location", "")).path
    page.wait_for_url(lambda url: urlparse(url).path == target, timeout=15000)
    page.wait_for_load_state("networkidle")


def _rename(page, label: str, new_name: str, new_version: str) -> None:
    """Open the header editor, type a new name and version, and save."""
    # The header's Edit button; the form's own Cancel shares the action.
    page.get_by_role("button", name="Edit", exact=True).and_(
        page.locator('[data-action="doc-meta#toggle"]')
    ).first.click()
    form = page.locator(NAME_FORM)
    form.wait_for(state="visible", timeout=5000)
    _name_field(form).fill(new_name)
    _version_field(form).fill(new_version)
    _save_and_follow(page, form.get_by_role("button", name="Save"), label)
    assert_no_csp_violations(page, during=f"{label} rename")


def _assert_renamed(page, label: str, resource: str, new_name: str, new_version: str) -> str:
    """The server's page after the save shows the new name and version.
    Returns the document's new slug, which follows the name."""
    slug_prefix = re.sub(r"[^a-z0-9]+", "-", new_name.lower()).strip("-")
    path = page.url.split("?")[0].rstrip("/")
    assert f"/{resource}/{slug_prefix}" in path, (
        f"{label}: after the rename the page is {page.url}, not the renamed document"
    )
    assert page.locator(".sparc-header-title").filter(has_text=new_name).count() > 0, (
        f"{label}: the renamed page does not show '{new_name}'"
    )
    form = page.locator(NAME_FORM)
    assert _name_field(form).input_value() == new_name, f"{label}: name not saved"
    assert _version_field(form).input_value() == new_version, f"{label}: version not saved"
    return path.rsplit("/", 1)[-1]


def test_copy_of_published_profile_can_be_renamed_and_reversioned(authed_page):
    source = published_profile_slug()
    if source is None:
        pytest.skip("no published profile on this instance to copy")
    page = authed_page
    record_csp(page)

    page.goto(f"/profile_documents/{source}")
    page.wait_for_load_state("networkidle")
    page.get_by_role("button", name="Create Editable Copy").click()
    confirm = page.locator("#sparc-confirm-modal-confirm")
    confirm.wait_for(state="visible", timeout=5000)
    started = time.monotonic()
    confirm.click()
    # Copying a NIST baseline duplicates every control and field in the one
    # request; under memory pressure that has taken over 15 seconds. The time is
    # printed, so a slow copy shows in the log rather than hiding in the limit.
    page.wait_for_url(lambda url: f"/profile_documents/{source}" not in url, timeout=60000)
    print(f"Create Editable Copy of {source}: {time.monotonic() - started:.1f}s")
    page.wait_for_load_state("networkidle")
    copy_slug = page.url.split("?")[0].rstrip("/").rsplit("/", 1)[-1]
    assert_no_csp_violations(page, during="create editable copy")

    new_name = f"phase2-ui-renamed-copy-{uuid.uuid4().hex[:8]}"
    try:
        _rename(page, "profile copy", new_name, "2.0.0")
        copy_slug = _assert_renamed(page, "profile copy", "profile_documents", new_name, "2.0.0")
    finally:
        delete_doc("profile_documents", copy_slug)


def _boundary_doc(kind: str, boundary_id: int) -> dict:
    return {"ssp": create_ssp, "sap": create_sap, "sar": create_sar}[kind](boundary_id)


@pytest.mark.parametrize("kind", ["cdef", "ssp", "sap", "sar"])
def test_document_can_be_renamed_and_reversioned(authed_page, kind):
    page = authed_page
    record_csp(page)
    resource = f"{kind}_documents"
    boundary = None
    if kind == "cdef":
        doc = create_cdef(with_controls=False)
    else:
        boundary = create_boundary()
        doc = _boundary_doc(kind, boundary["id"])
    slug = doc["slug"]
    new_name = f"phase2-ui-renamed-{kind}-{uuid.uuid4().hex[:8]}"
    try:
        page.goto(f"/{resource}/{slug}")
        page.wait_for_load_state("networkidle")
        _rename(page, kind, new_name, "3.1")
        slug = _assert_renamed(page, kind, resource, new_name, "3.1")
    finally:
        delete_doc(resource, slug)
        if boundary is not None:
            delete_doc("authorization_boundaries", boundary["slug"])


@pytest.mark.parametrize("kind", ["profile", "control_catalog"])
def test_oscal_metadata_form_saves_its_fields(authed_page, kind):
    page = authed_page
    record_csp(page)
    resource = f"{kind}s" if kind == "control_catalog" else "profile_documents"
    doc = create_catalog() if kind == "control_catalog" else create_profile()
    ident = doc["slug"]
    try:
        page.goto(f"/{resource}/{ident}")
        page.wait_for_load_state("networkidle")
        page.locator('[data-controller="oscal-metadata"] .card-header').first.click()
        form = page.locator(METADATA_FORM)
        form.wait_for(state="visible", timeout=5000)
        form.get_by_label("OSCAL Version").fill("1.1.3")
        form.get_by_label("Published Date").fill("2026-10-01T00:00:00Z")
        form.get_by_label("Description").fill(DESCRIPTION)
        # The page is not followed: a catalog's redirect goes on to its UUID
        # address, so the URL never equals the one the save names.
        _save_and_follow(page, form.get_by_role("button", name="Save Metadata"), kind, follow=False)
        assert_no_csp_violations(page, during=f"{kind} metadata save")

        # Read back from a fresh load of the document, not the page we typed into.
        page.goto(f"/{resource}/{ident}")
        page.wait_for_load_state("networkidle")
        form = page.locator(METADATA_FORM)
        expected = {
            "OSCAL Version": "1.1.3",
            "Published Date": "2026-10-01T00:00:00Z",
            "Description": DESCRIPTION,
        }
        for label, value in expected.items():
            assert form.get_by_label(label).input_value() == value, f"{kind}: {label} not saved"
    finally:
        delete_doc(resource, ident)
