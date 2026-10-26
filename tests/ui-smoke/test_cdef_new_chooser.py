"""UI smoke: the new-CDEF screen shows one way in at a time (v1.17.3).

Upload, Author and From a published profile are independent, each with its own
form. A chooser (tabs, cdef_new_chooser_controller.js) shows only the chosen
one, a choice can be linked directly (#author), and the arrow keys move between
choices. Checked in Chrome with zero CSP violations.

Selectors verified against app/views/cdef_documents/new.html.erb
(`[role='tab'][data-choice]`, `[role='tabpanel'][data-choice]`).
"""

from __future__ import annotations

import pytest
from playwright.sync_api import expect

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

NEW = "/cdef_documents/new"
CHOICES = ("upload", "author", "profile")


def _tab(page, key):
    return page.locator(f"[role='tab'][data-choice='{key}']")


def _panel(page, key):
    return page.locator(f"[role='tabpanel'][data-choice='{key}']")


def _assert_only(page, shown):
    for key in CHOICES:
        if key == shown:
            expect(_panel(page, key)).to_be_visible()
            expect(_tab(page, key)).to_have_attribute("aria-selected", "true")
        else:
            expect(_panel(page, key)).to_be_hidden()
            expect(_tab(page, key)).to_have_attribute("aria-selected", "false")


def test_one_form_at_a_time_and_each_choice_switches(authed_page, base_url):
    page = authed_page
    record_csp(page)
    page.goto(f"{base_url}{NEW}")
    page.wait_for_load_state("networkidle")

    expect(page.get_by_role("tablist")).to_be_visible()
    _assert_only(page, "upload")

    for key in ("author", "profile", "upload"):
        _tab(page, key).click()
        _assert_only(page, key)
        assert page.url.endswith(f"#{key}"), f"choosing {key} did not update the link: {page.url}"

    assert_no_csp_violations(page, during="switching between the new-CDEF choices")


def test_a_choice_can_be_linked_directly(authed_page, base_url):
    page = authed_page
    record_csp(page)
    page.goto(f"{base_url}{NEW}#author")
    page.wait_for_load_state("networkidle")

    _assert_only(page, "author")
    expect(page.locator("[data-testid='author-cdef-submit']")).to_be_visible()
    assert_no_csp_violations(page, during="opening the Author choice by its link")


def test_arrow_keys_move_between_choices(authed_page, base_url):
    page = authed_page
    page.goto(f"{base_url}{NEW}")
    page.wait_for_load_state("networkidle")

    _tab(page, "upload").focus()
    page.keyboard.press("ArrowRight")
    _assert_only(page, "author")
    expect(_tab(page, "author")).to_be_focused()
    page.keyboard.press("End")
    _assert_only(page, "profile")
    page.keyboard.press("ArrowRight")  # wraps to the first
    _assert_only(page, "upload")
