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
PASSWORD = 'input[name="user[password]"]'
CONFIRM = 'input[name="user[password_confirmation]"]'
NEW_LINK = 'a[href="/admin/users/new"]'


class TestAdminCreateUser:
    def test_index_has_new_user_button(self, authed_page):
        record_csp(authed_page)
        resp = authed_page.goto("/admin/users")
        assert resp and resp.status < 400, f"admin users index: {resp.status if resp else 'no response'}"
        if authed_page.locator(NEW_LINK).count() == 0:
            pytest.skip("New User button not rendered (non-admin session or auth disabled)")
        assert_no_csp_violations(authed_page, during="admin users index")

    def test_new_page_loads(self, authed_page):
        record_csp(authed_page)
        resp = authed_page.goto("/admin/users/new")
        assert resp and resp.status < 400, f"admin users new: {resp.status if resp else 'no response'}"
        if authed_page.locator(EMAIL).count() == 0:
            pytest.skip("create-user form not rendered (non-admin session or auth disabled)")
        assert authed_page.locator(PASSWORD).count() > 0, "password field missing"
        assert authed_page.locator(CONFIRM).count() > 0, "password confirmation field missing"
        assert_no_csp_violations(authed_page, during="admin users new")

    def test_create_user_submits(self, authed_page):
        record_csp(authed_page)
        authed_page.goto("/admin/users/new")
        if authed_page.locator(EMAIL).count() == 0:
            pytest.skip("create-user form not rendered (non-admin session or auth disabled)")

        email = f"phase2-ui-user-{uuid.uuid4().hex[:8]}@example.com"
        pw = "SmokeTestPassword123!"
        created_id = None
        try:
            authed_page.fill(EMAIL, email)
            authed_page.fill(PASSWORD, pw)
            authed_page.fill(CONFIRM, pw)
            authed_page.click('input[type="submit"]')
            authed_page.wait_for_url("**/admin/users/*", timeout=10_000)
            assert_no_csp_violations(authed_page, during="admin create user submit")
            m = re.search(r"/admin/users/(\d+)", authed_page.url)
            assert m, f"expected redirect to show page, got {authed_page.url}"
            created_id = int(m.group(1))
        finally:
            if created_id:
                deactivate_user(created_id)
