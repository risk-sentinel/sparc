"""Tests for the admin remediation-timeline (SLA) table (#809 D3), for #995.

  GET /api/v1/admin/remediation_timelines
  PUT /api/v1/admin/remediation_timelines

How many days a team has to remediate, keyed by profile baseline level x NIST
criticality. Feeds `AmendmentValidityService` when a boundary's profile carries
no ODP remediation value for a control, so these numbers decide when a
disposition expires.

PUT is an UPSERT keyed on (baseline_level, criticality) rather than a row id,
which is why there is no create/destroy pair and why `_crud_contract.py` does
not describe this group.

These tests write to instance-wide configuration — there is no per-test scope to
hide in. Every write is therefore restored to the value it displaced, and the
restore is verified, so a failed run cannot leave an SLA table that quietly
changes when dispositions expire.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.admin, pytest.mark.phase2]

PATH = "/api/v1/admin/remediation_timelines"


def _rows(client: httpx.Client) -> list[dict[str, Any]]:
    response = client.get(PATH)
    assert response.status_code == 200, response.text
    return response.json()["data"]


def _find(rows: list[dict[str, Any]], level: str, criticality: str) -> dict[str, Any] | None:
    return next(
        (r for r in rows if r["baseline_level"] == level and r["criticality"] == criticality),
        None,
    )


@pytest.fixture
def restorable_row(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    """One row, put back exactly as it was however the test ends."""
    rows = _rows(admin_client)
    assert rows, "the instance has no remediation timeline rows to exercise"
    original = rows[0]

    try:
        yield original
    finally:
        restored = admin_client.put(
            PATH,
            json={
                "baseline_level": original["baseline_level"],
                "criticality": original["criticality"],
                "days": original["days"],
            },
        )
        assert restored.status_code == 200, f"failed to restore the SLA row: {restored.text}"
        current = _find(_rows(admin_client), original["baseline_level"], original["criticality"])
        assert current and current["days"] == original["days"], (
            "the remediation timeline was left changed after the test"
        )


@pytest.mark.happy
class TestIndex:
    def test_lists_the_sla_table(self, admin_client: httpx.Client) -> None:
        rows = _rows(admin_client)

        assert rows, "no SLA rows at all — AmendmentValidityService has no fallback"
        for row in rows:
            assert set(row) >= {"baseline_level", "criticality", "days", "provisioned"}, row
            assert isinstance(row["days"], int), row

    def test_every_level_and_criticality_pair_is_unique(self, admin_client: httpx.Client) -> None:
        """The pair is the upsert key, so a duplicate makes one row
        unreachable — and makes which SLA applies a matter of ordering."""
        keys = [(r["baseline_level"], r["criticality"]) for r in _rows(admin_client)]

        assert len(keys) == len(set(keys)), sorted(keys)


@pytest.mark.happy
class TestUpsert:
    def test_a_change_is_persisted_and_confirmed_by_an_independent_read(
        self, admin_client: httpx.Client, restorable_row: dict[str, Any]
    ) -> None:
        new_days = restorable_row["days"] + 7

        response = admin_client.put(
            PATH,
            json={
                "baseline_level": restorable_row["baseline_level"],
                "criticality": restorable_row["criticality"],
                "days": new_days,
            },
        )

        assert response.status_code == 200, response.text
        assert response.json()["data"]["days"] == new_days

        reread = _find(
            _rows(admin_client), restorable_row["baseline_level"], restorable_row["criticality"]
        )
        assert reread and reread["days"] == new_days, (
            "the write reported success but the table still holds the old value"
        )

    def test_the_upsert_edits_rather_than_adds(
        self, admin_client: httpx.Client, restorable_row: dict[str, Any]
    ) -> None:
        """Keyed on the pair, not on an id. Writing the same pair twice must
        update one row, not accumulate rows that shadow each other."""
        before = len(_rows(admin_client))

        admin_client.put(
            PATH,
            json={
                "baseline_level": restorable_row["baseline_level"],
                "criticality": restorable_row["criticality"],
                "days": restorable_row["days"] + 3,
            },
        )

        assert len(_rows(admin_client)) == before, "the upsert added a row instead of editing one"


@pytest.mark.validation
class TestRefusals:
    def test_a_non_numeric_day_count_is_refused(
        self, admin_client: httpx.Client, restorable_row: dict[str, Any]
    ) -> None:
        response = admin_client.put(
            PATH,
            json={
                "baseline_level": restorable_row["baseline_level"],
                "criticality": restorable_row["criticality"],
                "days": "not-a-number",
            },
        )

        assert response.status_code == 422, response.text
        reread = _find(
            _rows(admin_client), restorable_row["baseline_level"], restorable_row["criticality"]
        )
        assert reread and reread["days"] == restorable_row["days"], (
            "a refused write still changed the SLA"
        )


@pytest.mark.authz
class TestAuthorization:
    def test_a_non_admin_cannot_read_the_table(self, user_client: httpx.Client) -> None:
        assert_error_envelope(user_client.get(PATH), expected_status=403)

    def test_a_non_admin_cannot_change_an_sla_and_nothing_moves(
        self, admin_client: httpx.Client, user_client: httpx.Client, restorable_row: dict[str, Any]
    ) -> None:
        response = user_client.put(
            PATH,
            json={
                "baseline_level": restorable_row["baseline_level"],
                "criticality": restorable_row["criticality"],
                "days": restorable_row["days"] + 99,
            },
        )

        assert response.status_code == 403, response.text
        reread = _find(
            _rows(admin_client), restorable_row["baseline_level"], restorable_row["criticality"]
        )
        assert reread and reread["days"] == restorable_row["days"], (
            "a refused caller still changed the SLA"
        )


@pytest.mark.auth
class TestAuthentication:
    def test_an_anonymous_caller_is_refused(self, anon_client: httpx.Client) -> None:
        assert anon_client.get(PATH).status_code == 401
        assert anon_client.put(PATH, json={"days": 1}).status_code == 401
