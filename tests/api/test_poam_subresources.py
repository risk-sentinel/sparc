"""Tests for the POA&M sub-objects (#1010).

#832 gave poam_risks an API and left its six siblings behind — items,
observations, findings, local components, remediations and milestones. Those
are the substance of a POA&M: what OSCAL exports. Found by the missing-endpoint
axis of #995.

Written as one parameterised contract because the six ARE one shape. Six
near-identical modules is how the six web controllers came to disagree.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import date
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.poam, pytest.mark.phase2]


# (segment, param key, minimal valid attributes)
RESOURCES = [
    ("items", "poam_item", {"title": "Patch the thing", "description": "Apply the patch",
                            "risk_status": "open"}),
    ("observations", "poam_observation", {"title": "Drift observed",
                                          "description": "Nightly scan"}),
    ("findings", "poam_finding", {
        "title": "AC-2 not satisfied",
        "description": "Accounts are not reviewed",
        # OSCAL requires a finding to name what it is about.
        "target_data": {"type": "statement-id", "target-id": "ac-2_smt",
                        "status": {"state": "not-satisfied"}},
    }),
    ("local_components", "poam_local_component", {"title": "Edge proxy",
                                                  "description": "Terminates TLS",
                                                  "component_type": "software"}),
]


@pytest.fixture
def poam(admin_client: httpx.Client, seeded_boundary_id: int) -> Iterator[dict[str, Any]]:
    suffix = uuid.uuid4().hex[:8]
    response = admin_client.post(
        "/api/v1/poam_documents",
        json={"poam_document": {
            "name": f"phase2-poam-{suffix}",
            "description": "Created by the API contract suite.",
            # Required: a POA&M documents the risks of a specific system, so it
            # has to say which one. The API enforces it.
            "authorization_boundary_id": seeded_boundary_id,
        }},
    )
    assert response.status_code in (200, 201), response.text
    record = response.json()["data"]
    try:
        yield record
    finally:
        admin_client.delete(f"/api/v1/poam_documents/{record['slug']}")


def _base(poam: dict[str, Any], segment: str) -> str:
    return f"/api/v1/poam_documents/{poam['slug']}/{segment}"


@pytest.mark.parametrize(("segment", "key", "attributes"), RESOURCES)
class TestDocumentNestedSubresources:
    @pytest.mark.happy
    def test_create_read_update_delete_round_trip(
        self, admin_client: httpx.Client, poam: dict[str, Any],
        segment: str, key: str, attributes: dict[str, Any]
    ) -> None:
        path = _base(poam, segment)

        created = admin_client.post(path, json={key: attributes})
        assert created.status_code == 201, created.text
        record = created.json()["data"]
        assert record["uuid"], "the server must assign a uuid — OSCAL needs one"

        # Independent read, not the write's echo.
        shown = admin_client.get(f"{path}/{record['id']}")
        assert shown.status_code == 200, shown.text
        assert shown.json()["data"]["title"] == attributes["title"]

        updated = admin_client.patch(
            f"{path}/{record['id']}", json={key: {"title": "Renamed by the suite"}}
        )
        assert updated.status_code == 200, updated.text

        reread = admin_client.get(f"{path}/{record['id']}").json()["data"]
        assert reread["title"] == "Renamed by the suite", (
            "the update reported success but an independent read disagrees"
        )

        deleted = admin_client.delete(f"{path}/{record['id']}")
        assert deleted.status_code == 200, deleted.text

        # Gone from show AND from the parent's index.
        assert admin_client.get(f"{path}/{record['id']}").status_code == 404
        listing = admin_client.get(path).json()["data"]
        assert record["id"] not in [row["id"] for row in listing]

    @pytest.mark.validation
    def test_a_server_assigned_uuid_cannot_be_supplied(
        self, admin_client: httpx.Client, poam: dict[str, Any],
        segment: str, key: str, attributes: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            _base(poam, segment), json={key: {**attributes, "uuid": str(uuid.uuid4())}}
        )
        assert response.status_code == 422, response.text
        assert "uuid" in " ".join(response.json()["details"])

    @pytest.mark.auth
    def test_no_token_returns_401(
        self, anon_client: httpx.Client, poam: dict[str, Any],
        segment: str, key: str, attributes: dict[str, Any]
    ) -> None:
        assert_error_envelope(
            anon_client.post(_base(poam, segment), json={key: attributes}),
            expected_status=401,
        )

    @pytest.mark.authz
    def test_non_privileged_caller_is_refused_and_creates_nothing(
        self, admin_client: httpx.Client, user_client: httpx.Client, poam: dict[str, Any],
        segment: str, key: str, attributes: dict[str, Any]
    ) -> None:
        path = _base(poam, segment)
        before = admin_client.get(path).json()["meta"]["count"]

        response = user_client.post(path, json={key: attributes})
        assert response.status_code in (401, 403, 404), response.text

        after = admin_client.get(path).json()["meta"]["count"]
        assert after == before, "a refused request created a record anyway"


class TestRemediationsAndMilestones:
    @pytest.mark.happy
    def test_remediation_and_milestone_round_trip(
        self, admin_client: httpx.Client, poam: dict[str, Any]
    ) -> None:
        risk = admin_client.post(
            f"/api/v1/poam_documents/{poam['slug']}/risks",
            json={"poam_risk": {"title": "Unpatched dependency",
                                "description": "A dependency is behind",
                                "statement": "Risk statement", "status": "open",
                                "deadline": date.today().isoformat()}},
        )
        if risk.status_code not in (200, 201):
            pytest.skip(f"could not create a risk to hang a remediation off: {risk.text[:200]}")
        risk_id = risk.json()["data"]["id"]

        remediations = f"/api/v1/poam_documents/{poam['slug']}/remediations"
        created = admin_client.post(
            remediations,
            json={"poam_remediation": {"title": "Rebuild the image",
                                       "poam_risk_id": risk_id, "lifecycle": "planned"}},
        )
        assert created.status_code == 201, created.text
        remediation = created.json()["data"]
        assert remediation["poam_risk_id"] == risk_id

        milestone = admin_client.post(
            f"{remediations}/{remediation['id']}/milestones",
            json={"poam_milestone": {"title": "Image built",
                                     "due_date": date.today().isoformat()}},
        )
        assert milestone.status_code == 201, milestone.text
        assert milestone.json()["data"]["poam_remediation_id"] == remediation["id"]

        # The parent reports the child, so the nesting is real and not just a URL.
        shown = admin_client.get(f"{remediations}/{remediation['id']}").json()["data"]
        assert shown["milestone_count"] == 1

    @pytest.mark.authz
    def test_a_risk_on_another_poam_cannot_be_attached(
        self, admin_client: httpx.Client, poam: dict[str, Any], seeded_boundary_id: int
    ) -> None:
        """Cross-document attachment is impossible by construction, not by a check."""
        other = admin_client.post(
            "/api/v1/poam_documents",
            json={"poam_document": {
                "name": f"phase2-other-{uuid.uuid4().hex[:8]}",
                "description": "Foreign POA&M",
                "authorization_boundary_id": seeded_boundary_id,
            }},
        )
        assert other.status_code in (200, 201), other.text
        other_poam = other.json()["data"]

        try:
            foreign_risk = admin_client.post(
                f"/api/v1/poam_documents/{other_poam['slug']}/risks",
                json={"poam_risk": {"title": "Foreign risk", "description": "Elsewhere",
                                    "statement": "Statement", "status": "open",
                                    "deadline": date.today().isoformat()}},
            )
            if foreign_risk.status_code not in (200, 201):
                pytest.skip("could not create a risk on the other POA&M")

            response = admin_client.post(
                f"/api/v1/poam_documents/{poam['slug']}/remediations",
                json={"poam_remediation": {"title": "Should not attach",
                                           "poam_risk_id": foreign_risk.json()["data"]["id"]}},
            )
            assert response.status_code == 404, response.text
        finally:
            admin_client.delete(f"/api/v1/poam_documents/{other_poam['slug']}")
