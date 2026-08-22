"""Tests for /api/v1/artifacts — the durable artifact resolver (#680).

Resolves an immutable artifact UUID (`show`) or a specific content version
(`version`) to a freshly-signed download URL.

This module used to cover only the deterministic edges — unknown uuid -> 404,
unauthenticated -> 401 — on the grounds that a happy path needs an Evidence
record with an attached blob. That left the thing the resolver is FOR entirely
unasserted: nothing here proved a real artifact resolves at all, so the module
would have passed against a `show` that always 404'd (#995). The fixture below
creates its own evidence with a file, which is what the evidence suite already
does, so the heavier fixture was never actually out of reach.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = pytest.mark.phase1

BASE = "/api/v1/artifacts"
_EVIDENCES = "/api/v1/evidences"


@pytest.fixture
def artifact(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    """An evidence record carrying a real attached file, and its own cleanup."""
    response = admin_client.post(
        _EVIDENCES,
        data={
            "evidence[title]": "Artifact resolver fixture",
            "evidence[description]": "Created by the API contract suite.",
            "evidence[evidence_type]": "artifact",
            "evidence[status]": "draft",
            "evidence[source]": "https://example.com/contract-suite",
            "evidence[control_ids]": "cm-6",
        },
        files={"evidence[file]": ("resolver.txt", b"durable artifact bytes", "text/plain")},
    )
    assert response.status_code == 201, response.text
    record = response.json()["data"]
    try:
        yield record
    finally:
        admin_client.delete(f"{_EVIDENCES}/{record['id']}")


class TestArtifactResolution:
    """The resolver's actual job, asserted on the response body."""

    @pytest.mark.happy
    def test_resolves_a_real_artifact_to_its_metadata_and_a_url(
        self, admin_client: httpx.Client, artifact: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{BASE}/{artifact['uuid']}")
        assert response.status_code == 200, response.text

        data = response.json()["data"]
        assert data["uuid"] == artifact["uuid"]
        assert data["title"] == "Artifact resolver fixture"
        assert data["filename"] == "resolver.txt"
        assert data["media_type"] == "text/plain"
        assert data["url"], "the resolver returned no download URL"

    @pytest.mark.happy
    def test_the_url_is_a_signed_blob_on_the_cookieless_user_content_origin(
        self, base_url: str, admin_client: httpx.Client, artifact: dict[str, Any]
    ) -> None:
        """The URL must be signed, and must NOT be on the application origin.

        #515 serves uploaded blobs from a cookieless `userdata.*` subdomain so
        the browser never sends the SPARC session cookie to user-controlled
        content. That is a security property of the resolver's output and
        nothing asserted it — a change that emitted app-origin blob URLs would
        have been caught by no test here.

        The bytes themselves are deliberately not fetched: the `userdata.*`
        origin is a separate host that this suite does not resolve locally, and
        a check that can only pass in one environment is worse than one that
        states what it verifies. The browser-side fetch belongs to ui-smoke.
        """
        resolved = admin_client.get(f"{BASE}/{artifact['uuid']}")
        assert resolved.status_code == 200, resolved.text
        url = resolved.json()["data"]["url"]

        assert url.startswith("https://"), url
        assert "/rails/active_storage/blobs/redirect/" in url, url
        assert url.endswith("resolver.txt?disposition=attachment"), url

        app_host = httpx.URL(base_url).host
        blob_host = httpx.URL(url).host
        assert blob_host != app_host, (
            f"blob URL is on the application origin ({blob_host}); #515 requires the "
            f"cookieless user-content origin so the session cookie is never sent with it"
        )
        assert blob_host.startswith("userdata."), blob_host

    @pytest.mark.happy
    def test_lists_the_versions_of_a_real_artifact(
        self, admin_client: httpx.Client, artifact: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{BASE}/{artifact['uuid']}/versions")
        assert response.status_code == 200, response.text

        payload = response.json()
        data = payload["data"]
        assert data["uuid"] == artifact["uuid"]
        assert data["current_version_uuid"], data

        versions = data["versions"]
        assert isinstance(versions, list), payload
        assert versions, "an artifact with an attached file reported no versions"
        assert payload["meta"]["count"] == len(versions), payload
        assert any(v["current"] for v in versions), versions


class TestArtifactResolver:
    def test_unknown_uuid_returns_404(self, admin_client: httpx.Client) -> None:
        assert_error_envelope(admin_client.get(f"{BASE}/{uuid.uuid4()}"), expected_status=404)

    def test_unknown_version_uuid_returns_404(self, admin_client: httpx.Client) -> None:
        # /api/v1/artifacts/versions/:uuid — resolve a specific content version.
        assert_error_envelope(
            admin_client.get(f"{BASE}/versions/{uuid.uuid4()}"), expected_status=404
        )

    @pytest.mark.auth
    def test_show_requires_token(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(f"{BASE}/{uuid.uuid4()}"), expected_status=401)

    @pytest.mark.auth
    def test_version_requires_token(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{BASE}/versions/{uuid.uuid4()}"), expected_status=401
        )


# api-inventory: covers artifacts#freshness
class TestFreshness:
    """`GET /artifacts/:uuid/freshness` — when this artifact was last reviewed
    and whether that is now overdue.

    Enablement only, and the endpoint says so in its own payload: SPARC reports
    freshness as DATA and the compliance assertion is made by the consuming
    system. So these assert the arithmetic is self-consistent, not that any
    particular artifact is compliant.
    """

    @pytest.mark.happy
    def test_reports_freshness_for_a_real_artifact(
        self, admin_client: httpx.Client, artifact: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{BASE}/{artifact['uuid']}/freshness")

        assert response.status_code == 200, response.text
        data = response.json()["data"]
        assert data["uuid"] == artifact["uuid"]
        assert data["title"] == "Artifact resolver fixture"
        assert "overdue" in data and isinstance(data["overdue"], bool)
        assert "note" in data, "the enablement-only caveat is part of the contract"

    @pytest.mark.happy
    def test_an_artifact_with_no_review_cadence_has_no_due_date(
        self, admin_client: httpx.Client, artifact: dict[str, Any]
    ) -> None:
        """A due date needs a cadence, not just a last-reviewed timestamp.

        The fixture carries no attestation, so nothing declares how often it
        must be re-reviewed. `next_review_due` is therefore null and the
        artifact cannot be overdue — inventing a due date from a default
        interval would manufacture a finding out of an absence of data, which is
        the opposite of what an enablement endpoint should do.
        """
        data = admin_client.get(f"{BASE}/{artifact['uuid']}/freshness").json()["data"]

        assert data["last_reviewed_at"], "the artifact records no review at all"
        assert data["review_frequency"] is None, data
        assert data["next_review_due"] is None, (
            "a due date appeared with no attestation declaring a cadence"
        )
        assert data["overdue"] is False, data
        assert data["days_overdue"] == 0, data

    @pytest.mark.happy
    def test_days_overdue_agrees_with_the_overdue_flag(
        self, admin_client: httpx.Client, artifact: dict[str, Any]
    ) -> None:
        """The two are computed separately, so they can disagree. A consumer
        branching on `overdue` and displaying `days_overdue` would then show a
        contradiction."""
        data = admin_client.get(f"{BASE}/{artifact['uuid']}/freshness").json()["data"]

        if data["overdue"]:
            assert data["days_overdue"] > 0, data
        else:
            assert data["days_overdue"] == 0, data

    @pytest.mark.validation
    def test_an_unknown_uuid_is_a_json_404(self, admin_client: httpx.Client) -> None:
        assert_error_envelope(
            admin_client.get(f"{BASE}/{uuid.uuid4()}/freshness"), expected_status=404
        )

    @pytest.mark.auth
    def test_an_anonymous_caller_is_refused(
        self, anon_client: httpx.Client, artifact: dict[str, Any]
    ) -> None:
        assert anon_client.get(f"{BASE}/{artifact['uuid']}/freshness").status_code == 401
