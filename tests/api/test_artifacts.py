"""Tests for /api/v1/artifacts — the durable artifact resolver (#680).

Resolves an immutable artifact UUID (`show`) or a specific content version
(`version`) to a freshly-signed download URL. The happy path needs an Evidence
record with an attached blob + uuid (heavier fixture); here we cover the
deterministic contract edges — unknown uuid → 404, unauthenticated → 401 —
which is what an external consumer hits first.
"""

from __future__ import annotations

import uuid

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = pytest.mark.phase1

BASE = "/api/v1/artifacts"


class TestArtifactResolver:
    def test_unknown_uuid_returns_404(self, admin_client: httpx.Client) -> None:
        assert_error_envelope(
            admin_client.get(f"{BASE}/{uuid.uuid4()}"), expected_status=404
        )

    def test_unknown_version_uuid_returns_404(self, admin_client: httpx.Client) -> None:
        # /api/v1/artifacts/versions/:uuid — resolve a specific content version.
        assert_error_envelope(
            admin_client.get(f"{BASE}/versions/{uuid.uuid4()}"), expected_status=404
        )

    @pytest.mark.auth
    def test_show_requires_token(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{BASE}/{uuid.uuid4()}"), expected_status=401
        )

    @pytest.mark.auth
    def test_version_requires_token(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{BASE}/versions/{uuid.uuid4()}"), expected_status=401
        )
