"""Layer 3 — axe-core accessibility sweep (WCAG 2.1 A+AA), baseline+ratchet (#599).

Audits the SPARC UI surface with axe, scoped to WCAG 2.1 A+AA (the Section 508
bar). New violations (vs a11y_baseline.json) fail; tracked debt passes; a page
with no baseline entry is skipped until captured (UPDATE_A11Y_BASELINE=1).

Drives off the SAME page inventory as test_authenticated_nav.py (pages.py), so
accessibility coverage and navigation coverage stay in lockstep. Navigation /
render-health (HTTP status, /login bounce, console/CSP errors) is asserted by
test_authenticated_nav.py; this file is the a11y layer over the same pages.

Run both browsers:
  uv run pytest test_accessibility.py --browser chromium --browser firefox
Capture/refresh the baseline (needs SPARC_SMOKE_SA_TOKEN for authed pages):
  UPDATE_A11Y_BASELINE=1 uv run pytest test_accessibility.py --browser chromium --browser firefox
"""

from __future__ import annotations

import re

import pytest

from a11y import assert_no_new_a11y_violations
from pages import MUST_EXIST_PAGES, SHOW_PAGES

# ── Unauthenticated ────────────────────────────────────────────────────────


def test_login_page_a11y(page):
    page.goto("/login")
    page.wait_for_load_state("networkidle")
    assert_no_new_a11y_violations(page, "login")


# ── Authenticated: index / admin / form pages ──────────────────────────────


@pytest.mark.authenticated
@pytest.mark.parametrize(
    "name,path", MUST_EXIST_PAGES, ids=[p[0] for p in MUST_EXIST_PAGES]
)
def test_page_a11y(authed_page, name, path):
    resp = authed_page.goto(path)
    if resp is not None and resp.status >= 400:
        pytest.skip(f"{path} returned HTTP {resp.status} on this deployment")
    authed_page.wait_for_load_state("networkidle")
    assert_no_new_a11y_violations(authed_page, name)


# ── Authenticated: show pages, discovered from existing prod-build data ─────


@pytest.mark.authenticated
@pytest.mark.parametrize(
    "name,index_path,pattern", SHOW_PAGES, ids=[p[0] for p in SHOW_PAGES]
)
def test_show_page_a11y(authed_page, name, index_path, pattern):
    resp = authed_page.goto(index_path)
    if resp is not None and resp.status >= 400:
        pytest.skip(f"{name}: index returned HTTP {resp.status}")
    authed_page.wait_for_load_state("networkidle")

    rx = re.compile(pattern)
    href = next(
        (
            h
            for h in authed_page.eval_on_selector_all(
                "a[href]", "els => els.map(e => e.getAttribute('href'))"
            )
            if h and rx.match(h.split("?")[0])
        ),
        None,
    )
    if not href:
        pytest.skip(f"no {name} record found on this deployment to audit")

    authed_page.goto(href)
    authed_page.wait_for_load_state("networkidle")
    assert_no_new_a11y_violations(authed_page, name)
