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


class TestResponseState:
    """#1242 — each row says whether the baseline needs it, and its state."""

    STATES = {"inherited", "hybrid_satisfied", "hybrid_unsatisfied",
              "responsibility_unsatisfied", "implemented", "missing"}

    def test_required_rows_carry_a_state_and_others_none(self, admin_client, ssp_slug):
        r = admin_client.get(f"/api/v1/ssp_documents/{ssp_slug}/statements",
                             params={"per_page": 100})
        assert r.status_code == 200, r.text
        rows = r.json()["data"]
        assert any(row["required"] for row in rows), "no row on the SSP is a required response"
        for row in rows:
            if row["required"]:
                assert row["response_state"] in self.STATES, row
            else:
                assert row["response_state"] is None, row
            assert row["cdef_reviewed"] in (True, False, None), row

    def test_the_document_totals_add_up(self, admin_client, ssp_slug):
        r = admin_client.get(f"/api/v1/ssp_documents/{ssp_slug}")
        assert r.status_code == 200, r.text
        progress = r.json()["data"]["response_progress"]
        assert progress["done"] + progress["owed"] == progress["required"], progress


class TestResetAndReview:
    """#1242 — reset_to_source and mark_reviewed, the screen's Reset and Mark reviewed."""

    def _authored(self, admin_client, ssp_slug):
        r = admin_client.get(f"/api/v1/ssp_documents/{ssp_slug}/statements",
                             params={"per_page": 100})
        rows = [row for row in r.json()["data"] if row["source_kind"] == "authored"]
        if not rows:
            pytest.skip("no authored statement on this SSP")
        return rows[0]

    def test_reset_to_source_refuses_a_row_with_nothing_overridden(self, admin_client, ssp_slug):
        row = self._authored(admin_client, ssp_slug)
        r = admin_client.post(f"/api/v1/ssp_control_statements/{row['id']}/reset_to_source")
        assert r.status_code == 422, r.text

    def test_mark_reviewed_refuses_a_row_no_cdef_fills(self, admin_client, ssp_slug):
        row = self._authored(admin_client, ssp_slug)
        r = admin_client.post(f"/api/v1/ssp_control_statements/{row['id']}/mark_reviewed")
        assert r.status_code == 422, r.text

    def test_both_refuse_an_unauthenticated_caller(self, base_url, statement):
        import httpx

        with httpx.Client(base_url=base_url, verify=False, timeout=30) as anon:
            for action in ("reset_to_source", "mark_reviewed"):
                r = anon.post(f"/api/v1/ssp_control_statements/{statement['id']}/{action}")
                assert r.status_code == 401, (action, r.text)


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
