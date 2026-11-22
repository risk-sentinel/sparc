"""#1390 — the FedRAMP package overview fields on the boundary edit form, in a browser.

Turns FedRAMP on, fills every field the FedRAMP Certification Package Overview requires, adds
its Security and Sales contacts with the form's "+ Add contact" control (the
Stimulus repeater), saves, then downloads the overview from the triage page's
FedRAMP card and checks it is SPARC's FedRAMP overview. Every step checks for
CSP violations.

Works on a throwaway boundary made through the API and removed afterwards.
"""

from __future__ import annotations

import json

import pytest

from _api_setup import create_boundary, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

FIELDS = {
    "package_id": "FR2400000001",
    "provider_name": "Example Provider",
    "service_name": "Example Cloud",
    "service_acronym": "EXC",
    "service_description": "Created by the ui-smoke suite (#1390).",
    "website": "https://provider.example",
    "logo": "https://provider.example/logo.png",
}


@pytest.fixture
def boundary():
    b = create_boundary()
    try:
        yield b
    finally:
        delete_doc("authorization_boundaries", b["slug"])


def _field(page, key: str):
    return page.locator(f"#authorization_boundary_fedramp_package_{key}")


def test_overview_fields_saved_and_overview_downloaded(authed_page, base_url, boundary):
    page = authed_page
    record_csp(page)
    page.goto(f"{base_url}/authorization_boundaries/{boundary['slug']}/edit")

    section = page.locator("[data-testid='boundary-fedramp-package']")
    assert section.count() == 1, (
        "the FedRAMP package overview section is missing from the edit form"
    )
    section.locator("summary").click()

    page.locator("#authorization_boundary_fedramp_enabled").check()
    for key, value in FIELDS.items():
        _field(page, key).fill(value)
    _field(page, "certification_type").select_option("20x")
    _field(page, "deployment_model").select_option("Public Cloud")
    page.locator("#authorization_boundary_fedramp_package_service_types_saas").check()

    add = section.locator("[data-testid='boundary-fedramp-add-contact']")
    rows = section.locator(
        "[data-oscal-repeater-target='rows'] [data-testid='boundary-fedramp-contact']"
    )
    for i, (kind, email) in enumerate(
        (("Security", "security@provider.example"), ("Sales", "sales@provider.example"))
    ):
        add.click()
        row = rows.nth(i)
        row.locator("select").select_option(kind)
        row.locator("input[type='email']").fill(email)
    assert rows.count() == 2, f"expected 2 contact rows after adding two, found {rows.count()}"
    assert_no_csp_violations(page, during="FedRAMP package overview fields (filling)")

    section.locator("xpath=ancestor::form").locator("input[type='submit']").click()
    # Under Turbo, networkidle can settle before the redirect is followed; wait
    # for the boundary page itself.
    page.wait_for_url(f"**/authorization_boundaries/{boundary['slug']}", timeout=15000)

    page.goto(f"{base_url}/authorization_boundaries/{boundary['slug']}/triage")
    card = page.locator("[data-testid='triage-fedramp-reports']")
    link = card.locator("[data-testid='triage-download-fedramp-overview']")
    assert link.count() == 1, "no overview download after every required field was saved"
    with page.expect_download() as download_info:
        link.click()
    download = download_info.value
    assert download.suggested_filename.endswith("fedramp-package-overview.json"), (
        download.suggested_filename
    )
    with open(download.path(), encoding="utf-8") as f:
        doc = json.load(f)
    assert doc["$schema"].endswith("fedramp-certification-package-overview-schema-2026-06-24.json")
    assert doc["serviceIdentification"]["serviceName"] == "Example Cloud"
    assert {c["contactType"] for c in doc["contactInformation"]} == {"Security", "Sales"}
    assert_no_csp_violations(page, during="FedRAMP package overview download")
