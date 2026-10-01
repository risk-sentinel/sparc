"""Repairs and decision fields added in the #1154 / #1181 / #1178 / #1179 bundle,
driven in a real browser under the enforced CSP.

1. **The production repair (2026-09-29).** An SSP with no baseline and no
   boundary could not be fixed from the UI: "Set baseline" failed validation
   (#952 requires a boundary), the metadata form that could set the boundary is
   gated until a baseline exists (#911), and the ungated attach action had no
   control on the SSP page. Production is ECS Fargate with no shell, so the UI
   is the only repair path. That state is LEGACY-only — since #952 no API or UI
   path can create it (and a boundary holding an SSP cannot be deleted) — so
   `bin/smoke-prep` builds the fixtures before the suite
   (`SPARC_SMOKE_ORPHAN_SSPS`), one per mutating test.
2. **Boundary decision dates** (`authorization_date`, `next_decision_date`).
3. **POA&M risk decision fields** (`blocks_ato`, `condition_expires`,
   `reopen_trigger`) and the restored *Remediating* status.
4. **The boundary page's multiple-SSP warning.**

Each is exercised in both directions: the change that should land does, and the
one that should be refused or reported is.
"""

from __future__ import annotations

import os

import pytest

from _api_setup import (
    create_boundary,
    create_poam,
    create_poam_risk,
    create_ssp,
    delete_doc,
    get_json,
    patch_json,
)
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


@pytest.fixture
def boundary():
    b = create_boundary()
    try:
        yield b
    finally:
        delete_doc("authorization_boundaries", b["slug"])


_ORPHANS = [s for s in os.environ.get("SPARC_SMOKE_ORPHAN_SSPS", "").split(",") if s]


@pytest.fixture
def orphan_ssp():
    """A legacy SSP with no boundary and no baseline, built by bin/smoke-prep."""
    if not _ORPHANS:
        pytest.skip("SPARC_SMOKE_ORPHAN_SSPS is empty — run `bin/smoke-prep --orphans`, which "
                    "builds the legacy boundary-less SSPs this state needs (no API path can)")
    slug = _ORPHANS.pop(0)
    ssp = get_json(f"/api/v1/ssp_documents/{slug}")
    assert ssp.get("authorization_boundary_id") is None, f"{slug} is not an orphan: {ssp}"
    try:
        yield ssp
    finally:
        delete_doc("ssp_documents", slug)


def _profile_option_label(page) -> str:
    """The first real profile offered by the baseline picker."""
    options = page.locator("#baseline_profile_document_id option").all_text_contents()
    real = [o for o in options if o.strip() and not o.startswith("Choose")]
    assert real, f"the baseline picker offers no profile: {options}"
    return real[0]


class TestRepairingAnOrphanedUnbaselinedSsp:
    def test_the_page_offers_both_repairs(self, authed_page, orphan_ssp):
        page = authed_page
        record_csp(page)
        page.goto(f"/ssp_documents/{orphan_ssp['slug']}")

        assert page.get_by_text("No boundary linked").is_visible()
        assert page.get_by_text("Baseline not set").is_visible()
        assert page.locator("#baseline_profile_document_id").is_visible()
        assert page.locator("#attach_ssp_document_boundary").is_visible()
        assert_no_csp_violations(page, "SSP page with both repair controls")

    def test_setting_the_baseline_succeeds_and_reports_the_missing_boundary(
        self, authed_page, orphan_ssp
    ):
        page = authed_page
        record_csp(page)
        page.goto(f"/ssp_documents/{orphan_ssp['slug']}")

        page.locator("#baseline_profile_document_id").select_option(
            label=_profile_option_label(page)
        )
        page.get_by_role("button", name="Set baseline").click()
        page.wait_for_load_state("networkidle")

        body = page.content()
        assert "Baseline set" in body
        assert "still needs attention" in body and "boundary" in body.lower()
        assert get_json(f"/api/v1/ssp_documents/{orphan_ssp['slug']}").get("profile_document_id")
        assert_no_csp_violations(page, "set baseline on an orphaned SSP")

    def test_setting_the_baseline_with_nothing_chosen_is_refused(self, authed_page, orphan_ssp):
        page = authed_page
        record_csp(page)
        page.goto(f"/ssp_documents/{orphan_ssp['slug']}")

        page.get_by_role("button", name="Set baseline").click()
        page.wait_for_load_state("networkidle")

        assert "nothing was selected" in page.content()
        ssp = get_json(f"/api/v1/ssp_documents/{orphan_ssp['slug']}")
        assert not ssp.get("profile_document_id")
        assert_no_csp_violations(page, "empty baseline submission")

    def test_linking_a_boundary_succeeds(self, authed_page, orphan_ssp, boundary):
        page = authed_page
        record_csp(page)
        page.goto(f"/ssp_documents/{orphan_ssp['slug']}")

        page.locator("#attach_ssp_document_boundary").select_option(value=str(boundary["id"]))
        page.get_by_role("button", name="Link boundary").click()
        page.wait_for_load_state("networkidle")

        assert f"is now part of {boundary['name']}" in page.content()
        assert "No boundary linked" not in page.content()
        ssp = get_json(f"/api/v1/ssp_documents/{orphan_ssp['slug']}")
        assert ssp.get("authorization_boundary_id") == boundary["id"]
        assert_no_csp_violations(page, "link a boundary from the banner")

    def test_linking_with_no_boundary_chosen_does_not_submit(self, authed_page, orphan_ssp):
        page = authed_page
        record_csp(page)
        page.goto(f"/ssp_documents/{orphan_ssp['slug']}")
        before = page.url

        # The select is `required`: the browser refuses the submit.
        page.get_by_role("button", name="Link boundary").click()
        page.wait_for_timeout(500)

        assert page.url == before
        assert "No boundary linked" in page.content()
        ssp = get_json(f"/api/v1/ssp_documents/{orphan_ssp['slug']}")
        assert ssp.get("authorization_boundary_id") is None
        assert_no_csp_violations(page, "empty boundary submission")

    def test_a_boundary_already_holding_an_ssp_says_so_before_you_choose(
        self, authed_page, orphan_ssp, boundary
    ):
        other = create_ssp(boundary["id"])
        try:
            page = authed_page
            page.goto(f"/ssp_documents/{orphan_ssp['slug']}")
            labels = page.locator("#attach_ssp_document_boundary option").all_text_contents()
            mine = [label for label in labels if boundary["name"] in label]

            assert mine, f"{boundary['name']} is not offered: {labels}"
            assert f"already linked to: {other['name']}" in mine[0]
        finally:
            delete_doc("ssp_documents", other["slug"])


class TestBoundaryDecisionDates:
    def test_the_dates_save_from_the_edit_form(self, authed_page, boundary):
        page = authed_page
        record_csp(page)
        page.goto(f"/authorization_boundaries/{boundary['slug']}/edit")

        page.locator("#authorization_boundary_authorization_date").fill("2026-03-31")
        page.locator("#authorization_boundary_next_decision_date").fill("2027-03-31")
        page.locator("form input[type=submit]").first.click()
        page.wait_for_load_state("networkidle")

        assert "Authorization boundary updated." in page.content()
        saved = get_json(f"/api/v1/authorization_boundaries/{boundary['slug']}")
        assert saved.get("authorization_date") == "2026-03-31"
        assert saved.get("next_decision_date") == "2027-03-31"
        assert_no_csp_violations(page, "boundary decision dates")

    def test_clearing_a_date_removes_it(self, authed_page, boundary):
        patch_json(f"/api/v1/authorization_boundaries/{boundary['slug']}",
                   {"authorization_boundary": {"next_decision_date": "2027-03-31"}})
        page = authed_page
        page.goto(f"/authorization_boundaries/{boundary['slug']}/edit")

        page.locator("#authorization_boundary_next_decision_date").fill("")
        page.locator("form input[type=submit]").first.click()
        page.wait_for_load_state("networkidle")

        saved = get_json(f"/api/v1/authorization_boundaries/{boundary['slug']}")
        assert not saved.get("next_decision_date")

    def test_a_malformed_date_is_refused_by_the_server(self, boundary):
        # The browser's date input cannot hold a malformed value, so the refusal
        # is proven at the endpoint that would accept one.
        r = patch_json(f"/api/v1/authorization_boundaries/{boundary['slug']}",
                       {"authorization_boundary": {"next_decision_date": "someday"}})
        assert r.status_code == 422, r.text
        assert not get_json(f"/api/v1/authorization_boundaries/{boundary['slug']}").get(
            "next_decision_date"
        )


class TestPoamRiskDecisionFields:
    @pytest.fixture
    def risk(self, boundary):
        poam = create_poam(boundary["id"])
        try:
            yield poam, create_poam_risk(poam["slug"])
        finally:
            delete_doc("poam_documents", poam["slug"])

    def _edit(self, page, poam, risk):
        page.goto(f"/poam_documents/{poam['slug']}/poam_risks/{risk['id']}/edit")

    def _submit(self, page):
        """Click Update and return the server's answer to the form submit.

        Turbo submits this form with fetch and swaps the body in place, so there
        is no new document and `wait_for_load_state("networkidle")` returns at
        once: that state was already reached when the edit page loaded. The
        assertions then raced the request. On a quick server they won; on the
        v1.17.0 release runner the save was still in flight and "Risk updated"
        was not on the page yet. For the refusal test the race ran the other
        way and could pass before the server had answered at all.
        """
        with page.expect_response(
            lambda r: r.request.method != "GET" and "/poam_risks/" in r.url
        ) as answered:
            page.get_by_role("button", name="Update Risk").click()
        return answered.value

    def test_the_decision_fields_and_remediating_save(self, authed_page, risk):
        poam, r = risk
        page = authed_page
        record_csp(page)
        self._edit(page, poam, r)

        page.locator("#poam_risk_status").select_option("remediating")
        page.locator("#poam_risk_blocks_ato").select_option("true")
        page.locator("#poam_risk_condition_expires").fill("2027-06-30")
        page.locator("#poam_risk_reopen_trigger").fill("score<0.85")
        response = self._submit(page)

        assert response.status in (302, 303), f"the save answered {response.status}"
        # The flash is on the page the redirect lands on, so wait for IT.
        page.get_by_text("Risk updated").first.wait_for()
        saved = get_json(f"/api/v1/poam_risks/{r['id']}")
        assert saved.get("status") == "remediating"
        assert saved.get("blocks_ato") is True
        assert saved.get("condition_expires") == "2027-06-30"
        assert saved.get("reopen_trigger") == "score<0.85"
        assert_no_csp_violations(page, "POA&M risk decision fields")

    def test_a_malformed_reopen_trigger_is_refused_and_nothing_saves(self, authed_page, risk):
        poam, r = risk
        page = authed_page
        record_csp(page)
        self._edit(page, poam, r)

        page.locator("#poam_risk_blocks_ato").select_option("true")
        page.locator("#poam_risk_reopen_trigger").fill("when it feels right")
        response = self._submit(page)

        # The refusal itself, from the server, before anything is read off the
        # page: nothing below can pass because the request had not finished.
        assert response.status == 422, f"a malformed trigger answered {response.status}"
        page.wait_for_load_state("networkidle")
        assert "Risk updated" not in page.content()
        assert "trigger" in page.content().lower()
        saved = get_json(f"/api/v1/poam_risks/{r['id']}")
        assert saved.get("reopen_trigger") in (None, "")
        assert saved.get("blocks_ato") is None
        assert_no_csp_violations(page, "malformed reopen trigger")


class TestMultipleSspWarning:
    def test_two_ssps_on_one_boundary_are_named(self, authed_page, boundary):
        first, second = create_ssp(boundary["id"]), create_ssp(boundary["id"])
        try:
            page = authed_page
            record_csp(page)
            page.goto(f"/authorization_boundaries/{boundary['slug']}")

            assert "2 system security plans point at this boundary" in page.content()
            assert first["name"] in page.content() and second["name"] in page.content()
            assert_no_csp_violations(page, "multiple-SSP warning")
        finally:
            delete_doc("ssp_documents", first["slug"])
            delete_doc("ssp_documents", second["slug"])

    def test_one_ssp_raises_no_warning(self, authed_page, boundary):
        only = create_ssp(boundary["id"])
        try:
            page = authed_page
            page.goto(f"/authorization_boundaries/{boundary['slug']}")
            assert "system security plans point at this boundary" not in page.content()
        finally:
            delete_doc("ssp_documents", only["slug"])
