"""UI smoke: Settings show pages use the shared page header (#1346).

The 1.18.0-rf layout pivot moved the Settings screens into the new frame but
kept their hand-built header rows, so buttons drifted again: on a user's page,
Edit, Suspend and Deactivate were small `sparc-action` buttons, while Issue
temporary password and Email reset link were Bootstrap `btn` buttons, taller
and wrapping.

For each Settings show page this opens the first record from its list, at
1280px in Chrome, and checks that the header is the shared one and that every
action button in it is the same height. The source-level rules (no Bootstrap
`btn`, every Settings show page renders the shared header) are
spec/views/button_schema_1346_spec.rb.

Selectors verified against app/views/shared/_page_header.html.erb.
"""

from __future__ import annotations

import re

import pytest
from playwright.sync_api import expect

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

SETTINGS = {
    "users": r"^/admin/users/\d+$",
    "service_accounts": r"^/admin/service_accounts/\d+$",
    "organizations": r"^/admin/organizations/[^/]+$",
    "roles": r"^/admin/roles/\d+$",
    "authorization_boundaries": r"^/admin/authorization_boundaries/[^/]+$",
    "audit_logs": r"^/admin/audit_logs/\d+$",
}

HEIGHTS = """header => [...header.querySelectorAll(
  '.sparc-page-header__actions > a, .sparc-page-header__actions > form > button'
)].filter(el => el.offsetParent !== null)
 .map(el => [el.textContent.trim(), Math.round(el.getBoundingClientRect().height)])"""


def _first_record(page, kind: str) -> str | None:
    page.goto(f"/admin/{kind}")
    page.wait_for_load_state("domcontentloaded")
    pattern = re.compile(SETTINGS[kind])
    hrefs = page.locator("main a[href]").evaluate_all("els => els.map(e => e.getAttribute('href'))")
    for href in hrefs:
        path = (href or "").split("?")[0]
        if pattern.match(path) and not path.endswith("/new"):
            return path
    return None


@pytest.mark.parametrize("kind", list(SETTINGS))
def test_settings_show_page_has_the_shared_header(authed_page, kind):
    page = authed_page
    record_csp(page)
    page.set_viewport_size({"width": 1280, "height": 900})
    path = _first_record(page, kind)
    if path is None:
        pytest.skip(f"no {kind} record listed on this instance")

    page.goto(path)
    page.wait_for_load_state("domcontentloaded")
    header = page.get_by_test_id("page-header")
    expect(header).to_be_visible()

    heights = header.evaluate(HEIGHTS)
    assert heights, f"{path}: the header shows no actions"
    assert len({h for _, h in heights}) == 1, f"{path}: header buttons differ in height: {heights}"
    assert_no_csp_violations(page, during=f"the {kind} Settings page")
