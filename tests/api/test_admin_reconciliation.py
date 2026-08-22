"""Tests for the instance-wide catalog-lineage report (#911 layer 2), for #995.

  GET /api/v1/admin/reconciliation

The per-document `reconciliation` object answers "what is wrong with THIS
document". This answers "how much of this instance is affected", which is the
question an operator has before a catalog upgrade lands on their users.

A report is a number an operator acts on, so the assertions here are about the
numbers AGREEING with each other. A summary whose parts do not add up to its
total is worse than no summary: it is a number someone will plan an upgrade
around.
"""

from __future__ import annotations

from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.admin, pytest.mark.phase2]

PATH = "/api/v1/admin/reconciliation"


@pytest.fixture(scope="module")
def report(admin_client: httpx.Client) -> dict[str, Any]:
    response = admin_client.get(PATH)
    assert response.status_code == 200, response.text
    return response.json()["data"]


@pytest.mark.happy
class TestReport:
    def test_returns_the_documented_summary(self, report: dict[str, Any]) -> None:
        assert set(report) >= {"total", "blocking", "advisory", "by_type", "documents"}, report
        assert isinstance(report["documents"], list)
        assert isinstance(report["by_type"], list)

    def test_blocking_and_advisory_account_for_the_total(self, report: dict[str, Any]) -> None:
        """Every affected document is one or the other. If they do not add up,
        some documents are counted in the headline and in neither severity, and
        an operator cannot tell how much of the work is urgent."""
        assert report["blocking"] + report["advisory"] == report["total"], (
            f"blocking {report['blocking']} + advisory {report['advisory']} "
            f"!= total {report['total']}"
        )

    def test_the_document_list_matches_the_total(self, report: dict[str, Any]) -> None:
        """The headline count and the list it summarises must describe the same
        set — this is exactly the shape of defect #984 was."""
        assert len(report["documents"]) == report["total"], (
            f"total says {report['total']}, the documents list holds {len(report['documents'])}"
        )

    def test_the_per_type_breakdown_sums_to_the_total(self, report: dict[str, Any]) -> None:
        """The breakdown an operator reads to decide which area to fix first."""
        by_type_total = sum(row["affected"] for row in report["by_type"])

        assert by_type_total == report["total"], (
            f"by_type affected sums to {by_type_total}, total says {report['total']}"
        )

    def test_no_type_reports_more_affected_than_it_holds(self, report: dict[str, Any]) -> None:
        offenders = [r for r in report["by_type"] if r["affected"] > r["total"]]

        assert not offenders, f"more affected than exist: {offenders}"


@pytest.mark.authz
class TestAuthorization:
    def test_a_non_admin_is_refused(self, user_client: httpx.Client) -> None:
        """Admin-only by design: it enumerates every document in the instance
        regardless of who can see them, so it cannot be boundary-scoped."""
        response = user_client.get(PATH)

        assert_error_envelope(response, expected_status=403)


@pytest.mark.auth
class TestAuthentication:
    def test_an_anonymous_caller_is_refused(self, anon_client: httpx.Client) -> None:
        assert anon_client.get(PATH).status_code == 401
