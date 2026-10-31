"""The page frame in a real browser (1.18.0-rf, owner-approved 10-31).

Posture-gated ("nav_shell"). Under SPARC_NAV_SHELL every list screen has the
settings screens' frame:
  - the list's outer container draws no box (no padding, border or fill);
  - on a list with a left column, the page header starts level with it;
  - a table's header row fits on one line at desktop width;
  - nothing scrolls sideways at phone width.
Checked on a document list (SAPs) and an admin list (Users).

Requires SPARC_SMOKE_SA_TOKEN.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, nav_shell_on, record_csp

pytestmark = [pytest.mark.authenticated, pytest.mark.posture("nav_shell")]

SCREENS = [("sap", "/sap_documents?view=table"), ("users", "/admin/users")]


def _open(page, path):
    record_csp(page)
    resp = page.goto(path)
    assert resp is not None and resp.ok, f"{path} returned {resp and resp.status}"
    page.wait_for_load_state("networkidle")
    if not nav_shell_on(page):
        pytest.skip("SPARC_NAV_SHELL is off on this stack")


@pytest.mark.parametrize(("label", "path"), SCREENS, ids=[s[0] for s in SCREENS])
def test_the_list_has_no_outer_box(authed_page, label, path):
    page = authed_page
    page.set_viewport_size({"width": 1280, "height": 900})
    _open(page, path)

    box = page.locator(".sparc-list-card").first.evaluate(
        """el => { const s = getComputedStyle(el);
                   return [s.paddingLeft, s.borderTopWidth, s.backgroundColor, s.boxShadow]; }"""
    )
    unboxed = ["0px", "0px", "rgba(0, 0, 0, 0)", "none"]
    assert box == unboxed, f"{label}: the list is still boxed {box}"
    assert_no_csp_violations(page, during=f"opening {label}")


@pytest.mark.parametrize(("label", "path"), SCREENS, ids=[s[0] for s in SCREENS])
def test_the_header_sits_beside_the_left_column(authed_page, label, path):
    page = authed_page
    page.set_viewport_size({"width": 1280, "height": 900})
    _open(page, path)
    side = page.locator(".sparc-filtered-collection__side").first
    if side.count() == 0:
        pytest.skip(f"{label}: no left column on this deployment")

    side_box = side.bounding_box()
    header_box = page.locator("[data-testid=page-header]").first.bounding_box()
    beside = header_box["x"] > side_box["x"] + side_box["width"]
    assert beside, f"{label}: the header is not beside the column"
    assert abs(header_box["y"] - side_box["y"]) <= 24, (
        f"{label}: the header starts {header_box['y'] - side_box['y']:.0f}px below the column"
    )


@pytest.mark.parametrize(("label", "path"), SCREENS, ids=[s[0] for s in SCREENS])
def test_table_headings_fit_on_one_line(authed_page, label, path):
    page = authed_page
    page.set_viewport_size({"width": 1280, "height": 900})
    _open(page, path)
    heads = page.locator(".sparc-list-card table.table thead th")
    if heads.count() == 0:
        pytest.skip(f"{label}: no table on this deployment")

    # A heading wraps when its own text spans more than one line; the cell's
    # height is the row's, so one wrapped heading makes every cell tall.
    wrapped = heads.evaluate_all(
        """els => els.filter(e => e.textContent.trim()).filter(e => {
             const r = document.createRange();
             r.selectNodeContents(e);
             const tops = new Set([...r.getClientRects()].map(c => Math.round(c.top)));
             return tops.size > 1;
           }).map(e => e.textContent.trim())"""
    )
    assert wrapped == [], f"{label}: these headings wrap: {wrapped}"


@pytest.mark.parametrize(("label", "path"), SCREENS, ids=[s[0] for s in SCREENS])
def test_nothing_scrolls_sideways_on_a_phone(authed_page, label, path):
    page = authed_page
    page.set_viewport_size({"width": 360, "height": 800})
    _open(page, path)
    overflow = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
    assert overflow <= 0, f"{label} at 360px scrolls sideways by {overflow}px"
