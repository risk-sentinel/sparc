"""Tests for GET /up and GET /up/ready (#1151).

The probes a load balancer points at. Until #1151 neither route existed, so
the health check in front of a deployment hit NGINX, which knows nothing about
Rails, the database or the schema — and a v1.16.2 upgrade with seven missing
columns reported healthy at every layer while serving 500s.

This suite runs against a DEPLOYED image, so it asserts what an orchestrator
relies on: no credentials needed, a stable body, a healthy instance reports
ready, and an unauthenticated caller learns counts — never names.

The unhealthy direction (503 on drift, on a pending migration, on a lost
database) needs a broken instance and is covered in
spec/requests/health_spec.rb, where the database can be damaged safely.

Read-only: no fixtures, no cleanup, nothing created.
"""

from __future__ import annotations

import httpx
import pytest

pytestmark = [pytest.mark.health, pytest.mark.phase2]


class TestLiveness:
    @pytest.mark.happy
    def test_answers_without_credentials(self, anon_client: httpx.Client) -> None:
        response = anon_client.get("/up")
        assert response.status_code == 200, response.text
        assert response.json() == {"status": "ok"}

    @pytest.mark.happy
    def test_is_not_redirected_to_a_login(self, anon_client: httpx.Client) -> None:
        response = anon_client.get("/up", follow_redirects=False)
        assert response.status_code == 200, (
            f"a probe must be answered, not redirected: {response.status_code} "
            f"{response.headers.get('location')}"
        )


class TestReadiness:
    @pytest.mark.happy
    def test_a_healthy_instance_is_ready(self, anon_client: httpx.Client) -> None:
        response = anon_client.get("/up/ready", follow_redirects=False)
        assert response.status_code == 200, response.text

        body = response.json()
        assert body["status"] == "ok"
        assert body["checks"] == {
            "database": "ok",
            "pending_migrations": 0,
            "schema_drift": 0,
        }

    @pytest.mark.happy
    def test_discloses_counts_only(self, anon_client: httpx.Client) -> None:
        """Every value under `checks` is a state word or a count — never a name."""
        body = anon_client.get("/up/ready").json()
        assert set(body) == {"status", "checks"}
        for key, value in body["checks"].items():
            assert isinstance(value, int) or value in ("ok", "unavailable"), (key, value)
