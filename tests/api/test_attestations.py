"""Tests for evidence attestations (#440, #610).

Endpoints, nested under an evidence record:
  - index, show, create, destroy
  - export (CMS / SAF CLI shape, collection)

SPARC has no Evidence-creation API (evidence is created in the UI or
seeded), so the full create -> show -> index -> export -> destroy lifecycle
runs only when an existing evidence id is supplied via the optional
SPARC_TEST_EVIDENCE_ID env var. Contract coverage (auth / authz / not-found)
runs unconditionally.
"""

from __future__ import annotations

import os
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.attestations, pytest.mark.phase2]

_EVIDENCE_ID = os.environ.get("SPARC_TEST_EVIDENCE_ID")
_MISSING_EVIDENCE = "99999999"


def _attestations_path(evidence_id: str | int) -> str:
    return f"/api/v1/evidences/{evidence_id}/attestations"


def _new_attestation_payload() -> dict[str, Any]:
    return {
        "attestation": {
            "attester_name": "Phase2 Reviewer",
            "attester_email": "phase2@example.com",
            "role": "isso",
            "statement": "Evidence reviewed and accurate as of this test run.",
            "frequency": "quarterly",
            "status": "current",
        }
    }


@pytest.fixture
def evidence_id() -> str:
    if not _EVIDENCE_ID:
        pytest.skip(
            "Set SPARC_TEST_EVIDENCE_ID to an existing evidence id to run the "
            "attestation lifecycle (SPARC has no evidence-creation API)."
        )
    return _EVIDENCE_ID


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
            _attestations_path(_EVIDENCE_ID or _MISSING_EVIDENCE),
            json=_new_attestation_payload(),
        )
        assert response.status_code in (401, 403, 404), response.text


# ── Full lifecycle (requires SPARC_TEST_EVIDENCE_ID) ──────────────────────

class TestLifecycle:
    @pytest.mark.happy
    def test_create_show_index_export_destroy(
        self, admin_client: httpx.Client, evidence_id: str
    ) -> None:
        base = _attestations_path(evidence_id)

        created = admin_client.post(base, json=_new_attestation_payload())
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
        response = admin_client.post(_attestations_path(evidence_id), json={"attestation": {}})
        assert_error_envelope(response, expected_status=422)
