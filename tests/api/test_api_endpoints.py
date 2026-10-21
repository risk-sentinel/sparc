"""Tests for GET /api/v1/api_endpoints (#1176).

What an API token's `allowed_endpoints` may name: every resource group, the
Read/Write levels its routes have, and the entries to send. Read from the same
definition the token forms show and the authentication check enforces.
"""

from __future__ import annotations

import httpx
import pytest

pytestmark = [pytest.mark.admin, pytest.mark.phase2]


class TestIndex:
    @pytest.mark.happy
    def test_lists_groups_levels_and_entries(self, admin_client: httpx.Client) -> None:
        response = admin_client.get("/api/v1/api_endpoints")
        assert response.status_code == 200, response.text

        groups = {g["group"]: g for g in response.json()["data"]}
        assert groups["ssp_documents"]["entries"] == [
            "ssp_documents:read", "ssp_documents:write",
        ]
        # A group whose routes only read offers no Write entry.
        assert groups["oscal"]["access_levels"] == ["read"]
        assert response.json()["meta"]["all_endpoints"] == "*"

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert anon_client.get("/api/v1/api_endpoints").status_code == 401

    @pytest.mark.authz
    def test_a_non_admin_cannot_read_it(self, user_client: httpx.Client) -> None:
        assert user_client.get("/api/v1/api_endpoints").status_code == 403
