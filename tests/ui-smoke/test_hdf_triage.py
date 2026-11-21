"""HDF Amendment triage UI smoke (#447).

Proves the triage screen loads, the core ingest→disposition interaction works in a
real browser (Stimulus, CSP-safe), and no CSP violation fires. Navigates from the
authorization-boundary show page via the "HDF Triage" button — exercising the new
route + nav link the way a user reaches it.

Runs authenticated (authed_page). Skips cleanly if the instance has no
authorization boundary to triage.
"""

from __future__ import annotations

import json
import tempfile
import uuid

import pytest
from playwright.sync_api import expect

from _api_setup import create_boundary, delete_doc
from helpers import assert_no_csp_violations, first_show_href, record_csp

# #1354 — ingest validates every upload with `hdf validate`, so this is a
# complete HDF v2 (InSpec exec-json) document: the v2 schema requires the
# statistics, platform release, profile sha256/supports/attributes/groups,
# control refs/tags/source_location and result code_desc/start_time.
HDF_SAMPLE = {
    "platform": {"name": "smoke", "release": "1.0"},
    "version": "5.22.3",
    "statistics": {"duration": 0.1},
    "profiles": [
        {
            "name": "trivy",
            "version": "1.0.0",
            "sha256": "0" * 64,
            "supports": [],
            "attributes": [],
            "groups": [],
            "controls": [
                {
                    "id": "CVE-SMOKE-1",
                    "title": "Smoke test finding",
                    "desc": "seeded by the ui-smoke",
                    "impact": 0.8,
                    "refs": [],
                    "tags": {},
                    "source_location": {"ref": "smoke", "line": 1},
                    "results": [
                        {
                            "status": "failed",
                            "code_desc": "smoke finding",
                            "start_time": "2026-06-01T00:00:00Z",
                        }
                    ],
                }
            ],
        }
    ],
}


def _open_triage(page, base_url):
    """Boundary show page -> click 'HDF Triage'.

    Returns False ONLY when there is genuinely no boundary to triage. A missing
    button on a boundary that DOES exist raises, because those two are not the
    same thing and must not both present as a skip.

    History: this located the header button by `a.btn`. #950 (Bundle X, v1.16.0)
    renamed 489 buttons from `.btn` to `sparc-action--*` and missed this one, so
    `a.btn` matched nothing, this returned False, and all four checks in this file
    SKIPPED — reporting green — from v1.16.0 until 2026-08-29. Keying on the
    DESTINATION fixes the immediate break; raising instead of returning False is
    what stops the next rename from hiding itself the same way.
    """
    # prefix has NO trailing slash — first_show_href appends its own.
    href = first_show_href(page, "/authorization_boundaries", "/authorization_boundaries")
    if not href:
        return False
    page.goto(f"{base_url}{href}", wait_until="networkidle")
    # An href is what the button is FOR; a class is how it looks this quarter.
    # The data-boundary-action hook keeps the original intent — the page's own
    # control, not the sidebar leaves, which carry the same destination and text.
    #
    # #1251 moved the header actions into a "More" menu, so open it first; a
    # menu item is in the DOM but not clickable until the menu is shown.
    page.locator("[data-boundary-action='more']").click()
    link = page.locator("[data-boundary-action='amendments'][href$='/triage']").filter(
        has_text="Findings Triage"
    )
    assert link.count() > 0, (
        f"boundary {href} exists but its 'Findings Triage' menu item was not found. "
        "This is a BROKEN LOCATOR, not an empty deployment — if the button was "
        "restyled, fix the selector rather than letting this degrade to a skip "
        "(see #950)."
    )
    link.first.click()
    # Turbo navigation — wait for the URL + heading rather than a content snapshot.
    page.wait_for_url("**/triage", timeout=10000)
    page.get_by_role("heading", name="Findings Triage").wait_for(timeout=10000)
    page.wait_for_load_state("networkidle")
    return True


def test_triage_page_loads_and_ingests(authed_page, base_url):
    page = authed_page
    record_csp(page)

    if not _open_triage(page, base_url):
        pytest.skip("no authorization boundary available to triage")

    heading = page.get_by_role("heading", name="Findings Triage")
    assert heading.count() == 1, "triage heading not rendered"
    assert page.locator("input[type='file']").count() > 0, "ingest upload form missing"
    # #1325 — a link when there is something to export, a disabled control
    # saying so when there is not; either way the control is there.
    assert page.get_by_test_id("triage-download-amendments").count() == 1, "export control missing"

    # Ingest a finding through the browser (set the file input + submit).
    with tempfile.NamedTemporaryFile("w", suffix=".hdf.json", delete=False) as f:
        json.dump(HDF_SAMPLE, f)
        sample_path = f.name
    page.locator("input[type='file']").first.set_input_files(sample_path)
    page.get_by_role("button", name="Upload & Ingest").click()
    page.wait_for_load_state("networkidle")

    assert "CVE-SMOKE-1" in page.content(), "ingested finding did not appear in the table"
    assert_no_csp_violations(page, during="HDF triage ingest")


def test_aggregation_controls_present(authed_page, base_url):
    """#809/#811 — the triage board exposes the target/CDEF + scope selectors at
    ingest, the lifecycle column, and the Aggregate / Download Package actions,
    all CSP-safe."""
    page = authed_page
    record_csp(page)

    if not _open_triage(page, base_url):
        pytest.skip("no authorization boundary available to triage")

    # Ingest scope controls (#811).
    assert page.locator("select[name='scanner_scope']").count() > 0, "scope selector missing"
    assert page.locator("select[name='cdef_document_id']").count() > 0, "CDEF selector missing"

    # New actions (#809).
    aggregate_btn = page.get_by_role("button", name="Aggregate into documents")
    assert aggregate_btn.count() > 0, "aggregate action missing"
    assert page.get_by_role("link", name="Download Package").count() > 0, "package link missing"

    # History toggle + lifecycle column (#811).
    assert page.locator("input[name='include_history']").count() > 0, "history toggle missing"
    lifecycle_col = page.get_by_role("columnheader", name="Lifecycle")
    assert lifecycle_col.count() > 0, "lifecycle column missing"

    assert_no_csp_violations(page, during="HDF triage aggregation controls")


def test_aggregate_action(authed_page, base_url):
    """Clicking Aggregate runs the aggregation and reports a per-document summary."""
    page = authed_page
    record_csp(page)

    if not _open_triage(page, base_url):
        pytest.skip("no authorization boundary available to triage")

    # Ensure at least one finding exists so aggregation has something to map.
    if "CVE-SMOKE-1" not in page.content():
        with tempfile.NamedTemporaryFile("w", suffix=".hdf.json", delete=False) as f:
            json.dump(HDF_SAMPLE, f)
            sample_path = f.name
        page.locator("input[type='file']").first.set_input_files(sample_path)
        page.get_by_role("button", name="Upload & Ingest").click()
        page.wait_for_load_state("networkidle")

    page.get_by_role("button", name="Aggregate into documents").click()
    # turbo_confirm renders SPARC's CSP-safe Bootstrap modal (not a native dialog).
    confirm = page.locator("#sparc-confirm-modal-confirm")
    confirm.wait_for(state="visible", timeout=5000)
    confirm.click()

    # The action redirects back with a success flash (rendered top-right).
    page.get_by_text("Aggregated into documents").wait_for(timeout=10000)

    assert_no_csp_violations(page, during="HDF triage aggregate action")


def test_disposition_form_stimulus_hint(authed_page, base_url):
    """Expanding a finding's disposition form and changing the kind updates the
    linkage hint (Stimulus, CSP-safe) — proves the controller is wired."""
    page = authed_page
    record_csp(page)

    if not _open_triage(page, base_url):
        pytest.skip("no authorization boundary available to triage")

    # Ensure at least one finding exists to disposition.
    ingested = False
    if page.locator("details").count() == 0:
        with tempfile.NamedTemporaryFile("w", suffix=".hdf.json", delete=False) as f:
            json.dump(HDF_SAMPLE, f)
            sample_path = f.name
        page.locator("input[type='file']").first.set_input_files(sample_path)
        page.get_by_role("button", name="Upload & Ingest").click()
        page.wait_for_load_state("networkidle")
        ingested = True

    details = page.locator("details").first
    if details.count() == 0:
        # This test supplies its own finding, so after an ingest "no findings"
        # is not thin data — the ingest failed and the skip was hiding it. It
        # did exactly that against a boundary whose triage page 500s: the run
        # reported a skip where it should have reported a broken screen.
        assert not ingested, (
            "ingested an HDF sample but no finding appeared — the ingest failed "
            f"on {page.url}"
        )
        pytest.skip("no findings to disposition")

    details.locator("summary").click()
    kind_select = details.locator("select[data-hdf-triage-target='kind']")
    kind_select.select_option("poam")
    hint = details.locator("[data-hdf-triage-target='hint']")
    assert "PoamFinding" in hint.inner_text(), "Stimulus hint did not update for kind=poam"

    assert_no_csp_violations(page, during="HDF triage disposition form")


def test_amendments_download_is_disabled_with_nothing_to_export(authed_page, base_url):
    """#1325 — a boundary with no dispositions has nothing to export: the
    download is shown disabled and says so, rather than handing out a document
    hdf rejects. A stale link to the download returns to the page with the
    reason."""
    page = authed_page
    record_csp(page)
    boundary = create_boundary()
    try:
        triage = f"{base_url}/authorization_boundaries/{boundary['slug']}/triage"
        page.goto(triage, wait_until="networkidle")

        control = page.get_by_test_id("triage-download-amendments")
        expect(control).to_have_text("No dispositions to export")
        expect(control).to_have_attribute("aria-disabled", "true")
        tag = control.evaluate("el => el.tagName")
        assert tag == "SPAN", f"the disabled control is a {tag}, not plain text"

        page.goto(f"{triage}/amendments", wait_until="networkidle")
        assert page.url.rstrip("/").endswith("/triage"), f"stale link landed on {page.url}"
        expect(page.locator(".flash-container")).to_contain_text("No dispositions to export")
        assert_no_csp_violations(page, during="#1325 empty amendments download")
    finally:
        delete_doc("authorization_boundaries", boundary["slug"])


def test_disposition_form_adjusted_impact(authed_page, base_url):
    """#1368 — the adjusted impact field is offered for riskAdjustment only.

    Shown and required for that kind; hidden and disabled for any other, so it
    is never submitted with one (the server refuses it there).
    """
    page = authed_page
    record_csp(page)

    if not _open_triage(page, base_url):
        pytest.skip("no authorization boundary available to triage")

    ingested = False
    if page.locator("details").count() == 0:
        with tempfile.NamedTemporaryFile("w", suffix=".hdf.json", delete=False) as f:
            json.dump(HDF_SAMPLE, f)
            sample_path = f.name
        page.locator("input[type='file']").first.set_input_files(sample_path)
        page.get_by_role("button", name="Upload & Ingest").click()
        page.wait_for_load_state("networkidle")
        ingested = True

    details = page.locator("details").first
    if details.count() == 0:
        assert not ingested, f"ingested an HDF sample but no finding appeared on {page.url}"
        pytest.skip("no findings to disposition")

    details.locator("summary").click()
    kind_select = details.locator("select[data-hdf-triage-target='kind']")
    impact = details.locator("input[name='adjusted_impact']")

    kind_select.select_option("riskAdjustment")
    assert impact.is_visible(), "adjusted impact is not shown for riskAdjustment"
    assert impact.is_enabled(), "adjusted impact is disabled for riskAdjustment"
    assert impact.evaluate("e => e.required"), "adjusted impact is not required for riskAdjustment"

    kind_select.select_option("poam")
    assert not impact.is_visible(), "adjusted impact is still shown for poam"
    assert impact.is_disabled(), "adjusted impact would be submitted with poam"

    assert_no_csp_violations(page, during="HDF triage adjusted impact field")


def test_disposition_form_nist_poam_fields(authed_page, base_url):
    """#1368 — the six NIST POA&M fields are on the form, required, with
    NIST's values, and the OSCAL POA&M download is offered."""
    page = authed_page
    record_csp(page)

    if not _open_triage(page, base_url):
        pytest.skip("no authorization boundary available to triage")

    # The download is offered whenever the amendments are (#1325: a boundary
    # with nothing to export shows a disabled control instead of both).
    poam = page.locator("[data-testid='triage-download-poam']")
    amendments = page.locator("[data-testid='triage-download-amendments']")
    nothing_to_export = amendments.evaluate("el => el.tagName") == "SPAN"
    assert poam.count() == (0 if nothing_to_export else 1), "the OSCAL POA&M download is missing"

    ingested = False
    if page.locator("details").count() == 0:
        with tempfile.NamedTemporaryFile("w", suffix=".hdf.json", delete=False) as f:
            json.dump(HDF_SAMPLE, f)
            sample_path = f.name
        page.locator("input[type='file']").first.set_input_files(sample_path)
        page.get_by_role("button", name="Upload & Ingest").click()
        page.wait_for_load_state("networkidle")
        ingested = True

    details = page.locator("details").first
    if details.count() == 0:
        assert not ingested, f"ingested an HDF sample but no finding appeared on {page.url}"
        pytest.skip("no findings to disposition")

    details.locator("summary").click()
    fieldset = details.locator("[data-testid='nist-poam-fields']")
    assert fieldset.is_visible(), "the NIST POA&M fields are not shown"

    selects = fieldset.locator("select")
    names = selects.evaluate_all("els => els.map(e => e.name)")
    assert sorted(names) == sorted([
        "nist_risk_prop", "nist_risk_status", "nist_response_lifecycle",
        "nist_facet_state", "nist_likelihood", "nist_impact",
    ]), names
    assert selects.evaluate_all("els => els.every(e => e.required)"), "a NIST field is not required"

    status_values = fieldset.locator("select[name='nist_risk_status'] option").evaluate_all(
        "els => els.map(e => e.value).filter(Boolean)"
    )
    assert status_values == [
        "open", "investigating", "remediating",
        "deviation-requested", "deviation-approved", "closed",
    ], status_values

    assert_no_csp_violations(page, during="HDF triage NIST POA&M fields")



def test_fedramp_report_downloads(authed_page, base_url):
    """#1354 / #1384 / #1390 — the FedRAMP report card: with a package overview
    address, each control downloads its report as JSON with zero CSP violations
    (the historical activity included); without one, the card says why and
    offers none."""
    page = authed_page
    record_csp(page)

    if not _open_triage(page, base_url):
        pytest.skip("no authorization boundary available to triage")

    card = page.locator("[data-testid='triage-fedramp-reports']")
    assert card.count() == 1, "the FedRAMP reports card is missing from the triage page"

    if card.locator("[data-testid='triage-fedramp-reports-unavailable']").count() == 1:
        assert card.locator("button").count() == 0, "report button offered, no package address"
        assert card.locator("[data-testid='triage-download-fedramp-ver-history']").count() == 0, (
            "historical activity offered, no package address"
        )
        assert_no_csp_violations(page, during="HDF triage FedRAMP reports (no package address)")
        return

    for testid, suffix in (
        ("triage-download-fedramp-vdr", "fedramp-vdr.json"),
        ("triage-download-fedramp-avi", "fedramp-avi.json"),
        ("triage-download-fedramp-ver-history", "fedramp-ver-history.json"),
    ):
        with page.expect_download() as download_info:
            card.locator(f"[data-testid='{testid}']").click()
        download = download_info.value
        assert download.suggested_filename.endswith(suffix), download.suggested_filename
        with open(download.path(), encoding="utf-8") as f:
            doc = json.load(f)
        assert doc["$schema"].startswith("https://fedramp.gov/schemas/fedramp-"), doc.get("$schema")
        assert_no_csp_violations(page, during=f"HDF triage FedRAMP download {testid}")


def test_fedramp_evaluation_recorded_and_shown(authed_page, base_url):
    """#1354 / #1384 — a failing finding's FedRAMP evaluation (internet-reachable,
    likely exploitable, N-rating, next reduction) is recorded from the triage
    page and shown in its row, with no CSP violation on the interaction."""
    page = authed_page
    record_csp(page)

    if not _open_triage(page, base_url):
        pytest.skip("no authorization boundary available to triage")

    # This test supplies its own failing finding, so a missing form after the
    # ingest is a broken screen, not thin data.
    if "CVE-SMOKE-1" not in page.content():
        with tempfile.NamedTemporaryFile("w", suffix=".hdf.json", delete=False) as f:
            json.dump(HDF_SAMPLE, f)
            sample_path = f.name
        page.locator("input[type='file']").first.set_input_files(sample_path)
        page.get_by_role("button", name="Upload & Ingest").click()
        page.wait_for_load_state("networkidle")

    selector = "details[data-testid='fedramp-evaluation'][data-fedramp-control='CVE-SMOKE-1']"
    details = page.locator(selector)
    assert details.count() == 1, (
        f"no FedRAMP evaluation form for the ingested failing finding CVE-SMOKE-1 on {page.url}"
    )

    details.locator("summary").click()
    definitions = details.locator("[data-testid='fedramp-pain-definitions']")
    assert "Exploitation is extremely unlikely" in definitions.inner_text(), (
        "FedRAMP's N-rating definitions are not shown"
    )

    note = f"ui-smoke {uuid.uuid4().hex[:8]}"
    details.locator("select[name='internet_reachable']").select_option("true")
    details.locator("select[name='likely_exploitable']").select_option("false")
    details.locator("select[name='pain_rating']").select_option("3")
    details.locator("select[name='next_reduction_rating']").select_option("1")
    details.locator("input[name='next_reduction_at']").fill("2026-12-15")
    details.locator("textarea[name='supplementary_info']").fill(note)
    details.get_by_role("button", name="Save FedRAMP evaluation").click()

    # A full-page form post that redirects back to the triage page.
    page.get_by_text("FedRAMP evaluation saved for CVE-SMOKE-1").wait_for(timeout=10000)
    page.wait_for_url("**/triage", timeout=10000)

    summary = page.locator(
        "[data-testid='fedramp-summary'][data-fedramp-control='CVE-SMOKE-1']"
    ).inner_text()
    for shown in ("IRV", "Not LEV", "N3", "next: N1 by 2026-12-15"):
        assert shown in summary, f"{shown!r} not shown after saving: {summary!r}"
    saved = page.locator(selector).locator("textarea[name='supplementary_info']").input_value()
    assert saved == note, f"the saved supplementary information did not read back: {saved!r}"

    assert_no_csp_violations(page, during="HDF triage FedRAMP evaluation")
