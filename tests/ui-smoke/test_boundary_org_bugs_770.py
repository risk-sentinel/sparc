"""#770 — boundary / environment / organization bug fixes, verified in a real
browser (page-load + interaction + zero CSP violations on interaction).

Covers the new interactive controls added for #770:
  - Bug 4: Artifact Summary tiles are clickable links
  - Bug 5: "Add Artifact" card on the boundary screen, pre-scoping the boundary
  - Bug 2: CDEF filter on the environment (sub-boundary) edit form
  - Bug 6: "Associate a boundary" form on the admin organization screen

Uses runtime discovery (first row on an index) rather than hardcoded slugs, and
skips cleanly when the demo seed hasn't provisioned the needed record — a
green skip beats a brittle failure, and the interaction assertions still run
whenever the data exists.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, first_show_href, record_csp

BOUNDARIES = "/authorization_boundaries"


def _first_boundary(page) -> str:
    href = first_show_href(page, BOUNDARIES, BOUNDARIES)
    if not href:
        pytest.skip("no authorization boundary seeded — run the demo seed")
    return href


class TestBoundaryShow:
    def test_artifact_tiles_are_links(self, authed_page):
        """Bug 4 — every Artifact Summary tile is a clickable link."""
        record_csp(authed_page)
        authed_page.goto(_first_boundary(authed_page))
        authed_page.wait_for_load_state("networkidle")

        tiles = authed_page.locator("a.sparc-hero-tile-link")
        assert tiles.count() >= 4, "expected all four artifact tiles to be links"
        assert_no_csp_violations(authed_page, during="boundary show render")

    def test_add_artifact_prescopes_the_boundary(self, authed_page):
        """Bug 5 — the Artifacts card's Add link carries the boundary scope."""
        record_csp(authed_page)
        authed_page.goto(_first_boundary(authed_page))
        authed_page.wait_for_load_state("networkidle")

        add = authed_page.get_by_role("link", name="Add Artifact")
        assert add.count() >= 1, "Add Artifact control missing from the boundary screen"
        href = add.first.get_attribute("href")
        assert "authorization_boundary_id=" in href, (
            f"Add Artifact link is not pre-scoped to the boundary: {href}"
        )

        add.first.click()
        authed_page.wait_for_load_state("networkidle")
        # The evidence form's boundary select should land pre-selected.
        selected = authed_page.locator("select#evidence_authorization_boundary_id option[selected]")
        assert selected.count() >= 1, "boundary was not pre-selected on the evidence form"
        assert_no_csp_violations(authed_page, during="Add Artifact navigation")


class TestEnvironmentForm:
    def test_cdef_filter_narrows_the_picker(self, authed_page):
        """Bug 2 — the environment edit form's CDEF picker has a working filter."""
        record_csp(authed_page)
        authed_page.goto(_first_boundary(authed_page))
        authed_page.wait_for_load_state("networkidle")

        # Find an environment "Edit" link (nested boundaries/:id/edit).
        edit = authed_page.locator("a[href*='/boundaries/'][href$='/edit']")
        if edit.count() == 0:
            pytest.skip("boundary has no environment to edit — run the demo seed")
        authed_page.goto(edit.first.get_attribute("href"))
        authed_page.wait_for_load_state("networkidle")

        filter_input = authed_page.locator("[data-checkbox-filter-target='input']")
        if filter_input.count() == 0:
            pytest.skip("environment has no CDEF picker (no completed CDEFs)")

        items = authed_page.locator("[data-checkbox-filter-target='item']")
        total = items.count()
        assert total >= 1

        # Type a string almost certainly not in any CDEF name -> everything hides.
        filter_input.first.fill("zzz-no-match-xyz")
        authed_page.wait_for_timeout(200)
        visible = sum(1 for i in range(total) if items.nth(i).is_visible())
        assert visible == 0, "filter did not hide non-matching components"

        empty = authed_page.locator("[data-checkbox-filter-target='empty']")
        assert empty.is_visible(), "empty-state message did not appear"

        # Clearing restores the full list.
        filter_input.first.fill("")
        authed_page.wait_for_timeout(200)
        visible = sum(1 for i in range(total) if items.nth(i).is_visible())
        assert visible == total, "clearing the filter did not restore the list"
        assert_no_csp_violations(authed_page, during="CDEF filter interaction")


class TestAdminOrgAssociation:
    def test_associate_boundary_form_present(self, authed_page):
        """Bug 6 — the admin organization screen exposes boundary association."""
        record_csp(authed_page)
        href = first_show_href(authed_page, "/admin/organizations", "/admin/organizations")
        if not href:
            pytest.skip("no organization seeded — run the demo seed")

        authed_page.goto(href)
        authed_page.wait_for_load_state("networkidle")

        assert authed_page.get_by_text("Associate a boundary").count() >= 1, (
            "associate-boundary control missing from the admin org screen"
        )
        assert_no_csp_violations(authed_page, during="admin org show render")
