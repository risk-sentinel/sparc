"""#1252 — a catalog whose controls sit in nested groups imports them, and the
family page heads each nested group over the controls it holds.

Uploads NIST's example catalog (`s1` → `s1.1` → `s1.1.1`; `s2` → `s2.1` →
`s2.1.1`) through Control Catalogs → Import, the screen an operator uses, then
reads the S2 family page:

  1. one heading, for the nested group `s2.1`, naming it;
  2. both of its controls listed under it;
  3. no CSP violation fires.

Each run gives the file a fresh uuid and title, so it imports as a new catalog
on any instance, and deletes the catalog afterwards.
"""

from __future__ import annotations

import json
import time
import uuid
from pathlib import Path

import pytest

from _api_setup import delete_doc, get_json
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

EXAMPLE = (
    Path(__file__).resolve().parents[2]
    / "spec/fixtures/files/profiles/nist_examples/basic_catalog.json"
)


def _example_file(tmp_path: Path) -> Path:
    data = json.loads(EXAMPLE.read_text())
    data["catalog"]["uuid"] = str(uuid.uuid4())
    title = f"phase2-ui-nested-{uuid.uuid4().hex[:8]}"
    data["catalog"]["metadata"]["title"] = title
    path = tmp_path / f"{title}.json"
    path.write_text(json.dumps(data))
    return path


def _wait_for_import(ref: str) -> dict:
    deadline = time.time() + 90
    catalog: dict = {}
    while time.time() < deadline:
        catalog = get_json(f"/api/v1/control_catalogs/{ref}")
        if catalog.get("status") in ("completed", "failed"):
            return catalog
        time.sleep(1)
    pytest.fail(f"catalog import did not finish: {catalog.get('status')}")


def test_family_page_heads_each_nested_group(authed_page, tmp_path):
    page = authed_page
    record_csp(page)
    catalog = None

    try:
        page.goto("/control_catalogs/import")
        upload = str(_example_file(tmp_path))
        page.set_input_files("input[type='file'][name='catalog_file']", upload)
        with page.expect_navigation(wait_until="domcontentloaded"):
            page.get_by_role("button", name="Import Catalog").click()

        ref = page.url.rstrip("/").split("/")[-1]
        catalog = _wait_for_import(ref)
        assert catalog["status"] == "completed", catalog

        page.goto(f"/control_catalogs/{ref}/control_families/s2")
        headings = page.get_by_test_id("catalog-subgroup-heading")
        assert headings.count() == 1, f"expected one nested-group heading, got {headings.count()}"
        assert "Business requirements of access control" in headings.inner_text()
        assert "s2.1" in headings.inner_text()

        listed = page.locator(
            "[data-testid='catalog-subgroup-heading'] ~ tr[data-control-db-id]"
        )
        assert listed.count() == 2, (
            f"expected s2.1.1 and s2.1.2 under the heading, got {listed.count()}"
        )

        assert_no_csp_violations(page, during="reading a family with nested groups")
    finally:
        if catalog:
            delete_doc("control_catalogs", catalog["id"])
