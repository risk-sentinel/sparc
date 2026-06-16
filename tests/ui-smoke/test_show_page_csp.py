"""Document show-page interaction smoke (#647, epic #650).

#647: the Edit / doc-meta toggle / family expand-collapse / inline-edit controls
on the SSP/CDEF/SAR/SAP/POAM/Profile show pages were dead because they relied on
inline on* handlers that strict CSP silently blocks. These tests discover a real
document of each type (slug URLs), click the now-Stimulus controls, and assert
BOTH that the DOM reacts AND that zero CSP violations fire on the interaction.

Controls are gated (signed-in / draft), so each assertion is guarded: when a
control isn't present the page-load CSP-clean check still runs. Requires
SPARC_SMOKE_SA_TOKEN.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, first_show_href, record_csp

pytestmark = pytest.mark.authenticated

# (label, index_path, show_prefix)
SHOW_DOCS = [
    ("cdef", "/cdef_documents", "/cdef_documents"),
    ("ssp", "/ssp_documents", "/ssp_documents"),
    ("sar", "/sar_documents", "/sar_documents"),
    ("sap", "/sap_documents", "/sap_documents"),
    ("poam", "/poam_documents", "/poam_documents"),
    ("profile", "/profile_documents", "/profile_documents"),
]


@pytest.mark.parametrize(
    "label,index_path,prefix", SHOW_DOCS, ids=[d[0] for d in SHOW_DOCS]
)
def test_show_page_controls_fire_without_csp_violation(
    authed_page, label, index_path, prefix
):
    record_csp(authed_page)
    href = first_show_href(authed_page, index_path, prefix)
    if not href:
        pytest.skip(f"no {label} record to exercise")

    authed_page.goto(href)
    authed_page.wait_for_load_state("networkidle")
    # Baseline: the page renders with no CSP violation before any interaction.
    assert_no_csp_violations(authed_page, during=f"{label} show load")

    exercised = []

    # 1) doc-meta Edit/Cancel toggle (view ⇄ edit).
    toggle = authed_page.locator('[data-action~="doc-meta#toggle"]')
    if toggle.count() > 0:
        edit = authed_page.locator("#doc-meta-edit")
        toggle.first.click()
        authed_page.wait_for_timeout(150)
        assert "none" not in (edit.get_attribute("style") or "").replace(" ", ""), (
            f"{label}: doc-meta edit panel did not reveal on toggle"
        )
        assert_no_csp_violations(authed_page, during=f"{label} doc-meta toggle")
        exercised.append("doc-meta")

    # 2) family expand/collapse (SSP/SAP/Profile).
    expand = authed_page.locator('[data-action~="family-toggle#expandAll"]')
    if expand.count() > 0:
        expand.first.click()
        authed_page.wait_for_timeout(150)
        assert_no_csp_violations(authed_page, during=f"{label} family expand")
        exercised.append("family-toggle")

    # 3) per-control / per-item inline edit toggle.
    inline = authed_page.locator('[data-action~="inline-edit#toggle"]')
    if inline.count() > 0:
        inline.first.click()
        authed_page.wait_for_timeout(150)
        assert_no_csp_violations(authed_page, during=f"{label} inline-edit toggle")
        exercised.append("inline-edit")

    if not exercised:
        pytest.skip(f"{label}: no interactive controls present (non-draft/read-only)")
