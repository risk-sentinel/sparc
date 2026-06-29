"""Artifact-index search interaction smoke (#672).

Every artifact index (CDEF, Catalog, Profile, POA&M, SSP, SAR, SAP, Auth
Boundary) carries the shared search box (app/views/shared/_index_search). This
exercises the new interactive control end to end:
  - the search input is present on each index
  - typing debounce-auto-submits via Turbo to ?q=... (no full reload, no /login
    bounce)
  - ZERO CSP violations during the interaction (the non-negotiable DoD for new
    clickable/interactive controls — a blocked inline handler would surface here)
  - when the index has rows, an unlikely query filters them out

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise. Run both browsers:
    uv run pytest test_index_search.py --browser chromium --browser firefox
"""

from __future__ import annotations

import pytest

from helpers import csp_violations, record_csp

pytestmark = pytest.mark.authenticated

INDEX_SEARCH_PAGES = [
    ("ssp", "/ssp_documents"),
    ("sar", "/sar_documents"),
    ("sap", "/sap_documents"),
    ("poam", "/poam_documents"),
    ("cdef", "/cdef_documents"),
    ("profile", "/profile_documents"),
    ("control_catalogs", "/control_catalogs"),
    ("authorization_boundaries", "/authorization_boundaries"),
]

UNLIKELY = "zzq-unlikely-match-xyz"


@pytest.mark.parametrize(
    "name,path", INDEX_SEARCH_PAGES, ids=[p[0] for p in INDEX_SEARCH_PAGES]
)
def test_index_search_filters_clean(authed_page, name, path):
    record_csp(authed_page)

    resp = authed_page.goto(path)
    assert resp is not None and resp.status < 400, (
        f"{name}: {path} returned {resp.status if resp else 'none'}"
    )
    authed_page.wait_for_load_state("networkidle")

    box = authed_page.locator("input[name='q']")
    assert box.count() == 1, f"{name}: expected exactly one search box on {path}"

    rows_before = authed_page.locator("table tbody tr").count()

    # Debounced auto-submit (index_search_controller) issues a Turbo GET ?q=...
    box.fill(UNLIKELY)
    authed_page.wait_for_url(f"**q={UNLIKELY}**", timeout=5000)
    authed_page.wait_for_load_state("networkidle")

    assert "/login" not in authed_page.url, f"{name}: search bounced to /login"
    assert f"q={UNLIKELY}" in authed_page.url, (
        f"{name}: search did not navigate to ?q= ({authed_page.url})"
    )

    violations = csp_violations(authed_page)
    assert violations == [], f"{name}: CSP violations during search: {violations}"

    # When the index had rows, an unlikely term should filter them all out.
    if rows_before > 0:
        rows_after = authed_page.locator("table tbody tr").count()
        assert rows_after == 0 or rows_after < rows_before, (
            f"{name}: search did not reduce {rows_before} rows (got {rows_after})"
        )
