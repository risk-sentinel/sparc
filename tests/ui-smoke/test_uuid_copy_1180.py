"""#1180 — the UUID badge is copyable, in a real browser.

A copy button is the shape of defect that RENDERS PERFECTLY and only fails when
pressed: the enforced CSP rejects an inline handler at click time, and
`navigator.clipboard` is undefined outside a secure context. Neither is visible
in a screenshot or an ERB diff, so the interaction is exercised here.

What is asserted:
  - the badge renders on the admin organization screen, for the organization
    itself and for every boundary row
  - pressing it actually copies, and copies the identifier that is DISPLAYED
    (chromium reads the clipboard back; every browser asserts the success state,
    which the controller only sets when the write resolved)
  - zero CSP violations DURING the click, not merely on render
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, first_show_href, record_csp

ORGS = "/admin/organizations"
UUID_BADGE = ".sparc-uuid"


def _org_page(page):
    href = first_show_href(page, ORGS, ORGS)
    if not href:
        pytest.skip("no organization seeded — run the demo seed")
    page.goto(href)
    page.wait_for_load_state("networkidle")
    return href


class TestUuidBadgeRenders:
    def test_organization_and_boundaries_expose_a_copyable_uuid(self, authed_page):
        record_csp(authed_page)
        _org_page(authed_page)

        badges = authed_page.locator(UUID_BADGE)
        assert badges.count() >= 1, "no copyable UUID badge on the organization screen"

        # The header badge is the organization's own, and says so.
        header = authed_page.locator(f"h1 ~ div {UUID_BADGE}, .d-flex {UUID_BADGE}").first
        assert "UUID" in header.inner_text(), "header badge lost its UUID label"

        # Every badge must carry a value to copy, and it must match what is shown.
        for i in range(badges.count()):
            badge = badges.nth(i)
            value = badge.get_attribute("data-clipboard-text-value")
            assert value, f"badge {i} has no clipboard value"
            shown = badge.locator(".sparc-uuid__value").inner_text().strip()
            assert shown == value, (
                f"badge {i} displays {shown!r} but would copy {value!r}"
            )

        # Each boundary row carries one, since that is the identifier the
        # federation key grammar keys on (#1180).
        rows = authed_page.locator("table tbody tr")
        for i in range(rows.count()):
            row = rows.nth(i)
            if row.locator("td[colspan]").count():
                continue  # empty-state row
            if row.locator("a[href*='/authorization_boundaries/']").count() == 0:
                continue  # members table
            assert row.locator(UUID_BADGE).count() == 1, (
                f"boundary row {i} has no UUID badge"
            )

        assert_no_csp_violations(authed_page, during="organization screen render")


class TestUuidBadgeCopies:
    def test_clicking_copies_the_identifier(self, authed_page, browser_name):
        record_csp(authed_page)
        _org_page(authed_page)

        badge = authed_page.locator(UUID_BADGE).first
        expected = badge.get_attribute("data-clipboard-text-value")
        assert expected, "first badge has no clipboard value"

        # Reading the clipboard back needs a permission only chromium exposes.
        # The local gate IS chromium, so the strongest assertion runs where it
        # can, and the weaker-but-real one runs everywhere.
        can_read = browser_name == "chromium"
        if can_read:
            authed_page.context.grant_permissions(
                ["clipboard-read", "clipboard-write"]
            )

        badge.locator("button").click()

        # The controller adds this ONLY when the write resolved, so it is a real
        # assertion of success and not of having clicked.
        copied = authed_page.locator(f"{UUID_BADGE}.sparc-uuid--copied")
        copied.first.wait_for(state="attached", timeout=3000)
        assert authed_page.locator(f"{UUID_BADGE}.sparc-uuid--failed").count() == 0, (
            "the copy reported failure"
        )

        if can_read:
            got = authed_page.evaluate("navigator.clipboard.readText()")
            assert got == expected, (
                f"clipboard holds {got!r}, expected the displayed UUID {expected!r}"
            )

        # The click is where an inline handler would be rejected, so this is the
        # assertion that matters most.
        assert_no_csp_violations(authed_page, during="UUID copy click")

    def test_confirmation_reverts(self, authed_page):
        """The tick is transient — a badge stuck in the copied state would read
        as "this one is copied" on a page showing several."""
        record_csp(authed_page)
        _org_page(authed_page)

        badge = authed_page.locator(UUID_BADGE).first
        badge.locator("button").click()
        authed_page.locator(f"{UUID_BADGE}.sparc-uuid--copied").first.wait_for(
            state="attached", timeout=3000
        )

        # confirmFor defaults to 1600ms; allow margin without making the test slow.
        authed_page.wait_for_timeout(2600)
        assert authed_page.locator(f"{UUID_BADGE}.sparc-uuid--copied").count() == 0, (
            "the copied confirmation never reverted"
        )
        assert_no_csp_violations(authed_page, during="UUID copy confirmation revert")
