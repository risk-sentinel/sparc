"""UI smoke: admin Create User page (#755).

Admin-initiated account creation lives at ``/admin/users/new`` (self-service
registration stays disabled). This asserts the index exposes a "New User"
button, the form page loads, and submitting it creates a user and redirects to
the show page — all with zero CSP violations. The creation *contract* is
covered by tests/api/test_users.py; here we verify the UI wiring.

Selectors verified against app/views/admin/users/{index,new}.html.erb.

No Playwright check exists for the #878 last-admin guard, deliberately. The show
page hides Suspend/Deactivate when ``@user == current_user``, and the only way a
target *is* the last active admin is for it to be the signed-in admin — so the
refusal is not reachable by clicking. It guards the paths that have no UI:
InactivityCheckJob, the REST API, and the service-account controller. Driving it
from a browser would mean POSTing the route directly, and a smoke run that
guessed wrong about how many admins the seeded instance has would deactivate a
real one. It is covered at the request and model layers instead — see
spec/requests/admin/users_spec.rb and spec/models/admin_lockout_protection_spec.rb.
"""

from __future__ import annotations

import re
import uuid

import pytest

from _api_setup import deactivate_user
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

EMAIL = 'input[name="user[email]"]'
# #877 — the admin no longer chooses the first credential. SPARC generates a
# temporary and forces its replacement at first sign-in, so these fields are
# GONE from the form; their absence is now the property worth asserting.
PASSWORD = 'input[name="user[password]"]'
CONFIRM = 'input[name="user[password_confirmation]"]'
NEW_LINK = 'a[href="/admin/users/new"]'


class TestAdminCreateUser:
    def test_index_has_new_user_button(self, authed_page):
        record_csp(authed_page)
        resp = authed_page.goto("/admin/users")
        assert resp and resp.status < 400, (
            f"admin users index: {resp.status if resp else 'no response'}"
        )
        if authed_page.locator(NEW_LINK).count() == 0:
            pytest.skip("New User button not rendered (non-admin session or auth disabled)")
        assert_no_csp_violations(authed_page, during="admin users index")

    def test_new_page_loads(self, authed_page):
        record_csp(authed_page)
        resp = authed_page.goto("/admin/users/new")
        assert resp and resp.status < 400, (
            f"admin users new: {resp.status if resp else 'no response'}"
        )
        if authed_page.locator(EMAIL).count() == 0:
            pytest.skip("create-user form not rendered (non-admin session or auth disabled)")
        # #877 — inverted deliberately. An admin-chosen password is one the
        # admin knows and, before #877, one the user was never made to replace.
        assert authed_page.locator(PASSWORD).count() == 0, (
            "password field is still on the form — the admin must not choose the credential (#877)"
        )
        assert authed_page.locator(CONFIRM).count() == 0, (
            "password confirmation field is still on the form (#877)"
        )
        assert "temporary password will be generated" in authed_page.content().lower(), (
            "the form should tell the admin a temporary will be issued"
        )
        assert_no_csp_violations(authed_page, during="admin users new")

    def test_create_user_submits(self, authed_page):
        record_csp(authed_page)
        authed_page.goto("/admin/users/new")
        if authed_page.locator(EMAIL).count() == 0:
            pytest.skip("create-user form not rendered (non-admin session or auth disabled)")

        email = f"phase2-ui-user-{uuid.uuid4().hex[:8]}@example.com"
        created_id = None
        try:
            authed_page.fill(EMAIL, email)
            # No password to fill — #877 issues one.
            authed_page.click('input[type="submit"]')
            # Redirect lands on the show page /admin/users/<id> — require digits
            # so we don't match the /admin/users/new we started on.
            authed_page.wait_for_url(re.compile(r"/admin/users/\d+"), timeout=10_000)
            assert_no_csp_violations(authed_page, during="admin create user submit")
            m = re.search(r"/admin/users/(\d+)", authed_page.url)
            assert m, f"expected redirect to show page, got {authed_page.url}"
            created_id = int(m.group(1))

            # #877 — the handover. The temporary is shown on this page load and
            # nowhere else (only its bcrypt digest is stored), so if the panel
            # fails to render, the admin cannot onboard the user at all and the
            # account is stranded. That makes its presence, and a non-empty
            # value in the field, the property that actually matters here.
            panel = authed_page.locator('input[aria-label="Temporary password"]')
            assert panel.count() == 1, (
                "the created user's page must show the one-time temporary "
                "password — without it there is no way to hand the credential over (#877)"
            )
            assert panel.input_value().strip(), "temporary password field rendered empty (#877)"
            assert "copy it now" in authed_page.content().lower(), (
                "the temporary should be presented as copy-once, not as a durable credential"
            )
        finally:
            if created_id:
                deactivate_user(created_id)
