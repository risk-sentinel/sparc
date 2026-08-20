"""Tests for /api/v1/control_catalogs/:id/controls (#895).

Second slice of the Catalog API, after control families. These assert against a
live instance what a request spec cannot: that the enumerated allowlist really
drops unknown keys over HTTP rather than only in a controller unit, that a
partial PATCH of guidance_data does not silently discard the rest of the
document, and that dotted sub-part identifiers survive routing.
"""

from __future__ import annotations

import uuid as uuidlib
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope, assert_paginated_envelope

pytestmark = [pytest.mark.catalogs, pytest.mark.phase2]

CATALOGS = "/api/v1/control_catalogs"


def _catalog_payload() -> dict[str, Any]:
    suffix = uuidlib.uuid4().hex[:8]
    return {
        "control_catalog": {
            "name": f"phase2-control-catalog-{suffix}",
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


@pytest.fixture
def family(admin_client: httpx.Client, catalog: dict[str, Any]) -> dict[str, Any]:
    code = f"X{uuidlib.uuid4().hex[:1].upper()}"
    response = admin_client.post(
        f"{CATALOGS}/{catalog['id']}/control_families",
        json={"control_family": {"code": code, "name": "Contract Family"}},
    )
    assert response.status_code in (200, 201), response.text
    return response.json().get("data") or response.json()


def _controls_path(catalog: dict[str, Any], ident: str | None = None) -> str:
    base = f"{CATALOGS}/{catalog['id']}/controls"
    return f"{base}/{ident}" if ident else base


def _family_controls_path(catalog: dict[str, Any], family: dict[str, Any]) -> str:
    return f"{CATALOGS}/{catalog['id']}/control_families/{family['code'].lower()}/controls"


def _create(
    client: httpx.Client,
    catalog: dict[str, Any],
    family: dict[str, Any],
    **overrides: Any,
) -> dict[str, Any]:
    prefix = family["code"].lower()
    body: dict[str, Any] = {
        "control_id": f"{prefix}-{uuidlib.uuid4().int % 9000 + 1000}",
        "title": "Contract Control",
    }
    body.update(overrides)
    response = client.post(_family_controls_path(catalog, family), json={"catalog_control": body})
    assert response.status_code in (200, 201), response.text
    return response.json().get("data") or response.json()


class TestIndex:
    @pytest.mark.happy
    def test_lists_the_catalogs_controls(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        control = _create(admin_client, catalog, family)

        response = admin_client.get(_controls_path(catalog))
        assert response.status_code == 200, response.text
        body = response.json()
        assert_paginated_envelope(body)
        assert control["identifier"] in [c["identifier"] for c in body["data"]]

    @pytest.mark.pagination
    def test_scopes_to_one_family_when_listed_through_it(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        mine = _create(admin_client, catalog, family)

        other_code = f"Y{uuidlib.uuid4().hex[:1].upper()}"
        other = admin_client.post(
            f"{CATALOGS}/{catalog['id']}/control_families",
            json={"control_family": {"code": other_code, "name": "Other Family"}},
        ).json()["data"]
        theirs = _create(admin_client, catalog, other)

        response = admin_client.get(_family_controls_path(catalog, family))
        assert response.status_code == 200, response.text
        identifiers = [c["identifier"] for c in response.json()["data"]]
        assert mine["identifier"] in identifiers
        assert theirs["identifier"] not in identifiers

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client, catalog: dict[str, Any]) -> None:
        assert_error_envelope(anon_client.get(_controls_path(catalog)), expected_status=401)


class TestShow:
    @pytest.mark.happy
    def test_addresses_a_control_by_canonical_identifier(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        control = _create(admin_client, catalog, family, title="Account Management")

        response = admin_client.get(_controls_path(catalog, control["identifier"]))
        assert response.status_code == 200, response.text
        data = response.json()["data"]
        assert data["title"] == "Account Management"
        assert data["control_catalog"]["id"] == catalog["id"]

    @pytest.mark.happy
    def test_a_dotted_sub_part_identifier_survives_routing(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        """48% of catalog rows are sub-parts and their identifiers contain dots.
        The default Rails segment pattern stops at a dot, so without the route
        constraint every one of them 404s."""
        prefix = family["code"].lower()
        control = _create(admin_client, catalog, family, control_id=f"{prefix}-7(4)(b)(1)")
        assert "." in control["identifier"], control["identifier"]

        response = admin_client.get(_controls_path(catalog, control["identifier"]))
        assert response.status_code == 200, response.text
        assert response.json()["data"]["identifier"] == control["identifier"]

    @pytest.mark.authz
    def test_a_control_from_another_catalog_is_404(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        other = admin_client.post(CATALOGS, json=_catalog_payload()).json()["data"]
        try:
            other_family = admin_client.post(
                f"{CATALOGS}/{other['id']}/control_families",
                json={"control_family": {"code": "ZQ", "name": "Elsewhere"}},
            ).json()["data"]
            elsewhere = _create(admin_client, other, other_family)

            response = admin_client.get(_controls_path(catalog, elsewhere["identifier"]))
            assert response.status_code == 404, response.text
        finally:
            admin_client.delete(f"{CATALOGS}/{other['id']}")


class TestCreate:
    @pytest.mark.happy
    def test_creates_a_control_with_baseline_levels(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        control = _create(
            admin_client,
            catalog,
            family,
            title="Access Enforcement",
            baseline_levels=["LOW", "HIGH"],
            guidance_data={"statement": "Enforce approved authorizations."},
        )

        assert control["baseline_levels"] == ["LOW", "HIGH"]
        assert control["baseline_impact"] == "LOW, HIGH"
        assert control["guidance_data"]["statement"] == "Enforce approved authorizations."

    @pytest.mark.validation
    def test_rejects_a_control_with_no_control_id(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            _family_controls_path(catalog, family), json={"catalog_control": {"title": "Nameless"}}
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_rejects_a_duplicate_control_id_in_the_family(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        control = _create(admin_client, catalog, family)

        response = admin_client.post(
            _family_controls_path(catalog, family),
            json={"catalog_control": {"control_id": control["control_id"], "title": "Dupe"}},
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.validation
    def test_rejects_an_unknown_baseline_level(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        prefix = family["code"].lower()
        response = admin_client.post(
            _family_controls_path(catalog, family),
            json={
                "catalog_control": {
                    "control_id": f"{prefix}-99",
                    "title": "Bad baseline",
                    "baseline_levels": ["LOW", "CATASTROPHIC"],
                }
            },
        )
        assert_error_envelope(response, expected_status=422)

    @pytest.mark.auth
    def test_no_token_returns_401(
        self, anon_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        response = anon_client.post(
            _family_controls_path(catalog, family),
            json={"catalog_control": {"control_id": "aa-1", "title": "X"}},
        )
        assert_error_envelope(response, expected_status=401)

    @pytest.mark.authz
    def test_non_admin_cannot_create(
        self, user_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        response = user_client.post(
            _family_controls_path(catalog, family),
            json={"catalog_control": {"control_id": "aa-2", "title": "X"}},
        )
        assert response.status_code in (401, 403, 404), response.text


class TestParameterEnumeration:
    """guidance_data is a free-form JSONB column that every OSCAL exporter
    reads, so the endpoint enumerates its keys instead of taking a loose hash."""

    @pytest.mark.validation
    def test_drops_an_unenumerated_guidance_key(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        control = _create(admin_client, catalog, family)

        response = admin_client.patch(
            _controls_path(catalog, control["identifier"]),
            json={
                "catalog_control": {
                    "guidance_data": {"check": "Verify it.", "injected_key": "should not land"}
                }
            },
        )
        assert response.status_code == 200, response.text
        guidance = response.json()["data"]["guidance_data"]
        assert guidance["check"] == "Verify it."
        assert "injected_key" not in guidance

    @pytest.mark.validation
    def test_refuses_an_unenumerated_attribute(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        control = _create(admin_client, catalog, family)

        response = admin_client.patch(
            _controls_path(catalog, control["identifier"]),
            json={
                "catalog_control": {
                    "title": "Renamed",
                    "id": 999_999,
                    "control_family_id": 999_999,
                }
            },
        )
        # #995 — refused rather than dropped. Applying the recognised half of a
        # body while discarding the rest, under a 200, is what let a caller
        # believe a re-parenting had taken.
        assert response.status_code == 422, response.text
        details = " ".join(response.json()["details"])
        assert "control_family_id" in details
        assert "id" in details

        unchanged = admin_client.get(_controls_path(catalog, control["identifier"]))
        assert unchanged.status_code == 200, unchanged.text
        assert unchanged.json()["data"]["title"] != "Renamed"

    @pytest.mark.validation
    def test_keeps_the_enumerated_odp_shape_and_drops_the_rest(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        control = _create(admin_client, catalog, family)

        response = admin_client.patch(
            _controls_path(catalog, control["identifier"]),
            json={
                "catalog_control": {
                    "params_data": [
                        {
                            "id": "odp.01",
                            "label": "time period",
                            "select": {"how-many": "one-or-more", "choice": ["remove", "disable"]},
                            "guidelines": [{"prose": "Organization-defined."}],
                            "smuggled": "nope",
                        }
                    ]
                }
            },
        )
        assert response.status_code == 200, response.text
        param = response.json()["data"]["params_data"][0]
        assert param["id"] == "odp.01"
        assert param["select"]["choice"] == ["remove", "disable"]
        assert "smuggled" not in param


class TestUpdate:
    @pytest.mark.happy
    def test_merges_guidance_data_rather_than_replacing_it(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        """A wholesale assignment would drop every key the caller did not
        resend, and the loss would only surface in an OSCAL export later."""
        control = _create(
            admin_client,
            catalog,
            family,
            guidance_data={"statement": "Original statement.", "check": "Original check."},
        )

        response = admin_client.patch(
            _controls_path(catalog, control["identifier"]),
            json={"catalog_control": {"guidance_data": {"check": "Revised check."}}},
        )
        assert response.status_code == 200, response.text
        guidance = response.json()["data"]["guidance_data"]
        assert guidance["check"] == "Revised check."
        assert guidance["statement"] == "Original statement."

    @pytest.mark.happy
    def test_an_empty_value_removes_a_guidance_key(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        control = _create(
            admin_client,
            catalog,
            family,
            guidance_data={"statement": "Keep me.", "check": "Remove me."},
        )

        response = admin_client.patch(
            _controls_path(catalog, control["identifier"]),
            json={"catalog_control": {"guidance_data": {"check": ""}}},
        )
        assert response.status_code == 200, response.text
        guidance = response.json()["data"]["guidance_data"]
        assert "check" not in guidance
        assert guidance["statement"] == "Keep me."

    @pytest.mark.happy
    def test_relabels_one_odp_without_resending_the_array(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        control = _create(
            admin_client,
            catalog,
            family,
            params_data=[
                {"id": "odp.01", "label": "original", "guidelines": [{"prose": "keep me"}]},
                {"id": "odp.02", "label": "untouched"},
            ],
        )

        response = admin_client.patch(
            _controls_path(catalog, control["identifier"]),
            json={"catalog_control": {"params_labels": {"odp.01": "revised label"}}},
        )
        assert response.status_code == 200, response.text
        params = {p["id"]: p for p in response.json()["data"]["params_data"]}
        assert params["odp.01"]["label"] == "revised label"
        assert params["odp.01"]["guidelines"] == [{"prose": "keep me"}]
        assert params["odp.02"]["label"] == "untouched"

    @pytest.mark.authz
    def test_non_admin_cannot_update(
        self,
        admin_client: httpx.Client,
        user_client: httpx.Client,
        catalog: dict[str, Any],
        family: dict[str, Any],
    ) -> None:
        control = _create(admin_client, catalog, family, title="Untouched")

        response = user_client.patch(
            _controls_path(catalog, control["identifier"]),
            json={"catalog_control": {"title": "Tampered"}},
        )
        assert response.status_code in (401, 403, 404), response.text

        after = admin_client.get(_controls_path(catalog, control["identifier"]))
        assert after.json()["data"]["title"] == "Untouched"


class TestDestroy:
    @pytest.mark.happy
    def test_deletes_a_leaf_control(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        control = _create(admin_client, catalog, family)

        response = admin_client.delete(_controls_path(catalog, control["identifier"]))
        assert response.status_code in (200, 204), response.text

        assert admin_client.get(_controls_path(catalog, control["identifier"])).status_code == 404

    @pytest.mark.validation
    def test_refuses_to_delete_a_control_that_still_has_sub_parts(
        self, admin_client: httpx.Client, catalog: dict[str, Any], family: dict[str, Any]
    ) -> None:
        """Sub-parts are separate rows with no foreign key to their parent, so a
        cascade would leave them pointing at a control that no longer exists."""
        prefix = family["code"].lower()
        parent = _create(admin_client, catalog, family, control_id=f"{prefix}-42")
        _create(admin_client, catalog, family, control_id=f"{prefix}-42a")

        response = admin_client.delete(_controls_path(catalog, parent["identifier"]))
        assert_error_envelope(response, expected_status=422)
        assert response.json().get("sub_parts") == [f"{prefix}-42a"]

        assert admin_client.get(_controls_path(catalog, parent["identifier"])).status_code == 200
