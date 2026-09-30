"""#1202 — choosing a boundary lists THAT boundary's documents, in a real browser.

The sidebar links every document list with `?authorization_boundary_id=`, and the
SSP, SAP and SAR lists ignored it: two boundaries showed the same rows. The only
browser check near this asserted that a link CONTAINED the parameter, never what
the page it opened listed, so it passed throughout. These assert the ROWS, in
both directions, with several documents per boundary (a boundary holds many).
"""

from __future__ import annotations

import pytest

from _api_setup import (
    create_boundary,
    create_poam,
    create_sap,
    create_sar,
    create_ssp,
    delete_doc,
)
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

LISTS = {
    "ssp_documents": lambda b: [create_ssp(b), create_ssp(b)],
    "sap_documents": lambda b: [create_sap(b), create_sap(b)],
    "sar_documents": lambda b: [create_sar(b), create_sar(b)],
    "poam_documents": lambda b: [create_poam(b), create_poam(b)],
}


@pytest.fixture(scope="module")
def two_boundaries():
    """Boundary A and B, each holding two documents of every listed type."""
    a, b = create_boundary(), create_boundary()
    docs: dict[str, dict[str, list]] = {}
    try:
        for resource, make in LISTS.items():
            docs[resource] = {"a": make(a["id"]), "b": make(b["id"])}
        yield a, b, docs
    finally:
        for resource, by_boundary in docs.items():
            for d in by_boundary["a"] + by_boundary["b"]:
                delete_doc(resource, d["slug"])
        delete_doc("authorization_boundaries", a["slug"])
        delete_doc("authorization_boundaries", b["slug"])


def _names_on(page) -> str:
    # The whole page: another boundary's document must not appear anywhere on it.
    return page.locator("body").inner_text()


@pytest.mark.parametrize("resource", list(LISTS))
@pytest.mark.parametrize("chosen,other", [("a", "b"), ("b", "a")])
def test_the_list_shows_only_the_chosen_boundarys_documents(
    authed_page, two_boundaries, resource, chosen, other
):
    a, b, docs = two_boundaries
    boundary = {"a": a, "b": b}[chosen]
    page = authed_page
    record_csp(page)

    page.goto(f"/{resource}?authorization_boundary_id={boundary['id']}&view=list")
    page.wait_for_load_state("networkidle")
    shown = _names_on(page)

    mine = [d["name"] for d in docs[resource][chosen]]
    theirs = [d["name"] for d in docs[resource][other]]
    assert all(n in shown for n in mine), (
        f"{resource}: this boundary's documents are missing: {mine}"
    )
    assert not any(n in shown for n in theirs), (
        f"{resource}: another boundary's documents are listed under {boundary['name']}: "
        f"{[n for n in theirs if n in shown]}"
    )
    assert_no_csp_violations(page, f"{resource} filtered to a boundary")
