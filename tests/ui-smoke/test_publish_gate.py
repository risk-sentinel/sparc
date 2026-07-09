"""UI smoke: publish gate under SPARC_REQUIRE_DOCUMENT_APPROVAL (#708).

Publish is a **web-only** flow — the API resources expose no publish endpoint —
so the approval gate is validated in the browser, not in tests/api. When the
flag is ON, a draft trust-store document cannot be published until approved: the
publish modal's readiness reports ``approval_required`` + ``checks.approved =
false``, so its confirm button stays "Fix & Publish" instead of "Confirm &
Publish".

Requires an instance with the env var **actually set**. When the flag is OFF
(the default and most deployments) these skip — detected via the same
``publish_check`` readiness the modal itself consumes.

Selectors verified against app/views/shared/_publish_button.html.erb +
app/javascript/controllers/publish_modal_controller.js.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import pytest

from _api_setup import create_catalog, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


@pytest.fixture
def draft_catalog(session_cookie) -> Iterator[dict[str, Any]]:
    doc = create_catalog()  # a freshly-created catalog is a draft
    try:
        yield doc
    finally:
        delete_doc("control_catalogs", doc["id"])


def _readiness(page, check_path: str):
    """Fetch the publish_check readiness (browser session) — the modal's own
    data source — to detect whether the approval gate is enabled + met."""
    return page.evaluate(
        """async (u) => {
             const r = await fetch(u, {credentials: 'same-origin',
                                       headers: {'Accept': 'application/json'}});
             return r.ok ? await r.json() : null;
        }""",
        check_path,
    )


class TestPublishGate:
    def test_publish_modal_blocks_unapproved_when_flag_on(
        self, authed_page, draft_catalog
    ):
        slug = draft_catalog.get("slug") or draft_catalog["id"]
        show = f"/control_catalogs/{slug}"
        record_csp(authed_page)
        authed_page.goto(show)
        authed_page.wait_for_load_state("networkidle")

        readiness = _readiness(authed_page, f"{show}/publish_check")
        if not (readiness and readiness.get("approval_required")):
            pytest.skip("SPARC_REQUIRE_DOCUMENT_APPROVAL not enabled on this instance")

        # Gate active + doc unapproved: readiness must reflect it.
        assert readiness.get("checks", {}).get("approved") is False, (
            f"expected checks.approved == false under the gate: {readiness}"
        )

        # UI: the publish modal opens and its confirm button is gated —
        # "Fix & Publish", not "Confirm & Publish" — and the flow is CSP-clean.
        authed_page.get_by_role("button", name="Publish").click()
        authed_page.locator("[data-publish-modal-target='modal']").wait_for(
            state="visible", timeout=5_000
        )
        btn = authed_page.locator("[data-publish-modal-target='publishBtn']")
        assert "Fix" in btn.inner_text(), (
            f"expected gated 'Fix & Publish' button, got {btn.inner_text()!r}"
        )
        assert_no_csp_violations(authed_page, during="publish modal (approval-gated)")
