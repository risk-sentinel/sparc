"""Tests for /api/v1/federation/identity (#1155).

The federation's identity constants — the namespace URI and the namespace
UUID every peer derives object identity against.

What these assertions protect is AGREEMENT. Object UUIDs are UUIDv5 derived
against one namespace UUID, and peers deduplicate without coordinating only
while every instance uses the same one. Two peers disagreeing does not raise
an error: the same logical object simply arrives under a second identity and
nothing reconciles it (#1159). So the contract asserted here is that the
published recipe actually computes the published value, checked by running the
derivation in Python rather than restating the constant — which also proves
Ruby's Digest::UUID and Python's uuid5 agree, the property #1161 formalises.

Read-only reference data: no fixtures, no cleanup, nothing created.
"""

from __future__ import annotations

import uuid

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.federation, pytest.mark.phase2]


PATH = "/api/v1/federation/identity"

# The registered values (#1155, owner-decided 2026-09-21). Repeated here
# deliberately: this suite runs against a DEPLOYED image, so it is the only
# place that can catch the constant being changed in code and in the Ruby spec
# together.
NAMESPACE_URI = "https://sparc.risk-sentinel.org/ns"
FEDERATION_UUID = "9f434272-f796-589b-b972-954790395630"


class TestIdentity:
    @pytest.mark.happy
    def test_serves_the_registered_identity(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(PATH)
        assert response.status_code == 200, response.text

        data = response.json()["data"]
        assert data["namespace_uri"] == NAMESPACE_URI
        assert data["federation_namespace_uuid"] == FEDERATION_UUID

    @pytest.mark.happy
    def test_published_recipe_computes_the_published_uuid(
        self, admin_client: httpx.Client
    ) -> None:
        """Derive it here rather than trust it.

        A peer is told the method, the namespace and the name; running that
        must reproduce the UUID sitting beside it. This is the assertion that
        makes the endpoint usable without copying a literal.
        """
        data = admin_client.get(PATH).json()["data"]
        derivation = data["derivation"]

        assert derivation["method"] == "uuidv5"
        assert derivation["namespace"] == "url"

        recomputed = uuid.uuid5(uuid.NAMESPACE_URL, derivation["name"])
        assert str(recomputed) == data["federation_namespace_uuid"]

    @pytest.mark.happy
    def test_reports_the_deployment_namespace_separately(
        self, admin_client: httpx.Client
    ) -> None:
        """The operator's local vocabulary is a different thing.

        It defaults to SPARC's own entry, so the two coincide on a default
        deployment; the point is that they are reported as separate fields and
        an integrator is not left assuming one from the other.
        """
        body = admin_client.get(PATH).json()

        assert "instance_namespace" in body["meta"]
        assert body["meta"]["api_version"] == "v1"

    @pytest.mark.happy
    def test_is_stable_across_calls(self, admin_client: httpx.Client) -> None:
        """Identity constants must not vary per request."""
        first = admin_client.get(PATH).json()["data"]
        second = admin_client.get(PATH).json()["data"]

        assert first == second

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(PATH), expected_status=401)


class TestDiscovery:
    @pytest.mark.happy
    def test_not_listed_in_discovery(self, admin_client: httpx.Client) -> None:
        """Deliberately absent, following the precedent /api/v1/guides set.

        That registry advertises the scoped compliance-data surface; a
        permission-free reference endpoint listed there would dilute the
        least-privilege view a no-permission caller sees. Asserted so that
        adding it later is a decision rather than an accident.
        """
        response = admin_client.get("/api/v1/available")
        assert response.status_code == 200, response.text

        paths = [endpoint["path"] for endpoint in response.json()["endpoints"]]
        assert PATH not in paths
