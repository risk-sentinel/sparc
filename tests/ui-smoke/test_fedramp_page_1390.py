"""#1390 — the boundary's FedRAMP page, in a browser.

Reaches it the way a user does (the boundary's More menu), answers one
FedRAMP rule and one KSI (adding a KSI evidence row with the Stimulus
repeater), sees each answer's status after saving, and downloads the
Security Decision Record carrying them. Every step checks for CSP violations.

Works on a throwaway boundary made through the API, with FedRAMP on, a 20x
Program Class B profile and an overview address, removed afterwards.
"""

from __future__ import annotations

import json

import pytest

from _api_setup import create_boundary, delete_doc, patch_json
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


@pytest.fixture
def boundary():
    b = create_boundary()
    try:
        r = patch_json(
            f"/api/v1/authorization_boundaries/{b['slug']}",
            {
                "authorization_boundary": {
                    "fedramp_enabled": True,
                    "fedramp_package_overview_uri": "https://provider.example/cpo.json",
                    "fedramp_package": {
                        "certification_type": "20x",
                        "certification_path": "Program",
                        "certification_class": "B",
                    },
                }
            },
        )
        assert r.status_code == 200, r.text
        yield b
    finally:
        delete_doc("authorization_boundaries", b["slug"])


def _answer(page, rule_id: str, status: str, text: str) -> None:
    entry = page.locator(f"[data-testid='fedramp-entry'][data-fedramp-rule='{rule_id}']")
    assert entry.count() == 1, f"{rule_id} is not listed on the FedRAMP page"
    entry.locator("summary").click()
    entry.locator(f"#fedramp_{rule_id}_status").select_option(status)
    entry.locator(f"#fedramp_{rule_id}_implementation").fill(text)


def test_fedramp_page_answers_and_sdr(authed_page, base_url, boundary):
    page = authed_page
    record_csp(page)
    page.goto(f"{base_url}/authorization_boundaries/{boundary['slug']}", wait_until="networkidle")
    page.locator("[data-boundary-action='more']").click()
    page.locator("[data-boundary-action='fedramp']").click()
    page.wait_for_url("**/fedramp", timeout=10000)
    page.get_by_role("heading", name="FedRAMP", exact=True).wait_for(timeout=10000)

    _answer(page, "SDR-CSO-FRR", "Implemented", "SPARC writes the record from these answers.")
    page.locator("[data-fedramp-rule='SDR-CSO-FRR'] [data-testid='fedramp-entry-save']").click()
    page.get_by_text("Saved SDR-CSO-FRR.").wait_for(timeout=10000)
    status = page.locator("[data-fedramp-rule='SDR-CSO-FRR'] [data-testid='fedramp-entry-status']")
    assert status.inner_text().strip() == "Implemented", status.inner_text()

    page.locator("[data-testid='fedramp-tab-ksi']").click()
    page.wait_for_url("**kind=ksi**", timeout=10000)
    _answer(page, "KSI-CED-RAT", "Partially Implemented", "Training is reviewed each quarter.")
    ksi = page.locator("[data-fedramp-rule='KSI-CED-RAT']")
    ksi.get_by_role("button", name="+ Add evidence").click()
    row = ksi.locator("[data-oscal-repeater-target='rows'] [data-testid='fedramp-evidence-row']")
    assert row.count() == 1, "the evidence repeater added no row"
    row.locator("select").select_option("Report")
    row.locator("input[aria-label='Evidence description']").fill("LMS completion report")
    ksi.locator("[data-testid='fedramp-entry-save']").click()
    page.get_by_text("Saved KSI-CED-RAT.").wait_for(timeout=10000)
    assert_no_csp_violations(page, during="FedRAMP page answers")

    with page.expect_download() as download_info:
        page.locator("[data-testid='fedramp-download-sdr']").click()
    download = download_info.value
    assert download.suggested_filename.endswith("fedramp-sdr.json"), download.suggested_filename
    with open(download.path(), encoding="utf-8") as f:
        doc = json.load(f)
    assert [r["frrID"] for r in doc["fedRampRequirements"]] == ["SDR-CSO-FRR"]
    ksi_entry = doc["keySecurityIndicators"][0]
    assert ksi_entry["ksiId"] == "KSI-CED-RAT"
    assert ksi_entry["ksiEvidence"][0]["evidenceDescription"] == "LMS completion report"
    assert doc["metadata"]["version"] == "2", doc["metadata"]
    assert_no_csp_violations(page, during="FedRAMP SDR download")
