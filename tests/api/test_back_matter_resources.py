"""Tests for /api/v1/back_matter_resources.

15 logical endpoints — CRUD plus link/unlink, promotion workflow
(request/approve/reject), lifecycle (archive/restore + change-log),
bulk import, and the promotion queue. Most complex single module in
the suite.

Per-test isolation: each test that needs a resource creates it via a
fixture and deletes on teardown. State-transition tests handle their
own setup so the assertion can run against the correct precondition
state (e.g. archive needs an unarchived resource; restore needs an
archived one).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope, assert_paginated_envelope


pytestmark = [pytest.mark.back_matter, pytest.mark.phase1]


PATH = "/api/v1/back_matter_resources"


# ── Helpers ────────────────────────────────────────────────────────────────

def _new_payload(**overrides: Any) -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    body = {
        "title": f"phase2-test-bmr-{suffix}",
        "rel": "reference",
        "media_type": "application/pdf",
        "href": f"https://example.com/phase2-{suffix}.pdf",
        "globally_available": True,
    }
    body.update(overrides)
    return {"back_matter_resource": body}


def _create(client: httpx.Client, **overrides: Any) -> dict[str, Any]:
    response = client.post(PATH, json=_new_payload(**overrides))
    assert response.status_code in (200, 201), response.text
    return response.json()["data"]


def _delete(client: httpx.Client, resource_id: int) -> None:
    response = client.delete(f"{PATH}/{resource_id}")
    assert response.status_code in (200, 404), response.text


# ── Fixtures ───────────────────────────────────────────────────────────────

@pytest.fixture
def resource(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    res = _create(admin_client)
    try:
        yield res
    finally:
        _delete(admin_client, res["id"])


@pytest.fixture
def archived_resource(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    res = _create(admin_client)
    try:
        archive = admin_client.post(f"{PATH}/{res['id']}/archive")
        assert archive.status_code == 200, archive.text
        yield res
    finally:
        _delete(admin_client, res["id"])


# ── index / show ───────────────────────────────────────────────────────────

class TestIndex:
    @pytest.mark.happy
    def test_admin_lists_resources(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH)
        assert response.status_code == 200, response.text
        assert_paginated_envelope(response.json())

    @pytest.mark.pagination
    def test_filter_by_rel(
        self, admin_client: httpx.Client, resource: dict[str, Any]
    ) -> None:
        response = admin_client.get(PATH, params={"rel": "reference"})
        assert response.status_code == 200
        for r in response.json()["data"]:
            assert r["rel"] == "reference"

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(PATH), expected_status=401)


class TestShow:
    @pytest.mark.happy
    def test_admin_shows_resource(
        self, admin_client: httpx.Client, resource: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{PATH}/{resource['id']}")
        assert response.status_code == 200
        assert response.json()["data"]["id"] == resource["id"]

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(f"{PATH}/0"), expected_status=401)

    def test_unknown_id_returns_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/9999999")
        assert_error_envelope(response, expected_status=404)


# ── create / update / destroy ──────────────────────────────────────────────

class TestCreate:
    @pytest.mark.happy
    def test_admin_creates_resource(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(PATH, json=_new_payload())
        assert response.status_code in (200, 201)
        _delete(admin_client, response.json()["data"]["id"])

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(PATH, json=_new_payload()), expected_status=401
        )

    @pytest.mark.authz
    def test_non_admin_returns_403(self, user_client: httpx.Client) -> None:
        response = user_client.post(PATH, json=_new_payload())
        assert response.status_code in (401, 403)

    @pytest.mark.authz
    def test_non_admin_cannot_create_authoritative(
        self, user_client: httpx.Client
    ) -> None:
        response = user_client.post(PATH, json=_new_payload(source="authoritative"))
        # Either 401/403 (lacks write at all) or 403 (specifically blocked
        # from authoritative creation). Both are correct rejections.
        assert response.status_code in (401, 403)

    @pytest.mark.validation
    def test_missing_title_returns_422(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(
            PATH, json={"back_matter_resource": {"rel": "reference"}}
        )
        assert_error_envelope(response, expected_status=422)


class TestUpdate:
    @pytest.mark.happy
    def test_admin_updates_resource(
        self, admin_client: httpx.Client, resource: dict[str, Any]
    ) -> None:
        new_title = f"updated-{uuid.uuid4().hex[:6]}"
        response = admin_client.patch(
            f"{PATH}/{resource['id']}",
            json={"back_matter_resource": {"title": new_title}},
        )
        assert response.status_code == 200
        assert response.json()["data"]["title"] == new_title

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.patch(f"{PATH}/0", json={}), expected_status=401
        )


class TestDestroy:
    @pytest.mark.happy
    def test_admin_destroys_resource(self, admin_client: httpx.Client) -> None:
        res = _create(admin_client)
        response = admin_client.delete(f"{PATH}/{res['id']}")
        assert response.status_code == 200
        assert response.json()["data"]["deleted"] is True

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.delete(f"{PATH}/0"), expected_status=401)


# ── link / unlink ──────────────────────────────────────────────────────────

class TestLink:
    @pytest.mark.validation
    def test_invalid_linkable_type_returns_422(
        self, admin_client: httpx.Client, resource: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            f"{PATH}/{resource['id']}/link",
            json={"linkable_type": "NotARealModel", "linkable_id": 1},
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(f"{PATH}/0/link", json={}), expected_status=401
        )


class TestUnlink:
    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.delete(f"{PATH}/0/unlink", params={"link_id": 1}),
            expected_status=401,
        )


# ── promotion workflow ────────────────────────────────────────────────────

class TestPromotion:
    @pytest.mark.happy
    def test_admin_requests_promotion(
        self, admin_client: httpx.Client, resource: dict[str, Any]
    ) -> None:
        response = admin_client.post(f"{PATH}/{resource['id']}/promote")
        assert response.status_code == 200, response.text

    @pytest.mark.auth
    def test_promote_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(f"{PATH}/0/promote"), expected_status=401
        )

    @pytest.mark.auth
    def test_approve_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(f"{PATH}/0/approve_promotion"), expected_status=401
        )

    @pytest.mark.auth
    def test_reject_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(f"{PATH}/0/reject_promotion"), expected_status=401
        )


class TestPromotionQueue:
    @pytest.mark.happy
    def test_admin_lists_queue(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/promotion_queue")
        assert response.status_code == 200
        body = response.json()
        assert "data" in body and "meta" in body
        assert isinstance(body["data"], list)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{PATH}/promotion_queue"), expected_status=401
        )


# ── archive / restore / changes ────────────────────────────────────────────

class TestArchiveRestore:
    @pytest.mark.happy
    def test_admin_archives_resource(
        self, admin_client: httpx.Client, resource: dict[str, Any]
    ) -> None:
        response = admin_client.post(f"{PATH}/{resource['id']}/archive")
        assert response.status_code == 200, response.text

    @pytest.mark.happy
    def test_admin_restores_resource(
        self, admin_client: httpx.Client, archived_resource: dict[str, Any]
    ) -> None:
        response = admin_client.post(f"{PATH}/{archived_resource['id']}/restore")
        assert response.status_code == 200, response.text

    def test_double_archive_returns_409(
        self, admin_client: httpx.Client, archived_resource: dict[str, Any]
    ) -> None:
        # Already archived; second archive should conflict.
        response = admin_client.post(f"{PATH}/{archived_resource['id']}/archive")
        assert_error_envelope(response, expected_status=409)

    def test_restore_unarchived_returns_409(
        self, admin_client: httpx.Client, resource: dict[str, Any]
    ) -> None:
        # Not archived; restore should conflict.
        response = admin_client.post(f"{PATH}/{resource['id']}/restore")
        assert_error_envelope(response, expected_status=409)

    @pytest.mark.auth
    def test_archive_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(f"{PATH}/0/archive"), expected_status=401
        )


class TestChanges:
    @pytest.mark.happy
    def test_admin_reads_change_log(
        self, admin_client: httpx.Client, archived_resource: dict[str, Any]
    ) -> None:
        # The archive-fixture flow already produces at least one change
        # entry (archived_at: nil -> timestamp). The endpoint should return
        # that row.
        response = admin_client.get(f"{PATH}/{archived_resource['id']}/changes")
        assert response.status_code == 200
        body = response.json()
        assert "data" in body and isinstance(body["data"], list)
        if body["data"]:
            entry = body["data"][0]
            assert "change_type" in entry
            assert "changed_at" in entry

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{PATH}/0/changes"), expected_status=401
        )


# ── bulk import ────────────────────────────────────────────────────────────

class TestBulk:
    @pytest.mark.happy
    def test_admin_bulk_imports(self, admin_client: httpx.Client) -> None:
        suffix = uuid.uuid4().hex[:8]
        payload = {
            "entries": [
                {
                    "title": f"bulk-1-{suffix}",
                    "rel": "reference",
                    "href": "https://example.com/bulk1.pdf",
                    "media_type": "application/pdf",
                },
                {
                    "title": f"bulk-2-{suffix}",
                    "rel": "evidence",
                    "href": "https://example.com/bulk2.pdf",
                    "media_type": "application/pdf",
                },
            ]
        }
        response = admin_client.post(f"{PATH}/bulk", json=payload)
        assert response.status_code == 201, response.text
        body = response.json()["data"]
        assert "batch_uuid" in body
        assert isinstance(body["imported"], list)
        for resource in body["imported"]:
            _delete(admin_client, resource["id"])

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(f"{PATH}/bulk", json={"entries": []}),
            expected_status=401,
        )

    @pytest.mark.authz
    def test_non_admin_returns_403(self, user_client: httpx.Client) -> None:
        response = user_client.post(f"{PATH}/bulk", json={"entries": []})
        assert response.status_code in (401, 403)
