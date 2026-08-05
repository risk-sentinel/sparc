"""#902 / #903 — evidence upload feedback and collection-date provenance.

#902 was reported as "the upload gave no indication of success or failure, and
the file did not land". Four separate silent paths fed that one report, and each
gets a test here that fails against the pre-fix code:

  1. A *successful* upload showed nothing. The controller set `flash[:notice]`
     and the layout rendered only success/error/warning, so the success message
     was discarded before it reached the page.
  2. Submitting with no file did nothing at all. The file input is `d-none` and
     carried the native `required` attribute; Chrome refuses to submit a form
     with a required control it cannot focus and reports it only to the console.
  3. A request blocked at the edge (the WAF 403 in sparc-iac#620) never reached
     Rails, so no controller could set a flash and the page sat there.
  4. Errors that did render auto-dismissed after 12s, so a failure could vanish
     before it was read.

#903 covered the Collection Date field, which accepted future values and was
then silently overwritten by the server.

Every check is asserted in BOTH directions where a posture is involved (#885):
the failure case shows an error AND the success case does not.
"""

from __future__ import annotations

import pytest

from _api_setup import delete_evidences_titled
from helpers import assert_no_csp_violations, record_csp

NEW_EVIDENCE = "/evidences/new"

# Every record this module creates is named with this prefix so teardown can
# find it — these carry uploaded files and the instance is screenshotted for a
# public wiki, so nothing may be left behind.
TITLE_PREFIX = "phase2-ui-evidence902"

# Success auto-dismisses at 8s; errors used to auto-dismiss at 12s and must
# now never do so. Waited out in real time rather than fast-forwarded with a
# mocked clock — installing fake timers would freeze Stimulus and Turbo too,
# which is exactly the machinery these two tests exist to exercise. The cost is
# ~14s in a suite that already runs for minutes.
PAST_AUTO_DISMISS_MS = 14_000

# Stands in for the AWS WAF block page: a 403 with an HTML body, which is what
# actually reached the browser in sparc-iac#620.
WAF_BLOCK_BODY = (
    "<html><head><title>403 Forbidden</title></head>"
    "<body>Request blocked by security policy.</body></html>"
)


@pytest.fixture(autouse=True)
def _sweep_created_evidence():
    yield
    delete_evidences_titled(TITLE_PREFIX)


def _fill_metadata(page, title: str = TITLE_PREFIX) -> None:
    """Fill every required metadata field, leaving the file to the caller."""
    page.fill("#evidence_title", title)
    page.fill("#evidence_description", "Uploaded by the #902 smoke test.")
    page.fill("#evidence_source", "ui-smoke")
    page.select_option("#evidence_evidence_type", "artifact")


def _attach_pdf(page, name: str = "smoke-evidence.pdf") -> None:
    """Attach a small valid PDF to the (visually hidden) dropzone input."""
    page.set_input_files(
        "input[type=file][name='evidence[file]']",
        files=[{
            "name": name,
            "mimeType": "application/pdf",
            "buffer": b"%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n%%EOF\n",
        }],
    )


def _evidence_form(page):
    """The evidence form specifically — `form` alone also matches Sign Out."""
    return page.locator("form").filter(has=page.locator("#evidence_title"))


def _wait_for_saved(page) -> None:
    """Wait for the create to land on a saved record.

    Deliberately NOT `wait_for_url("**/evidences/**")`: that glob also matches
    `/evidences/new`, so it returns instantly without waiting for anything and
    whatever follows races the navigation.
    """
    page.wait_for_url(
        lambda url: "/evidences/" in url and not url.rstrip("/").endswith("/new"),
        timeout=15_000,
    )


class TestSuccessIsVisible:
    """Path 1 — a working upload must say so."""

    def test_successful_upload_reports_the_file_by_name(self, authed_page):
        record_csp(authed_page)
        authed_page.goto(NEW_EVIDENCE)
        authed_page.wait_for_load_state("networkidle")

        _fill_metadata(authed_page)
        _attach_pdf(authed_page)
        authed_page.click("input[type=submit][value='Upload Evidence']")
        _wait_for_saved(authed_page)

        success = authed_page.locator(".flash-container .alert-success")
        success.first.wait_for(state="visible", timeout=10_000)
        text = success.first.text_content() or ""

        # Confirms the FILE landed, not merely that a record was created.
        assert "uploaded successfully" in text, f"no success confirmation: {text!r}"
        assert "smoke-evidence.pdf" in text, f"success message omits the filename: {text!r}"
        assert "SHA-256" in text, f"success message omits the checksum: {text!r}"

        assert_no_csp_violations(authed_page, during="evidence upload")


class TestMissingFileIsRefusedVisibly:
    """Path 2 — submitting with no file must explain itself, not no-op."""

    def test_submit_without_a_file_shows_an_error_and_does_not_navigate(self, authed_page):
        record_csp(authed_page)
        authed_page.goto(NEW_EVIDENCE)
        authed_page.wait_for_load_state("networkidle")

        _fill_metadata(authed_page, title=f"{TITLE_PREFIX}-never-created")
        # Deliberately no file.
        authed_page.click("input[type=submit][value='Upload Evidence']")

        error = authed_page.locator(".sparc-dropzone__error")
        error.wait_for(state="visible", timeout=5_000)
        assert "Select a file" in (error.text_content() or ""), (
            "submitting with no file produced no visible message — the exact "
            "silent no-op reported in #902"
        )

        # Still on the form: nothing was submitted.
        assert authed_page.url.endswith("/evidences/new"), (
            f"form submitted despite having no file (now at {authed_page.url})"
        )
        assert_no_csp_violations(authed_page, during="submit with no file")

    def test_the_same_form_submits_once_a_file_is_attached(self, authed_page):
        """Both directions: the guard must not be a blanket submit blocker."""
        authed_page.goto(NEW_EVIDENCE)
        authed_page.wait_for_load_state("networkidle")

        _fill_metadata(authed_page, title=f"{TITLE_PREFIX}-attached")
        authed_page.click("input[type=submit][value='Upload Evidence']")
        authed_page.locator(".sparc-dropzone__error").wait_for(state="visible", timeout=5_000)

        # Now satisfy it and submit again.
        _attach_pdf(authed_page)
        authed_page.click("input[type=submit][value='Upload Evidence']")
        _wait_for_saved(authed_page)

        assert not authed_page.url.endswith("/evidences/new"), (
            "form still refused to submit after a valid file was attached"
        )
        assert "uploaded successfully" in " ".join(
            authed_page.locator(".flash-container .alert-success").all_text_contents()
        ), "the retried submit did not report success"


class TestEdgeBlockIsSurfaced:
    """Path 3 — a POST that never reaches Rails must still be reported."""

    def test_waf_style_403_produces_a_visible_error(self, authed_page):
        record_csp(authed_page)
        authed_page.goto(NEW_EVIDENCE)
        authed_page.wait_for_load_state("networkidle")

        # Intercept only the create POST, mimicking the edge block in
        # sparc-iac#620: the app never sees the request.
        def block_post(route, request):
            if request.method == "POST":
                route.fulfill(status=403, content_type="text/html", body=WAF_BLOCK_BODY)
            else:
                route.continue_()

        authed_page.route("**/evidences", block_post)

        _fill_metadata(authed_page, title=f"{TITLE_PREFIX}-blocked")
        _attach_pdf(authed_page)
        authed_page.click("input[type=submit][value='Upload Evidence']")

        alert = authed_page.locator(".flash-container .alert-danger")
        alert.first.wait_for(state="visible", timeout=10_000)
        text = alert.first.text_content() or ""

        assert "403" in text, f"error does not name the status: {text!r}"
        assert "blocked" in text.lower(), f"error does not explain the block: {text!r}"

        # The user's work is still on screen — the whole point of intercepting
        # the render rather than letting the edge's page replace it.
        assert authed_page.input_value("#evidence_title") == f"{TITLE_PREFIX}-blocked", (
            "the filled-in form was lost when the submission failed"
        )
        assert_no_csp_violations(authed_page, during="WAF-blocked submit")

    def test_no_error_is_invented_when_the_post_succeeds(self, authed_page):
        """Negative direction: the interceptor must not fire on a good submit."""
        authed_page.goto(NEW_EVIDENCE)
        authed_page.wait_for_load_state("networkidle")

        _fill_metadata(authed_page, title=f"{TITLE_PREFIX}-unblocked")
        _attach_pdf(authed_page)
        authed_page.click("input[type=submit][value='Upload Evidence']")
        _wait_for_saved(authed_page)

        errors = authed_page.locator(".flash-container .alert-danger")
        assert errors.count() == 0, (
            f"a successful upload reported an error: {errors.all_text_contents()}"
        )


class TestErrorFlashPersists:
    """Path 4 — an error must wait for acknowledgement; success may fade."""

    def test_error_survives_the_auto_dismiss_window_and_closes_on_click(self, authed_page):
        record_csp(authed_page)
        authed_page.goto(NEW_EVIDENCE)
        authed_page.wait_for_load_state("networkidle")

        authed_page.route(
            "**/evidences",
            lambda route, request: (
                route.fulfill(status=403, content_type="text/html", body=WAF_BLOCK_BODY)
                if request.method == "POST"
                else route.continue_()
            ),
        )

        _fill_metadata(authed_page, title=f"{TITLE_PREFIX}-persistent")
        _attach_pdf(authed_page)
        authed_page.click("input[type=submit][value='Upload Evidence']")

        alert = authed_page.locator(".flash-container .alert-danger")
        alert.first.wait_for(state="visible", timeout=10_000)

        authed_page.wait_for_timeout(PAST_AUTO_DISMISS_MS)

        assert alert.first.is_visible(), (
            "the error flash auto-dismissed — a failure the user can miss is the "
            "silent-failure complaint in #902 all over again"
        )

        # It must still be dismissible on demand.
        alert.first.locator("button.btn-close").click()
        alert.first.wait_for(state="detached", timeout=5_000)
        assert_no_csp_violations(authed_page, during="dismiss persistent error")

    def test_success_still_fades_on_its_own(self, authed_page):
        """Both directions: persistence is for errors only, not every flash."""
        authed_page.goto(NEW_EVIDENCE)
        authed_page.wait_for_load_state("networkidle")

        _fill_metadata(authed_page, title=f"{TITLE_PREFIX}-fading")
        _attach_pdf(authed_page)
        authed_page.click("input[type=submit][value='Upload Evidence']")
        _wait_for_saved(authed_page)

        success = authed_page.locator(".flash-container .alert-success")
        success.first.wait_for(state="visible", timeout=10_000)

        # Real time, not a mocked clock: the success path is a Turbo navigation
        # plus a CSS fade-out animation, and freezing the page's timers to skip
        # the wait would also freeze the machinery under test.
        success.first.wait_for(state="detached", timeout=PAST_AUTO_DISMISS_MS)


class TestControlPicker:
    """#902 follow-up — control links must name a control that exists.

    The field was free text. A typo linked evidence to a control in no catalog,
    and copying the padded id SPARC displays (AC-02) never matched the canonical
    one catalogs store (ac-2) — every seeded link was dead that way. The picker
    can only emit identifiers that resolve.
    """

    def test_the_free_text_control_field_is_gone(self, authed_page):
        record_csp(authed_page)
        authed_page.goto(NEW_EVIDENCE)
        authed_page.wait_for_load_state("networkidle")

        # The hidden field still carries the value, but it must not be a
        # user-typable text box any more.
        control_input = authed_page.locator("#evidence_control_ids")
        assert control_input.count() == 1, "the control_ids field disappeared entirely"
        assert control_input.get_attribute("type") == "hidden", (
            "#902 regression: Control IDs is a free-text field again, so a typo "
            "can once more link evidence to a control that does not exist"
        )
        assert_no_csp_violations(authed_page, during="evidence form load")

    def test_searching_finds_a_real_control_and_adds_it_as_a_chip(self, authed_page):
        record_csp(authed_page)
        authed_page.goto(NEW_EVIDENCE)
        authed_page.wait_for_load_state("networkidle")

        authed_page.fill("#evidence_control_search", "ac-2")
        option = authed_page.locator(".sparc-control-picker__option").first
        option.wait_for(state="visible", timeout=10_000)
        chosen = (option.locator(".sparc-control-picker__option-id").text_content() or "").strip()
        option.click()

        chip = authed_page.locator(".sparc-control-picker__chip").first
        chip.wait_for(state="visible", timeout=5_000)
        assert chosen in (chip.text_content() or ""), "the picked control did not become a chip"

        # The hidden field is what actually posts, and it must hold a canonical id.
        posted = authed_page.input_value("#evidence_control_ids")
        assert posted, "picking a control did not populate the submitted field"
        assert posted == posted.lower(), (
            f"expected a canonical (lowercase) identifier, got {posted!r} — the "
            "padded form is what used to match nothing"
        )
        assert_no_csp_violations(authed_page, during="control picker interaction")

    def test_searching_the_padded_form_finds_the_canonical_control(self, authed_page):
        """The exact reported mismatch: type what the UI shows, find what is stored."""
        authed_page.goto(NEW_EVIDENCE)
        authed_page.wait_for_load_state("networkidle")

        authed_page.fill("#evidence_control_search", "AC-02")
        option = authed_page.locator(".sparc-control-picker__option").first
        option.wait_for(state="visible", timeout=10_000)

        assert option.count() >= 1, (
            "searching the padded form SPARC displays returned nothing — the "
            "display/storage mismatch behind #902"
        )

    def test_an_unknown_identifier_offers_nothing(self, authed_page):
        """Both directions: the picker must not invent a match for a typo."""
        authed_page.goto(NEW_EVIDENCE)
        authed_page.wait_for_load_state("networkidle")

        authed_page.fill("#evidence_control_search", "ZZ-999")
        results = authed_page.locator(".sparc-control-picker__results")
        results.wait_for(state="visible", timeout=10_000)

        assert authed_page.locator(".sparc-control-picker__option").count() == 0, (
            "the picker offered a match for an identifier that exists in no catalog"
        )
        assert "No matching controls" in (results.text_content() or "")

    def test_a_picked_control_survives_the_save(self, authed_page):
        record_csp(authed_page)
        authed_page.goto(NEW_EVIDENCE)
        authed_page.wait_for_load_state("networkidle")

        _fill_metadata(authed_page, title=f"{TITLE_PREFIX}-linked")
        _attach_pdf(authed_page)

        authed_page.fill("#evidence_control_search", "ac-2")
        option = authed_page.locator(".sparc-control-picker__option").first
        option.wait_for(state="visible", timeout=10_000)
        option.click()
        authed_page.locator(".sparc-control-picker__chip").first.wait_for(
            state="visible", timeout=5_000
        )
        linked = authed_page.input_value("#evidence_control_ids")

        authed_page.click("input[type=submit][value='Upload Evidence']")
        _wait_for_saved(authed_page)

        body = authed_page.locator("body").inner_text().lower()
        assert linked.split(",")[0] in body or linked.split(",")[0].upper() in body, (
            f"the linked control {linked!r} is not shown on the saved evidence"
        )
        assert_no_csp_violations(authed_page, during="save with a linked control")


class TestCollectionProvenance:
    """#903 — collection date is recorded, never solicited."""

    def test_no_editable_collection_date_or_collector(self, authed_page):
        record_csp(authed_page)
        authed_page.goto(NEW_EVIDENCE)
        authed_page.wait_for_load_state("networkidle")

        assert authed_page.locator("[name='evidence[collected_at]']").count() == 0, (
            "#903 regression: the form still offers an editable Collection Date, "
            "which accepts future values and is then discarded by the server"
        )
        assert authed_page.locator("[name='evidence[collected_by]']").count() == 0, (
            "#903 regression: the form still offers an editable Collected By"
        )

        body = _evidence_form(authed_page).inner_text()
        assert "Collection Date" in body, "the provenance is no longer shown at all"
        assert "recorded automatically" in body.lower(), (
            "the form does not explain how Collection Date is set"
        )
        assert_no_csp_violations(authed_page, during="evidence form load")
