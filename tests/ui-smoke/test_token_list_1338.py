"""UI smoke: the token list never scrolls sideways (#1338).

At 1280px a service account's API Tokens table ran past its card, and the
user page's table scrolled sideways inside its card. Both pages now list tokens
from one partial, each token one entry whose facts wrap.

This creates a service account limited to SSP Read, then opens its service
account page and its user page (the user page shows any account) at 1280px
and at phone width. On each it checks that the page doesn't scroll
sideways, that no element of a card runs past the card, and that the token's
facts and buttons are there.

Selectors verified against app/views/admin/api_tokens/_token_list.html.erb,
app/views/admin/service_accounts/{new,show}.html.erb and
app/views/admin/users/show.html.erb.
"""

from __future__ import annotations

import re
import uuid

import pytest
from playwright.sync_api import expect

from _api_setup import deactivate_service_account
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

NEW_ALL = "#sa_endpoints_all"
NEW_SSP_READ = "#sa_endpoints_ssp_documents_read"

# Anything inside the token card whose right edge passes the card's, and how far
# the page scrolls sideways. (Other cards' tables are the next update's, #1340.)
OVERFLOW_JS = """() => {
  const out = [];
  const list = document.querySelector('[data-testid=api-token-list]');
  for (const card of [list && list.closest('.card')].filter(Boolean)) {
    const edge = card.getBoundingClientRect().right;
    for (const el of card.querySelectorAll('*')) {
      const r = el.getBoundingClientRect();
      if (r.width > 0 && r.right > edge + 1) {
        out.push(`${el.tagName.toLowerCase()}.${el.className}: ${Math.round(r.right - edge)}px`);
      }
    }
  }
  const sideways = document.documentElement.scrollWidth - window.innerWidth;
  return { sideways, past: out.slice(0, 5) };
}"""


def _assert_fits(page, where):
    result = page.evaluate(OVERFLOW_JS)
    assert result["sideways"] <= 0, f"{where}: the page scrolls sideways by {result['sideways']}px"
    assert not result["past"], f"{where}: runs past its card: {result['past']}"


def test_token_list_fits_without_sideways_scroll(authed_page):
    page = authed_page
    record_csp(page)
    resp = page.goto("/admin/service_accounts/new")
    status = resp.status if resp else "no response"
    assert resp and resp.status < 400, f"new service account form: {status}"
    if page.locator(NEW_ALL).count() == 0:
        pytest.skip("service-account form not rendered (non-admin session or auth disabled)")
    if page.locator('select[name="user[owner_id]"] option:not([value=""])').count() == 0:
        pytest.skip("no active person to own a service account on this instance")

    name = f"phase2-ui-sa1338-{uuid.uuid4().hex[:8]}"
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

        pages = {
            "service account page": f"/admin/service_accounts/{created_id}",
            "user page": f"/admin/users/{created_id}",
        }
        for width, height in ((1280, 900), (390, 844)):
            page.set_viewport_size({"width": width, "height": height})
            for label, path in pages.items():
                page.goto(path)
                page.wait_for_load_state("domcontentloaded")
                entry = page.get_by_test_id("api-token").first
                expect(entry).to_be_visible()
                facts = page.get_by_test_id("token-limits").first.inner_text()
                assert "System security plans (SSP): Read" in facts, f"{label}: {facts}"
                assert "Any address" in facts, f"{label}: {facts}"
                expect(entry.get_by_role("button", name="Reissue")).to_be_visible()
                _assert_fits(page, f"{label} at {width}px")
        assert_no_csp_violations(page, during="the token list on both pages")
    finally:
        page.set_viewport_size({"width": 1280, "height": 900})
        if created_id:
            deactivate_service_account(created_id)
