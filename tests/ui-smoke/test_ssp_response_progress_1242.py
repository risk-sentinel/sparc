"""#1242 — an SSP counts the responses its baseline requires, not its controls.

What only a browser proves: the header figure and every control's badge render
on a real seeded SSP, agree with the API's `response_progress`, carry no CSP
violation, and move when an author writes a response through the control's
Edit form (#1312: the one place an item is answered) and the page
reloads. The counts themselves are rspec's (derived from the
profile, never pinned); this checks the screen reads the same definition.
"""

from __future__ import annotations

import re

import pytest

from _api_setup import _client
from helpers import assert_no_csp_violations, record_csp, show_hrefs

FIGURE = "[data-testid='ssp-response-progress']"
BADGE = "[data-testid='control-response-badge']"


def _api_progress(slug: str) -> dict:
    with _client() as c:
        r = c.get(f"/api/v1/ssp_documents/{slug}")
        assert r.status_code == 200, r.text[:200]
        return r.json()["data"]["response_progress"]


def _figure(page) -> dict[str, int]:
    figure = page.locator(FIGURE)
    figure.wait_for(state="attached", timeout=10000)
    return {k: int(figure.get_attribute(f"data-{k}")) for k in ("required", "done", "owed")}


def _open_all(page) -> None:
    page.evaluate(
        "() => document.querySelectorAll('details.sparc-family-group, details.card-details')"
        "        .forEach(d => { d.open = true })"
    )


def _seeded_ssp(page) -> tuple[str, str]:
    """The first seeded SSP whose baseline requires responses: (href, slug)."""
    for href in show_hrefs(page, "/ssp_documents", "/ssp_documents"):
        page.goto(href)
        page.wait_for_load_state("networkidle")
        if page.locator(FIGURE).count() and _figure(page)["required"] > 0:
            return href, href.rstrip("/").rsplit("/", 1)[-1]
    pytest.skip("no seeded SSP requires any response — run the demo seed")


def test_header_and_badges_agree_with_the_api(authed_page):
    page = authed_page
    record_csp(page)
    _href, slug = _seeded_ssp(page)

    figure = _figure(page)
    api = _api_progress(slug)
    assert figure == {k: api[k] for k in ("required", "done", "owed")}, (figure, api)
    assert figure["done"] + figure["owed"] == figure["required"]

    # A badge on every control card, single-response enhancements included.
    cards = page.locator(".control-card").count()
    assert cards > 0
    assert page.locator(BADGE).count() == cards, "a control card has no response badge"
    # text_content, not inner_text: the badges sit in collapsed family groups,
    # and inner_text of hidden text is "".
    texts = page.locator(BADGE).all_text_contents()
    assert all(re.fullmatch(r"\d+/\d+ done|Not in baseline", t.strip()) for t in texts), texts
    assert_no_csp_violations(page, during="reading an SSP's response progress")


def test_writing_a_response_moves_the_counts(authed_page):
    page = authed_page
    href, slug = _seeded_ssp(page)
    before = _figure(page)
    if before["owed"] == 0:
        pytest.skip("the seeded SSP owes no response to write")

    _open_all(page)
    row = page.locator("tr[data-statement-id]:has([data-response-state='missing'])").first
    row.wait_for(state="attached", timeout=5000)
    statement_id = row.get_attribute("id").removeprefix("stmt-")
    card = row.locator("xpath=ancestor::div[contains(@class,'control-card')]").first
    card.locator("[id^='edit-btn-']").first.click()
    prose = card.locator(f"textarea[name='statements[{statement_id}][implementation_prose]']")
    prose.wait_for(state="visible", timeout=5000)
    prose.fill("ui-smoke #1242 response")
    try:
        with page.expect_navigation(wait_until="load"):
            card.locator("input[type='submit'][value='Save Changes']").first.click()

        after = _figure(page)
        assert after["done"] == before["done"] + 1, (before, after)
        assert after["owed"] == before["owed"] - 1, (before, after)
        assert after["required"] == before["required"]
        assert _api_progress(slug)["done"] == after["done"]
    finally:
        with _client() as c:
            c.patch(f"/api/v1/ssp_control_statements/{statement_id}",
                    json={"ssp_control_statement": {"implementation_prose": ""}})
