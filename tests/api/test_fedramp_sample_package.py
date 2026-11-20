"""The FedRAMP sample package, uploaded through the API (#1354, #1384).

    POST /api/v1/authorization_boundaries/:id/received_documents

samples/fedramp-package-demo/ is one fictional provider's complete package:
one document per FedRAMP package schema SPARC vendors, each valid by its
schema and complete. invalid/ holds variants that each fail one documented
way. Both directories carry a manifest; these tests read their expectations
from it, so the API is held to the same list as the RSpec suite
(spec/samples/fedramp_package_demo_spec.rb).

Each test works on a throwaway phase2 boundary, removed afterwards with
everything it received.
"""

from __future__ import annotations

import hashlib
import json
import uuid
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import httpx
import pytest

pytestmark = [pytest.mark.exchange, pytest.mark.phase2]

BOUNDARIES = "/api/v1/authorization_boundaries"
PACKAGE = Path(__file__).resolve().parents[2] / "samples" / "fedramp-package-demo"
MANIFEST = json.loads((PACKAGE / "manifest.json").read_text())
INVALID_MANIFEST = json.loads((PACKAGE / "invalid" / "manifest.json").read_text())


@pytest.fixture
def boundary(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(
        BOUNDARIES,
        json={
            "authorization_boundary": {
                "name": f"phase2-boundary-fedramp-sample-{uuid.uuid4().hex[:8]}",
                "description": "Created by the FedRAMP sample package API tests (#1354)",
            }
        },
    )
    assert response.status_code in (200, 201), response.text
    record = response.json().get("data") or response.json()
    try:
        yield record
    finally:
        admin_client.delete(f"{BOUNDARIES}/{record['id']}")


def _upload(client: httpx.Client, boundary: dict[str, Any], path: Path) -> httpx.Response:
    return client.post(
        f"{BOUNDARIES}/{boundary['id']}/received_documents",
        files={"file": (path.name, path.read_bytes(), "application/json")},
    )


class TestFedrampSamplePackage:
    @pytest.mark.happy
    def test_every_document_is_stored_valid_for_review(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        for entry in MANIFEST["documents"]:
            path = PACKAGE / entry["file"]
            response = _upload(admin_client, boundary, path)
            assert response.status_code == 201, f"{entry['file']}: {response.text}"
            assert response.json()["status"] == "stored", entry["file"]
            data = response.json()["data"]
            assert data["state"] == "pending_review", entry["file"]
            assert data["valid"] is True, entry["file"]
            assert data["format"] == "fedramp", entry["file"]
            assert data["document_type"] == entry["document_type"], entry["file"]
            assert data["sha256"] == hashlib.sha256(path.read_bytes()).hexdigest()
            assert data["validation"]["errors"] == [], entry["file"]

        listed = admin_client.get(
            f"{BOUNDARIES}/{boundary['id']}/received_documents",
            params={"state": "pending_review"},
        )
        assert listed.status_code == 200, listed.text
        assert listed.json()["meta"]["count"] == len(MANIFEST["documents"])

    @pytest.mark.validation
    def test_a_blank_required_field_is_stored_invalid_with_its_error(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        entry = next(
            d for d in INVALID_MANIFEST["documents"] if d["file"] == "vdr-blank-required-field.json"
        )
        response = _upload(admin_client, boundary, PACKAGE / "invalid" / entry["file"])
        assert response.status_code == 201, response.text
        data = response.json()["data"]
        assert data["state"] == "invalid"
        assert data["valid"] is False
        assert data["validation"]["errors"] == entry["expected_errors"]
