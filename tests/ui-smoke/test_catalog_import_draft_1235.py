"""#1235 — an uploaded catalog lands as Draft and is published through Publish.

Before, `CatalogImportService` set every import to Published before its quality
warnings were even computed, so an uploaded catalog was read-only, trusted
content the moment it landed: the user could not correct what the warnings
pointed at, and the approval gate never applied.

This drives the real upload through the screen and checks:

  1. the catalog is a Draft (the API reports `in_progress`, and Publish is
     offered on the page);
  2. the Publish dialog lists the import's warnings as advisory;
  3. publishing goes through the publish action: when document approval is
     required the unapproved catalog is refused and stays Draft, otherwise it is
     published.

The uploaded catalog is generated per run with a fresh UUID, so the import can
never resolve to a catalog that already exists, and it is deleted afterwards.
"""

from __future__ import annotations

import json
import time
import uuid

import pytest

from _api_setup import delete_doc, get_json
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

IMPORT_PATH = "/control_catalogs/import"
# The job runs in the background; a two-control catalog takes seconds.
IMPORT_TIMEOUT_S = 90


def _catalog_json(title: str) -> bytes:
    """Two controls, one with no statement, so the import raises a warning."""
    return json.dumps({
        "catalog": {
            "uuid": str(uuid.uuid4()),
            "metadata": {
                "title": title,
                "last-modified": "2026-10-21T00:00:00Z",
                "version": "1.0",
                "oscal-version": "1.2.3",
            },
            "groups": [{
                "id": "zz",
                "class": "family",
                "title": "Smoke Family",
                "controls": [
                    {"id": "zz-1", "class": "SP800-53", "title": "Has a statement",
                     "parts": [{"id": "zz-1_smt", "name": "statement",
                                "prose": "The organization does the thing."}]},
                    {"id": "zz-2", "class": "SP800-53", "title": "Has no statement"},
                ],
            }],
        }
    }).encode()


def _wait_for_import(catalog_ref: str) -> dict:
    deadline = time.monotonic() + IMPORT_TIMEOUT_S
    while True:
        data = get_json(f"/api/v1/control_catalogs/{catalog_ref}")
        if data.get("status") in ("completed", "failed") or time.monotonic() > deadline:
            return data
        time.sleep(2)


def _dismiss_import_warnings(page) -> None:
    """The generated catalog always raises a warning, so the warnings modal
    opens (animated) on first view; wait for it, dismiss it, and wait until its
    backdrop is gone, or it intercepts every click behind it."""
    ack = page.get_by_role("button", name="Acknowledge & Dismiss")
    ack.wait_for(state="visible", timeout=10_000)
    ack.click()
    page.locator(".modal-backdrop").wait_for(state="detached", timeout=10_000)


@pytest.fixture
def uploaded_catalog(authed_page):
    page = authed_page
    name = f"phase2-ui-catalog1235-{uuid.uuid4().hex[:8]}"
    record_csp(page)

    page.goto(IMPORT_PATH)
    page.set_input_files(
        "input[type=file][name='catalog_file']",
        files=[{"name": f"{name}.json", "mimeType": "application/json",
                "buffer": _catalog_json(name)}],
    )
    with page.expect_navigation():
        page.get_by_role("button", name="Import Catalog").click()
    ref = page.url.rstrip("/").split("/")[-1].split("?")[0]
    assert ref != "import", f"the upload was not accepted; still on {page.url}"

    data = _wait_for_import(ref)
    try:
        yield page, ref, data
    finally:
        delete_doc("control_catalogs", data.get("id") or ref)


def test_an_uploaded_catalog_is_a_draft_with_advisory_warnings(uploaded_catalog):
    page, ref, data = uploaded_catalog

    assert data["status"] == "completed", f"import did not complete: {data.get('status')}"
    assert data["lifecycle_status"] == "in_progress", (
        f"an uploaded catalog must land as Draft, got {data['lifecycle_status']!r}"
    )

    page.reload()
    _dismiss_import_warnings(page)

    page.get_by_role("button", name="Publish", exact=True).click()
    advisory = page.get_by_test_id("publish-advisory-warnings")
    advisory.wait_for(state="visible")
    items = advisory.locator("li").all_text_contents()
    assert any("statement" in t.lower() for t in items), (
        f"the publish dialog should list the missing-statement warning, got {items}"
    )
    assert not any("priority" in t.lower() or "baseline impact" in t.lower() for t in items), (
        f"a catalog is not checked for priority or baseline impact (#1235), got {items}"
    )
    assert_no_csp_violations(page)


def test_publishing_an_uploaded_catalog_goes_through_publish(uploaded_catalog):
    page, ref, data = uploaded_catalog
    assert data["status"] == "completed"

    readiness = page.request.get(
        f"/control_catalogs/{ref}/publish_check", headers={"Accept": "application/json"}
    ).json()

    page.reload()
    _dismiss_import_warnings(page)
    page.get_by_role("button", name="Publish", exact=True).click()
    page.locator("[data-publish-modal-target='publishBtn']").click()
    page.wait_for_load_state("load")

    after = get_json(f"/api/v1/control_catalogs/{ref}")
    if readiness.get("approval_required"):
        # Both directions of the gate: unapproved stays Draft and says why.
        assert after["lifecycle_status"] == "in_progress", (
            "an unapproved catalog must not publish while approval is required"
        )
        assert "approved" in page.content().lower()
    else:
        assert after["lifecycle_status"] == "published"
    assert_no_csp_violations(page)
