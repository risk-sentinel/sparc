"""SSP components — the CRUD surface that did not exist until #998.

Components could be created, edited and deleted only through the enrichment
screen, which made the web UI the only way to perform those mutations. This
suite exercises the endpoints against a running instance, including the OSCAL
validation pair: a `validation` component recording a certificate and the
product component it validates.
"""

from __future__ import annotations

import uuid

import pytest

pytestmark = [pytest.mark.documents, pytest.mark.phase2]


def _component_payload(**overrides):
    body = {
        "component_type": "software",
        "title": f"api-suite component {uuid.uuid4().hex[:8]}",
        "description": "Created by the API contract suite.",
    }
    body.update(overrides)
    return {"ssp_component": body}


@pytest.fixture
def ssp_slug(admin_client):
    """An SSP the caller can write to. Skips rather than failing on an instance
    with none — the suite runs against whatever is seeded, and 'no SSP here' is
    a property of the instance, not a defect in the endpoint."""
    r = admin_client.get("/api/v1/ssp_documents", params={"per_page": 5})
    r.raise_for_status()
    rows = r.json().get("data", [])
    if not rows:
        pytest.skip("no SSP documents on this instance to attach components to")
    return rows[0]["slug"]


@pytest.fixture
def component(admin_client, ssp_slug):
    r = admin_client.post(f"/api/v1/ssp_documents/{ssp_slug}/components", json=_component_payload())
    r.raise_for_status()
    created = r.json()["data"]
    yield created
    admin_client.delete(f"/api/v1/ssp_documents/{ssp_slug}/components/{created['uuid']}")


class TestComponentCrud:
    def test_list_returns_the_documents_components(self, admin_client, ssp_slug, component):
        r = admin_client.get(f"/api/v1/ssp_documents/{ssp_slug}/components")
        assert r.status_code == 200
        uuids = [c["uuid"] for c in r.json()["data"]]
        assert component["uuid"] in uuids, "a component just created is not in the list"

    def test_show_resolves_by_uuid(self, admin_client, ssp_slug, component):
        r = admin_client.get(f"/api/v1/ssp_documents/{ssp_slug}/components/{component['uuid']}")
        assert r.status_code == 200
        assert r.json()["data"]["title"] == component["title"]

    def test_update_changes_only_what_was_sent(self, admin_client, ssp_slug, component):
        r = admin_client.patch(
            f"/api/v1/ssp_documents/{ssp_slug}/components/{component['uuid']}",
            json={"ssp_component": {"title": "renamed by the api suite"}},
        )
        assert r.status_code == 200
        body = r.json()["data"]
        assert body["title"] == "renamed by the api suite"
        assert body["description"] == component["description"], (
            "an unsent field was changed by the update"
        )

    def test_create_rejects_a_component_with_no_title(self, admin_client, ssp_slug):
        r = admin_client.post(
            f"/api/v1/ssp_documents/{ssp_slug}/components",
            json={"ssp_component": {"component_type": "software", "description": "x"}},
        )
        assert r.status_code == 422, (
            f"a component with no title was accepted with {r.status_code}"
        )


class TestValidationPair:
    """#998 — the assertion a pipeline needs to write, and could not."""

    def test_a_validation_records_its_certificate_and_its_product(
        self, admin_client, ssp_slug, component
    ):
        r = admin_client.post(
            f"/api/v1/ssp_documents/{ssp_slug}/components",
            json=_component_payload(
                component_type="validation",
                title=f"FIPS 140-2 certificate {uuid.uuid4().hex[:6]}",
                validation_type="fips-140-2",
                validation_reference="4282",
                validation_details_href="https://csrc.nist.gov/example/4282",
                validates_component_id=component["id"],
            ),
        )
        assert r.status_code == 201, r.text
        created = r.json()["data"]
        try:
            validation = created["validation"]
            assert validation["validation_type"] == "fips-140-2"
            assert validation["validation_reference"] == "4282"
            assert validation["validates_component_uuid"] == component["uuid"], (
                "the validation was accepted without recording what it validates"
            )

            # The other side of the pair — the claim must be followable both ways.
            product = admin_client.get(
                f"/api/v1/ssp_documents/{ssp_slug}/components/{component['uuid']}"
            ).json()["data"]
            assert created["uuid"] in [v["uuid"] for v in product["validated_by"]]
        finally:
            admin_client.delete(f"/api/v1/ssp_documents/{ssp_slug}/components/{created['uuid']}")

    def test_a_validation_claim_on_a_non_validation_is_refused(self, admin_client, ssp_slug):
        """An enum value with no supporting fields reads as support without being
        it — and so does a field stored where no exporter will read it."""
        r = admin_client.post(
            f"/api/v1/ssp_documents/{ssp_slug}/components",
            json=_component_payload(component_type="software", validation_reference="4282"),
        )
        assert r.status_code == 422, (
            f"a certificate was recorded against a non-validation component ({r.status_code})"
        )
