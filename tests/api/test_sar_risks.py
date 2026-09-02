"""Tests for SAR risks (#1090).

Five logical endpoints, nested on a SAR document:
  - index, create           (/api/v1/sar_documents/:sar_document_id/risks)
  - show, update, destroy   (/api/v1/sar_risks/:id)

SAR risks had NO API at all before this. POA&M has eight sub-resource
controllers; SAR had none, so a risk was reachable only through the enrich
screen, which accepted `title`, `description` and `status`. `impact` and
`likelihood` — the OSCAL rating — could not be set anywhere, and the columns sat
blank on every risk in the estate.

The contract pinned here is therefore two things: that the endpoints exist and
behave like their POA&M siblings, and that a RATING set through the API comes
back as the OSCAL facets it will actually export as. A rating a client cannot
verify is the defect #1090 fixed.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _crud_contract import CrudContract

pytestmark = [pytest.mark.sar_risks, pytest.mark.phase2]

_SAR_DOCS = "/api/v1/sar_documents"
_RISKS = "/api/v1/sar_risks"

# OSCAL requires these four on a risk. `deadline` is NOT among them: POA&M
# requires one because a plan needs a time commitment, which is a SPARC rule
# about POA&Ms rather than an OSCAL rule about assessment results.
REQUIRED_FIELDS = ("title", "description", "statement", "status")


def _complete_risk() -> dict[str, Any]:
    return {
        "title": "Unpatched TLS library in the web tier",
        "description": "The deployed image carries a TLS library with a known flaw.",
        "statement": "An attacker on the path could downgrade the connection.",
        "status": "open",
        "impact": "high",
        "likelihood": "moderate",
    }


def _existing_sar(client: httpx.Client) -> dict[str, Any]:
    rows = client.get(_SAR_DOCS, params={"items": 50}).json()["data"]
    assert rows, "no SAR document on this instance"
    # A risk hangs off a RESULT, so only a SAR that has one can take a risk.
    for row in rows:
        probe = client.post(
            f"{_SAR_DOCS}/{row['id']}/risks", json={"sar_risk": _complete_risk()}
        )
        if probe.status_code == 201:
            client.delete(f"{_RISKS}/{probe.json()['data']['id']}")
            return row
    pytest.skip("no SAR document on this instance has a result to attach a risk to")


@pytest.fixture
def sar_doc(admin_client: httpx.Client) -> dict[str, Any]:
    return _existing_sar(admin_client)


def _risks_path(doc: dict[str, Any]) -> str:
    return f"{_SAR_DOCS}/{doc['id']}/risks"


@pytest.fixture
def risk(admin_client: httpx.Client, sar_doc: dict[str, Any]) -> Iterator[dict[str, Any]]:
    resp = admin_client.post(_risks_path(sar_doc), json={"sar_risk": _complete_risk()})
    assert resp.status_code == 201, resp.text
    created = resp.json()["data"]
    try:
        yield created
    finally:
        admin_client.delete(f"{_RISKS}/{created['id']}")


class TestCrudContract(CrudContract):
    PARAM_KEY = "sar_risk"
    IDENTIFIER = "id"

    def _base_path(self, admin_client):
        return _risks_path(_existing_sar(admin_client))

    def _payload(self, admin_client):
        return {
            "title": f"contract risk {uuid.uuid4().hex[:6]}",
            "description": "Created by the contract suite",
            "statement": "Risk statement",
            "status": "open",
        }

    def _update_fields(self):
        return {"title": f"renamed {uuid.uuid4().hex[:6]}"}

    def _url(self, client, record):
        return f"{_RISKS}/{record['id']}"


class TestCreate:
    @pytest.mark.happy
    def test_creates_a_risk_carrying_its_rating(
        self, admin_client: httpx.Client, sar_doc: dict[str, Any]
    ) -> None:
        resp = admin_client.post(_risks_path(sar_doc), json={"sar_risk": _complete_risk()})

        assert resp.status_code == 201, resp.text
        data = resp.json()["data"]
        assert data["impact"] == "high"
        assert data["likelihood"] == "moderate"
        assert data["uuid"], "server must assign a uuid when the caller omits one"
        assert "missing_fields" not in data

        admin_client.delete(f"{_RISKS}/{data['id']}")

    @pytest.mark.happy
    def test_reports_the_rating_as_the_facets_it_will_export_as(
        self, admin_client: httpx.Client, sar_doc: dict[str, Any]
    ) -> None:
        """OSCAL carries a rating in characterizations[].facets[], never in a
        top-level field. A client must be able to see what will ship."""
        resp = admin_client.post(_risks_path(sar_doc), json={"sar_risk": _complete_risk()})
        assert resp.status_code == 201, resp.text
        data = resp.json()["data"]

        facets = [f for c in data["characterizations"] for f in c["facets"]]
        # name/system/value are ALL required on a facet by the OSCAL schema.
        for facet in facets:
            assert {"name", "system", "value"} <= set(facet), facet
        pairs = {(f["name"], f["value"]) for f in facets}
        assert ("impact", "high") in pairs
        assert ("likelihood", "moderate") in pairs
        # A characterization requires an origin; omitting it fails schema validation.
        assert all("origin" in c for c in data["characterizations"])

        admin_client.delete(f"{_RISKS}/{data['id']}")

    @pytest.mark.validation
    @pytest.mark.parametrize("field", REQUIRED_FIELDS)
    def test_rejects_a_risk_missing_a_required_field(
        self, admin_client: httpx.Client, sar_doc: dict[str, Any], field: str
    ) -> None:
        """Each field on its own — an over-broad rejection cannot satisfy this."""
        payload = _complete_risk()
        payload.pop(field)

        resp = admin_client.post(_risks_path(sar_doc), json={"sar_risk": payload})

        assert resp.status_code == 422, f"{field}: {resp.status_code} {resp.text}"


class TestUpdate:
    @pytest.mark.happy
    def test_sets_a_rating_on_an_existing_risk(
        self, admin_client: httpx.Client, risk: dict[str, Any]
    ) -> None:
        resp = admin_client.patch(
            f"{_RISKS}/{risk['id']}",
            json={"sar_risk": {"impact": "very-high", "likelihood": "low"}},
        )

        assert resp.status_code == 200, resp.text
        data = resp.json()["data"]
        assert data["impact"] == "very-high"
        assert data["likelihood"] == "low"


class TestIndex:
    @pytest.mark.happy
    def test_lists_risks_with_the_collection_envelope(
        self, admin_client: httpx.Client, sar_doc: dict[str, Any], risk: dict[str, Any]
    ) -> None:
        resp = admin_client.get(_risks_path(sar_doc))

        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert any(r["id"] == risk["id"] for r in body["data"])
        assert {"page", "pages", "count", "items"} <= set(body["meta"])

    @pytest.mark.happy
    def test_accepts_the_slug_the_listing_hands_out(
        self, admin_client: httpx.Client, sar_doc: dict[str, Any]
    ) -> None:
        resp = admin_client.get(f"{_SAR_DOCS}/{sar_doc['slug']}/risks")

        assert resp.status_code == 200, resp.text
