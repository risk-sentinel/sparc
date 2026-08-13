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

from helpers import assert_no_csp_violations, record_csp, show_hrefs

pytestmark = pytest.mark.authenticated

# The controls this test exercises. Also used to choose a document that can
# actually exercise them.
# How many documents to open looking for one with usable controls. Each costs a
# page load, so this is a sample, not a scan.
MAX_CANDIDATES = 10

CONTROL_SELECTORS = [
    '[data-action~="doc-meta#toggle"]',
    '[data-action~="family-toggle#expandAll"]',
    '[data-action~="inline-edit#toggle"]',
]

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
    # A large page so the sample below can reach the whole collection: these
    # indexes sort newest-first, and on a CDEF index led by 230 freshly-ingested
    # AWS Labs documents every editable one is at the far end.
    # Both ends of the collection. `per_page` is capped server-side at 200, and
    # a CDEF index carrying the full AWS Labs corpus runs past that — so the
    # editable documents, being the oldest, fall entirely off page one. Reading
    # only the first page is how this test came to conclude that no document
    # anywhere had a usable control.
    listed = []
    for page_param in ("?per_page=200", "?per_page=200&page=2"):
        for href in show_hrefs(authed_page, f"{index_path}{page_param}", prefix, limit=200):
            if href not in listed:
                listed.append(href)
    if not listed:
        pytest.skip(f"no {label} record to exercise")

    # Sample across the collection rather than walking it from the top: each
    # candidate costs a page load, and the document that can exercise these
    # controls may be anywhere. Ends first, then spread through the middle.
    candidates = []
    for pick in [0, len(listed) - 1] + [
        (len(listed) * n) // MAX_CANDIDATES for n in range(1, MAX_CANDIDATES)
    ]:
        href = listed[pick] if 0 <= pick < len(listed) else None
        if href and href not in candidates:
            candidates.append(href)
        if len(candidates) >= MAX_CANDIDATES:
            break

    # Find a document whose controls are actually usable, rather than assuming
    # the first one is. A read-only document still RENDERS these controls — AWS
    # Labs CDEFs are the case in point (#466) — so `count() > 0` is presence in
    # the DOM, not clickability, and clicking a control the user cannot click
    # times out. Visibility is the honest gate.
    href = None
    for candidate in candidates:
        authed_page.goto(candidate)
        authed_page.wait_for_load_state("networkidle")
        if any(
            authed_page.locator(sel).count() > 0
            and authed_page.locator(sel).first.is_visible()
            for sel in CONTROL_SELECTORS
        ):
            href = candidate
            break

    if href is None:
        # Named, not silent: a skip that does not say what it looked at is
        # indistinguishable from a test that never ran.
        pytest.skip(
            f"{label}: none of the {len(candidates)} sampled (of {len(listed)}) expose "
            f"an interactive control (all read-only or non-draft)"
        )

    # Baseline: the page renders with no CSP violation before any interaction.
    assert_no_csp_violations(authed_page, during=f"{label} show load")

    exercised = []

    # 1) doc-meta Edit/Cancel toggle (view ⇄ edit).
    toggle = authed_page.locator('[data-action~="doc-meta#toggle"]')
    if toggle.count() > 0 and toggle.first.is_visible():
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
    if expand.count() > 0 and expand.first.is_visible():
        expand.first.click()
        authed_page.wait_for_timeout(150)
        assert_no_csp_violations(authed_page, during=f"{label} family expand")
        exercised.append("family-toggle")

    # 3) per-control / per-item inline edit toggle.
    inline = authed_page.locator('[data-action~="inline-edit#toggle"]')
    if inline.count() > 0 and inline.first.is_visible():
        inline.first.click()
        authed_page.wait_for_timeout(150)
        assert_no_csp_violations(authed_page, during=f"{label} inline-edit toggle")
        exercised.append("inline-edit")

    if not exercised:
        pytest.skip(f"{label}: no interactive controls present (non-draft/read-only)")
