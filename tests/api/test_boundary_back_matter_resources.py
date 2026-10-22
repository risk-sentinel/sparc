"""Tests for /api/v1/authorization_boundaries/:id/back_matter_resources (#1249).

A boundary's OWN back-matter: diagrams, inventory, PPSM, CRM. The Boundary
Completeness row "Back-matter documents" counted these and nothing could create
one, so the row stayed "Not started" for every UI user. The boundary page now
has a Back Matter section, and this is its API equivalent.

Checked against the boundary in the path: listing needs
`authorization_boundaries.read` AND `back_matter.read`, writing needs
`back_matter.write`. There is no show route; every write is confirmed by an
independent read of the index, never by the write's own echo.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.phase2]


def _path(boundary: Any) -> str:
    return f"/api/v1/authorization_boundaries/{boundary}/back_matter_resources"


def _payload(**overrides: Any) -> dict[str, Any]:
    body = {
        "title": f"phase2-boundary-diagram-{uuid.uuid4().hex[:8]}",
        "description": "Created by the API contract suite.",
        "href": "https://example.gov/docs/boundary-diagram.pdf",
        "media_type": "application/pdf",
        "rel": "diagram",
    }
    body.update(overrides)
    return {"back_matter_resource": body}


def _listed(client: httpx.Client, boundary_id: int) -> dict[int, dict[str, Any]]:
    response = client.get(_path(boundary_id), params={"items": 200})
    assert response.status_code == 200, response.text
    return {row["id"]: row for row in response.json()["data"]}


@pytest.fixture
def boundary_resource(
    admin_client: httpx.Client, seeded_boundary_id: int
) -> Iterator[tuple[int, dict[str, Any]]]:
    response = admin_client.post(_path(seeded_boundary_id), json=_payload())
    assert response.status_code == 201, response.text
    record = response.json()["data"]
    try:
        yield seeded_boundary_id, record
    finally:
        admin_client.delete(f"{_path(seeded_boundary_id)}/{record['id']}")


class TestCreate:
    @pytest.mark.happy
    def test_create_persists_on_the_boundary(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        payload = _payload()
        created = admin_client.post(_path(seeded_boundary_id), json=payload)
        assert created.status_code == 201, created.text
        record = created.json()["data"]
        try:
            # Independent read through the index, not the write's echo.
            row = _listed(admin_client, seeded_boundary_id).get(record["id"])
            assert row is not None, "the created resource is not in the boundary's index"
            sent = payload["back_matter_resource"]
            assert row["title"] == sent["title"]
            assert row["href"] == sent["href"]
            assert row["rel"] == "diagram"
            assert row["source"] == "managed"
            assert row["resourceable_type"] == "AuthorizationBoundary"
            assert row["resourceable_id"] == seeded_boundary_id
            assert row["uuid"], row
        finally:
            admin_client.delete(f"{_path(seeded_boundary_id)}/{record['id']}")

    @pytest.mark.validation
    def test_missing_title_is_refused(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        response = admin_client.post(_path(seeded_boundary_id), json=_payload(title=""))
        assert response.status_code == 422, response.text

    @pytest.mark.validation
    def test_owner_is_never_taken_from_the_body(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        response = admin_client.post(
            _path(seeded_boundary_id),
            json=_payload(resourceable_type="SspDocument", resourceable_id=1),
        )
        assert response.status_code == 422, response.text
        assert "resourceable_type" in " ".join(response.json()["details"])

    @pytest.mark.validation
    def test_unsafe_href_scheme_is_refused(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        response = admin_client.post(
            _path(seeded_boundary_id), json=_payload(href="javascript:alert(1)")
        )
        assert response.status_code == 422, response.text

    @pytest.mark.auth
    def test_no_token_returns_401(
        self, anon_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        assert_error_envelope(
            anon_client.post(_path(seeded_boundary_id), json=_payload()),
            expected_status=401,
        )

    @pytest.mark.authz
    def test_caller_without_write_is_refused_and_creates_nothing(
        self, admin_client: httpx.Client, user_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        before = _listed(admin_client, seeded_boundary_id)

        response = user_client.post(_path(seeded_boundary_id), json=_payload())
        assert response.status_code in (401, 403, 404), response.text

        assert _listed(admin_client, seeded_boundary_id).keys() == before.keys(), (
            "a refused request created a resource anyway"
        )


class TestIndex:
    @pytest.mark.happy
    def test_lists_the_created_resource(
        self, admin_client: httpx.Client, boundary_resource: tuple[int, dict[str, Any]]
    ) -> None:
        boundary_id, record = boundary_resource
        assert record["id"] in _listed(admin_client, boundary_id)

    @pytest.mark.authz
    def test_caller_without_read_cannot_list(
        self, user_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        response = user_client.get(_path(seeded_boundary_id))
        assert response.status_code in (401, 403, 404), response.text

    @pytest.mark.validation
    def test_unknown_boundary_is_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(_path("no-such-boundary-1249"))
        assert response.status_code == 404, response.text


class TestUpdate:
    @pytest.mark.happy
    def test_update_persists(
        self, admin_client: httpx.Client, boundary_resource: tuple[int, dict[str, Any]]
    ) -> None:
        boundary_id, record = boundary_resource
        title = f"phase2-renamed-{uuid.uuid4().hex[:8]}"

        response = admin_client.patch(
            f"{_path(boundary_id)}/{record['id']}",
            json={"back_matter_resource": {"title": title}},
        )
        assert response.status_code == 200, response.text

        assert _listed(admin_client, boundary_id)[record["id"]]["title"] == title

    @pytest.mark.authz
    def test_caller_without_write_cannot_update(
        self, admin_client: httpx.Client, user_client: httpx.Client,
        boundary_resource: tuple[int, dict[str, Any]]
    ) -> None:
        boundary_id, record = boundary_resource

        response = user_client.patch(
            f"{_path(boundary_id)}/{record['id']}",
            json={"back_matter_resource": {"title": "should not stick"}},
        )
        assert response.status_code in (401, 403, 404), response.text
        assert _listed(admin_client, boundary_id)[record["id"]]["title"] == record["title"]


class TestDestroy:
    @pytest.mark.happy
    def test_delete_removes_it_from_the_index(
        self, admin_client: httpx.Client, seeded_boundary_id: int
    ) -> None:
        created = admin_client.post(_path(seeded_boundary_id), json=_payload())
        assert created.status_code == 201, created.text
        record = created.json()["data"]

        deleted = admin_client.delete(f"{_path(seeded_boundary_id)}/{record['id']}")
        assert deleted.status_code == 200, deleted.text

        assert record["id"] not in _listed(admin_client, seeded_boundary_id)

    @pytest.mark.authz
    def test_caller_without_write_cannot_delete(
        self, admin_client: httpx.Client, user_client: httpx.Client,
        boundary_resource: tuple[int, dict[str, Any]]
    ) -> None:
        boundary_id, record = boundary_resource

        response = user_client.delete(f"{_path(boundary_id)}/{record['id']}")
        assert response.status_code in (401, 403, 404), response.text
        assert record["id"] in _listed(admin_client, boundary_id), (
            "a refused delete removed the resource anyway"
        )
