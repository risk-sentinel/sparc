"""SSP control statements — per-statement implementation prose (#1100).

OSCAL models an SSP this way: `implemented-requirement.statements` identifies
which statements within a control are addressed, and each carries its own
implementation prose. SPARC has stored statements since #393, but the only route
that could WRITE `implementation_prose` was an HTML member action — the web UI
was the sole way to author the field carrying the actual system security plan.

Exercised against a running instance. These assert the CONTRACT, not just that
the endpoints answer: that structure cannot be rewritten by a client, that
`answered` tracks the prose, and that a prose edit round-trips.
"""

from __future__ import annotations

import uuid

import pytest

pytestmark = [pytest.mark.documents, pytest.mark.phase2]


@pytest.fixture(scope="module")
def ssp_slug(admin_client):
    r = admin_client.get("/api/v1/ssp_documents", params={"per_page": 25})
    assert r.status_code == 200, r.text
    for doc in r.json()["data"]:
        slug = doc.get("slug") or doc.get("id")
        s = admin_client.get(f"/api/v1/ssp_documents/{slug}/statements", params={"per_page": 1})
        if s.status_code == 200 and s.json()["data"]:
            return slug
    pytest.skip("no SSP on this instance carries statements — run the demo seed")


@pytest.fixture(scope="module")
def statement(admin_client, ssp_slug):
    r = admin_client.get(f"/api/v1/ssp_documents/{ssp_slug}/statements", params={"per_page": 50})
    assert r.status_code == 200, r.text
    rows = r.json()["data"]
    assert rows, "the SSP reported no statements"
    return rows[0]


class TestIndex:
    def test_lists_statements_for_the_document(self, admin_client, ssp_slug):
        r = admin_client.get(f"/api/v1/ssp_documents/{ssp_slug}/statements")

        assert r.status_code == 200, r.text
        body = r.json()
        assert body["data"], "expected at least one statement"
        # The API-wide envelope is {count, items, page, pages} — not `total`.
        assert "count" in body["meta"], body["meta"]
        assert body["meta"]["count"] >= len(body["data"])

    def test_each_row_carries_its_catalog_identity(self, statement):
        # statement_id and label come from the catalog's part tree — they are what
        # an exported document references (#397).
        assert statement["statement_id"]
        assert "control_id" in statement
        assert "answered" in statement

    def test_narrows_to_one_control(self, admin_client, ssp_slug, statement):
        control_id = statement["control_id"]
        r = admin_client.get(
            f"/api/v1/ssp_documents/{ssp_slug}/statements", params={"control_id": control_id}
        )

        assert r.status_code == 200, r.text
        returned = {row["control_id"] for row in r.json()["data"]}
        assert returned == {control_id}, f"?control_id leaked other controls: {returned}"


class TestUpdate:
    def test_writes_prose_and_reads_it_back(self, admin_client, statement):
        marker = f"api-suite {uuid.uuid4().hex[:8]}"
        sid = statement["id"]
        original = admin_client.get(f"/api/v1/ssp_control_statements/{sid}").json()["data"]

        try:
            r = admin_client.patch(
                f"/api/v1/ssp_control_statements/{sid}",
                json={"ssp_control_statement": {"implementation_prose": marker}},
            )
            assert r.status_code == 200, r.text
            assert r.json()["data"]["implementation_prose"] == marker

            again = admin_client.get(f"/api/v1/ssp_control_statements/{sid}")
            assert again.json()["data"]["implementation_prose"] == marker
        finally:
            admin_client.patch(
                f"/api/v1/ssp_control_statements/{sid}",
                json={"ssp_control_statement": {
                    "implementation_prose": original.get("implementation_prose") or ""}},
            )

    def test_answered_follows_the_prose(self, admin_client, statement):
        sid = statement["id"]
        original = admin_client.get(f"/api/v1/ssp_control_statements/{sid}").json()["data"]

        try:
            admin_client.patch(
                f"/api/v1/ssp_control_statements/{sid}",
                json={"ssp_control_statement": {"implementation_prose": "answered now"}},
            )
            now = admin_client.get(f"/api/v1/ssp_control_statements/{sid}").json()["data"]
            assert now["answered"] is True

            admin_client.patch(
                f"/api/v1/ssp_control_statements/{sid}",
                json={"ssp_control_statement": {"implementation_prose": ""}},
            )
            cleared = admin_client.get(f"/api/v1/ssp_control_statements/{sid}").json()["data"]
            assert cleared["answered"] is False
        finally:
            admin_client.patch(
                f"/api/v1/ssp_control_statements/{sid}",
                json={"ssp_control_statement": {
                    "implementation_prose": original.get("implementation_prose") or ""}},
            )

    def test_refuses_to_let_a_client_rewrite_the_catalog_structure(self, admin_client, statement):
        # statement_id and parent_statement_id belong to the catalog's part tree.
        # permit_strictly rejects the whole request rather than dropping them, so
        # a caller is told instead of believing a write landed.
        sid = statement["id"]
        r = admin_client.patch(
            f"/api/v1/ssp_control_statements/{sid}",
            json={"ssp_control_statement": {
                "statement_id": "hijacked", "implementation_prose": "x"}},
        )

        assert r.status_code == 422, r.text
        after = admin_client.get(f"/api/v1/ssp_control_statements/{sid}").json()["data"]
        assert after["statement_id"] == statement["statement_id"]


class TestSurface:
    """No create, no destroy — structure comes from the catalog, not the client."""

    def test_create_is_not_routed(self, admin_client, ssp_slug):
        r = admin_client.post(
            f"/api/v1/ssp_documents/{ssp_slug}/statements",
            json={"ssp_control_statement": {"statement_id": "invented"}},
        )
        assert r.status_code in (404, 405), r.text

    def test_destroy_is_not_routed(self, admin_client, statement):
        r = admin_client.delete(f"/api/v1/ssp_control_statements/{statement['id']}")
        assert r.status_code in (404, 405), r.text


class TestAuthorization:
    def test_rejects_an_unauthenticated_caller(self, base_url):
        import httpx

        with httpx.Client(base_url=base_url, verify=False, timeout=30) as anon:
            r = anon.get("/api/v1/ssp_documents/any/statements")

        assert r.status_code == 401, r.text
