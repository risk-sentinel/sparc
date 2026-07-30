"""UI smoke: admin Create User page (#755).

Admin-initiated account creation lives at ``/admin/users/new`` (self-service
registration stays disabled). This asserts the index exposes a "New User"
button, the form page loads, and submitting it creates a user and redirects to
the show page — all with zero CSP violations. The creation *contract* is
covered by tests/api/test_users.py; here we verify the UI wiring.

Selectors verified against app/views/admin/users/{index,new}.html.erb.
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
        finally:
            if created_id:
                deactivate_user(created_id)
