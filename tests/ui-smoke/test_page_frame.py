"""The page frame in a real browser (1.18.0-rf, owner-approved 10-31).

Every list screen has the
settings screens' frame:
  - the list's outer container draws no box (no padding, border or fill);
  - on a list with a left column, the page header starts level with it;
  - a table's headings each fit on one line at desktop width;
  - nothing scrolls sideways at phone width;
  - every list's Table view fits at 1280px with no sideways scroll.
Checked on a document list (SAPs) and an admin list (Users).

Requires SPARC_SMOKE_SA_TOKEN.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

SCREENS = [("sap", "/sap_documents?view=table"), ("users", "/admin/users")]


def _open(page, path):
    record_csp(page)
    resp = page.goto(path)
    assert resp is not None and resp.ok, f"{path} returned {resp and resp.status}"
    page.wait_for_load_state("networkidle")


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


# Every list's Table view fits beside the left column at 1280px with no sideways
# scroll (owner, 2026-10-31). Measured on the box that scrolls the table.
TABLE_LISTS = [
    "ssp_documents",
    "sap_documents",
    "sar_documents",
    "poam_documents",
    "profile_documents",
    "cdef_documents",
    "control_catalogs",
    "evidences",
    "control_mappings",
    "converters",
    "leveraged_poam_documents",
]


@pytest.mark.parametrize("name", TABLE_LISTS)
def test_table_view_fits_without_scrolling(authed_page, name):
    page = authed_page
    page.set_viewport_size({"width": 1280, "height": 900})
    _open(page, f"/{name}?view=table")
    if page.locator(".sparc-list-card table.table tbody tr").count() == 0:
        pytest.skip(f"{name}: no records to draw a table on this deployment")

    over = page.locator(".sparc-list-card table.table").first.evaluate(
        """t => { let box = t.parentElement;
                  const shows = b => getComputedStyle(b).overflowX === 'visible';
                  while (box && shows(box)) box = box.parentElement;
                  return box ? box.scrollWidth - box.clientWidth : 0; }"""
    )
    assert over <= 0, f"{name}: the table scrolls sideways by {over}px at 1280px"


@pytest.mark.parametrize("name", TABLE_LISTS)
def test_table_headings_fit_their_columns(authed_page, name):
    """No heading spills out of its column or is cut mid-word (a heading may
    wrap between words)."""
    page = authed_page
    page.set_viewport_size({"width": 1280, "height": 900})
    _open(page, f"/{name}?view=table")
    if page.locator(".sparc-list-card table.table tbody tr").count() == 0:
        pytest.skip(f"{name}: no records to draw a table on this deployment")

    problems = page.locator(".sparc-list-card table.table thead th").evaluate_all(
        """ths => ths.filter(th => th.textContent.trim()).flatMap(th => {
             const text = th.textContent.trim();
             const r = document.createRange();
             r.selectNodeContents(th);
             const lines = new Set([...r.getClientRects()].map(c => Math.round(c.top))).size;
             const words = text.split(/\\s+/).length;
             const out = [];
             if (th.scrollWidth > th.clientWidth) out.push(`${text}: wider than its column`);
             if (lines > words) out.push(`${text}: cut mid-word`);
             return out;
           })"""
    )
    assert problems == [], f"{name}: {problems}"
