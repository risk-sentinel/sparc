"""#1268 — Refresh from AWS Labs reports what the refresh is doing.

An operator pressed Refresh Now, was told "queued", and no CDEF ever appeared;
nothing on the screen said whether the refresh had started, kept nothing, or
failed. Now the CDEF screen shows the last refresh's state beside the button.

Only a browser proves the whole path: the confirmation modal, the POST behind
CSP, the redirect, and a status line that names a real state rather than the
"queued" flash alone. Waiting for the refresh to FINISH is not part of this
check: it downloads every upstream file, and the outcomes are pinned by
spec/services/aws_labs_refresh_reporting_1268_spec.rb.

Posture-dependent: the button exists only with SPARC_AWS_LABS_CDEF_ENABLED.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

STATUS = "[data-testid='aws-labs-refresh-status']"
# Any state a refresh can be in once one has been requested ("never" is not one).
STATES = {
    "queued", "running", "completed", "unchanged",
    "kept_nothing", "failed", "never_started", "stuck",
}


def test_refresh_now_shows_the_refresh_state(authed_page):
    page = authed_page
    record_csp(page)
    page.goto("/cdef_documents")
    page.wait_for_load_state("networkidle")

    button = page.get_by_role("button", name="Refresh from AWS Labs")
    if button.count() == 0:
        pytest.skip("AWS Labs ingest is off on this instance (SPARC_AWS_LABS_CDEF_ENABLED)")

    assert page.locator(STATUS).count() == 1, "the refresh status line is missing beside the button"
    button.click()
    modal = page.locator("#refreshAwsLabsModal")
    modal.wait_for(state="visible", timeout=5000)
    assert "one to two minutes" in modal.inner_text()

    with page.expect_navigation(wait_until="load"):
        modal.get_by_role("button", name="Refresh Now").click()

    body = page.locator("body").inner_text()
    if "already in flight" in body:
        pytest.skip("a refresh was already in flight on this instance; rerun once it finishes")
    assert "could not be queued" not in body, body[:400]
    assert "queued" in body.lower()

    state = page.locator(STATUS).get_attribute("data-state")
    assert state in STATES, f"after Refresh Now the status reads {state!r}"
    assert_no_csp_violations(page, during="Refresh from AWS Labs")
