"""Tests for POST /api/v1/document_validations (#1354, #1384).

The endpoint checks a FedRAMP package, OSCAL, HDF or XCCDF document against
the schemas SPARC pins, and checks that every field those schemas require is
filled in. It stores nothing. A document that can be checked gets 200 with
`valid` true or false; one that cannot be checked at all gets 422.
"""

from __future__ import annotations

import json

import httpx
import pytest

pytestmark = [pytest.mark.document_validations, pytest.mark.phase2]

PATH = "/api/v1/document_validations"


def _vdr(description: str = "Outdated library") -> dict:
    return {
        "certificationPackageOverviewUri": "https://provider.example/package/cpo.json",
        "reportPeriod": {"from": "2026-10-01T00:00:00Z", "to": "2026-10-31T23:59:59Z"},
        "vulnerabilities": [
            {
                "providerTrackingId": "VULN-1",
                "detection": {"detectedAt": "2026-10-02T10:00:00Z", "detectionSource": "scanner"},
                "vulnerabilityDescription": description,
            }
        ],
    }


def _post_json(client: httpx.Client, body: dict, **params: str) -> httpx.Response:
    return client.post(
        PATH,
        params=params or None,
        content=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )


class TestDocumentValidations:
    @pytest.mark.happy
    def test_complete_fedramp_report_is_valid(self, admin_client: httpx.Client) -> None:
        response = _post_json(admin_client, _vdr())
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["valid"] is True, body
        assert body["format"] == "fedramp"
        assert body["document_type"] == "vulnerability-detail-report"
        assert len(body["schema"]["sha256"]) == 64

    def test_blank_required_field_is_reported(self, admin_client: httpx.Client) -> None:
        response = _post_json(admin_client, _vdr(description="  "))
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["valid"] is False
        assert {
            "check": "completeness",
            "pointer": "/vulnerabilities/0/vulnerabilityDescription",
            "message": "required field is blank",
        } in body["errors"], body["errors"]

    @pytest.mark.happy
    def test_multipart_upload(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(
            PATH, files={"file": ("vdr.json", json.dumps(_vdr()).encode(), "application/json")}
        )
        assert response.status_code == 200, response.text
        assert response.json()["valid"] is True

    def test_document_type_parameter(self, admin_client: httpx.Client) -> None:
        response = _post_json(
            admin_client,
            {"certificationPackageOverviewUri": "https://x.example/cpo.json"},
            document_format="fedramp",
            document_type="incident-report",
        )
        assert response.status_code == 200, response.text
        assert response.json()["document_type"] == "incident-report"
        assert response.json()["valid"] is False

    def test_unreadable_document_is_422(self, admin_client: httpx.Client) -> None:
        response = admin_client.post(
            PATH, content=b"not json", headers={"Content-Type": "text/plain"}
        )
        assert response.status_code == 422, response.text
        assert response.json()["error"] == "The document could not be checked"

    def test_requires_a_token(self, anon_client: httpx.Client) -> None:
        response = _post_json(anon_client, _vdr())
        assert response.status_code == 401, response.text
