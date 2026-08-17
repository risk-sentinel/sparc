"""Tests for POA&M risks (#832).

Five logical endpoints, nested on a POA&M document:
  - index, create   (/api/v1/poam_documents/:poam_document_id/risks)
  - show, update, destroy   (/api/v1/poam_risks/:id)

The point of this endpoint is rejection at the point of entry. `PoamRisk`
used to validate only `uuid`, so a risk could be saved with no title,
description, statement, status or deadline; the resulting POA&M then failed
OSCAL schema validation at EXPORT, far from the input that caused it and with
nothing to say which record was at fault.

So the contract these tests pin is not merely "CRUD works" — it is that an
incomplete risk is refused with a 422 that NAMES what is missing, and that a
pre-existing incomplete row is reported via `missing_fields` rather than
discovered one failed edit at a time.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _document_helpers import create_doc, delete_doc, make_payload
from conftest import assert_error_envelope

pytestmark = [pytest.mark.poam_risks, pytest.mark.phase2]

_POAM_DOCS = "/api/v1/poam_documents"
_RISKS = "/api/v1/poam_risks"
_MISSING_ID = "99999999"

# Every field the model requires. Each is dropped in turn below.
REQUIRED_FIELDS = ("title", "description", "statement", "status", "deadline")


def _complete_risk() -> dict[str, Any]:
    return {
        "title": "Hard-coded credentials in the admin panel",
        "description": "Static credentials are present in the deployed configuration.",
        "statement": (
            "An attacker with read access to the image can authenticate as an administrator."
        ),
        "status": "open",
        "deadline": "2026-12-31T00:00:00Z",
        "impact": "high",
        "likelihood": "medium",
    }


@pytest.fixture
def poam_doc(admin_client: httpx.Client, seeded_boundary_id: int) -> Iterator[dict[str, Any]]:
    # #952 — a POA&M requires an authorization boundary at create.
    doc = create_doc(
        admin_client,
        _POAM_DOCS,
        make_payload("poam_document", {"authorization_boundary_id": seeded_boundary_id}),
    )
    try:
        yield doc
    finally:
        delete_doc(admin_client, _POAM_DOCS, doc["slug"])


def _risks_path(doc: dict[str, Any]) -> str:
    return f"{_POAM_DOCS}/{doc['id']}/risks"


@pytest.fixture
def risk(admin_client: httpx.Client, poam_doc: dict[str, Any]) -> Iterator[dict[str, Any]]:
    resp = admin_client.post(_risks_path(poam_doc), json={"poam_risk": _complete_risk()})
    assert resp.status_code == 201, resp.text
    created = resp.json()["data"]
    try:
        yield created
    finally:
        admin_client.delete(f"{_RISKS}/{created['id']}")


class TestCreate:
    @pytest.mark.happy
    def test_creates_a_complete_risk(
        self, admin_client: httpx.Client, poam_doc: dict[str, Any]
    ) -> None:
        resp = admin_client.post(_risks_path(poam_doc), json={"poam_risk": _complete_risk()})

        assert resp.status_code == 201, resp.text
        data = resp.json()["data"]
        assert data["title"] == _complete_risk()["title"]
        assert data["uuid"], "server must assign a uuid when the caller omits one"
        assert "missing_fields" not in data, "a complete risk must not be flagged as incomplete"

        admin_client.delete(f"{_RISKS}/{data['id']}")

    @pytest.mark.validation
    @pytest.mark.parametrize("field", REQUIRED_FIELDS)
    def test_rejects_a_risk_missing_a_required_field(
        self, admin_client: httpx.Client, poam_doc: dict[str, Any], field: str
    ) -> None:
        """Each field on its own — an over-broad rejection cannot satisfy this."""
        payload = _complete_risk()
        payload.pop(field)

        resp = admin_client.post(_risks_path(poam_doc), json={"poam_risk": payload})

        assert resp.status_code == 422, f"missing {field} was accepted: {resp.text}"
        body = resp.json()
        detail = " ".join(body.get("details") or []) + " " + str(body.get("error", ""))
        assert field.replace("_", " ") in detail.lower(), (
            f"the 422 did not name the missing field {field!r}: {resp.text}"
        )

    @pytest.mark.validation
    def test_the_rejected_risk_is_not_persisted(
        self, admin_client: httpx.Client, poam_doc: dict[str, Any]
    ) -> None:
        """A rejection that still writes the row would resurface at export."""
        payload = _complete_risk()
        payload.pop("deadline")
        admin_client.post(_risks_path(poam_doc), json={"poam_risk": payload})

        listed = admin_client.get(_risks_path(poam_doc))
        assert listed.status_code == 200
        assert listed.json()["data"] == []


class TestIndex:
    @pytest.mark.happy
    @pytest.mark.pagination
    def test_lists_risks_in_a_paginated_envelope(
        self, admin_client: httpx.Client, poam_doc: dict[str, Any], risk: dict[str, Any]
    ) -> None:
        resp = admin_client.get(_risks_path(poam_doc))

        assert resp.status_code == 200
        body = resp.json()
        assert any(r["id"] == risk["id"] for r in body["data"])
        assert set(body["meta"]) >= {"page", "pages", "count", "items"}


class TestShowUpdateDestroy:
    @pytest.mark.happy
    def test_shows_the_detailed_representation(
        self, admin_client: httpx.Client, risk: dict[str, Any]
    ) -> None:
        resp = admin_client.get(f"{_RISKS}/{risk['id']}")

        assert resp.status_code == 200
        data = resp.json()["data"]
        assert data["statement"], "show must return the OSCAL-required statement"
        assert data["description"]

    @pytest.mark.happy
    def test_updates_a_risk(self, admin_client: httpx.Client, risk: dict[str, Any]) -> None:
        resp = admin_client.patch(
            f"{_RISKS}/{risk['id']}", json={"poam_risk": {"title": "Revised title"}}
        )

        assert resp.status_code == 200
        assert resp.json()["data"]["title"] == "Revised title"

    @pytest.mark.validation
    def test_refuses_to_blank_a_required_field(
        self, admin_client: httpx.Client, risk: dict[str, Any]
    ) -> None:
        """The rules apply on UPDATE too — grandfathering would keep bad data."""
        resp = admin_client.patch(f"{_RISKS}/{risk['id']}", json={"poam_risk": {"deadline": None}})

        assert resp.status_code == 422, resp.text
        still_there = admin_client.get(f"{_RISKS}/{risk['id']}").json()["data"]
        assert still_there["deadline"], "the deadline was cleared despite the 422"

    @pytest.mark.happy
    def test_destroys_a_risk(
        self, admin_client: httpx.Client, poam_doc: dict[str, Any]
    ) -> None:
        created = admin_client.post(
            _risks_path(poam_doc), json={"poam_risk": _complete_risk()}
        ).json()["data"]

        resp = admin_client.delete(f"{_RISKS}/{created['id']}")

        assert resp.status_code == 200
        assert admin_client.get(f"{_RISKS}/{created['id']}").status_code == 404


class TestNotFound:
    def test_show_missing_risk_returns_404(self, admin_client: httpx.Client) -> None:
        resp = admin_client.get(f"{_RISKS}/{_MISSING_ID}")

        assert_error_envelope(resp, expected_status=404)

    def test_create_under_missing_document_returns_404(
        self, admin_client: httpx.Client
    ) -> None:
        resp = admin_client.post(
            f"{_POAM_DOCS}/{_MISSING_ID}/risks", json={"poam_risk": _complete_risk()}
        )

        assert resp.status_code == 404


class TestAuth:
    @pytest.mark.auth
    def test_anonymous_cannot_list(
        self, anon_client: httpx.Client, poam_doc: dict[str, Any]
    ) -> None:
        resp = anon_client.get(_risks_path(poam_doc))

        assert_error_envelope(resp, expected_status=401)

    @pytest.mark.authz
    def test_non_admin_cannot_create(
        self, user_client: httpx.Client, poam_doc: dict[str, Any]
    ) -> None:
        """Requires poam.write on the boundary; the contract user has none."""
        resp = user_client.post(_risks_path(poam_doc), json={"poam_risk": _complete_risk()})

        assert resp.status_code in (403, 404), (
            f"a non-admin created a POA&M risk: {resp.status_code} {resp.text}"
        )
