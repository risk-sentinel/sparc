"""Tests for SAR objective determinations (v1.17.2).

Two endpoints, nested on a SAR document:
  - index   GET   /api/v1/sar_documents/:sar_document_id/objectives
  - update  PATCH /api/v1/sar_documents/:sar_document_id/objectives/:id

Recording a per-objective result was web-only, so a pipeline could not record
an assessment at all. And a failed objective changed nothing but its own
status: the POA&M is built from SAR risks, so an assessed failure never reached
it. The contract pinned here: a failure opens the control's risk, and clearing
it closes the risk again.
"""

from __future__ import annotations

from typing import Any

import httpx
import pytest

pytestmark = [pytest.mark.sar_objectives, pytest.mark.phase2]

_SAR_DOCS = "/api/v1/sar_documents"


def _objectives_path(doc: dict[str, Any]) -> str:
    return f"{_SAR_DOCS}/{doc['id']}/objectives"


def _sar_with_objectives(client: httpx.Client) -> tuple[dict[str, Any], dict[str, Any]]:
    """A SAR that has a determinable objective still pending, and that objective."""
    rows = client.get(_SAR_DOCS, params={"items": 50}).json()["data"]
    for row in rows:
        listing = client.get(_objectives_path(row), params={"items": 200})
        if listing.status_code != 200:
            continue
        for objective in listing.json()["data"]:
            if objective["determinable"] and objective["status"] == "pending":
                return row, objective
    pytest.skip("no SAR on this instance has a pending, determinable objective")


def _control_risk(
    client: httpx.Client, doc: dict[str, Any], control_id: str
) -> dict[str, Any] | None:
    risks = client.get(f"{_SAR_DOCS}/{doc['id']}/risks", params={"items": 200}).json()["data"]
    return next((r for r in risks if r["title"] == f"Risk for {control_id}"), None)


@pytest.fixture
def pending(admin_client: httpx.Client):
    doc, objective = _sar_with_objectives(admin_client)
    before = _control_risk(admin_client, doc, objective["control_id"])
    yield doc, objective
    admin_client.patch(
        f"{_objectives_path(doc)}/{objective['objective_id']}",
        json={"sar_control_objective": {"status": "pending"}},
    )
    # A risk this test opened is closed again by the reset above; one that was
    # already there is left as it was found.
    if before is None:
        risk = _control_risk(admin_client, doc, objective["control_id"])
        assert risk is None or risk["status"] == "closed"


class TestIndex:
    @pytest.mark.happy
    def test_lists_objectives_with_the_collection_envelope(
        self, admin_client: httpx.Client
    ) -> None:
        doc, _ = _sar_with_objectives(admin_client)
        payload = admin_client.get(_objectives_path(doc)).json()

        assert payload["meta"]["count"] > 0
        first = payload["data"][0]
        assert {"objective_id", "control_id", "status", "determinable"} <= first.keys()
        assert "_obj" in first["objective_id"]

    def test_filters_by_control(self, admin_client: httpx.Client) -> None:
        doc, objective = _sar_with_objectives(admin_client)
        rows = admin_client.get(
            _objectives_path(doc), params={"control_id": objective["control_id"], "items": 200}
        ).json()["data"]

        assert rows
        assert {r["control_id"] for r in rows} == {objective["control_id"]}


class TestUpdate:
    @pytest.mark.happy
    def test_a_failed_objective_opens_the_control_risk_and_clearing_it_closes_it(
        self, admin_client: httpx.Client, pending
    ) -> None:
        doc, objective = pending
        url = f"{_objectives_path(doc)}/{objective['objective_id']}"

        failed = admin_client.patch(
            url,
            json={
                "sar_control_objective": {"status": "failed", "assessor_notes": "contract suite"}
            },
        )
        assert failed.status_code == 200, failed.text
        assert failed.json()["data"]["status"] == "failed"
        assert failed.json()["data"]["assessed_at"]
        risk = _control_risk(admin_client, doc, objective["control_id"])
        assert risk is not None and risk["status"] == "open"

        passing = admin_client.patch(url, json={"sar_control_objective": {"status": "passing"}})
        assert passing.status_code == 200, passing.text

        # Closed once nothing of the control is failing; still open if another
        # objective of the same control failed before this test.
        still_failing = [
            o for o in admin_client.get(
                _objectives_path(doc), params={"control_id": objective["control_id"], "items": 200}
            ).json()["data"]
            if o["status"] == "failed"
        ]
        expected = "open" if still_failing else "closed"
        assert _control_risk(admin_client, doc, objective["control_id"])["status"] == expected

    def test_accepts_the_record_id_as_well_as_the_objective_id(
        self, admin_client: httpx.Client, pending
    ) -> None:
        doc, objective = pending
        resp = admin_client.patch(
            f"{_objectives_path(doc)}/{objective['id']}",
            json={"sar_control_objective": {"assessor_name": "Contract Suite"}},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["data"]["assessor_name"] == "Contract Suite"

    def test_rejects_a_status_that_is_not_a_determination(
        self, admin_client: httpx.Client, pending
    ) -> None:
        doc, objective = pending
        resp = admin_client.patch(
            f"{_objectives_path(doc)}/{objective['objective_id']}",
            json={"sar_control_objective": {"status": "probably-fine"}},
        )
        assert resp.status_code == 422

    def test_refuses_an_unknown_field(self, admin_client: httpx.Client, pending) -> None:
        doc, objective = pending
        resp = admin_client.patch(
            f"{_objectives_path(doc)}/{objective['objective_id']}",
            json={"sar_control_objective": {"objective_id": "ac-99_obj.z"}},
        )
        assert resp.status_code in (400, 422)


class TestAuthorization:
    def test_requires_a_token(self, anon_client: httpx.Client, admin_client: httpx.Client) -> None:
        doc, _ = _sar_with_objectives(admin_client)
        assert anon_client.get(_objectives_path(doc)).status_code == 401
