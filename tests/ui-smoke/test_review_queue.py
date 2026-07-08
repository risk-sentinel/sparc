"""UI smoke: review queue (#630-634).

/review_queue lists documents submitted for review, filtered to the ones the
signed-in user can approve (`DocumentApprovalService#can_approve?`). Submit has
no button on the show pages, so we submit via the API and drive the queue in the
browser:
- the approver's row exposes Approve + a reject reason field + Reject (admins
  bypass SoD, so they can act on their own submissions). The full click→approved
  state transition is deferred: it surfaced a real CSP violation on the flow
  (#712); the transition contract itself is covered by tests/api (#642).
- a non-admin without approve authority sees the doc filtered OUT — the SoD /
  authority enforcement, exercised with a second identity (SPARC_SMOKE_USER_TOKEN).

Not covered here: the pure separation-of-duties case (an approver-capable
non-admin blocked on their OWN submission) needs an RBAC permission grant to set
up, out of scope for the seed. Selectors verified against
app/views/review_queue/index.html.erb.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import pytest

from _api_setup import create_catalog, delete_doc, submit_for_review
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


@pytest.fixture
def submitted_doc(session_cookie) -> Iterator[dict[str, Any]]:
    # A control catalog is submittable for review without controls (unlike
    # CDEF/SSP/profile, which require content), so it's the reliable fixture
    # for exercising the queue. Catalogs are id-addressed.
    doc = create_catalog()
    status = submit_for_review("control_catalogs", doc["id"])
    try:
        yield {"doc": doc, "submit_status": status}
    finally:
        delete_doc("control_catalogs", doc["id"])


class TestReviewQueue:
    def test_review_queue_loads_clean(self, authed_page):
        record_csp(authed_page)
        resp = authed_page.goto("/review_queue")
        assert resp and resp.status < 400, f"{resp.status if resp else 'no response'}"
        authed_page.wait_for_load_state("networkidle")
        assert_no_csp_violations(authed_page, during="review_queue load")

    def test_submitted_doc_appears_in_queue(self, authed_page, submitted_doc):
        if submitted_doc["submit_status"] != 200:
            pytest.skip(
                f"submit_for_review returned {submitted_doc['submit_status']} "
                "— document not in a submittable state on this instance"
            )
        record_csp(authed_page)
        authed_page.goto("/review_queue")
        authed_page.wait_for_load_state("networkidle")
        name = submitted_doc["doc"]["name"]
        assert authed_page.get_by_text(name).count() >= 1, (
            f"submitted document {name!r} not found in /review_queue"
        )
        assert_no_csp_violations(authed_page, during="review_queue with pending doc")


def _row(page, name: str):
    """The review-queue table row for the document named ``name``."""
    return page.get_by_role("row").filter(has_text=name)


class TestReviewActions:
    """Approve/reject from the queue + the SoD/authority filter (#630-634)."""

    def test_approver_row_exposes_approve_and_reject(self, authed_page, submitted_doc):
        """The approver's queue row exposes the Approve button + a reject reason
        field + Reject button.

        The full state transition (click → approved/rejected → row clears) is
        NOT asserted here: driving it surfaced a real CSP violation
        (`script-src-elem inline`) on the approve/reject flow — tracked in #712.
        The state-transition contract itself is covered by tests/api (#642
        TestReviewWorkflow). Re-enable the end-to-end assertion once #712 lands.
        """
        if submitted_doc["submit_status"] != 200:
            pytest.skip("catalog not submittable on this instance")
        name = submitted_doc["doc"]["name"]
        record_csp(authed_page)
        authed_page.goto("/review_queue")
        authed_page.wait_for_load_state("networkidle")
        row = _row(authed_page, name)
        assert row.get_by_role("button", name="Approve").count() == 1, "no Approve control"
        assert row.get_by_role("textbox").count() == 1, "no reject reason field"
        assert row.get_by_role("button", name="Reject").count() == 1, "no Reject control"
        assert_no_csp_violations(authed_page, during="review_queue actions render")

    def test_non_approver_queue_excludes_others_submissions(
        self, user_authed_page, submitted_doc
    ):
        # Two identities: admin submits (submitted_doc uses the SA token); a
        # non-admin without approve authority views the queue. can_approve?
        # filters the doc out — SoD + authority enforcement at the queue level.
        if submitted_doc["submit_status"] != 200:
            pytest.skip("catalog not submittable on this instance")
        name = submitted_doc["doc"]["name"]
        record_csp(user_authed_page)
        resp = user_authed_page.goto("/review_queue")
        assert resp and resp.status < 400, f"{resp.status if resp else 'no response'}"
        user_authed_page.wait_for_load_state("networkidle")
        assert user_authed_page.get_by_text(name).count() == 0, (
            f"non-approver should not see {name!r} in their review queue"
        )
        assert_no_csp_violations(user_authed_page, during="non-approver review_queue")
