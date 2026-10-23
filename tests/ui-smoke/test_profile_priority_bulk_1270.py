"""#1270 — set a control's priority in place, and change many controls at once.

What only a browser proves: the priority selector saves on change with no
reload (a fetch, behind CSP), the bulk bar appears only once something is
selected, a family's "select all" takes the controls shown, the checkboxes
reach the bar's form through their `form` attribute, and the "Not set" chip
filters to the controls that need a priority. Every check reads the result
back, from the API or a reloaded page, rather than trusting what the screen
showed after the click.
"""

from __future__ import annotations

from typing import Any

import pytest

from _api_setup import _client, _name, create_tailorable_profile, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

BAR = "form#profile-bulk-form"


def _api(method: str, path: str, **kwargs) -> dict[str, Any]:
    with _client() as c:
        r = c.request(method, path, **kwargs)
        assert r.status_code in (200, 201), f"{method} {path}: {r.status_code} {r.text[:200]}"
        return r.json().get("data") or {}


def _priorities(slug: str) -> dict[str, str | None]:
    return _api("GET", f"/api/v1/profile_documents/{slug}")["control_priorities"]


def _set(slug: str, priority: str | None, *control_ids: str) -> None:
    _api("PUT", f"/api/v1/profile_documents/{slug}/controls/bulk",
         json={"control_ids": list(control_ids), "priority": priority})


@pytest.fixture
def profile():
    p = create_tailorable_profile()   # ac-1 and ac-2 selected
    try:
        _set(p["slug"], None, "ac-1", "ac-2")
        yield p
    finally:
        delete_doc("profile_documents", p["slug"])


@pytest.fixture
def resource(profile):
    r = _api("POST", "/api/v1/back_matter_resources", json={"back_matter_resource": {
        "title": _name("bulk-resource"), "href": "https://example.com/bulk.pdf",
        "media_type": "application/pdf", "globally_available": True,
        "resourceable_type": "ProfileDocument", "resourceable_id": profile["id"],
    }})
    try:
        yield r
    finally:
        with _client() as c:
            c.delete(f"/api/v1/back_matter_resources/{r['id']}")


def _open(page, slug: str) -> None:
    page.goto(f"/profile_documents/{slug}")
    page.wait_for_load_state("networkidle")
    group = page.locator("details.sparc-family-group").first
    if not group.evaluate("e => e.open"):
        group.locator("> summary").click()
    page.locator("select[aria-label='Priority for AC-1']").wait_for(state="visible", timeout=5000)


def _card(page, control: str):
    return page.locator(f".control-card:has(select[aria-label='Priority for {control}'])")


class TestInlinePriority:
    def test_set_from_not_set_saves_without_a_reload(self, authed_page, profile):
        page = authed_page
        record_csp(page)
        _open(page, profile["slug"])

        select = page.locator("select[aria-label='Priority for AC-1']")
        assert select.input_value() == "", "AC-1 should start with no priority"
        assert "sparc-priority-select--unset" in (select.get_attribute("class") or "")

        url_before = page.url
        with page.expect_response(lambda r: "/profile_controls/bulk" in r.url) as saved:
            select.select_option("P2")
        assert saved.value.status == 200, saved.value.text()
        page.get_by_role("status").filter(has_text="Saved").first.wait_for(timeout=5000)
        assert page.url == url_before, "the page navigated; the selector should save in place"

        assert _priorities(profile["slug"])["ac-1"] == "P2"
        page.reload()
        _open(page, profile["slug"])
        assert page.locator("select[aria-label='Priority for AC-1']").input_value() == "P2"
        assert_no_csp_violations(page, during="setting a priority in place")


class TestBulkBar:
    def test_select_a_family_and_set_its_priority(self, authed_page, profile):
        page = authed_page
        record_csp(page)
        _open(page, profile["slug"])

        bar = page.locator(BAR)
        assert bar.is_hidden(), "the bulk bar shows before anything is selected"
        page.get_by_label("Select all AC controls shown").check()
        bar.wait_for(state="visible", timeout=3000)
        assert "2 selected" in bar.inner_text()

        bar.locator("select[name=priority]").select_option("P1")
        with page.expect_navigation(wait_until="load"):
            bar.get_by_role("button", name="Set priority").click()

        assert _priorities(profile["slug"]) == {"ac-1": "P1", "ac-2": "P1"}
        assert_no_csp_violations(page, during="setting a family's priority from the bulk bar")

    def test_link_a_resource_to_several_controls(self, authed_page, profile, resource):
        page = authed_page
        _open(page, profile["slug"])

        _card(page, "AC-1").get_by_label("Select AC-1").check()
        _card(page, "AC-2").get_by_label("Select AC-2").check()
        bar = page.locator(BAR)
        bar.locator("select[name=resource_id]").select_option(label=resource["title"])
        with page.expect_navigation(wait_until="load"):
            bar.get_by_role("button", name="Link resource").click()

        for control in ("AC-1", "AC-2"):
            _open(page, profile["slug"])
            _card(page, control).get_by_role("link", name="Edit").click()
            page.wait_for_load_state("load")
            assert resource["title"] in page.locator("body").inner_text(), (
                f"{control}'s Edit screen does not list the resource the bulk bar linked"
            )


class TestNotSetFilter:
    def test_the_not_set_chip_shows_the_controls_without_a_priority(self, authed_page, profile):
        _set(profile["slug"], "P3", "ac-2")
        page = authed_page
        _open(page, profile["slug"])

        page.locator(".summary-chip", has_text="Not set").click()

        assert _card(page, "AC-1").is_visible(), "the control without a priority is hidden"
        assert _card(page, "AC-2").is_hidden(), "a control with a priority is still shown"


class TestEditScreen:
    def test_the_edit_screen_has_no_parameter_fields(self, authed_page, profile):
        page = authed_page
        _open(page, profile["slug"])
        _card(page, "AC-1").get_by_role("link", name="Edit").click()
        page.wait_for_load_state("load")

        assert page.get_by_label("Priority").is_visible()
        assert page.locator("input[name^='param_values']").count() == 0, (
            "the Edit screen still carries the per-parameter table"
        )
        assert page.locator("textarea[name='fields[parameter_value]']").count() == 0
