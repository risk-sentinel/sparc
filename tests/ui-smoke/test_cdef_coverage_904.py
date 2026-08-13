"""CDEF coverage wizard (#904).

Request specs cover what the verdicts are. What a browser adds is that the
wizard is reachable from the boundary screen, that the sensitivity notice is
actually on the page before a file picker opens, and that the analyse → save
round trip works without the operator re-selecting files.

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise.
    uv run pytest test_cdef_coverage_904.py --browser chromium
"""

from __future__ import annotations

import json

import pytest

from helpers import csp_violations, record_csp

pytestmark = pytest.mark.authenticated

FAKE_SECRET = "ui-smoke-tfstate-secret-do-not-store"


def _state_json(resource_types):
    return json.dumps({
        "version": 4,
        "resources": [
            {"mode": "managed", "type": rtype, "name": "example",
             "instances": [{"attributes": {"password": FAKE_SECRET}}]}
            for rtype in resource_types
        ],
    })


def _upload(page, filenames_and_types):
    page.locator("input[type='file']").first.set_input_files([
        {"name": name, "mimeType": "application/json", "buffer": _state_json(types).encode()}
        for name, types in filenames_and_types
    ])


def test_wizard_warns_before_a_file_is_chosen(authed_page):
    """Someone about to upload live credentials is told what happens to them."""
    record_csp(authed_page)

    resp = authed_page.goto("/cdef_coverage/new")
    assert resp is not None and resp.status < 400

    body = authed_page.content()
    assert "not stored" in body, "the upload screen does not say the state file is not stored"
    assert "plaintext secrets" in body, "the upload screen does not warn what state files contain"

    assert not csp_violations(authed_page), csp_violations(authed_page)


def test_analyze_reports_verdicts_and_leaks_no_attribute_values(authed_page):
    record_csp(authed_page)
    authed_page.goto("/cdef_coverage/new")

    _upload(authed_page, [("prod.tfstate", ["aws_ecs_service", "aws_guardduty_detector"])])
    authed_page.locator("input[type='submit'][value='Analyze coverage']").click()
    authed_page.wait_for_load_state("networkidle")

    body = authed_page.content()
    assert "guardduty" in body, "a deployed service is missing from the report"
    assert "Needs a CDEF" in body, "no verdict was rendered"
    assert FAKE_SECRET not in body, "a resource attribute value reached the page"

    assert not csp_violations(authed_page), csp_violations(authed_page)


def test_save_does_not_ask_for_the_files_again(authed_page):
    """The signed token is what makes this possible — the upload is long gone."""
    record_csp(authed_page)
    authed_page.goto("/cdef_coverage/new")

    _upload(authed_page, [("prod.tfstate", ["aws_guardduty_detector"])])
    authed_page.locator("input[type='submit'][value='Analyze coverage']").click()
    authed_page.wait_for_load_state("networkidle")

    save = authed_page.locator("input[type='submit'][value='Save analysis']")
    assert save.count() == 1, "the report screen offers no way to save"

    save.click()
    authed_page.wait_for_url("**/cdef_coverage/**", timeout=10000)
    authed_page.wait_for_load_state("networkidle")

    body = authed_page.content()
    assert "Coverage analysis" in body
    assert "guardduty" in body, "the saved run lost its findings"
    assert FAKE_SECRET not in body

    assert not csp_violations(authed_page), csp_violations(authed_page)


def test_boundary_screen_offers_the_wizard(authed_page):
    resp = authed_page.goto("/authorization_boundaries")
    assert resp is not None and resp.status < 400
    authed_page.wait_for_load_state("networkidle")

    # Navigate by href rather than clicking the first matching anchor: the nav
    # dropdown also links boundaries and its items are not visible, so a click
    # times out on an element that is present but hidden. `/new` and nested
    # routes are excluded — only a boundary's own show page carries the button.
    hrefs = authed_page.eval_on_selector_all(
        "a[href^='/authorization_boundaries/']",
        "els => els.map(e => e.getAttribute('href'))",
    )
    shows = [h for h in hrefs if h and h.count("/") == 2 and not h.endswith("/new")]
    if not shows:
        pytest.skip("no authorization boundaries on this deployment")

    authed_page.goto(shows[0])
    authed_page.wait_for_load_state("networkidle")

    # Located by href, not by text: the sidebar's Help & Guides menu also
    # carries a "CDEF Coverage" link (wiki/User-Guide-*.md pages are served
    # in-app at /help/<slug>), and matching on text finds that one first.
    link = authed_page.locator("a[href^='/cdef_coverage/new']")
    assert link.count() >= 1, "the boundary screen does not offer the coverage wizard"
    assert "authorization_boundary_id=" in link.first.get_attribute("href"), (
        "the wizard link from a boundary does not pre-attach that boundary"
    )
