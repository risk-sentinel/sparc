"""#947 — recording an attestation with no file, in a browser.

This is the one check that cannot be done anywhere else, and the reason the
issue was filed. The evidence form set `required` on a dropzone whose real
`<input type="file">` is `d-none`, and a browser cannot focus a hidden required
field to report a validation message. So the form simply **refused to submit
with nothing shown** — no error, no scroll, no hint. Server-side specs cannot
see it: the request never leaves the browser, so from Rails' point of view
nothing happened at all.

Three things are proven here that rspec structurally cannot:

  1. Choosing the **Attestation** type reveals the statement/attester fields and
     the submit actually goes through with no file attached.
  2. An artefact type with no file is refused **visibly** — the page comes back
     carrying a readable reason rather than sitting there inert.
  3. Neither path trips a CSP violation. The type-driven reveal is a Stimulus
     controller precisely because inline `on*=` handlers are forbidden, and a
     handler that stopped working would fail exactly the way the original
     defect did: silently.
"""

from __future__ import annotations

import pytest

from _api_setup import create_boundary, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


@pytest.fixture
def boundary():
    b = create_boundary()
    try:
        yield b
    finally:
        delete_doc("authorization_boundaries", b["slug"])


def _fill_common(page, title: str, boundary_id: int | None = None) -> None:
    page.fill("#evidence_title", title)
    page.fill("#evidence_description", "Recorded by the ui-smoke suite.")
    page.fill("#evidence_source", "Manual")
    if boundary_id is not None:
        page.select_option("#evidence_authorization_boundary_id", str(boundary_id))
    # Evidence must support at least one control (#947). The picker posts
    # canonical ids through a hidden field.
    page.eval_on_selector(
        "#evidence_control_ids",
        "el => { el.value = 'ac-2'; el.dispatchEvent(new Event('change', {bubbles: true})); }",
    )


class TestAnAttestationNeedsNoFile:
    def test_choosing_attestation_reveals_the_statement_fields(self, authed_page, boundary):
        page = authed_page
        record_csp(page)
        page.goto("/evidences/new")
        page.wait_for_load_state("networkidle")

        block = page.locator('[data-evidence-type-fields-target="attestation"]')
        assert block.count() > 0, "the attestation block is not on the form at all"
        assert not block.first.is_visible(), "attestation fields showed for an artefact type"

        page.select_option("#evidence_evidence_type", "signed_statement")
        page.wait_for_timeout(200)

        assert block.first.is_visible(), (
            "choosing Attestation did not reveal the statement/attester fields — "
            "the Stimulus controller did not run"
        )
        assert_no_csp_violations(page, during="switching the evidence type")

    def test_an_attestation_saves_with_no_file_attached(self, authed_page, boundary):
        """The headline defect: this submit used to do nothing, silently."""
        page = authed_page
        record_csp(page)
        page.goto("/evidences/new")
        page.wait_for_load_state("networkidle")

        title = "ui-smoke fileless attestation"
        page.select_option("#evidence_evidence_type", "signed_statement")
        page.wait_for_timeout(200)
        # Left instance-wide on purpose. The attester/role options are computed
        # server-side for the boundary the form was RENDERED with, so choosing a
        # different boundary here and then a role would be testing a known
        # staleness rather than the fileless path this test is about. Boundary-
        # less evidence is also the common shape in practice.
        _fill_common(page, title)

        # The attester list holds only accounts that may attest here; an
        # Instance Admin is always among them.
        attester = page.locator('select[name*="[attester_user_id]"]').first
        options = attester.locator("option[value]:not([value=''])")
        assert options.count() > 0, (
            "no account was offered as an attester — the roster query returned nobody, "
            "so an attestation could not be recorded by anyone"
        )
        attester.select_option(index=1)
        page.wait_for_timeout(400)

        # The role list is narrowed to what that attester may attest under.
        role = page.locator('select[name*="[role]"]').first
        choices = [
            role.locator("option").nth(i).get_attribute("value")
            for i in range(role.locator("option").count())
        ]
        real = [c for c in choices if c]
        assert real, "the attester was offered no role to attest under"
        role.select_option(real[0])

        page.fill(
            'textarea[name*="[statement]"]',
            "I have reviewed the access list and confirm its validity.",
        )

        # No file is chosen anywhere. That is the point.
        page.click('input[type="submit"][value="Upload Evidence"]')
        page.wait_for_timeout(5000)

        assert "/evidences/new" not in page.url, (
            "the form did not submit — it stayed on /evidences/new, which is exactly "
            "the silent refusal #947 was filed about"
        )
        assert title in page.content(), "the attestation did not save"
        assert_no_csp_violations(page, during="submitting a fileless attestation")


class TestAnArtefactStillNeedsItsFile:
    def test_missing_file_is_refused_with_a_visible_reason(self, authed_page, boundary):
        """The other half: the rule still applies, and now it SPEAKS.

        Before #947 this submit was refused by a hidden `required` attribute
        that could not render a message. The rule now lives on the model, so
        the page comes back carrying one.
        """
        page = authed_page
        record_csp(page)
        page.goto("/evidences/new")
        page.wait_for_load_state("networkidle")

        page.select_option("#evidence_evidence_type", "screenshot")
        page.wait_for_timeout(200)
        _fill_common(page, "ui-smoke artefact with no file", boundary["id"])

        page.click('input[type="submit"][value="Upload Evidence"]')
        page.wait_for_load_state("networkidle")

        # The refusal may come from either layer, and BOTH are acceptable
        # because both are VISIBLE — which is the whole point:
        #
        #   * the dropzone's own capture-phase guard (#902), which intercepts
        #     before the request and renders "Select a file before submitting";
        #   * or the model (#947), if the guard is off, whose error renders in
        #     the form's error summary.
        #
        # What must never happen again is a refusal with NOTHING shown.
        body = page.content()
        shown = (
            "Select a file before submitting" in body
            or "is required for Screenshot evidence" in body
        )
        assert shown, (
            "the form refused the submit without saying why — a constraint that "
            "cannot report itself is the defect, not the fix"
        )
        # And it must not have silently saved something instead.
        assert "/evidences/new" in page.url or "is required for" in body
        assert_no_csp_violations(page, during="submitting an artefact with no file")
