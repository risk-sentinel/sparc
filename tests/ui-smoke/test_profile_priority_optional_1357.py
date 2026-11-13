"""#1357 — a baseline control's priority is optional.

Priority codes are not part of NIST SP 800-53 Rev 5, so Publish no longer
waits on one. What only a browser proves: clicking Publish on a baseline whose
controls have no priority opens the publish flow, not the "Prioritization
Required" block the dialog used to raise, and the flow is CSP-clean. The
readiness the dialog reads is checked too, from the browser session.
"""

from __future__ import annotations

from typing import Any

import pytest

from _api_setup import _client, create_tailorable_profile, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


def _api(method: str, path: str, **kwargs) -> dict[str, Any]:
    with _client() as c:
        r = c.request(method, path, **kwargs)
        assert r.status_code in (200, 201), f"{method} {path}: {r.status_code} {r.text[:200]}"
        return r.json().get("data") or {}


@pytest.fixture
def profile():
    p = create_tailorable_profile()   # ac-1 and ac-2 selected
    try:
        _api("PUT", f"/api/v1/profile_documents/{p['slug']}/controls/bulk",
             json={"control_ids": ["ac-1", "ac-2"], "priority": None})
        yield p
    finally:
        delete_doc("profile_documents", p["slug"])


def _readiness(page, slug: str) -> dict[str, Any]:
    return page.evaluate(
        """async (u) => {
             const r = await fetch(u, {credentials: 'same-origin',
                                       headers: {'Accept': 'application/json'}});
             return r.ok ? await r.json() : null;
        }""",
        f"/profile_documents/{slug}/publish_check",
    )


def test_publish_never_asks_for_priorities(authed_page, profile):
    page = authed_page
    slug = profile["slug"]
    priorities = _api("GET", f"/api/v1/profile_documents/{slug}")["control_priorities"]
    assert priorities == {"ac-1": None, "ac-2": None}, priorities

    record_csp(page)
    page.goto(f"/profile_documents/{slug}")
    page.wait_for_load_state("networkidle")

    readiness = _readiness(page, slug)
    assert readiness is not None, "publish_check did not answer"
    assert "controls_prioritized" not in readiness.get("checks", {}), readiness
    assert not [e for e in readiness.get("errors", []) if "prioriti" in e.lower()], readiness

    page.get_by_role("button", name="Publish", exact=True).click()
    # The dialog opens, or the parameter block does when this baseline's
    # parameters are untailored (#1357 leaves that check as it is). Either
    # way it is not the prioritization block.
    page.wait_for_function(
        """() => document.getElementById('parameter-warning-modal') ||
                 !document.querySelector("[data-publish-modal-target='modal']").classList.contains('sparc-d-none')""",
        timeout=10000,
    )
    assert page.locator("#prioritization-warning-modal").count() == 0
    assert page.get_by_text("Prioritization Required").count() == 0
    assert page.get_by_text("All controls prioritized").count() == 0
    assert_no_csp_violations(page, during="Publish on a baseline with no priorities")
