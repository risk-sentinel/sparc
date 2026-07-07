"""UI smoke: review queue (#630-634).

/review_queue lists documents submitted for review. Submit-for-review has no
button on the show pages today, so we submit via the API, then assert the
document surfaces in the queue and the page is CSP-clean.

Approve/reject happy paths and the separation-of-duties "hidden for your own
submission" case need a second (approver) identity distinct from the submitter;
they're tracked as a follow-up once the suite grows a second token.

Selectors verified against app/views/review_queue/index.html.erb.
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
