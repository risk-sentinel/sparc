"""Admin > Remediation Timelines UI smoke (#809).

The SLA grid (profile baseline x NIST criticality -> days) is what supplies an
amendment's validity window when the boundary profile carries no ODP value, so a
broken grid silently changes how long a suppression lasts. Proves the screen
loads, a cell round-trips through a real save, and no CSP violation fires.

Runs authenticated (authed_page). Skips cleanly when the smoke identity is not an
instance admin — the screen is admin-only by design.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp

PATH = "/admin/remediation_timelines"


def _open_grid(page, base_url):
    """Navigate to the grid. Returns False when the identity can't reach it."""
    page.goto(f"{base_url}{PATH}", wait_until="networkidle")
    if "/login" in page.url or "/admin/remediation_timelines" not in page.url:
        return False
    return page.locator("#remediation-timelines-grid").count() > 0


def test_grid_loads(authed_page, base_url):
    """The grid renders every baseline row and criticality column."""
    page = authed_page
    record_csp(page)

    if not _open_grid(page, base_url):
        pytest.skip("remediation timelines grid not reachable (non-admin identity)")

    page.get_by_role("heading", name="Remediation Timelines").wait_for(timeout=10000)

    grid = page.locator("#remediation-timelines-grid")
    for baseline in ("Low", "Moderate", "High"):
        assert grid.get_by_role("rowheader", name=baseline).count() > 0, (
            f"baseline row {baseline} missing"
        )
    for criticality in ("Critical", "High", "Moderate", "Low", "Informational", "Unknown"):
        assert grid.get_by_role("columnheader", name=criticality).count() > 0, (
            f"criticality column {criticality} missing"
        )

    assert_no_csp_violations(page, during="remediation timelines grid load")


def test_cell_save_round_trips(authed_page, base_url):
    """Editing a cell and saving persists the new value across a reload."""
    page = authed_page
    record_csp(page)

    if not _open_grid(page, base_url):
        pytest.skip("remediation timelines grid not reachable (non-admin identity)")

    cell = page.get_by_label("High Critical days")
    assert cell.count() > 0, "High/Critical cell missing"

    original = cell.first.input_value()
    new_value = "11" if original != "11" else "12"

    cell.first.fill(new_value)
    # The cell's own form owns the adjacent Save button.
    cell.first.locator("xpath=following-sibling::input[@type='submit']").first.click()
    page.wait_for_load_state("networkidle")

    _open_grid(page, base_url)
    assert page.get_by_label("High Critical days").first.input_value() == new_value, (
        "saved remediation window did not persist"
    )

    # Restore so repeated smoke runs stay idempotent.
    restored = page.get_by_label("High Critical days")
    restored.first.fill(original)
    restored.first.locator("xpath=following-sibling::input[@type='submit']").first.click()
    page.wait_for_load_state("networkidle")

    assert_no_csp_violations(page, during="remediation timelines cell save")
