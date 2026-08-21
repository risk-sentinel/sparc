"""Tests for /api/v1/control_catalogs/:id/control_families (#895).

First slice of the Catalog API. The catalog container had a full API while its
contents had none — you could create a catalog over the API but not put a single
family in it.

Two things these assert that a request spec cannot: that the identifier decision
holds against a live instance (uuid, slug and numeric id all resolve), and that
the enumerated param allowlist actually rejects extra keys over HTTP rather than
only in a controller unit.
"""

from __future__ import annotations

import uuid as uuidlib
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _crud_contract import CrudContract
from conftest import assert_error_envelope, assert_paginated_envelope

pytestmark = [pytest.mark.catalogs, pytest.mark.phase2]

CATALOGS = "/api/v1/control_catalogs"


def _catalog_payload() -> dict[str, Any]:
    suffix = uuidlib.uuid4().hex[:8]
    return {
        "control_catalog": {
            "name": f"phase2-family-catalog-{suffix}",
            "version": "1.0.0",
            "source": "OSCAL",
        }
    }


@pytest.fixture
def catalog(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(CATALOGS, json=_catalog_payload())
    assert response.status_code in (200, 201), response.text
    c = response.json().get("data") or response.json()
    try:
        yield c
    finally:
        admin_client.delete(f"{CATALOGS}/{c['id']}")


def _path(catalog: dict[str, Any], ident: str | None = None) -> str:
    key = ident if ident is not None else catalog["id"]
    return f"{CATALOGS}/{key}/control_families"


def _create(client: httpx.Client, catalog: dict[str, Any], **overrides: Any) -> dict[str, Any]:
    body = {"code": f"X{uuidlib.uuid4().hex[:1].upper()}", "name": "Contract Family"}
    body.update(overrides)
    response = client.post(_path(catalog), json={"control_family": body})
    assert response.status_code in (200, 201), response.text
    return response.json().get("data") or response.json()


# #995 — the shared matrix for this nested group.
class TestCrudContract(CrudContract):
    PARAM_KEY = "control_family"
    IDENTIFIER = "code"

    def _base_path(self, admin_client):
        catalogs = admin_client.get("/api/v1/control_catalogs", params={"items": 1})
        rows = catalogs.json()["data"]
        assert rows, "no control catalog on this instance"
        return f"/api/v1/control_catalogs/{rows[0]['id']}/control_families"

    def _payload(self, admin_client):
        return {"code": f"Z{uuidlib.uuid4().hex[:2].upper()}", "name": "Contract Family"}

    def _update_fields(self):
        return {"name": f"Renamed {uuidlib.uuid4().hex[:6]}"}


class TestCatalogIdentifier:
    """#895 recorded the decision: uuid is the stable identity, but slug and
    numeric id keep resolving so nothing already written breaks."""

    @pytest.mark.happy
    def test_resolves_by_every_accepted_form(
        self, admin_client: httpx.Client, catalog: dict[str, Any]
    ) -> None:
        uuid_form = catalog.get("uuid") or catalog.get("oscal_uuid")
        for form in (catalog["id"], catalog.get("slug"), uuid_form):
            if not form:
                continue
            response = admin_client.get(_path(catalog, str(form)))
            assert response.status_code == 200, f"{form!r} did not resolve: {response.text}"

    @pytest.mark.authz
    def test_unknown_catalog_is_404(
        self, admin_client: httpx.Client, catalog: dict[str, Any]
    ) -> None:
        response = admin_client.get(_path(catalog, f"missing-{uuidlib.uuid4().hex[:8]}"))
        assert response.status_code == 404, response.text


class TestIndex:
    @pytest.mark.happy
    def test_lists_the_catalogs_families(
        self, admin_client: httpx.Client, catalog: dict[str, Any]
    ) -> None:
        family = _create(admin_client, catalog)

        response = admin_client.get(_path(catalog))
        assert response.status_code == 200, response.text
        body = response.json()
        assert_paginated_envelope(body)
        assert family["code"] in [f["code"] for f in body["data"]]

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client, catalog: dict[str, Any]) -> None:
        assert_error_envelope(anon_client.get(_path(catalog)), expected_status=401)


class TestShow:
    @pytest.mark.happy
    def test_addresses_a_family_by_code_case_insensitively(
        self, admin_client: httpx.Client, catalog: dict[str, Any]
    ) -> None:
        family = _create(admin_client, catalog, name="Case Test")

        response = admin_client.get(f"{_path(catalog)}/{family['code'].lower()}")
        assert response.status_code == 200, response.text
        assert response.json()["data"]["name"] == "Case Test"

    @pytest.mark.authz
    def test_code_from_another_catalog_is_404(
        self, admin_client: httpx.Client, catalog: dict[str, Any]
    ) -> None:
        other = admin_client.post(CATALOGS, json=_catalog_payload())
        other_catalog = other.json().get("data") or other.json()
        try:
            elsewhere = _create(admin_client, other_catalog)
            response = admin_client.get(f"{_path(catalog)}/{elsewhere['code'].lower()}")
            assert response.status_code == 404, response.text
        finally:
            admin_client.delete(f"{CATALOGS}/{other_catalog['id']}")


class TestCreate:
    @pytest.mark.happy
    def test_creates_a_family(self, admin_client: httpx.Client, catalog: dict[str, Any]) -> None:
        family = _create(admin_client, catalog, name="Audit and Accountability", sort_order=2)

        assert family["name"] == "Audit and Accountability"
        assert family["sort_order"] == 2
        assert family["controls_count"] == 0

    @pytest.mark.validation
    def test_rejects_a_duplicate_code(
        self, admin_client: httpx.Client, catalog: dict[str, Any]
    ) -> None:
        family = _create(admin_client, catalog)

        response = admin_client.post(
            _path(catalog), json={"control_family": {"code": family["code"], "name": "Dupe"}}
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_rejects_a_family_with_no_name(
        self, admin_client: httpx.Client, catalog: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            _path(catalog), json={"control_family": {"code": "QQ", "name": ""}}
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_refuses_fields_outside_the_allowlist(
        self, admin_client: httpx.Client, catalog: dict[str, Any]
    ) -> None:
        """Params are enumerated, not a loose hash — an endpoint accepting
        arbitrary keys would let them into a record the OSCAL exporters read."""
        response = admin_client.post(
            _path(catalog),
            json={
                "control_family": {
                    "code": "ZQ",
                    "name": "Allowlist Test",
                    "id": 999_999,
                    "control_catalog_id": 999_999,
                }
            },
        )
        # #995 — refused rather than silently dropped, so a caller aiming a
        # record at another catalog is told so instead of receiving 201.
        assert response.status_code == 422, response.text
        details = " ".join(response.json()["details"])
        assert "control_catalog_id" in details
        assert "id" in details

        clean = admin_client.post(
            _path(catalog), json={"control_family": {"code": "ZQ", "name": "Allowlist Test"}}
        )
        assert clean.status_code in (200, 201), clean.text
        created = clean.json().get("data") or clean.json()
        assert created["control_catalog_id"] == catalog["id"]
        admin_client.delete(f"{_path(catalog)}/{created['code']}")

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client, catalog: dict[str, Any]) -> None:
        response = anon_client.post(
            _path(catalog), json={"control_family": {"code": "AA", "name": "X"}}
        )
        assert_error_envelope(response, expected_status=401)

    @pytest.mark.authz
    def test_non_admin_cannot_create(
        self, user_client: httpx.Client, catalog: dict[str, Any]
    ) -> None:
        response = user_client.post(
            _path(catalog), json={"control_family": {"code": "AB", "name": "X"}}
        )
        assert response.status_code in (401, 403, 404), response.text


class TestUpdateDestroy:
    @pytest.mark.happy
    def test_updates_a_family(self, admin_client: httpx.Client, catalog: dict[str, Any]) -> None:
        family = _create(admin_client, catalog)

        response = admin_client.patch(
            f"{_path(catalog)}/{family['code'].lower()}",
            json={"control_family": {"name": "Renamed Family"}},
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["name"] == "Renamed Family"

    @pytest.mark.happy
    def test_deletes_an_empty_family(
        self, admin_client: httpx.Client, catalog: dict[str, Any]
    ) -> None:
        family = _create(admin_client, catalog)

        response = admin_client.delete(f"{_path(catalog)}/{family['code'].lower()}")
        assert response.status_code in (200, 204), response.text

        assert admin_client.get(f"{_path(catalog)}/{family['code'].lower()}").status_code == 404
