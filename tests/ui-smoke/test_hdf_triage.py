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


def test_disposition_form_stimulus_hint(authed_page, base_url):
    """Expanding a finding's disposition form and changing the kind updates the
    linkage hint (Stimulus, CSP-safe) — proves the controller is wired."""
    page = authed_page
    record_csp(page)

    if not _open_triage(page, base_url):
        pytest.skip("no authorization boundary available to triage")

    # Ensure at least one finding exists to disposition.
    if page.locator("details").count() == 0:
        with tempfile.NamedTemporaryFile("w", suffix=".hdf.json", delete=False) as f:
            json.dump(HDF_SAMPLE, f)
            sample_path = f.name
        page.locator("input[type='file']").first.set_input_files(sample_path)
        page.get_by_role("button", name="Upload & Ingest").click()
        page.wait_for_load_state("networkidle")

    details = page.locator("details").first
    if details.count() == 0:
        pytest.skip("no findings to disposition")

    details.locator("summary").click()
    kind_select = details.locator("select[data-hdf-triage-target='kind']")
    kind_select.select_option("poam")
    hint = details.locator("[data-hdf-triage-target='hint']")
    assert "PoamFinding" in hint.inner_text(), "Stimulus hint did not update for kind=poam"

    assert_no_csp_violations(page, during="HDF triage disposition form")
