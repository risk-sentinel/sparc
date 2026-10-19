"""UI smoke: the API token endpoint picker (#1176).

The free-text "Allowed Endpoints" box on the new-service-account form became a
list: one row per API resource group, Read and Write per row, and an "All
endpoints" row (owner, 2026-10-17/18). "All endpoints" and the per-resource
boxes are alternatives, which a Stimulus controller enforces in the browser.

These checks drive that behaviour in Chrome, then create an account limited to
one resource's Read and read the limit back off its page. The rules themselves
(Read vs Write per route, refusal of an unticked form, required expiry) are
covered at the request layer: spec/requests/admin/api_token_lifetime_1176_spec.rb.

Selectors verified against app/views/admin/api_tokens/_endpoint_picker.html.erb
and app/views/admin/service_accounts/{new,show}.html.erb.
"""

from __future__ import annotations

import re
import uuid

import pytest

from _api_setup import deactivate_service_account
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

PICKER = "#sa_endpoints"
ALL = "#sa_endpoints_all"
SSP_READ = "#sa_endpoints_ssp_documents_read"
SSP_WRITE = "#sa_endpoints_ssp_documents_write"
# A read-only group offers no Write box at all.
OSCAL_WRITE = "#sa_endpoints_oscal_write"


def _open_form(page) -> None:
    record_csp(page)
    resp = page.goto("/admin/service_accounts/new")
    assert resp and resp.status < 400, (
        f"new service account form: {resp.status if resp else 'no response'}"
    )
    if page.locator(PICKER).count() == 0:
        pytest.skip("service-account form not rendered (non-admin session or auth disabled)")


class TestEndpointPicker:
    def test_starts_on_all_endpoints_with_the_rest_disabled(self, authed_page):
        _open_form(authed_page)

        assert authed_page.locator(ALL).is_checked(), "a fresh form starts on All endpoints"
        assert authed_page.locator(SSP_READ).is_disabled(), (
            "with All endpoints ticked, the per-resource boxes must be disabled"
        )
        assert authed_page.locator(OSCAL_WRITE).count() == 0, (
            "OSCAL translations only read, so it must offer no Write box"
        )
        rows = authed_page.locator(f"{PICKER} tbody tr").count()
        assert rows > 20, f"expected one row per API resource group, found {rows}"
        assert_no_csp_violations(authed_page, during="service account form")

    def test_all_and_the_resource_boxes_are_alternatives(self, authed_page):
        _open_form(authed_page)

        authed_page.locator(ALL).uncheck()
        assert authed_page.locator(SSP_READ).is_enabled(), (
            "unticking All endpoints must hand the choice to the resource boxes"
        )
        authed_page.locator(SSP_READ).check()
        authed_page.locator(SSP_WRITE).check()

        authed_page.locator(ALL).check()
        assert not authed_page.locator(SSP_READ).is_checked(), (
            "ticking All endpoints must clear the per-resource choices"
        )
        assert authed_page.locator(SSP_WRITE).is_disabled()
        assert_no_csp_violations(authed_page, during="endpoint picker toggling")

    def test_a_read_only_account_shows_its_limit(self, authed_page):
        _open_form(authed_page)
        owner = authed_page.locator('select[name="user[owner_id]"] option:not([value=""])')
        if owner.count() == 0:
            pytest.skip("no active person to own a service account on this instance")

        name = f"phase2-ui-sa-{uuid.uuid4().hex[:8]}"
        created_id = None
        try:
            authed_page.fill('input[name="user[display_name]"]', name)
            authed_page.fill('input[name="user[email]"]', f"{name}@service.local")
            authed_page.select_option('select[name="user[owner_id]"]', index=1)
            authed_page.locator(ALL).uncheck()
            authed_page.locator(SSP_READ).check()
            authed_page.click('input[type="submit"]')

            authed_page.wait_for_url(re.compile(r"/admin/service_accounts/\d+"), timeout=10_000)
            m = re.search(r"/admin/service_accounts/(\d+)", authed_page.url)
            assert m, f"expected the account page, got {authed_page.url}"
            created_id = int(m.group(1))

            limits = authed_page.locator("tr.sparc-token-limits").first.inner_text()
            assert "System security plans (SSP): Read" in limits, limits
            assert "Write" not in limits, f"only Read was ticked: {limits}"
            assert authed_page.get_by_role("button", name="Renew").count() == 1
            assert authed_page.get_by_role("button", name="Reissue").count() == 1
            assert_no_csp_violations(authed_page, during="service account with a Read limit")
        finally:
            if created_id:
                deactivate_service_account(created_id)
