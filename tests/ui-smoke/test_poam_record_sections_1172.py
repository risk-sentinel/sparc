"""UI smoke: the POA&M page reaches every record it holds (v1.17.2).

Risks, remediations, observations, findings and components each get a section
below the items, with Edit and Delete. A risk is resolved with Close (a required
note, recorded in its OSCAL risk log) and Reopen; a remediation with Mark
completed. Before this, an unlinked risk appeared nowhere on the page.

The test makes its own risk and remediation through the API, clicks through
Close, Reopen, Mark completed, Edit and Delete, and removes whatever is left in
a ``finally``.

Selectors verified against app/views/poam_documents/_record_sections.html.erb.
"""

from __future__ import annotations

import os
import uuid

import pytest
from playwright.sync_api import expect

import helpers
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


def _row(page, section_key, title):
    section = page.get_by_test_id(f"poam-section-{section_key}")
    if section.get_attribute("open") is None:
        section.locator("summary").first.click()
    return section.get_by_test_id("poam-record-row").filter(has_text=title)


def test_poam_page_edits_resolves_and_deletes_records(authed_page, base_url):
    token = os.environ.get("SPARC_SMOKE_SA_TOKEN")
    if not token:
        pytest.skip("SPARC_SMOKE_SA_TOKEN not set — cannot create and clean up test records")
    headers = {"Authorization": f"Bearer {token}"}

    page = authed_page
    record_csp(page)
    href = helpers.first_show_href(page, "/poam_documents", "/poam_documents")
    if not href:
        pytest.skip("no POA&M on this deployment — nothing to exercise")
    slug = href.rstrip("/").split("/")[-1]
    title = f"Smoke section risk {uuid.uuid4().hex[:8]}"

    created = page.request.post(
        f"{base_url}/api/v1/poam_documents/{slug}/risks",
        headers=headers,
        data={
            "poam_risk": {
                "title": title,
                "description": "Created by the v1.17.2 smoke test.",
                "statement": "Asset X has weakness Y allowing Z.",
                "status": "open",
                "deadline": "2027-06-30",
            }
        },
    )
    assert created.status == 201, created.text()
    risk_id = created.json()["data"]["id"]
    deleted = False

    try:
        rem = page.request.post(
            f"{base_url}/api/v1/poam_documents/{slug}/remediations",
            headers=headers,
            data={
                "poam_remediation": {
                    "title": f"{title} fix",
                    "description": "Apply the vendor patch.",
                    "lifecycle": "planned",
                    "poam_risk_id": risk_id,
                }
            },
        )
        assert rem.status == 201, rem.text()

        page.goto(f"{base_url}{href}")
        page.wait_for_load_state("domcontentloaded")

        # The risk is linked to no item, and is listed anyway.
        row = _row(page, "risks", title)
        expect(row).to_have_count(1)

        # Close, with the required note.
        row.get_by_test_id("close-risk").locator("summary").click()
        row.get_by_label("Closing note").fill("Patched; verified by rescan.")
        row.get_by_role("button", name="Close risk").click()
        expect(page.get_by_text(f'Risk "{title}" closed')).to_be_visible()
        row = _row(page, "risks", title)
        expect(row.locator(".sparc-tag-outline", has_text="closed")).to_be_visible()

        # Reopen, with its own note.
        row.get_by_test_id("reopen-risk").locator("summary").click()
        row.get_by_label("Reopening note").fill("Regressed in the next build.")
        row.get_by_role("button", name="Reopen risk").click()
        expect(page.get_by_text(f'Risk "{title}" reopened')).to_be_visible()

        # Mark the remediation completed.
        rem_row = _row(page, "remediations", f"{title} fix")
        rem_row.get_by_role("button", name="Mark completed").click()
        expect(page.get_by_text("marked completed")).to_be_visible()
        rem_row = _row(page, "remediations", f"{title} fix")
        expect(rem_row.get_by_role("button", name="Mark completed")).to_have_count(0)

        # Edit reaches the risk's form.
        _row(page, "risks", title).get_by_role("link", name="Edit").click()
        page.wait_for_url(f"**/poam_risks/{risk_id}/edit")
        expect(page.get_by_label("Title", exact=True)).to_have_value(title)
        page.go_back()
        page.wait_for_load_state("domcontentloaded")

        # Delete, accepting the confirmation that names what goes with it.
        messages = []

        def _accept(dialog):
            messages.append(dialog.message)
            dialog.accept()

        page.once("dialog", _accept)
        _row(page, "risks", title).get_by_role("button", name="Delete").click()
        expect(page.get_by_text(f'Risk "{title}" removed')).to_be_visible()
        deleted = True
        assert messages and "Close it instead" in messages[0], messages

        assert_no_csp_violations(page, during="editing, resolving and deleting POA&M records")
    finally:
        if not deleted:
            page.request.delete(
                f"{base_url}/api/v1/poam_risks/{risk_id}",
                headers=headers,
                fail_on_status_code=False,
            )
