"""#1252 — a profile that tailors by include-all, exclude-controls and alters
shows exactly the controls it selects, and what it tailors, on its page.

Builds an invented catalog (family ZZ: zz-1 with one enhancement, zz-2, zz-10)
through the API, imports a profile file through `POST
/api/v1/profile_documents/import` (the same conversion job a browser upload
runs), and reads the baseline page:

  1. every catalog control except the excluded one has a card;
  2. the control the profile alters shows what it removes and adds;
  3. no CSP violation fires.

Values are invented. The profile and catalog are deleted afterwards.
"""

from __future__ import annotations

import json
import time
import uuid

import pytest

from _api_setup import _client, create_catalog, delete_doc, get_json, post_json
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

CONTROLS = [
    ("zz-1", "Invented Policy"),
    ("zz-1.1", "Invented Policy Review"),
    ("zz-2", "Invented Inventory"),
    ("zz-10", "Invented Logging"),
]
EXCLUDED = "zz-10"


def _profile_json(catalog_uuid: str) -> dict:
    resource = str(uuid.uuid4())
    return {
        "profile": {
            "uuid": str(uuid.uuid4()),
            "metadata": {
                "title": "Invented ZZ Baseline",
                "last-modified": "2026-10-22T00:00:00Z",
                "version": "1",
                "oscal-version": "1.2.3",
            },
            "imports": [
                {
                    "href": f"#{resource}",
                    "include-all": {},
                    "exclude-controls": [{"with-ids": [EXCLUDED]}],
                }
            ],
            "modify": {
                "alters": [
                    {
                        "control-id": "zz-1",
                        "removes": [{"by-id": "zz-1_smt.b"}],
                        "adds": [
                            {
                                "position": "ending",
                                "by-id": "zz-1_smt",
                                "parts": [
                                    {
                                        "id": "zz-1_smt.c",
                                        "name": "item",
                                        "prose": "Brief staff annually.",
                                    }
                                ],
                            }
                        ],
                    }
                ]
            },
            "back-matter": {
                "resources": [
                    {
                        "uuid": resource,
                        "title": "Invented ZZ catalog",
                        "rlinks": [{"href": f"catalog-{catalog_uuid}.json"}],
                    }
                ]
            },
        }
    }


def _import_profile(data: dict) -> dict:
    with _client() as c:
        r = c.post(
            "/api/v1/profile_documents/import",
            files={
                "file": ("invented-zz-profile.json", json.dumps(data).encode(), "application/json")
            },
        )
        r.raise_for_status()
        doc = r.json()["data"][0]
    deadline = time.time() + 60
    while time.time() < deadline:
        current = get_json(f"/api/v1/profile_documents/{doc['slug']}")
        if current.get("status") in ("completed", "failed"):
            return current
        time.sleep(1)
    pytest.fail(f"profile import did not finish: {current.get('status')}")


@pytest.fixture
def tailored_profile():
    catalog = create_catalog()
    ref = catalog.get("oscal_uuid") or catalog["id"]
    post_json(
        f"/api/v1/control_catalogs/{ref}/control_families",
        {"control_family": {"code": "ZZ", "name": "Invented"}},
    )
    for control_id, title in CONTROLS:
        post_json(
            f"/api/v1/control_catalogs/{ref}/control_families/zz/controls",
            {"catalog_control": {"control_id": control_id, "title": title}},
        )
    profile = None
    try:
        profile = _import_profile(_profile_json(catalog["oscal_uuid"]))
        assert profile["status"] == "completed", profile
        yield profile
    finally:
        if profile:
            delete_doc("profile_documents", profile["slug"])
        delete_doc("control_catalogs", catalog["id"])


def test_profile_page_shows_the_selection_and_the_tailoring(authed_page, tailored_profile):
    page = authed_page
    record_csp(page)

    page.goto(f"/profile_documents/{tailored_profile['slug']}")

    titles = [
        t.strip() for t in page.locator(".control-card .sparc-ctrl-title").all_text_contents()
    ]
    expected = [title for control_id, title in CONTROLS if control_id != EXCLUDED]
    assert sorted(titles) == sorted(expected), f"cards {titles}, expected {expected}"

    card = page.locator(".control-card", has_text="Invented Policy").filter(has_not_text="Review")
    card.locator("summary").first.click()
    alters = card.get_by_test_id("profile-control-alters")
    assert alters.get_by_test_id("alter-remove").inner_text().strip() == "by-id=zz-1_smt.b"
    assert "Brief staff annually." in alters.get_by_test_id("alter-add").inner_text()

    assert_no_csp_violations(page, during="reading a tailored baseline")
