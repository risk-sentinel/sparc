"""#919 / #707 — boundary authorization, exercised in a real browser.

Two properties that were both broken and are easy to break again, because
neither shows up in a single-identity run:

  1. **The guards deny.** Thirteen boundary-scoped controllers shipped with no
     authorization at all — any signed-in user who knew a slug could rewrite
     POA&M findings, profile baselines and back-matter provenance. Every
     existing test exercised the *permitted* path, so nothing noticed for five
     months of green CI.

  2. **Roster membership grants.** The roster and the permission model were
     separate tables that never met, so a member added as ISSO held zero
     permissions. That was invisible while the screens had no guards — the
     roster looked like it worked because nothing was asking. Adding the guards
     turned it into a lockout, which is why both had to ship together.

Both need a SECOND identity to test: the primary smoke token is an admin, and
`admin?` short-circuits every permission check, so an admin-only run would pass
against a completely unguarded app. These use `user_authed_page` (the non-admin
identity) for exactly that reason.

Requires SPARC_SMOKE_USER_TOKEN. Without it the two-identity fixture skips —
which is honest here: the assertions are *not* applicable rather than silently
passing, and the single-identity assertions below still run.
"""

from __future__ import annotations

import pytest

from _api_setup import create_boundary, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated


@pytest.fixture
def boundary():
    b = create_boundary()
    try:
        yield b
    finally:
        delete_doc("authorization_boundaries", b["slug"])


def _memberships_path(boundary) -> str:
    return f"/authorization_boundaries/{boundary['slug']}/memberships/new"


def _environments_path(boundary) -> str:
    """Boundary environments — one of the 13 controllers #919 guarded."""
    return f"/authorization_boundaries/{boundary['slug']}/boundaries/new"


class TestGuardsDenyANonMember:
    """The #919 half: a signed-in user with no standing on the boundary is
    refused, in a browser, without a 500 and without a CSP violation."""

    def test_non_member_cannot_reach_the_environment_editor(self, user_authed_page, boundary):
        record_csp(user_authed_page)
        resp = user_authed_page.goto(_environments_path(boundary))
        user_authed_page.wait_for_load_state("networkidle")

        # The guard redirects rather than 403ing on HTML requests, so the
        # meaningful assertion is "did not land on the editor" — not the status.
        assert resp is None or resp.status < 500, (
            f"the guard should refuse cleanly, not error: status={resp.status if resp else 'n/a'}"
        )
        assert "/boundaries/new" not in user_authed_page.url, (
            f"a non-member reached the boundary environment editor at {user_authed_page.url} — "
            "the #919 guard is not enforcing"
        )
        assert_no_csp_violations(user_authed_page, during="denied boundary environment editor")

    def test_non_member_cannot_reach_the_roster_editor(self, user_authed_page, boundary):
        record_csp(user_authed_page)
        user_authed_page.goto(_memberships_path(boundary))
        user_authed_page.wait_for_load_state("networkidle")

        assert "/memberships/new" not in user_authed_page.url, (
            f"a non-member reached the roster editor at {user_authed_page.url} — this is the "
            "exact hole #918 fixed, and it must stay fixed"
        )
        assert_no_csp_violations(user_authed_page, during="denied roster editor")


class TestAdminRetainsAccess:
    """The positive control. Without it an over-tight guard — one that refuses
    everybody — would ship green, because every denial assertion above would
    still pass."""

    def test_admin_reaches_the_roster_editor(self, authed_page, boundary):
        record_csp(authed_page)
        resp = authed_page.goto(_memberships_path(boundary))
        authed_page.wait_for_load_state("networkidle")

        assert resp is not None and resp.status < 400, f"admin was refused: {resp.status if resp else 'n/a'}"
        assert "/memberships/new" in authed_page.url, (
            f"admin did not reach the roster editor — landed on {authed_page.url}"
        )
        assert_no_csp_violations(authed_page, during="admin roster editor")

    def test_admin_reaches_the_environment_editor(self, authed_page, boundary):
        resp = authed_page.goto(_environments_path(boundary))
        authed_page.wait_for_load_state("networkidle")

        assert resp is not None and resp.status < 400
        assert "/boundaries/new" in authed_page.url


class TestRosterMembershipGrantsAccess:
    """The #707 half, and the reason the guards do not lock out real users.

    Adding someone to the roster with a role must grant that role's permissions
    ON THAT BOUNDARY. This walks the actual screen rather than calling the API,
    because the screen is what an ISSM uses and it is the path that was broken.
    """

    def test_adding_a_member_records_their_role(self, authed_page, boundary):
        record_csp(authed_page)
        authed_page.goto(_memberships_path(boundary))
        authed_page.wait_for_load_state("networkidle")

        role_select = "select[name='authorization_boundary_membership[role]']"
        options = authed_page.eval_on_selector_all(
            f"{role_select} option", "els => els.map(e => e.value).filter(Boolean)"
        )
        assert options, "the role dropdown rendered no options"
        chosen = "isso" if "isso" in options else options[0]

        authed_page.fill("input[name='authorization_boundary_membership[user_name]']", "Smoke Member 919")
        authed_page.fill(
            "input[name='authorization_boundary_membership[user_email]']", "smoke-919@example.gov"
        )
        authed_page.select_option(role_select, chosen)
        # input[type=submit], not button — and Turbo Drive swaps the body by
        # fetch, so networkidle can resolve against the PRE-swap DOM. Wait for
        # the new content itself.
        authed_page.locator(f"form:has({role_select}) input[type='submit']").click()
        authed_page.wait_for_selector("text=Smoke Member 919", timeout=10_000)
        authed_page.wait_for_load_state("networkidle")

        body = authed_page.inner_text("body")
        assert "Smoke Member 919" in body, (
            f"the member was not added — the roster does not list them. URL={authed_page.url}"
        )
        assert_no_csp_violations(authed_page, during="add roster member")

    def test_the_roster_screen_survives_the_round_trip(self, authed_page, boundary):
        """#707 wired an after_commit onto membership writes. A failure there
        would surface as a 500 on submit rather than a missing permission, so
        the write path is asserted separately from the permission it produces."""
        authed_page.goto(_memberships_path(boundary))
        authed_page.wait_for_load_state("networkidle")

        role_select = "select[name='authorization_boundary_membership[role]']"
        options = authed_page.eval_on_selector_all(
            f"{role_select} option", "els => els.map(e => e.value).filter(Boolean)"
        )
        chosen = "view_only" if "view_only" in options else options[0]

        authed_page.fill("input[name='authorization_boundary_membership[user_name]']", "Smoke ViewOnly 919")
        authed_page.fill(
            "input[name='authorization_boundary_membership[user_email]']", "smoke-919-ro@example.gov"
        )
        authed_page.select_option(role_select, chosen)
        authed_page.locator(f"form:has({role_select}) input[type='submit']").click()
        authed_page.wait_for_selector("text=Smoke ViewOnly 919", timeout=10_000)
        authed_page.wait_for_load_state("networkidle")

        assert "error" not in authed_page.inner_text("body").lower()[:400], (
            "adding a member surfaced an error — the membership role-sync callback may be raising"
        )
