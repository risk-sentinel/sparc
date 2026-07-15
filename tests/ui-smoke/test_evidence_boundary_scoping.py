"""#738 — Evidence boundary-scoping, verified in a real browser as a NON-admin.

Uses deterministic demo-seed fixtures:
  - "SMOKE GLOBAL EVIDENCE"     — nil boundary, visible to all authenticated users
  - "SMOKE RESTRICTED EVIDENCE" — in "Smoke Restricted Boundary" (no members),
                                  so it is inaccessible to any non-admin identity

Needs SPARC_SMOKE_USER_TOKEN (the second, non-admin identity); the
`user_authed_page` fixture auto-skips when it is unset. The `authed_page`
(admin) identity is used only to discover the restricted record's URL, so a
real scoping regression can't hide behind "no data".
"""

from __future__ import annotations

import pytest

from helpers import csp_violations, record_csp

GLOBAL_TITLE = "SMOKE GLOBAL EVIDENCE"
RESTRICTED_TITLE = "SMOKE RESTRICTED EVIDENCE"


def _restricted_href(admin_page) -> str:
    admin_page.goto("/evidences")
    admin_page.wait_for_load_state("networkidle")
    link = admin_page.get_by_role("link", name=RESTRICTED_TITLE)
    if link.count() == 0:
        pytest.skip(f"seed fixture '{RESTRICTED_TITLE}' missing — run the demo seed (SPARC_SEED_DEMO=true)")
    href = link.first.get_attribute("href")
    assert href, "restricted evidence link has no href"
    return href


def test_non_admin_index_hides_out_of_boundary_evidence(user_authed_page, authed_page):
    _restricted_href(authed_page)  # assert the fixtures exist (admin can see the restricted one)

    record_csp(user_authed_page)
    user_authed_page.goto("/evidences")
    user_authed_page.wait_for_load_state("networkidle")
    body = user_authed_page.content()

    assert GLOBAL_TITLE in body, "non-admin should see global (nil-boundary) evidence"
    assert RESTRICTED_TITLE not in body, (
        "#738 regression: a non-admin sees out-of-boundary evidence in the index"
    )
    assert csp_violations(user_authed_page) == [], "CSP violations on /evidences as non-admin"


def test_non_admin_direct_show_of_out_of_boundary_is_blocked(user_authed_page, authed_page):
    href = _restricted_href(authed_page)

    record_csp(user_authed_page)
    resp = user_authed_page.goto(href)
    user_authed_page.wait_for_load_state("networkidle")

    assert resp is None or resp.status < 500, f"server error on a blocked show ({resp.status if resp else '?'})"
    assert RESTRICTED_TITLE not in user_authed_page.content(), (
        "#738 regression: out-of-boundary evidence content leaked to a non-admin"
    )
    assert not user_authed_page.url.rstrip("/").endswith(href.rstrip("/")), (
        "non-admin was not redirected away from the restricted show page"
    )
    assert csp_violations(user_authed_page) == [], "CSP violations on the blocked show as non-admin"
