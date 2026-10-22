"""UI smoke: editing a token's limits in place (#1233).

Before, a token's endpoint and CIDR limits could be changed only by
Regenerate, which revoked the token and made every client swap credentials.
"Edit limits" on the service-account page now changes them on the same token
(owner, 2026-10-21: admin only).

This creates an account limited to SSP Read, opens Edit limits, adds
Control catalogs Read, and reads both limits back off the account page. The
rules (validation, admin-only, both directions of enforcement, audit) are
covered at the request layer: spec/requests/api_token_limits_edit_1233_spec.rb.

Selectors verified against app/views/admin/api_tokens/{edit,_endpoint_picker}.html.erb
and app/views/admin/service_accounts/{new,show}.html.erb.
"""

from __future__ import annotations

import re
import uuid

import pytest

from _api_setup import deactivate_service_account
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

NEW_ALL = "#sa_endpoints_all"
NEW_SSP_READ = "#sa_endpoints_ssp_documents_read"
EDIT_ALL = "#edit_token_endpoints_all"
EDIT_SSP_READ = "#edit_token_endpoints_ssp_documents_read"
EDIT_CATALOGS_READ = "#edit_token_endpoints_control_catalogs_read"


def test_edit_limits_changes_the_same_token(authed_page):
    page = authed_page
    record_csp(page)
    resp = page.goto("/admin/service_accounts/new")
    status = resp.status if resp else "no response"
    assert resp and resp.status < 400, f"new service account form: {status}"
    if page.locator(NEW_ALL).count() == 0:
        pytest.skip("service-account form not rendered (non-admin session or auth disabled)")
    owner = page.locator('select[name="user[owner_id]"] option:not([value=""])')
    if owner.count() == 0:
        pytest.skip("no active person to own a service account on this instance")

    name = f"phase2-ui-sa1233-{uuid.uuid4().hex[:8]}"
    created_id = None
    try:
        page.fill('input[name="user[display_name]"]', name)
        page.fill('input[name="user[email]"]', f"{name}@service.local")
        page.select_option('select[name="user[owner_id]"]', index=1)
        page.locator(NEW_ALL).uncheck()
        page.locator(NEW_SSP_READ).check()
        page.click('input[type="submit"]')

        page.wait_for_url(re.compile(r"/admin/service_accounts/\d+"), timeout=10_000)
        m = re.search(r"/admin/service_accounts/(\d+)", page.url)
        assert m, f"expected the account page, got {page.url}"
        created_id = int(m.group(1))
        tokens_before = page.locator("tr.sparc-token-limits").count()

        page.get_by_test_id("edit-token-limits").first.click()
        page.wait_for_url(re.compile(r"/api_tokens/\d+/edit"), timeout=10_000)
        assert not page.locator(EDIT_ALL).is_checked(), "the form must show the token's own limits"
        assert page.locator(EDIT_SSP_READ).is_checked(), "SSP Read was the token's limit"

        page.locator(EDIT_CATALOGS_READ).check()
        page.fill("#api_token_allowed_cidrs", "10.0.0.0/8")
        page.get_by_role("button", name="Save Limits").click()

        page.wait_for_url(re.compile(rf"/admin/service_accounts/{created_id}$"), timeout=10_000)
        limits = page.locator("tr.sparc-token-limits").first.inner_text()
        assert "System security plans (SSP): Read" in limits, limits
        assert "Control catalogs: Read" in limits, limits
        assert "10.0.0.0/8" in limits, limits
        assert page.locator("tr.sparc-token-limits").count() == tokens_before, (
            "editing limits must change the token, not issue another"
        )
        assert_no_csp_violations(page, during="editing a token's limits")
    finally:
        if created_id:
            deactivate_service_account(created_id)
