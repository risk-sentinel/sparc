"""Boundary readiness report (#940).

GET /api/v1/authorization_boundaries/:id/readiness — what SPARC knows about a
boundary, and what is still missing. Read-only, so it is safe to poll from a
pipeline and to render on every page load.

The same service backs the Adoption readiness card on the boundary screen, so
this contract and that screen cannot disagree.
"""

from __future__ import annotations

from typing import Any

import httpx
import pytest

pytestmark = [pytest.mark.boundaries, pytest.mark.phase2]

BOUNDARIES = "/api/v1/authorization_boundaries"

VALID_STATUSES = {"complete", "partial", "absent", "not_modelled"}


def _any_boundary_id(client: httpx.Client) -> Any:
    response = client.get(BOUNDARIES, params={"per_page": 1})
    assert response.status_code == 200, response.text
    rows = response.json().get("data", [])
    if not rows:
        pytest.skip("no authorization boundary on this instance")
    return rows[0]["id"]


def test_readiness_returns_the_report(admin_client: httpx.Client) -> None:
    boundary_id = _any_boundary_id(admin_client)

    response = admin_client.get(f"{BOUNDARIES}/{boundary_id}/readiness")

    assert response.status_code == 200, response.text
    data = response.json()["data"]
    assert data["boundary"]["id"] == boundary_id
    assert data["sections"], "the report carries no sections"


def test_every_section_has_a_known_status(admin_client: httpx.Client) -> None:
    boundary_id = _any_boundary_id(admin_client)

    sections = admin_client.get(f"{BOUNDARIES}/{boundary_id}/readiness").json()["data"]["sections"]

    for section in sections:
        assert section["status"] in VALID_STATUSES, section
        assert section["title"], section
        assert section["detail"], f"section {section['key']} has no explanation"


def test_every_section_points_at_the_adoption_guide(admin_client: httpx.Client) -> None:
    """A gap is only useful if it says where to go and close it."""
    boundary_id = _any_boundary_id(admin_client)

    sections = admin_client.get(f"{BOUNDARIES}/{boundary_id}/readiness").json()["data"]["sections"]

    assert all(section["guide_anchor"] for section in sections)


def test_summary_counts_every_section(admin_client: httpx.Client) -> None:
    boundary_id = _any_boundary_id(admin_client)

    data = admin_client.get(f"{BOUNDARIES}/{boundary_id}/readiness").json()["data"]

    assert set(data["summary"]) == VALID_STATUSES
    assert sum(data["summary"].values()) == len(data["sections"])


def test_boundary_addressable_by_slug(admin_client: httpx.Client) -> None:
    response = admin_client.get(BOUNDARIES, params={"per_page": 1})
    rows = response.json().get("data", [])
    if not rows or not rows[0].get("slug"):
        pytest.skip("no boundary with a slug on this instance")

    by_slug = admin_client.get(f"{BOUNDARIES}/{rows[0]['slug']}/readiness")

    assert by_slug.status_code == 200, by_slug.text


def test_requires_authentication(anon_client: httpx.Client, admin_client: httpx.Client) -> None:
    boundary_id = _any_boundary_id(admin_client)

    response = anon_client.get(f"{BOUNDARIES}/{boundary_id}/readiness")

    assert response.status_code in (401, 403), response.text


def test_is_read_only(admin_client: httpx.Client) -> None:
    """Polling the report must not change the boundary it reports on."""
    boundary_id = _any_boundary_id(admin_client)
    before = admin_client.get(f"{BOUNDARIES}/{boundary_id}").json()["data"]

    admin_client.get(f"{BOUNDARIES}/{boundary_id}/readiness")
    after = admin_client.get(f"{BOUNDARIES}/{boundary_id}").json()["data"]

    assert after == before
