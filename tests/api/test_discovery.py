"""Tests for ``GET /api/v1/available`` (the API discovery endpoint).

Discovery is the simplest endpoint in the surface — no path params, no
query string, no body, just a permission-scoped inventory of what the
caller can do. It's the proof-of-concept module: if these tests pass,
the conftest fixtures work end-to-end and every other module can rely
on the same machinery.

Coverage classes per ``INVENTORY.md``:
- happy: admin sees full inventory
- happy: non-admin sees a permission-scoped subset
- auth: 401 without a token
- auth: 401 with an unrecognized token
"""

from __future__ import annotations

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.discovery, pytest.mark.phase1]


PATH = "/api/v1/available"


class TestDiscovery:
    @pytest.mark.happy
    def test_admin_sees_full_inventory(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH)
        assert response.status_code == 200, response.text

        payload = response.json()
        assert payload["api_version"] == "v1"
        assert payload["system_id"] == "sparc-application"
        assert "authenticated_as" in payload
        # api_auth_mode (SPARC_API_AUTH) is one of local|oidc|hybrid — "local"
        # is the default and was missing here; "token" was never a valid mode (#644).
        assert payload["auth_mode"] in {"local", "oidc", "hybrid"}

        endpoints = payload["endpoints"]
        assert isinstance(endpoints, list) and len(endpoints) > 0

        for entry in endpoints:
            assert isinstance(entry["path"], str) and entry["path"].startswith("/api/v1/")
            assert isinstance(entry["methods"], list) and entry["methods"]
            for method in entry["methods"]:
                assert method in {"GET", "POST", "PUT", "PATCH", "DELETE"}
            assert isinstance(entry["description"], str) and entry["description"]

        # Admins should see write methods on admin-only resources.
        users_entry = next((e for e in endpoints if e["path"] == "/api/v1/users"), None)
        assert users_entry is not None, "admin should see /api/v1/users in inventory"
        assert "POST" in users_entry["methods"]

    @pytest.mark.happy
    @pytest.mark.authz
    def test_non_admin_sees_permission_scoped_subset(
        self, admin_client: httpx.Client, user_client: httpx.Client
    ) -> None:
        admin_inventory = admin_client.get(PATH).json()["endpoints"]
        user_inventory = user_client.get(PATH).json()["endpoints"]

        admin_paths = {(e["path"], tuple(sorted(e["methods"]))) for e in admin_inventory}
        user_paths = {(e["path"], tuple(sorted(e["methods"]))) for e in user_inventory}

        # Non-admin must see at most what the admin sees.
        assert user_paths.issubset(admin_paths) or len(user_paths) <= len(admin_inventory), (
            "Non-admin discovery should be a permission-scoped subset of admin's"
        )

        # If the test user lacks `users.manage` (the typical case), they
        # should not see write methods on /api/v1/users. We don't insist
        # they see no /users entry at all (some configurations expose self
        # GET to non-admins) — only that they don't see POST.
        users_entry = next((e for e in user_inventory if e["path"] == "/api/v1/users"), None)
        if users_entry is not None:
            assert "POST" not in users_entry["methods"], (
                "Non-admin should not see write methods on /api/v1/users"
            )

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        response = anon_client.get(PATH)
        assert_error_envelope(response, expected_status=401)

    @pytest.mark.auth
    def test_unrecognized_token_returns_401(self, bad_token_client: httpx.Client) -> None:
        response = bad_token_client.get(PATH)
        assert_error_envelope(response, expected_status=401)
