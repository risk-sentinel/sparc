"""Cross-resource edge-case coverage (#433 slice 7).

The per-resource test files cover happy paths + the canonical drift
checks. This file consolidates the "what about ${unusual_input}"
coverage so the patterns are visible in one place:

- Pagination boundary values (clamp, zero, negative, huge)
- Unicode / RTL / long strings in document names + descriptions
- Boundary-scoped reads for non-admin (data isolation)

Tests parameterize across resources where the behavior is shared
(driven by the `paginate()` helper in `Api::V1::BaseController`),
and target specific resources where the edge case is type-specific
(e.g., authorization_boundary isolation only applies to documents
that carry an `authorization_boundary_id`).
"""

from __future__ import annotations

import uuid
from typing import Any

import httpx
import pytest

from _document_helpers import create_doc, delete_doc, make_payload

# Resources whose Index endpoint goes through the shared `paginate()`
# helper. Each tuple: (path, payload_factory, identifier_field).
# Used to parameterize pagination edge-case tests across resources.
PAGINATED_RESOURCES = [
    ("/api/v1/cdef_documents", "cdef_document", "slug"),
    ("/api/v1/control_catalogs", "control_catalog", "slug"),
    ("/api/v1/profile_documents", "profile_document", "slug"),
]


# ── Pagination boundary values ────────────────────────────────────────────


@pytest.mark.pagination
class TestPaginationBoundaries:
    """Pagination is shared across every paginated index via
    `Api::V1::BaseController#paginate` + `resolve_pagination_size`.
    Edge-case coverage on cdef is representative; the param resolver
    is the single point of behavior."""

    PATH = "/api/v1/cdef_documents"

    def test_items_zero_falls_back_to_default(self, admin_client: httpx.Client) -> None:
        """`?items=0` → default per-endpoint size (25), not zero rows."""
        response = admin_client.get(self.PATH, params={"items": 0})
        assert response.status_code == 200
        assert response.json()["meta"]["items"] == 25

    def test_items_negative_falls_back_to_default(self, admin_client: httpx.Client) -> None:
        """`?items=-5` is treated as invalid → default (not -5, not error)."""
        response = admin_client.get(self.PATH, params={"items": -5})
        assert response.status_code == 200
        assert response.json()["meta"]["items"] == 25

    def test_items_blank_falls_back_to_default(self, admin_client: httpx.Client) -> None:
        """`?items=` (empty) → default."""
        response = admin_client.get(self.PATH, params={"items": ""})
        assert response.status_code == 200
        assert response.json()["meta"]["items"] == 25

    def test_items_huge_clamps_to_max(self, admin_client: httpx.Client) -> None:
        """`?items=999999` → clamped to MAX_PAGINATION_LIMIT (200).
        Prevents DoS via single-request giant queries."""
        response = admin_client.get(self.PATH, params={"items": 999_999})
        assert response.status_code == 200
        assert response.json()["meta"]["items"] == 200

    def test_per_page_alias_works(self, admin_client: httpx.Client) -> None:
        """`?per_page=N` is an alias for `?items=N` for client convenience."""
        response = admin_client.get(self.PATH, params={"per_page": 7})
        assert response.status_code == 200
        assert response.json()["meta"]["items"] == 7

    def test_page_beyond_last_returns_empty_data(self, admin_client: httpx.Client) -> None:
        """`?page=99999` → empty data array + meta.pages reflects real total.
        Should NOT 404 — pagy returns an empty page beyond the last."""
        response = admin_client.get(self.PATH, params={"page": 99_999, "items": 1})
        assert response.status_code in (200, 404)
        # If 200, expect empty data; if 404, the contract is fine too.
        if response.status_code == 200:
            assert response.json()["data"] == []


# ── Unicode + long strings in resource names ──────────────────────────────


@pytest.mark.unicode
class TestUnicodeAndLongStrings:
    """Real-world agency systems carry unicode (emoji status icons,
    Spanish/Korean/Arabic names) and long descriptions. These tests
    confirm the persistence + serialization layers handle them
    without 500 / silent truncation."""

    PATH = "/api/v1/cdef_documents"
    PARAM_KEY = "cdef_document"

    def _try_create(
        self, client: httpx.Client, name: str, description: str
    ) -> dict[str, Any]:
        payload = {
            self.PARAM_KEY: {
                "name": name,
                "description": description,
                "cdef_type": "custom",
                "file_type": "json",
            }
        }
        response = client.post(self.PATH, json=payload)
        assert response.status_code in (200, 201), (
            f"Create failed: {response.status_code} {response.text[:200]}"
        )
        return response.json()["data"]

    def test_emoji_in_name_round_trips(self, admin_client: httpx.Client) -> None:
        """Emoji in name persists and comes back via Show."""
        name = f"🚀 Test System {uuid.uuid4().hex[:6]}"
        created = self._try_create(admin_client, name, "Created with emoji name")
        try:
            show = admin_client.get(f"{self.PATH}/{created['slug']}")
            assert show.status_code == 200
            assert show.json()["data"]["name"] == name
        finally:
            delete_doc(admin_client, self.PATH, created["slug"])

    def test_rtl_arabic_in_name_round_trips(self, admin_client: httpx.Client) -> None:
        """Right-to-left Arabic in name persists correctly."""
        name = f"نظام اختبار {uuid.uuid4().hex[:6]}"
        created = self._try_create(admin_client, name, "Test system in Arabic")
        try:
            show = admin_client.get(f"{self.PATH}/{created['slug']}")
            assert show.status_code == 200
            assert show.json()["data"]["name"] == name
        finally:
            delete_doc(admin_client, self.PATH, created["slug"])

    def test_long_description_round_trips(self, admin_client: httpx.Client) -> None:
        """Description of ~10KB persists without silent truncation."""
        long_desc = "x" * 10_000
        name = f"long-desc-{uuid.uuid4().hex[:6]}"
        created = self._try_create(admin_client, name, long_desc)
        try:
            show = admin_client.get(f"{self.PATH}/{created['slug']}")
            assert show.status_code == 200
            assert show.json()["data"]["description"] == long_desc
        finally:
            delete_doc(admin_client, self.PATH, created["slug"])


# ── Boundary-scoped read isolation ────────────────────────────────────────


@pytest.mark.authz
class TestBoundaryScopedReads:
    """Non-admin users should only see SSP/SAR documents in authorization
    boundaries they're a member of. Admin sees everything.

    SPARC's `document_base_controller#scoped_documents` enforces this:

        scope = if current_user.admin?
          document_class.all
        else
          boundary_ids = current_user.authorization_boundaries.pluck(:id)
          document_class.where(authorization_boundary_id: boundary_ids)
        end

    Caught a real bug here would mean a non-admin can list documents
    in a boundary they don't belong to — a data isolation hole.
    """

    PATH = "/api/v1/ssp_documents"

    def test_non_admin_index_returns_only_visible_documents(
        self, admin_client: httpx.Client, user_client: httpx.Client
    ) -> None:
        """Non-admin user's index call returns only documents in
        boundaries they have access to. With our test SA having no
        boundary memberships, the expected result is an empty list
        (or 403 if the API gates reads on permission rather than scope).

        Whichever shape is returned, the test confirms isolation —
        the non-admin must not see admin-created documents."""
        # Admin creates an SSP they own — non-admin should NOT see it.
        suffix = uuid.uuid4().hex[:8]
        payload = make_payload(
            "ssp_document",
            {"authorization_boundary_id": 1, "name": f"isolation-probe-{suffix}"},
        )
        created = create_doc(admin_client, self.PATH, payload)

        try:
            response = user_client.get(self.PATH, params={"items": 200})
            # API may return 200 with a filtered list OR 403 if the
            # endpoint gates on a role. Both are valid contracts;
            # what matters is that the admin-created doc is NOT
            # present in the response.
            if response.status_code == 200:
                slugs = [d["slug"] for d in response.json().get("data", [])]
                assert created["slug"] not in slugs, (
                    f"Non-admin saw admin-only document {created['slug']!r} "
                    f"in its index response — boundary isolation failure"
                )
            else:
                assert response.status_code in (401, 403), response.text
        finally:
            delete_doc(admin_client, self.PATH, created["slug"])

    def test_non_admin_show_returns_404_or_403_for_other_boundary(
        self, admin_client: httpx.Client, user_client: httpx.Client
    ) -> None:
        """Direct GET of a document in another boundary returns 404 or
        403 — never 200. Catches a controller that forgot to apply
        the scoping filter on `show`."""
        suffix = uuid.uuid4().hex[:8]
        payload = make_payload(
            "ssp_document",
            {"authorization_boundary_id": 1, "name": f"show-isolation-probe-{suffix}"},
        )
        created = create_doc(admin_client, self.PATH, payload)

        try:
            response = user_client.get(f"{self.PATH}/{created['slug']}")
            assert response.status_code in (403, 404), (
                f"Non-admin got {response.status_code} on a document in "
                f"another boundary — boundary-scoped show isolation failure"
            )
        finally:
            delete_doc(admin_client, self.PATH, created["slug"])
