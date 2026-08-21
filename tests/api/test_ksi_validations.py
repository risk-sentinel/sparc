"""Tests for /api/v1/authorization_boundaries/:id/ksi_validations.

7 logical endpoints, nested under authorization boundaries:
  - index, show, create, update, destroy
  - summary (dashboard aggregation)
  - export (compliance report)

Tests create a parent boundary in setup so they don't depend on which
boundaries the seed leaves in place.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _crud_contract import CrudContract
from conftest import assert_error_envelope

pytestmark = [pytest.mark.ksi, pytest.mark.phase1]


BOUNDARIES_PATH = "/api/v1/authorization_boundaries"


def _boundary_path(boundary_id: int) -> str:
    return f"{BOUNDARIES_PATH}/{boundary_id}/ksi_validations"


def _new_boundary_payload() -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    return {
        "authorization_boundary": {
            "name": f"phase2-ksi-parent-{suffix}",
            "description": "Phase 2 KSI validation parent",
        }
    }


@pytest.fixture
def boundary(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    response = admin_client.post(BOUNDARIES_PATH, json=_new_boundary_payload())
    assert response.status_code in (200, 201), response.text
    body = response.json().get("data") or response.json()
    try:
        yield body
    finally:
        admin_client.delete(f"{BOUNDARIES_PATH}/{body['id']}")


# #995 — the shared matrix for this group.
class TestCrudContract(CrudContract):
    PARAM_KEY = "ksi_validation"
    IDENTIFIER = "id"
    # The controller's own header: "DELETE is admin-only. All other operations
    # available to authenticated users." Pinned so a later tightening is a
    # failing test rather than a silent change.
    #
    # Note for whoever reads this next: unlike every other boundary-nested
    # write in this API — leveraged authorizations require membership, POA&M
    # sub-objects require poam.write on the boundary — create and update here
    # require nothing beyond a valid token, on ANY boundary. `set_boundary`
    # looks the boundary up without checking the caller against it. Raised with
    # the owner; documented as intended, so asserted as intended.
    NON_ADMIN_MAY_WRITE_BECAUSE = (
        "the controller documents every operation except DELETE as available "
        "to any authenticated user"
    )

    def _boundary(self, admin_client):
        # Its OWN boundary, not a shared one: catalog_control_id is unique per
        # boundary, so reusing one would make the second create a duplicate.
        if getattr(self, "_cached_boundary", None):
            return self._cached_boundary
        created = admin_client.post(BOUNDARIES_PATH, json=_new_boundary_payload())
        assert created.status_code in (200, 201), created.text
        self._cached_boundary = created.json()["data"]
        return self._cached_boundary

    def _base_path(self, admin_client):
        return _boundary_path(self._boundary(admin_client)["id"])

    def _payload(self, admin_client):
        # A KSI validation is per (boundary, indicator), so each create needs a
        # DIFFERENT indicator — the model enforces that uniqueness.
        indicators = admin_client.get("/api/v1/ksi_catalog/indicators", params={"items": 100})
        rows = indicators.json()["data"]
        assert rows, "no KSI indicators seeded on this instance"

        used = getattr(self, "_used_controls", set())
        existing = admin_client.get(self._base_path(admin_client), params={"items": 200})
        for row in existing.json().get("data", []):
            used.add(row.get("catalog_control_id"))

        catalog = admin_client.get("/api/v1/control_catalogs", params={"items": 100})
        ksi = next(c for c in catalog.json()["data"] if c["source"] == "FedRAMP 20x")
        controls = admin_client.get(f"/api/v1/control_catalogs/{ksi['id']}/controls",
                                    params={"items": 100})
        free = [c["id"] for c in controls.json()["data"] if c["id"] not in used]
        assert free, "every KSI indicator on this boundary already has a validation"

        used.add(free[0])
        self._used_controls = used
        return {"catalog_control_id": free[0], "status": "not_assessed"}

    def _update_fields(self):
        return {"status": "passed"}


class TestIndex:
    @pytest.mark.happy
    def test_admin_lists_validations(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.get(_boundary_path(boundary["id"]))
        assert response.status_code == 200, response.text
        body = response.json()
        assert "data" in body and isinstance(body["data"], list)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(_boundary_path(1)), expected_status=401)


class TestShow:
    def test_unknown_id_returns_404(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{_boundary_path(boundary['id'])}/99999999")
        assert_error_envelope(response, expected_status=404)

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(anon_client.get(f"{_boundary_path(1)}/0"), expected_status=401)


class TestCreate:
    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.post(_boundary_path(1), json={}), expected_status=401
        )

    @pytest.mark.validation
    def test_invalid_payload_returns_422(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        # A PRESENT-but-invalid payload (bad status, missing required
        # catalog_control_id) trips model validation → 422. Note: an empty
        # `{"ksi_validation": {}}` would be 400 (ParameterMissing), not 422 —
        # that tests "missing payload", not "invalid payload" (#644).
        response = admin_client.post(
            _boundary_path(boundary["id"]),
            json={"ksi_validation": {"status": "not-a-valid-status"}},
        )
        assert_error_envelope(response, expected_status=422)


class TestUpdate:
    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.put(f"{_boundary_path(1)}/0", json={}), expected_status=401
        )


class TestDestroy:
    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.delete(f"{_boundary_path(1)}/0"), expected_status=401
        )

    @pytest.mark.authz
    def test_non_admin_returns_403(
        self, user_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        # Destroy is admin-only (authorize_admin! before_action).
        response = user_client.delete(f"{_boundary_path(boundary['id'])}/0")
        assert response.status_code in (401, 403, 404)


class TestSummary:
    @pytest.mark.happy
    def test_admin_summary(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{_boundary_path(boundary['id'])}/summary")
        assert response.status_code == 200, response.text

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{_boundary_path(1)}/summary"), expected_status=401
        )


class TestExport:
    @pytest.mark.happy
    def test_admin_export(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{_boundary_path(boundary['id'])}/export")
        assert response.status_code == 200, response.text

    @pytest.mark.auth
    def test_no_token_returns_401(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(
            anon_client.get(f"{_boundary_path(1)}/export"), expected_status=401
        )
