"""Creating a profile from a catalog must actually load the catalog's controls.

This is the gap that let a completely broken screen ship. "Create Profile from
Catalog" reported **"Failed to load controls. Try again."** for every catalog,
and nothing caught it, because every layer was individually fine:

  - the route existed
  - the controller worked
  - the JSON view worked
  - the #881 canonicalisation redirect was a correct 301 to a correct URL

Only the COMBINATION failed. `/control_catalogs/:id.json` 301'd to
`/control_catalogs/<uuid>` **without the `.json`**, and fetch() follows
redirects transparently, so the picker asked for JSON and silently received a
whole HTML page. `response.json()` threw and the catch-all rendered a generic
message with nothing in the log.

Page-load coverage could never have caught this: the page returns HTTP 200 with
no console error and no CSP violation. The failure only exists AFTER the catalog
select changes. So this drives the interaction and asserts on what the user
actually needs — controls they can select — rather than on the page rendering.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

PAGE = "/profile_documents/select_catalog"
CATALOG_SELECT = "select[data-family-selector-target='catalogSelect']"
CONTROLS_LIST = "[data-family-selector-target='controlsList']"


def _first_real_catalog(page):
    """Value of the first non-blank catalog option, or None."""
    return page.evaluate(
        f"""() => {{
            const sel = document.querySelector("{CATALOG_SELECT}");
            if (!sel) return null;
            const opt = [...sel.options].find(o => o.value && o.value.trim() !== "");
            return opt ? opt.value : null;
        }}"""
    )


def test_selecting_a_catalog_loads_its_controls(authed_page):
    """The bug, driven end to end."""
    record_csp(authed_page)
    authed_page.goto(PAGE)
    authed_page.wait_for_load_state("networkidle")

    catalog_value = _first_real_catalog(authed_page)
    if not catalog_value:
        pytest.skip("no control catalog seeded on this deployment")

    authed_page.select_option(CATALOG_SELECT, catalog_value)

    # The controls list is populated asynchronously.
    authed_page.wait_for_selector(f"{CONTROLS_LIST} input[type='checkbox']", timeout=15000)

    text = authed_page.locator(CONTROLS_LIST).inner_text()
    assert "Failed to load controls" not in text, (
        "the catalog picker could not load controls — this is the #881 "
        "format-dropping redirect regressing"
    )

    checkboxes = authed_page.locator(f"{CONTROLS_LIST} input[type='checkbox']").count()
    assert checkboxes > 0, "catalog selected but no controls were offered"

    assert_no_csp_violations(authed_page, during="catalog selection")


def test_the_controls_request_returns_json_not_html(authed_page):
    """Assert the mechanism too, because the symptom is so generic.

    If this ever fails while the test above passes, the picker is rendering
    something that is not the catalog's real controls.
    """
    authed_page.goto(PAGE)
    authed_page.wait_for_load_state("networkidle")

    catalog_value = _first_real_catalog(authed_page)
    if not catalog_value:
        pytest.skip("no control catalog seeded on this deployment")

    responses = []
    authed_page.on(
        "response",
        lambda r: responses.append((r.url, r.status, r.headers.get("content-type", "")))
        if "/control_catalogs/" in r.url
        else None,
    )

    authed_page.select_option(CATALOG_SELECT, catalog_value)
    authed_page.wait_for_selector(f"{CONTROLS_LIST} input[type='checkbox']", timeout=15000)

    final = [r for r in responses if r[1] == 200]
    assert final, f"no successful catalog request; saw {responses}"
    assert any("application/json" in ctype for _, _, ctype in final), (
        f"the catalog request did not come back as JSON: {final}"
    )


def test_controls_can_be_selected_and_the_count_updates(authed_page):
    """Select All must actually select something — 0 selected is the failure."""
    authed_page.goto(PAGE)
    authed_page.wait_for_load_state("networkidle")

    catalog_value = _first_real_catalog(authed_page)
    if not catalog_value:
        pytest.skip("no control catalog seeded on this deployment")

    authed_page.select_option(CATALOG_SELECT, catalog_value)
    authed_page.wait_for_selector(f"{CONTROLS_LIST} input[type='checkbox']", timeout=15000)

    authed_page.click("text=Select All")

    checked = authed_page.locator(f"{CONTROLS_LIST} input[type='checkbox']:checked").count()
    assert checked > 0, "Select All selected nothing — the picker has no usable controls"
