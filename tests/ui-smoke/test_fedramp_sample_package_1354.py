"""UI smoke: the FedRAMP sample package through Received documents (#1354).

samples/fedramp-package-demo/ is a fictional provider's complete package;
invalid/ holds variants that each fail one documented way (see the
manifests there). This drops the package's Vulnerability Detail Report and
its blank-required-field variant on a boundary's Received documents
dropzone, as a person would, and reads what the page says about each: the
valid one waits for review, the invalid one is stored with its error shown
and no Accept.

The boundary is `phase2-ui-*` named (create_boundary) and removed in
teardown through the API, which removes what it received.

Selectors verified against app/views/received_documents/*.html.erb, as in
test_connections_received_documents_1354.py.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

from _api_setup import create_boundary, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

PACKAGE = Path(__file__).resolve().parents[2] / "samples" / "fedramp-package-demo"
VALID_VDR = PACKAGE / "vulnerability-detail-report.json"
BLANK_VDR = PACKAGE / "invalid" / "vdr-blank-required-field.json"


def _expected_error() -> dict:
    manifest = json.loads((PACKAGE / "invalid" / "manifest.json").read_text())
    entry = next(d for d in manifest["documents"] if d["file"] == BLANK_VDR.name)
    return entry["expected_errors"][0]


def _boundary_path(boundary) -> str:
    """Boundary pages are addressed by slug; the numeric id is a 404."""
    return f"/authorization_boundaries/{boundary.get('slug') or boundary['id']}"


def _upload(page, boundary, path: Path) -> None:
    """Upload through the dropzone on the boundary's Received documents page."""
    page.goto(f"{_boundary_path(boundary)}/received_documents")
    page.wait_for_load_state("networkidle")
    form = page.locator("[data-testid='received-upload-form']")
    assert form.count() == 1, "the upload card is not offered to an exchange.upload holder"
    form.locator("input[type='file']").set_input_files(str(path))
    with page.expect_navigation(wait_until="networkidle"):
        page.locator("[data-testid='received-upload-submit']").click()
    assert re.search(r"/received_documents/\d+$", page.url), (
        f"upload did not open the version: {page.url}"
    )


def test_sample_package_vdr_valid_and_blank_field(authed_page):
    page = authed_page
    record_csp(page)
    boundary = create_boundary()
    try:
        _upload(page, boundary, VALID_VDR)
        metadata = page.locator("[data-testid='received-metadata']").inner_text()
        assert "Pending review" in metadata
        assert VALID_VDR.name in metadata, "the File row does not name the uploaded sample"
        assert "vulnerability-detail-report" in page.locator("h1").first.inner_text()
        assert page.locator("[data-testid='validation-errors']").count() == 0

        expected = _expected_error()
        _upload(page, boundary, BLANK_VDR)
        assert "Invalid" in page.locator("[data-testid='received-metadata']").inner_text()
        errors = page.locator("[data-testid='validation-errors']")
        assert errors.count() == 1, "the invalid version's errors are not shown"
        assert expected["pointer"] in errors.inner_text()
        assert expected["message"] in errors.inner_text()
        assert page.locator("[data-testid='review-accept']").count() == 0, (
            "an invalid version is offered for acceptance"
        )
        assert_no_csp_violations(page, during="uploading the FedRAMP sample package")
    finally:
        delete_doc("authorization_boundaries", boundary.get("slug") or boundary["id"])
