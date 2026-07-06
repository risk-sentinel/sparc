"""Shared contract for the populate-from-profile endpoints (#628).

`POST /api/v1/<resource>/:id/populate_from_profile` with a
``{"source_profile_id": <id-or-slug>}`` body seeds an existing document's
controls from a **published** profile (only published profiles with a resolved
catalog are a valid basis). Contract:

    200 -> {data: <serialized document, detailed>}
    404 -> {error: "Published profile not found"}   (unknown/unpublished profile)
    401 -> unauthenticated

Subclass ``PopulateFromProfileContract``, set ``PATH``, and provide a
``populate_doc`` fixture yielding a slug-addressed target document.

The happy path needs a published profile to exist on the target instance; when
none is present the test skips (mirrors the ui-smoke "no sample record" skip)
rather than failing, so the edge-case contract (404 / 401) still runs
everywhere.

Underscore-prefixed file name signals "internal to the test suite".
"""

from __future__ import annotations

import uuid
from typing import Any

import httpx
import pytest


class PopulateFromProfileContract:
    PATH: str = ""

    def _populate(
        self, client: httpx.Client, slug: str, source_profile_id: Any
    ) -> httpx.Response:
        return client.post(
            f"{self.PATH}/{slug}/populate_from_profile",
            json={"source_profile_id": source_profile_id},
        )

    @staticmethod
    def _published_profile(admin_client: httpx.Client) -> Any | None:
        """Return the id/slug of any published profile on the instance, else None."""
        resp = admin_client.get("/api/v1/profile_documents", params={"items": 100})
        if resp.status_code != 200:
            return None
        for item in resp.json().get("data", []):
            status = item.get("lifecycle_status") or item.get("status")
            if status == "published":
                return item.get("slug") or item.get("id")
        return None

    @pytest.mark.happy
    def test_populate_from_published_profile(
        self, admin_client: httpx.Client, populate_doc: dict[str, Any]
    ) -> None:
        profile = self._published_profile(admin_client)
        if profile is None:
            pytest.skip("no published profile on this instance to populate from")
        resp = self._populate(admin_client, populate_doc["slug"], profile)
        assert resp.status_code == 200, resp.text
        assert resp.json()["data"], resp.text

    def test_unknown_profile_returns_404(
        self, admin_client: httpx.Client, populate_doc: dict[str, Any]
    ) -> None:
        resp = self._populate(
            admin_client, populate_doc["slug"], f"missing-{uuid.uuid4().hex}"
        )
        assert resp.status_code == 404, resp.text
        assert "error" in resp.json()

    @pytest.mark.auth
    def test_populate_requires_token(
        self, anon_client: httpx.Client, populate_doc: dict[str, Any]
    ) -> None:
        resp = self._populate(anon_client, populate_doc["slug"], "any")
        assert resp.status_code == 401, resp.text
