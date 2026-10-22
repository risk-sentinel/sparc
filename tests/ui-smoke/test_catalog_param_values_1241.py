"""#1241 — the catalog editor sets a parameter's VALUE, not its label.

A catalog parameter can carry an assigned value in `values`, apart from its
descriptive `label`. The editor showed and edited only the label, so a value
typed there was stored as a label and every screen showed the generic wording.

This builds a throwaway catalog with one control through the API, then drives
the edit form in the browser:

  1. the Value column offers a text input for a plain parameter and the
     parameter's choices for a select; the label is shown, not editable;
  2. saving stores the value in `values` (read back through the API) and leaves
     the label exactly as it was;
  3. no CSP violation fires on the interaction.

A select value that is not one of the choices cannot be offered by the browser,
so its refusal is covered by spec/requests/catalog_control_param_values_spec.rb.
Values are invented. The catalog is deleted afterwards.
"""

from __future__ import annotations

import pytest

from _api_setup import create_catalog, delete_doc, get_json, post_json
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

PARAMS = [
    {"id": "zz-01_odp.01", "label": "frequency"},
    {"id": "zz-01_odp.02",
     "select": {"how-many": "one", "choice": ["organization-level", "system-level"]}},
]


@pytest.fixture
def catalog_control():
    catalog = create_catalog()
    ref = catalog.get("oscal_uuid") or catalog["id"]
    post_json(f"/api/v1/control_catalogs/{ref}/control_families",
              {"control_family": {"code": "ZZ", "name": "Smoke Family"}})
    control = post_json(f"/api/v1/control_catalogs/{ref}/control_families/zz/controls",
                        {"catalog_control": {
                            "control_id": "zz-1", "title": "Smoke parameter values",
                            "guidance_data": {
                                "statement": "Review {{ insert: param, zz-01_odp.01 }}.",
                            },
                            "params_data": PARAMS,
                        }})
    try:
        yield ref, control
    finally:
        delete_doc("control_catalogs", catalog["id"])


def test_the_value_column_sets_values_and_leaves_the_label(authed_page, catalog_control):
    ref, control = catalog_control
    page = authed_page
    record_csp(page)

    page.goto(f"/catalog_controls/{control['id']}/edit")

    labels = page.get_by_test_id("catalog-param-label").all_text_contents()
    assert any("frequency" in t for t in labels), f"the label should be shown, got {labels}"
    assert page.locator("input[name^='catalog_control[params_labels]']").count() == 0, (
        "the label must not be an editable field any more (#1241)"
    )

    page.locator("input[name='catalog_control[params_values][zz-01_odp.01]']").fill("quarterly-invented")
    page.locator("select[name='catalog_control[params_values][zz-01_odp.02]']").select_option("system-level")
    with page.expect_navigation():
        page.get_by_role("button", name="Save Control").click()
    assert_no_csp_violations(page, during="saving parameter values")

    saved = get_json(f"/api/v1/control_catalogs/{ref}/controls/zz-1")
    params = {p["id"]: p for p in saved["params_data"]}
    assert params["zz-01_odp.01"].get("values") == ["quarterly-invented"], params["zz-01_odp.01"]
    assert params["zz-01_odp.01"].get("label") == "frequency", "the label must be left as it was"
    assert params["zz-01_odp.02"].get("values") == ["system-level"], params["zz-01_odp.02"]
