"""UI smoke: the risk forms author every OSCAL risk field the API accepts (v1.17.2).

* The SAR enrich risk card gains Deadline and Remediations.
* The POA&M risk form gains Threat IDs and Mitigating Factors, through the
  same section the SAR card uses (``shared/_risk_oscal_collections``).

The SAR check is interaction only: it adds rows and does not save, because
saving the enrich form rewrites the whole seeded SAR. The POA&M check is a full
round trip on a risk it creates and then deletes through the API:
1. a non-URI threat ID is refused, with the message and the typed title kept;
2. the corrected risk saves;
3. the edit screen shows what was stored.

Selectors verified against app/views/sar_documents/enrich.html.erb,
app/views/shared/_risk_oscal_collections.html.erb and
app/views/poam_risks/_form.html.erb.
"""

from __future__ import annotations

import os
import uuid

import pytest
from playwright.sync_api import expect

import helpers
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

THREAT_SYSTEM = "https://attack.mitre.org"
THREAT_ID = "https://attack.mitre.org/techniques/T1078"
REFUSAL = "A threat ID needs its system and its ID as full URIs"


def test_sar_risk_card_offers_deadline_and_remediations(authed_page, base_url):
    page = authed_page
    record_csp(page)
    href = helpers.first_show_href(page, "/sar_documents", "/sar_documents")
    if not href:
        pytest.skip("no SAR document on this deployment — nothing to exercise")
    page.goto(f"{base_url}{href}/enrich")
    page.wait_for_load_state("domcontentloaded")

    page.locator("summary", has_text="Risks (").first.click()

    # The add-risk template carries the deadline too, so a new risk gets one.
    page.get_by_role("button", name="+ Add Risk").click()
    card = page.locator("#risks-container .risk-entry").last
    expect(card.get_by_label("Risk Deadline")).to_be_visible()

    card.locator("details summary").click()
    remediations = card.get_by_test_id("risk-remediations")
    before = remediations.locator(".repeater-row").count()
    remediations.get_by_role("button", name="+ Add remediation").click()
    rows = remediations.locator(".repeater-row")
    expect(rows).to_have_count(before + 1)

    lifecycle = rows.last.get_by_label("Remediation lifecycle")
    assert lifecycle.locator("option").all_text_contents() == [
        "Recommendation",
        "Planned",
        "Completed",
    ]

    assert_no_csp_violations(page, during="adding a risk and a remediation on the enrich screen")


def _find_risk_id(page, base_url, slug, title, token):
    headers = {"Authorization": f"Bearer {token}"}
    first = page.request.get(f"{base_url}/api/v1/poam_documents/{slug}/risks", headers=headers)
    assert first.ok, first.text()
    pages = first.json()["meta"]["pages"] or 1
    # Ordered by id, so a risk created just now is on the last page.
    last = page.request.get(
        f"{base_url}/api/v1/poam_documents/{slug}/risks?page={pages}", headers=headers
    )
    for risk in last.json()["data"]:
        if risk["title"] == title:
            return risk["id"]
    return None


def _fill_required(page, title):
    page.get_by_label("Title", exact=True).fill(title)
    page.get_by_label("Description", exact=True).fill("Created by the v1.17.2 smoke test.")
    page.get_by_label("Statement", exact=True).fill("Asset X has weakness Y allowing Z.")
    page.locator("select[name='poam_risk[status]']").select_option("open")
    page.locator("select[name='poam_risk[impact]']").select_option("high")
    page.locator("select[name='poam_risk[likelihood]']").select_option("moderate")
    page.locator("input[name='poam_risk[deadline]']").fill("2027-06-30")


def test_poam_risk_form_authors_threat_ids_and_mitigating_factors(authed_page, base_url):
    token = os.environ.get("SPARC_SMOKE_SA_TOKEN")
    if not token:
        pytest.skip("SPARC_SMOKE_SA_TOKEN not set — cannot clean up the risk this test creates")

    page = authed_page
    record_csp(page)
    href = helpers.first_show_href(page, "/poam_documents", "/poam_documents")
    if not href:
        pytest.skip("no POA&M on this deployment — nothing to exercise")
    slug = href.rstrip("/").split("/")[-1]
    title = f"Smoke risk {uuid.uuid4().hex[:8]}"
    risk_id = None

    try:
        page.goto(f"{base_url}{href}/poam_risks/new")
        page.wait_for_load_state("domcontentloaded")
        _fill_required(page, title)

        section = page.get_by_test_id("poam-risk-collections")
        section.locator("summary").click()
        section.get_by_role("button", name="+ Add threat ID").click()
        section.get_by_label("Threat ID system").last.fill(THREAT_SYSTEM)
        section.get_by_label("Threat ID", exact=True).last.fill("T1078")
        section.get_by_role("button", name="+ Add mitigating factor").click()
        section.get_by_label("Mitigating factor description").last.fill("MFA on every account")

        # 1. A bare code is refused, and the title typed survives.
        page.get_by_role("button", name="Add Risk").click()
        refusal = page.get_by_text(REFUSAL)
        expect(refusal).to_be_visible()
        expect(page.get_by_label("Title", exact=True)).to_have_value(title)

        # 2. Corrected, it saves. The refused rows are not kept, so add them again.
        section = page.get_by_test_id("poam-risk-collections")
        section.locator("summary").click()
        section.get_by_role("button", name="+ Add threat ID").click()
        section.get_by_label("Threat ID system").last.fill(THREAT_SYSTEM)
        section.get_by_label("Threat ID", exact=True).last.fill(THREAT_ID)
        section.get_by_role("button", name="+ Add mitigating factor").click()
        section.get_by_label("Mitigating factor description").last.fill("MFA on every account")
        _fill_required(page, title)
        page.get_by_role("button", name="Add Risk").click()
        page.wait_for_url(f"**{href}")
        expect(page.get_by_text("Risk added")).to_be_visible()

        # 3. What was stored is what the edit screen shows.
        risk_id = _find_risk_id(page, base_url, slug, title, token)
        assert risk_id, f"the saved risk {title!r} was not found through the API"
        page.goto(f"{base_url}{href}/poam_risks/{risk_id}/edit")
        page.wait_for_load_state("domcontentloaded")
        section = page.get_by_test_id("poam-risk-collections")
        section.locator("summary").click()
        expect(section.get_by_label("Threat ID", exact=True).first).to_have_value(THREAT_ID)
        expect(section.get_by_label("Mitigating factor description").first).to_have_value(
            "MFA on every account"
        )

        assert_no_csp_violations(page, during="authoring a POA&M risk's threat IDs and factors")
    finally:
        if risk_id is None:
            risk_id = _find_risk_id(page, base_url, slug, title, token)
        if risk_id:
            page.request.delete(
                f"{base_url}/api/v1/poam_risks/{risk_id}",
                headers={"Authorization": f"Bearer {token}"},
                fail_on_status_code=False,
            )
