"""Tests for evidence attestations (#440, #610).

Endpoints, nested under an evidence record:
  - index, show, create, destroy
  - export (CMS / SAF CLI shape, collection)

The lifecycle creates its own evidence through the Evidence API (#756).
Before that API existed this suite depended on an externally-supplied
SPARC_TEST_EVIDENCE_ID and skipped by default; that env var is no longer
read. Contract coverage (auth / authz / not-found) runs unconditionally.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.attestations, pytest.mark.phase2]

_EVIDENCES = "/api/v1/evidences"
_MISSING_EVIDENCE = "99999999"


def _attestations_path(evidence_id: str | int) -> str:
    return f"/api/v1/evidences/{evidence_id}/attestations"


def _admin_user_id(admin_client: httpx.Client) -> int:
    """The attesting account. Resolved from the API rather than assumed, so the
    suite does not depend on the admin happening to be user 1."""
    response = admin_client.get("/api/v1/users?per_page=100")
    assert response.status_code == 200, response.text
    return next(u["id"] for u in response.json()["data"] if u.get("admin"))


def _new_attestation_payload(admin_user_id: int = 1) -> dict[str, Any]:
    # attested_at is required (Attestation validates presence) and status is
    # bounded to Attestation::STATUSES == %w[passed failed]. This payload
    # previously sent status="current" and omitted attested_at — it never
    # failed because the lifecycle skipped by default until #756 gave the
    # suite a way to create its own evidence.
    #
    # #947 — an attestation now references an ACCOUNT, and the role it claims is
    # checked against what that account holds on the evidence's boundary.
    # `attester_name` / `attester_email` are no longer accepted: the server
    # snapshots them from the resolved account, so a request can no longer name
    # one person while referencing another.
    #
    # The admin's own id is used because an Instance Admin clears the roster
    # check the way it clears every other permission check; `so_iso` is a seeded
    # role that carries `evidence.attest`.
    return {
        "attestation": {
            "attester_user_id": admin_user_id,
            "role": "so_iso",
            "statement": "Evidence reviewed and accurate as of this test run.",
            "attested_at": "2026-01-01T00:00:00Z",
            "frequency": "quarterly",
            "status": "passed",
        }
    }


@pytest.fixture
def evidence_id(admin_client: httpx.Client) -> Iterator[str]:
    """Create a throwaway evidence record for the lifecycle, then remove it."""
    # #947 — evidence must support at least one control, and an artefact type
    # must carry its file, so the host record is created multipart.
    created = admin_client.post(
        _EVIDENCES,
        data={
            "evidence[title]": "Attestation lifecycle evidence",
            "evidence[description]": "Created by the attestation contract suite.",
            "evidence[evidence_type]": "artifact",
            "evidence[status]": "draft",
            "evidence[source]": "https://example.com/contract-suite",
            "evidence[control_ids]": "ac-2",
        },
        files={"evidence[file]": ("evidence.txt", b"attestation host artifact", "text/plain")},
    )
    assert created.status_code == 201, created.text
    evidence = created.json()["data"]
    try:
        yield str(evidence["id"])
    finally:
        admin_client.delete(f"{_EVIDENCES}/{evidence['id']}")


# ── Contract coverage (always runs) ───────────────────────────────────────

class TestAuth:
    @pytest.mark.auth
    def test_index_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(_attestations_path(1)), expected_status=401)

    @pytest.mark.auth
    def test_show_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(f"{_attestations_path(1)}/0"), expected_status=401)

    @pytest.mark.auth
    def test_create_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(_attestations_path(1), json=_new_attestation_payload()),
            expected_status=401,
        )

    @pytest.mark.auth
    def test_destroy_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.delete(f"{_attestations_path(1)}/0"), expected_status=401)

    @pytest.mark.auth
    def test_export_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{_attestations_path(1)}/export"), expected_status=401
        )


class TestNotFound:
    def test_export_unknown_evidence_returns_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{_attestations_path(_MISSING_EVIDENCE)}/export")
        assert_error_envelope(response, expected_status=404)

    def test_index_unknown_evidence_returns_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(_attestations_path(_MISSING_EVIDENCE))
        assert_error_envelope(response, expected_status=404)


class TestAuthz:
    @pytest.mark.authz
    def test_non_privileged_create_rejected(self, user_client: httpx.Client) -> None:
        # A user without evidence.write may not create. Tolerate 401/403/404
        # depending on whether the (test) evidence exists.
        response = user_client.post(
            _attestations_path(_MISSING_EVIDENCE),
            # The evidence does not exist, so the payload's attester is never
            # reached — the assertion is about the guard, not the body.
            json=_new_attestation_payload(),
        )
        assert response.status_code in (401, 403, 404), response.text


# ── Full lifecycle ────────────────────────────────────────────────────────

class TestLifecycle:
    @pytest.mark.happy
    def test_create_show_index_export_destroy(
        self, admin_client: httpx.Client, evidence_id: str
    ) -> None:
        base = _attestations_path(evidence_id)

        payload = _new_attestation_payload(_admin_user_id(admin_client))
        created = admin_client.post(base, json=payload)
        assert created.status_code == 201, created.text
        attestation = created.json()["data"]
        att_id = attestation["id"]
        assert attestation["signature_hash"], "create must return a signature_hash"

        try:
            shown = admin_client.get(f"{base}/{att_id}")
            assert shown.status_code == 200, shown.text
            assert shown.json()["data"]["id"] == att_id

            listed = admin_client.get(base)
            assert listed.status_code == 200, listed.text
            ids = [a["id"] for a in listed.json()["data"]]
            assert att_id in ids

            exported = admin_client.get(f"{base}/export")
            assert exported.status_code == 200, exported.text
            assert exported.json()["meta"]["schema"] == "cms-attestation-v1"
        finally:
            deleted = admin_client.delete(f"{base}/{att_id}")
            assert deleted.status_code == 204, deleted.text

    @pytest.mark.validation
    def test_invalid_payload_returns_422(
        self, admin_client: httpx.Client, evidence_id: str
    ) -> None:
        """An attestation present but empty fails model validation -> 422."""
        response = admin_client.post(
            _attestations_path(evidence_id), json={"attestation": {"attester_name": ""}}
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_missing_root_key_returns_400(
        self, admin_client: httpx.Client, evidence_id: str
    ) -> None:
        """A payload with no `attestation` key is malformed, not unprocessable.

        Previously escaped `params.require` uncaught and returned Rails' HTML
        error page from a JSON endpoint. 400 per docs/api/errors.md.
        """
        response = admin_client.post(_attestations_path(evidence_id), json={})
        assert_error_envelope(response, expected_status=400)
