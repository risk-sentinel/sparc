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

import pytest

from helpers import assert_no_csp_violations, first_show_href, record_csp

HDF_SAMPLE = {
    "platform": {"name": "smoke"},
    "profiles": [
        {
            "name": "trivy",
            "controls": [
                {
                    "id": "CVE-SMOKE-1",
                    "title": "Smoke test finding",
                    "desc": "seeded by the ui-smoke",
                    "impact": 0.8,
                    "results": [{"status": "failed"}],
                }
            ],
        }
    ],
}


def _open_triage(page, base_url):
    """Boundary show page -> click 'HDF Triage'. Returns False if no boundary."""
    # prefix has NO trailing slash — first_show_href appends its own.
    href = first_show_href(page, "/authorization_boundaries", "/authorization_boundaries")
    if not href:
        return False
    page.goto(f"{base_url}{href}", wait_until="networkidle")
    # The header button (class .btn) — distinct from the sidebar "Amendments"
    # leaf links (.sparc-sidebar-leaf), which also read "Amendments".
    link = page.locator("a.btn", has_text="Amendments")
    if link.count() == 0:
        return False
    link.first.click()
    # Turbo navigation — wait for the URL + heading rather than a content snapshot.
    page.wait_for_url("**/triage", timeout=10000)
    page.get_by_role("heading", name="HDF Amendment Triage").wait_for(timeout=10000)
    page.wait_for_load_state("networkidle")
    return True


def test_triage_page_loads_and_ingests(authed_page, base_url):
    page = authed_page
    record_csp(page)

    if not _open_triage(page, base_url):
        pytest.skip("no authorization boundary available to triage")

    assert "HDF Amendment Triage" in page.content(), "triage heading not rendered"
    assert page.locator("input[type='file']").count() > 0, "ingest upload form missing"
    assert page.get_by_role("link", name="Download Amendments").count() > 0, "export link missing"

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
