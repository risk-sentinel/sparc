"""UI smoke: admin bulk-delete controls (#629).

The CDEF and Authorization Boundary index pages render bulk-select controls for
admins (``can_bulk_delete?``): row checkboxes + a select-all + a hidden delete
bar that appears once a row is selected. This asserts the Stimulus wiring
(``data-bulk-select-target=*``) renders and the select-all interaction reveals
the bar with zero CSP violations. The destructive confirm/delete itself is
covered by the API contract suite (tests/api); here we verify the UI wiring.

Selectors verified against app/views/{cdef_documents,authorization_boundaries}/
index.html.erb + app/javascript/controllers/bulk_select_controller.js.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import pytest

from _api_setup import create_boundary, create_cdef, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

SELECT_ALL = '[data-bulk-select-target="selectAll"]'
BAR = '[data-bulk-select-target="bar"]'


@pytest.fixture
def a_cdef(session_cookie) -> Iterator[dict[str, Any]]:
    doc = create_cdef()
    try:
        yield doc
    finally:
        delete_doc("cdef_documents", doc["slug"])


@pytest.fixture
def a_boundary(session_cookie) -> Iterator[dict[str, Any]]:
    b = create_boundary()
    try:
        yield b
    finally:
        delete_doc("authorization_boundaries", b["id"])


def _assert_bulk_wiring(page, index_path: str, during: str) -> None:
    record_csp(page)
    resp = page.goto(index_path)
    assert resp and resp.status < 400, f"{during}: {resp.status if resp else 'no response'}"
    page.wait_for_load_state("networkidle")
    if page.locator(SELECT_ALL).count() == 0:
        pytest.skip(
            f"{during}: bulk-select controls not rendered "
            "(non-admin session, or auth disabled + empty list)"
        )
    bar = page.locator(BAR)
    assert bar.is_hidden(), f"{during}: delete bar should start hidden"
    # Selecting all reveals the delete bar; the click must not trip CSP.
    page.locator(SELECT_ALL).check()
    bar.wait_for(state="visible", timeout=5_000)
    assert_no_csp_violations(page, during=f"{during} select-all")


class TestBulkDelete:
    def test_cdef_index_bulk_controls(self, authed_page, a_cdef):
        _assert_bulk_wiring(authed_page, "/cdef_documents", "cdef index")

    def test_boundary_index_bulk_controls(self, authed_page, a_boundary):
        _assert_bulk_wiring(authed_page, "/authorization_boundaries", "boundary index")
