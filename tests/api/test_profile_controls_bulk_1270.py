"""#1270 — PUT /api/v1/profile_documents/:slug/controls/bulk.

Sets the priority of, and links/unlinks back-matter resources on, a set of a
profile's controls: the change the Profile screen's bulk bar and inline
priority selector make. Each test reads the result back from the profile's
own endpoints rather than trusting the response.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope
from schemas import ProfileControlsBulkResult

pytestmark = [pytest.mark.documents, pytest.mark.phase2]

PROFILES_PATH = "/api/v1/profile_documents"
CONTROLS = ["ac-1", "ac-2"]


def _bulk(slug: str) -> str:
    return f"{PROFILES_PATH}/{slug}/controls/bulk"


def _priorities(client: httpx.Client, slug: str) -> dict[str, str | None]:
    """Each control's priority, read back from the profile itself."""
    response = client.get(f"{PROFILES_PATH}/{slug}")
    assert response.status_code == 200, response.text[:200]
    return response.json()["data"]["control_priorities"]


@pytest.fixture
def profile(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    catalogs = admin_client.get("/api/v1/control_catalogs", params={"items": 50})
    assert catalogs.status_code == 200, catalogs.text
    catalog = next((c for c in catalogs.json()["data"] if "800-53" in (c.get("name") or "")), None)
    assert catalog, "no NIST 800-53 catalog on this instance to select controls from"

    created = admin_client.post(
        PROFILES_PATH,
        json={
            "profile_document": {
                "name": f"phase2-bulk-{uuid.uuid4().hex[:8]}",
                "control_catalog_id": catalog["id"],
            }
        },
    )
    assert created.status_code == 201, created.text
    slug = created.json()["data"]["slug"]
    try:
        selected = admin_client.put(
            f"{PROFILES_PATH}/{slug}/controls", json={"control_ids": CONTROLS}
        )
        assert selected.status_code == 200, selected.text
        yield created.json()["data"]
    finally:
        admin_client.delete(f"{PROFILES_PATH}/{slug}")


@pytest.fixture
def resource(admin_client: httpx.Client, profile: dict[str, Any]) -> Iterator[dict[str, Any]]:
    created = admin_client.post(
        "/api/v1/back_matter_resources",
        json={
            "back_matter_resource": {
                "title": f"phase2-bulk-resource-{uuid.uuid4().hex[:8]}",
                "href": "https://example.com/bulk.pdf",
                "media_type": "application/pdf",
                "globally_available": True,
                "resourceable_type": "ProfileDocument",
                "resourceable_id": profile["id"],
            }
        },
    )
    assert created.status_code == 201, created.text
    body = created.json()["data"]
    try:
        yield body
    finally:
        admin_client.delete(f"/api/v1/back_matter_resources/{body['id']}")


class TestBulkEdit:
    @pytest.mark.happy
    def test_sets_priority_on_every_named_control(self, admin_client, profile):
        response = admin_client.put(
            _bulk(profile["slug"]), json={"control_ids": CONTROLS, "priority": "P1"}
        )

        assert response.status_code == 200, response.text
        result = ProfileControlsBulkResult.model_validate(response.json()["data"])
        assert sorted(result.control_ids) == CONTROLS
        assert result.priority == "P1" and result.priority_changed

        assert _priorities(admin_client, profile["slug"]) == {"ac-1": "P1", "ac-2": "P1"}

    @pytest.mark.happy
    def test_null_clears_and_absent_leaves_priority(self, admin_client, profile, resource):
        slug = profile["slug"]
        cleared = admin_client.put(_bulk(slug), json={"control_ids": ["ac-1"], "priority": None})
        assert cleared.status_code == 200, cleared.text
        assert ProfileControlsBulkResult.model_validate(cleared.json()["data"]).priority is None
        assert _priorities(admin_client, slug)["ac-1"] is None
        before = _priorities(admin_client, slug)

        linked = admin_client.put(
            _bulk(slug), json={"control_ids": CONTROLS, "link_resource_ids": [resource["id"]]}
        )
        assert linked.status_code == 200, linked.text
        result = ProfileControlsBulkResult.model_validate(linked.json()["data"])
        assert result.priority_changed is False
        assert result.linked == 2
        assert _priorities(admin_client, slug) == before, "a link-only change altered a priority"

        again = admin_client.put(
            _bulk(slug), json={"control_ids": CONTROLS, "link_resource_ids": [resource["id"]]}
        )
        assert ProfileControlsBulkResult.model_validate(again.json()["data"]).linked == 0, (
            "linked twice"
        )

        unlinked = admin_client.put(
            _bulk(slug), json={"control_ids": ["ac-2"], "unlink_resource_ids": [resource["id"]]}
        )
        assert ProfileControlsBulkResult.model_validate(unlinked.json()["data"]).unlinked == 1

    @pytest.mark.validation
    def test_refuses_a_control_not_in_the_profile(self, admin_client, profile):
        response = admin_client.put(
            _bulk(profile["slug"]), json={"control_ids": ["ac-1", "zz-9"], "priority": "P1"}
        )

        assert_error_envelope(response, expected_status=422)
        assert "zz-9" in response.json()["error"]
        assert _priorities(admin_client, profile["slug"])["ac-1"] != "P1", (
            "a refused change was written"
        )

    @pytest.mark.validation
    def test_refuses_an_unknown_priority(self, admin_client, profile):
        response = admin_client.put(
            _bulk(profile["slug"]), json={"control_ids": ["ac-1"], "priority": "urgent"}
        )

        assert_error_envelope(response, expected_status=422)

    @pytest.mark.authz
    def test_refuses_a_caller_without_profiles_write(self, user_client, profile):
        response = user_client.put(
            _bulk(profile["slug"]), json={"control_ids": ["ac-1"], "priority": "P1"}
        )

        assert_error_envelope(response, expected_status=403)

    @pytest.mark.auth
    def test_refuses_an_anonymous_caller(self, anon_client, profile):
        response = anon_client.put(
            _bulk(profile["slug"]), json={"control_ids": ["ac-1"], "priority": "P1"}
        )

        assert response.status_code == 401
