"""Bringing an SSP up to its own baseline, in the browser (#1337).

An SSP that names a baseline but lacks some of its controls (an import, or a
baseline declared afterwards) is offered Bring up to baseline on its page. The
author sees how many controls and items will be added, confirms, and lands
back on the SSP page, which says what was added and no longer offers the
action. Zero CSP violations throughout.

The SSP is made for this test, through the API: it names a published
baseline and holds none of its controls. It is deleted after the test.
"""

from __future__ import annotations

import re

import pytest

import _api_setup as api
from helpers import assert_no_csp_violations, record_csp


@pytest.fixture
def ssp_short_of_baseline():
    boundary = api.create_boundary()
    ssp = api.create_ssp(boundary["id"])
    try:
        data = api.get_json("/api/v1/profile_documents?items=100")
        for profile in data:
            if (profile.get("lifecycle_status") or profile.get("status")) != "published":
                continue
            api.patch_json(f"/api/v1/ssp_documents/{ssp['slug']}",
                           {"ssp_document": {"profile_document_id": profile["id"]}})
            preview = api.get_json(f"/api/v1/ssp_documents/{ssp['slug']}/bring_up_to_baseline")
            if preview["controls_added"]:
                yield ssp, profile, preview
                return
        pytest.skip("needs a published baseline with a resolved catalog")
    finally:
        api.delete_doc("ssp_documents", ssp["slug"])
        api.delete_doc("authorization_boundaries", boundary["id"])


def test_bring_up_to_baseline_after_seeing_what_is_added(authed_page, ssp_short_of_baseline):
    ssp, profile, preview = ssp_short_of_baseline
    page = authed_page
    record_csp(page)

    page.goto(f"/ssp_documents/{ssp['slug']}")
    page.wait_for_load_state("networkidle")
    page.locator("[data-testid=bring-up-to-baseline-link]").click()
    page.wait_for_url("**/bring_up_to_baseline")

    controls = page.locator("[data-testid=bring-up-controls] strong").inner_text()
    assert controls == str(len(preview["controls_added"])), (
        f"the page says {controls} controls; the API previews {len(preview['controls_added'])}"
    )

    confirm = page.locator("[data-testid=confirm-bring-up]")
    confirm.locator("button, input[type=submit]").first.click()
    page.wait_for_url(re.compile(rf"/ssp_documents/{re.escape(str(ssp['slug']))}$"))
    flash = page.locator(".flash-container").inner_text()
    assert f"Brought up to '{profile['name']}'" in flash, flash
    assert page.locator("[data-testid=bring-up-to-baseline-link]").count() == 0, (
        "the SSP still offers Bring up to baseline after holding every control"
    )
    after = api.get_json(f"/api/v1/ssp_documents/{ssp['slug']}/bring_up_to_baseline")
    assert after["controls_added"] == [], f"controls still missing: {after['controls_added'][:5]}"
    assert_no_csp_violations(page, during="bringing an SSP up to its baseline")
