"""Changing an SSP's baseline, in the browser (#1330).

The SSP page offers Change baseline. The author chooses another published
baseline, sees what the change does (controls added, kept for their answers,
removed), and confirms it; the SSP page then says what was done. Zero CSP
violations throughout.

The SSP is made for this test, through the API, and deleted after it.
"""

from __future__ import annotations

import pytest

import _api_setup as api
from helpers import assert_no_csp_violations, record_csp


def _published_profiles() -> list[dict]:
    data = api.get_json("/api/v1/profile_documents?items=100")
    return [p for p in data if (p.get("lifecycle_status") or p.get("status")) == "published"]


@pytest.fixture
def ssp_on_one_baseline():
    profiles = _published_profiles()
    if len(profiles) < 2:
        pytest.skip("needs two published baselines to change between")
    boundary = api.create_boundary()
    ssp = api.create_ssp(boundary["id"])
    api.post_json(f"/api/v1/ssp_documents/{ssp['slug']}/populate_from_profile",
                  {"source_profile_id": profiles[0]["id"]})
    yield ssp, profiles[1]
    api.delete_doc("ssp_documents", ssp["slug"])
    api.delete_doc("authorization_boundaries", boundary["id"])


def test_change_baseline_after_seeing_what_changes(authed_page, ssp_on_one_baseline):
    ssp, target = ssp_on_one_baseline
    page = authed_page
    record_csp(page)

    page.goto(f"/ssp_documents/{ssp['slug']}")
    page.wait_for_load_state("networkidle")
    page.locator("[data-testid=change-baseline-link]").click()
    # Turbo swaps the page in after the click returns: wait for it.
    page.wait_for_url("**/change_baseline")

    page.locator("[data-testid=baseline-choice]").select_option(value=str(target["id"]))
    page.locator("[data-testid=preview-baseline-change]").click()
    page.wait_for_url(f"**/change_baseline?profile_document_id={target['id']}*")

    delta = page.locator("[data-testid=baseline-delta]")
    assert delta.is_visible(), "the delta was not shown before confirming"
    for part in ("delta-added", "delta-unchanged", "delta-kept", "delta-removed"):
        assert delta.locator(f"[data-testid={part}]").count() == 1, f"the delta does not say {part}"

    confirm = page.locator("[data-testid=confirm-baseline-change]")
    confirm.locator("button, input[type=submit]").first.click()
    page.wait_for_url(f"**/ssp_documents/{ssp['slug']}")
    flash = page.locator(".flash-container").inner_text()
    assert f"Baseline changed to '{target['name']}'" in flash, flash
    assert_no_csp_violations(page, during="ssp baseline change")
