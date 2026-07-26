"""Shared contract for the DocumentApprovalApi review workflow (#630/#634).

The submit_for_review -> approve/reject flow is a single concern
(app/controllers/concerns/document_approval_api.rb) included by every
document controller that supports review: CDEF, profile_documents, and
control_catalogs. Rather than duplicate the five contract tests per module,
each test file subclasses ``ReviewWorkflowContract``, sets ``PATH`` +
``IDENT_KEY`` (``"slug"`` or ``"id"``, matching how that resource is
addressed), and provides a ``review_doc`` fixture yielding a freshly-created
document.

Contract: success renders ``{data: {approval_status, submitted_*, approved_*,
rejection_reason}}``; failure renders ``{error}`` with the transition's status
code.

Underscore-prefixed file name signals "internal to the test suite" — not
imported anywhere outside ``tests/api/``.
"""

from __future__ import annotations

from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope


class ReviewWorkflowContract:
    """Mixin of the five review-workflow contract tests.

    Subclasses must define ``PATH``, optionally override ``IDENT_KEY``, and
    provide a ``review_doc`` fixture.
    """

    PATH: str = ""
    IDENT_KEY: str = "slug"

    def _ident(self, doc: dict[str, Any]) -> Any:
        return doc[self.IDENT_KEY]

    def _submit_or_skip(self, admin_client: httpx.Client, ident: Any) -> httpx.Response:
        """Submit for review, or skip if the doc type can't be given content here.

        Content-gated types reject an empty document with 422 "missing required
        content: ... At least one control". #757 provisions that content where an
        API path exists — CDEF fixtures populate_from_profile off the seeded
        published baseline, so their submit -> approve/reject contract now runs.
        The remaining skip is **profile**: a profile's baseline controls are
        built in the UI baseline builder or imported from a resolved-profile file
        via an async DocumentConversionJob — there is no synchronous API to seed
        them, so profile review stays documented-skipped (see the note on
        test_profile_documents.TestReviewWorkflow). Control catalogs submit empty.
        """
        submit = admin_client.post(f"{self.PATH}/{ident}/submit_for_review")
        if submit.status_code == 422 and "content" in submit.text.lower():
            pytest.skip(
                "content-gated type not provisionable via the synchronous API "
                "(profile baselines are UI/async-import only) — see #757"
            )
        assert submit.status_code == 200, submit.text
        return submit

    @pytest.mark.happy
    def test_submit_then_approve(
        self, admin_client: httpx.Client, review_doc: dict[str, Any]
    ) -> None:
        ident = self._ident(review_doc)
        submit = self._submit_or_skip(admin_client, ident)
        assert submit.json()["data"]["approval_status"]

        approve = admin_client.post(f"{self.PATH}/{ident}/approve")
        assert approve.status_code == 200, approve.text
        data = approve.json()["data"]
        assert data["approved_by_user_id"] is not None
        assert data["approved_at"] is not None

    @pytest.mark.happy
    def test_submit_then_reject_records_reason(
        self, admin_client: httpx.Client, review_doc: dict[str, Any]
    ) -> None:
        ident = self._ident(review_doc)
        self._submit_or_skip(admin_client, ident)
        reject = admin_client.post(
            f"{self.PATH}/{ident}/reject", json={"reason": "needs more detail"}
        )
        assert reject.status_code == 200, reject.text
        assert reject.json()["data"]["rejection_reason"] == "needs more detail"

    @pytest.mark.auth
    def test_non_admin_cannot_approve(
        self,
        admin_client: httpx.Client,
        user_client: httpx.Client,
        review_doc: dict[str, Any],
    ) -> None:
        ident = self._ident(review_doc)
        admin_client.post(f"{self.PATH}/{ident}/submit_for_review")
        assert user_client.post(f"{self.PATH}/{ident}/approve").status_code in (401, 403)

    def test_approve_without_submit_is_rejected(
        self, admin_client: httpx.Client, review_doc: dict[str, Any]
    ) -> None:
        # A draft that was never submitted for review cannot be approved.
        resp = admin_client.post(f"{self.PATH}/{self._ident(review_doc)}/approve")
        assert resp.status_code in (409, 422), resp.text

    @pytest.mark.auth
    def test_submit_requires_token(
        self, anon_client: httpx.Client, review_doc: dict[str, Any]
    ) -> None:
        assert_error_envelope(
            anon_client.post(f"{self.PATH}/{self._ident(review_doc)}/submit_for_review"),
            expected_status=401,
        )
