"""#875 — the Add Member role dropdown, exercised in a real browser.

The bug: SPARC_AUTH_BOUNDARY_ROLES was read as a list of role *values* while the
model pinned `role` to an enum of seven keys, so a configured human label passed
the controller's allowlist and then raised ArgumentError inside the enum — a 500
on submit. Nothing in the browser suite touched this screen, and the one request
spec that did stubbed the configured roles specifically to route around it.

These checks are posture-independent by design: they assert what must hold
whether or not SPARC_AUTH_BOUNDARY_ROLES is set, so neither run can pass by
silently skipping (#885). To prove the *configured* posture as well, boot the
stack with a custom vocabulary and name the role you expect to see:

    SPARC_AUTH_BOUNDARY_ROLES='isso, system_owner, security_champion:Security Champion'
    SPARC_SMOKE_EXPECT_ROLE=security_champion   # for this suite

With SPARC_SMOKE_EXPECT_ROLE unset the configured-vocabulary assertion is not
skipped — it is simply not applicable, and every other assertion still runs.
"""

from __future__ import annotations

import os
import re

import pytest

from _api_setup import create_boundary, delete_doc
from helpers import assert_no_csp_violations, record_csp

# Titleize applied to a value it never should have seen. These exact strings are
# what the pre-fix code rendered from the shipped .env, so they make a good
# canary for a regression back to labels-as-values.
MANGLED = ["Assessor / 3 Pao", "Authorizing Official (Ao)", "3 Pao"]


@pytest.fixture
def boundary():
    b = create_boundary()
    try:
        yield b
    finally:
        delete_doc("authorization_boundaries", b["slug"])


def _add_member_path(boundary) -> str:
    return f"/authorization_boundaries/{boundary['slug']}/memberships/new"


ROLE_SELECT = "select[name='authorization_boundary_membership[role]']"
NAME_INPUT = "input[name='authorization_boundary_membership[user_name]']"
EMAIL_INPUT = "input[name='authorization_boundary_membership[user_email]']"
# Scope to the form that owns the role select. A bare "form button[type=submit]"
# also matches the nav's hidden Sign Out button, which is first in DOM order.
MEMBER_FORM = f"form:has({ROLE_SELECT})"


def _role_options(page) -> list[tuple[str, str]]:
    return page.eval_on_selector_all(
        f"{ROLE_SELECT} option",
        "els => els.map(e => [e.value, e.textContent.trim()])",
    )


class TestAddMemberRoles:
    def test_dropdown_is_populated_and_clean(self, authed_page, boundary):
        record_csp(authed_page)
        authed_page.goto(_add_member_path(boundary))
        authed_page.wait_for_load_state("networkidle")

        options = _role_options(authed_page)
        assert options, "the role dropdown rendered no options"
        assert all(value for value, _ in options), f"an option had an empty value: {options}"
        assert_no_csp_violations(authed_page, during="add member render")

    def test_labels_are_not_titleize_mangled(self, authed_page, boundary):
        """The secondary symptom of #875 — role_label_for titleizing a value it
        did not recognise, so 'Assessor / 3PAO' displayed as 'Assessor / 3 Pao'."""
        authed_page.goto(_add_member_path(boundary))
        authed_page.wait_for_load_state("networkidle")

        labels = [label for _, label in _role_options(authed_page)]
        for bad in MANGLED:
            assert not any(bad in label for label in labels), (
                f"role label {bad!r} is a titleized raw value — {labels}"
            )

    def test_submitting_a_role_from_the_dropdown_saves(self, authed_page, boundary):
        """The 500. Whatever the dropdown offers must be acceptable on submit —
        the two used to disagree."""
        record_csp(authed_page)
        authed_page.goto(_add_member_path(boundary))
        authed_page.wait_for_load_state("networkidle")

        options = _role_options(authed_page)
        value, label = options[0]

        authed_page.fill(NAME_INPUT, "Smoke Tester")
        authed_page.fill(EMAIL_INPUT, "smoke@example.gov")
        authed_page.select_option(ROLE_SELECT, value)
        authed_page.locator(f"{MEMBER_FORM} input[type='submit']").click()

        # Turbo Drive navigates by fetch and swaps the body, so networkidle can
        # resolve against the PRE-swap DOM. Wait for the new content itself.
        authed_page.wait_for_selector("text=Smoke Tester", timeout=10_000)
        authed_page.wait_for_load_state("networkidle")

        body = authed_page.inner_text("body")
        assert "Smoke Tester" in body, "the member was not added"
        assert label in body, f"expected the role label {label!r} in the confirmation"
        # #869 — a successful add stays on the add screen.
        assert re.search(r"/memberships/new$", authed_page.url), (
            f"expected to stay on the add screen, got {authed_page.url}"
        )
        assert_no_csp_violations(authed_page, during="add member submit")

    def test_configured_vocabulary_is_offered(self, authed_page, boundary):
        """The configured posture. Runs only when the stack was booted with a
        custom vocabulary AND the expected role was named — otherwise there is
        nothing to assert, which is different from skipping a check that applies.
        """
        expected = os.environ.get("SPARC_SMOKE_EXPECT_ROLE")
        if not expected:
            pytest.skip(
                "SPARC_SMOKE_EXPECT_ROLE not set — this asserts the CONFIGURED "
                "SPARC_AUTH_BOUNDARY_ROLES posture; the default posture is covered "
                "by the other tests in this file, which always run"
            )

        authed_page.goto(_add_member_path(boundary))
        authed_page.wait_for_load_state("networkidle")

        values = [value for value, _ in _role_options(authed_page)]
        assert expected in values, (
            f"configured role {expected!r} was not offered — dropdown held {values}"
        )
