"""#981 — the attester role list must follow the boundary select.

The eligible attesters and roles are computed server-side for the boundary the
form was *rendered* with. Changing the Authorization Boundary select left them
behind, so the form offered a pair the server would then correctly refuse:

    Role 'Policy Manager' is not a role that may attest.

That asymmetry is deliberate (#947). An instance-scoped grant satisfies
`has_permission?` on *every* boundary, so Policy may attest to provider /
leveraged-SSP material belonging to no system, but must not thereby gain
authority over an individual system's evidence. The model was always right; the
form had not been told.

This is the only place the defect is visible. rspec covers the endpoint's
answers (spec/requests/attester_eligibility_spec.rb), but "the select changed
and the other select followed" is a browser interaction — and the mechanism is
a Stimulus controller listening for a dispatched event, so a CSP regression or
a controller that failed to connect would break it exactly the way the original
bug behaved: silently, with stale options that look authoritative.
"""

from __future__ import annotations

import pytest

from _api_setup import create_boundary, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

# Attribute selectors, not ids: nested `fields_for :attestations` produces
# `evidence[attestations_attributes][0][...]`, so the id differs between the
# evidence form and the standalone attestation screen that shares the partial.
# The same idiom test_fileless_attestation_947.py already uses.
ATTESTER = 'select[name*="[attester_user_id]"]'
ROLE = 'select[name*="[role]"]'
BOUNDARY = "#evidence_authorization_boundary_id"


@pytest.fixture
def boundary():
    b = create_boundary()
    try:
        yield b
    finally:
        delete_doc("authorization_boundaries", b["slug"])


def _role_options(page) -> list[str]:
    return page.eval_on_selector(
        ROLE, "el => Array.from(el.options).map(o => o.value).filter(Boolean)"
    )


def _attester_options(page) -> list[str]:
    return page.eval_on_selector(
        ATTESTER, "el => Array.from(el.options).map(o => o.value).filter(Boolean)"
    )


def _open_attestation_form(page) -> None:
    page.goto("/evidences/new")
    page.wait_for_load_state("networkidle")
    # The attester fields only exist once the type is an attestation (#947).
    page.select_option("#evidence_evidence_type", "signed_statement")
    page.wait_for_timeout(200)


class TestTheAttesterListFollowsTheBoundary:
    def test_changing_the_boundary_refreshes_the_attester_list(
        self, authed_page, boundary
    ):
        page = authed_page
        record_csp(page)
        _open_attestation_form(page)

        # Asserting the REQUEST is the honest check here. Comparing option lists
        # before and after would pass vacuously on an instance where both
        # boundaries happen to have the same eligible set — and "the form never
        # asked" is precisely the bug. This fails if the Stimulus controller did
        # not connect, if the event did not reach it, or if the URL value is
        # missing, which are the ways this silently regresses.
        with page.expect_request(
            lambda r: "/attestations/eligible" in r.url, timeout=5000
        ) as request_info:
            page.select_option(BOUNDARY, str(boundary["id"]))

        assert f"authorization_boundary_id={boundary['id']}" in request_info.value.url, (
            f"the refresh asked for the wrong boundary: {request_info.value.url}"
        )

        page.wait_for_load_state("networkidle")

        assert page.locator(ATTESTER).count() > 0, "the attester select vanished"
        assert isinstance(_attester_options(page), list), (
            "attester options were not readable after the refresh"
        )
        assert_no_csp_violations(page, during="boundary change refresh")

    def test_an_instance_scoped_role_is_withdrawn_once_a_boundary_is_chosen(
        self, authed_page, boundary
    ):
        """The defect itself, as one assertion.

        With no boundary the form may legitimately offer an instance-scoped
        attesting role (`policy_manager`). Once a boundary is named the server
        will refuse it, so the form must stop offering it. Skips when no such
        role is on the instance — the seeded posture decides that, and an
        instance without one cannot exhibit the bug.
        """
        page = authed_page
        record_csp(page)
        _open_attestation_form(page)

        attesters = _attester_options(page)
        if not attesters:
            pytest.skip("no eligible attester on this instance for instance-wide evidence")

        instance_scoped = None
        for attester in attesters:
            page.select_option(ATTESTER, attester)
            page.wait_for_timeout(150)
            if "policy_manager" in _role_options(page):
                instance_scoped = attester
                break

        if instance_scoped is None:
            pytest.skip("no instance-scoped attesting role offered on this instance")

        page.select_option(BOUNDARY, str(boundary["id"]))
        page.wait_for_load_state("networkidle")

        # The same person may or may not still be listed; what must be true is
        # that policy_manager is not offered on a named boundary by anyone.
        for attester in _attester_options(page):
            page.select_option(ATTESTER, attester)
            page.wait_for_timeout(150)
            assert "policy_manager" not in _role_options(page), (
                "an instance-scoped attesting role is still offered after "
                "choosing a boundary — the server will refuse this pair"
            )

        assert_no_csp_violations(page, during="instance-scoped role withdrawal")

    def test_clearing_the_boundary_restores_instance_scope(self, authed_page, boundary):
        page = authed_page
        record_csp(page)
        _open_attestation_form(page)

        page.select_option(BOUNDARY, str(boundary["id"]))
        page.wait_for_load_state("networkidle")
        scoped = _attester_options(page)

        page.select_option(BOUNDARY, "")
        page.wait_for_load_state("networkidle")
        restored = _attester_options(page)

        # Instance-wide eligibility is a superset: anyone who may attest on some
        # boundary may attest on provider material, plus the instance roles.
        assert set(scoped).issubset(set(restored)), (
            f"clearing the boundary lost attesters: {sorted(set(scoped) - set(restored))}"
        )
        assert_no_csp_violations(page, during="boundary cleared")
