"""Layer 3 — axe-core accessibility smoke (WCAG 2.1 A+AA), baseline+ratchet (#599).

Reuses the pages Layers 1/2 already drive; adds an axe audit to each. New
violations (vs a11y_baseline.json) fail; tracked debt passes. Run in both
browsers:  uv run pytest test_accessibility.py --browser chromium --browser firefox
"""

from __future__ import annotations

import pytest

from a11y import assert_no_new_a11y_violations

# Same core pages as test_authenticated_nav.py, kept in sync intentionally.
CORE_PAGES = [
    ("dashboard", "/"),
    ("ssp_index", "/ssp_documents"),
    ("sar_index", "/sar_documents"),
    ("cdef_index", "/cdef_documents"),
    ("poam_index", "/poam_documents"),
]


def test_login_page_a11y(page):
    page.goto("/login")
    page.wait_for_load_state("networkidle")
    assert_no_new_a11y_violations(page, "login")


@pytest.mark.authenticated
@pytest.mark.parametrize("name,path", CORE_PAGES, ids=[p[0] for p in CORE_PAGES])
def test_authenticated_page_a11y(authed_page, name, path):
    authed_page.goto(path)
    authed_page.wait_for_load_state("networkidle")
    assert_no_new_a11y_violations(authed_page, name)
