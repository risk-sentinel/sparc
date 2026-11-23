"""UI smoke: the received-document viewer (#1390 part G).

Owner decisions, 2026-11-23: the change list is the default tab when there is
a compared version; side by side, this version and the compared version are
the other tabs; "Compare with" any other version of the same document; a
version that failed validation says what is wrong and what is needed, can be
responded to and never accepted; questions asked about places in the document
go with Respond and are exported (Markdown, JSON) to share out of band.

A person's path, in Chrome: upload the sample package's Vulnerability Detail
Report, accept it, upload its second version
(spec/fixtures/files/fedramp/viewer), read the change list, switch tabs, ask
about a change, respond, download the review; then upload the blank-field
variant, compare it with another version, and ask the provider to fix it.

The suite's admin is the break-glass exemption from separation of duties, so
it may decide what it uploads. The boundary is `phase2-ui-*` named
(create_boundary) and removed in teardown through the API.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from _api_setup import create_boundary, delete_doc
from a11y import assert_no_new_a11y_violations
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

ROOT = Path(__file__).resolve().parents[2]
V1 = ROOT / "samples" / "fedramp-package-demo" / "vulnerability-detail-report.json"
V2 = (
    ROOT
    / "spec"
    / "fixtures"
    / "files"
    / "fedramp"
    / "viewer"
    / "vulnerability-detail-report.v2.json"
)
BLANK = ROOT / "samples" / "fedramp-package-demo" / "invalid" / "vdr-blank-required-field.json"


def _boundary_path(boundary) -> str:
    return f"/authorization_boundaries/{boundary.get('slug') or boundary['id']}"


def _upload(page, boundary, path: Path) -> None:
    page.goto(f"{_boundary_path(boundary)}/received_documents")
    page.wait_for_load_state("networkidle")
    form = page.locator("[data-testid='received-upload-form']")
    form.locator("input[type='file']").set_input_files(str(path))
    with page.expect_navigation(wait_until="networkidle"):
        page.locator("[data-testid='received-upload-submit']").click()
    assert re.search(r"/received_documents/\d+$", page.url), (
        f"upload did not open the version: {page.url}"
    )


def _accept(page) -> None:
    page.locator("[data-testid='review-accept']").click()
    confirm = page.locator("#sparc-confirm-modal-confirm")
    confirm.wait_for(state="visible", timeout=5000)
    with page.expect_navigation(wait_until="networkidle"):
        confirm.click()


def _viewer_tab(page) -> str:
    return page.locator("[data-testid='document-viewer']").get_attribute("data-viewer-tab")


VIEWER_TAB_IS = (
    "key => document.querySelector(\"[data-testid='document-viewer']\")?.dataset.viewerTab === key"
)


def _open_tab(page, key: str) -> None:
    page.locator(f"[data-testid='viewer-tab-{key}']").click()
    page.wait_for_function(VIEWER_TAB_IS, arg=key)


def test_viewer_tabs_questions_and_export(authed_page):
    page = authed_page
    record_csp(page)
    boundary = create_boundary()
    try:
        _upload(page, boundary, V1)
        _accept(page)
        _upload(page, boundary, V2)

        assert _viewer_tab(page) == "changes", "the change list is not the default tab"
        changes = page.locator("[data-testid='delta-changes'] tbody tr")
        assert changes.count() >= 3
        assert "ECW-VULN-0014" in page.locator("[data-testid='delta-changes']").inner_text()
        assert_no_new_a11y_violations(page, "received_document_viewer")

        _open_tab(page, "side")
        assert page.locator("[data-testid='viewer-side']").count() == 1
        _open_tab(page, "current")
        doc = page.locator("[data-testid='viewer-document']")
        assert "Removed in this version" in doc.inner_text(), (
            "the dropped vulnerability is not shown"
        )
        _open_tab(page, "compared")
        assert page.locator("[data-testid='viewer-document']").count() == 1
        _open_tab(page, "changes")

        # Ask about the first change, word the question, respond.
        ask = page.locator("[data-testid='delta-changes'] button.sparc-viewer-ask").first
        ask.click()
        assert ask.get_attribute("aria-pressed") == "true"
        tray = page.locator("[data-testid='review-questions'] li")
        assert tray.count() == 1
        tray.first.locator("input").fill("Why did this change?")
        with page.expect_navigation(wait_until="networkidle"):
            page.locator("[data-testid='review-respond']").click()
        recorded = page.locator("[data-testid='review-questions-recorded']")
        assert "Why did this change?" in recorded.inner_text()

        with page.expect_download() as download_info:
            page.locator("[data-testid='review-export-md']").click()
        markdown = Path(download_info.value.path()).read_text()
        assert "## Questions for the provider" in markdown
        assert "Why did this change?" in markdown

        assert_no_csp_violations(page, during="reviewing a second version in the viewer")
    finally:
        delete_doc("authorization_boundaries", boundary.get("slug") or boundary["id"])


def test_invalid_version_guidance_and_compare_with(authed_page):
    page = authed_page
    record_csp(page)
    boundary = create_boundary()
    try:
        _upload(page, boundary, V1)
        _accept(page)
        _upload(page, boundary, V2)
        _accept(page)
        _upload(page, boundary, BLANK)

        assert page.locator("[data-testid='viewer-invalid-banner']").count() == 1
        assert page.locator("[data-testid='review-accept']").count() == 0
        errors = page.locator("[data-testid='validation-errors']").inner_text()
        assert "Vulnerability description is blank." in errors
        assert "FedRAMP's schema requires it." in errors

        page.locator("[data-testid='ask-fix-errors']").click()
        assert page.locator("[data-testid='review-questions'] li").count() >= 1

        # Compare with the earlier accepted version instead of the one in effect.
        select = page.locator("[data-testid='viewer-compare']")
        first_option = select.locator("option").last.get_attribute("value")
        select.select_option(first_option)
        page.locator("[data-testid='viewer-compare-submit']").click()
        page.locator("[data-testid='viewer-compare-banner']").wait_for(
            state="visible", timeout=10000
        )
        assert "not stored" in page.locator("[data-testid='viewer-compare-banner']").inner_text()

        assert page.locator("[data-testid='review-respond']").count() == 1, (
            "an invalid version cannot be answered"
        )
        assert_no_csp_violations(page, during="reviewing an invalid version")
    finally:
        delete_doc("authorization_boundaries", boundary.get("slug") or boundary["id"])
