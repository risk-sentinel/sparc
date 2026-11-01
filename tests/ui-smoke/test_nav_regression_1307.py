"""Navigation regression checks for the 1.18.0-rf shell (#1307).

Posture-gated ("nav_shell"). End to end, the way a person uses it:

  * Nothing reachable before is lost. Every link the classic header and sidebar
    offered on v1.17.5 (nav_inventory.json) is found on the shell's home page or
    a boundary's page and opened by CLICKING it, opening the menu that holds it
    first, for the administrator and for a member. Each lands on its page,
    signed in, with zero CSP violations. Skipped: external links, Sign Out (it
    would end the suite's session), links that open a new tab, the user guides
    (covered by the help checks), and links the member's screens refuse
    (nav_inventory_paths.REMOVED).
  * Switching boundary moves the lists and their counts: two boundaries, each
    with its own SSP; inside each, the SSPs tab counts one and lists only that
    boundary's plan.
  * At 390px (a phone) every tab can be scrolled into view and opened, and each
    header menu opens inside the screen.

The request spec spec/requests/shell_nav_inventory_spec.rb checks the same
inventory against the rendered HTML for every posture; this proves it live.

Requires SPARC_SMOKE_SA_TOKEN (SPARC_SMOKE_USER_TOKEN for the member check).
"""

from __future__ import annotations

from urllib.parse import urlparse

import pytest
from playwright.sync_api import expect

from _api_setup import create_boundary, create_ssp, delete_doc
from helpers import SHELL_HEADER, assert_no_csp_violations, nav_shell_on, record_csp
from nav_inventory_paths import POSTURES, REMOVED, condition_for, normalize_path

pytestmark = [pytest.mark.authenticated, pytest.mark.posture("nav_shell")]

# Tags every link and form on the page with data-navreg-id and returns each
# one's href, whether it opens a new tab, and whether it sits in the shell's
# navigation (header or tab bar), which is preferred when a path appears twice.
COLLECT_JS = r"""
() => [...document.querySelectorAll("a[href], form[action]")].map((el, i) => {
  el.setAttribute("data-navreg-id", String(i));
  const href = el.tagName === "FORM" ? el.getAttribute("action") : el.getAttribute("href");
  return { id: i, href, blank: el.getAttribute("target") === "_blank",
           nav: !!el.closest("[data-testid=shell-header], [data-testid=shell-bar]") };
})
"""

# Opens, outermost first, every closed dropdown or switcher panel between the
# document and one tagged element; returns how many toggles were tagged.
REVEAL_JS = r"""
(id) => {
  const el = document.querySelector(`[data-navreg-id="${id}"]`);
  const chain = [];
  for (let n = el.parentElement; n; n = n.parentElement) {
    if (n.classList.contains("dropdown-menu")) {
      const t = n.parentElement.querySelector(":scope > .dropdown-toggle");
      if (t) chain.unshift(t);
    }
    if (n.matches("[data-testid=shell-switcher-panel]")) {
      chain.unshift(document.querySelector("[data-testid=shell-switcher]"));
    }
  }
  chain.forEach((t, k) => t.setAttribute("data-navreg-open", String(k)));
  return chain.length;
}
"""


def _open(page, path):
    resp = page.goto(path)
    assert resp is not None and resp.ok, f"{path} returned {resp and resp.status}"
    page.wait_for_load_state("networkidle")
    assert "/login" not in page.url, f"the smoke session is not signed in: {page.url}"
    if not nav_shell_on(page):
        pytest.skip("SPARC_NAV_SHELL is off on this stack")


def _first_boundary_path(page):
    href = page.locator("a[href^='/authorization_boundaries/']").evaluate_all(
        "els => els.map(e => e.getAttribute('href'))"
        ".find(h => /^\\/authorization_boundaries\\/[^/?#]+$/.test(h))"
    )
    return href


def _pages(page):
    _open(page, "/")
    boundary = _first_boundary_path(page)
    return ["/"] + ([boundary] if boundary else []), boundary


def _find(page, pages, path):
    """(page, element id) of a link to `path`, preferring the shell's navigation."""
    best = None
    for where in pages:
        _open(page, where)
        for link in page.evaluate(COLLECT_JS):
            if not link["href"] or link["href"].startswith("#") or link["blank"]:
                continue
            if normalize_path(link["href"]) == path:
                if link["nav"]:
                    return where, link["id"], link["href"]
                best = best or (where, link["id"], link["href"])
    return best


def _click_through(page, posture):
    record_csp(page)
    pages, boundary = _pages(page)
    recorded = {e["path"] for e in POSTURES[posture]}
    wanted = sorted(
        p
        for p in recorded - REMOVED.get(posture, set())
        if condition_for(p) not in ("resources", "fido2")
        and not (condition_for(p) == "boundary" and boundary is None)
        and p not in ("/logout", "/help/:guide")
    )
    assert wanted, f"{posture}: nothing recorded to check"

    failures = []
    for path in wanted:
        found = _find(page, pages, path)
        if found is None:
            failures.append(f"{path}: no link to it on {', '.join(pages)}")
            continue
        where, element, href = found
        _open(page, where)
        page.evaluate(COLLECT_JS)
        for k in range(page.evaluate(REVEAL_JS, element)):
            toggle = page.locator(f'[data-navreg-open="{k}"]')
            if toggle.is_visible():
                toggle.click()
        link = page.locator(f'[data-navreg-id="{element}"]')
        if not link.is_visible():
            link.scroll_into_view_if_needed()
        want = urlparse(href).path
        link.click()
        try:
            page.wait_for_url(lambda u, w=want: urlparse(u).path == w, timeout=15_000)
        except Exception:  # noqa: BLE001 - reported with the page it reached
            failures.append(f"{path}: clicked on {where}, landed on {page.url}")
            continue
        page.wait_for_load_state("networkidle")
        if "/login" in page.url:
            failures.append(f"{path}: bounced to sign-in")
        assert_no_csp_violations(page, during=f"{posture}: {path}")
    assert not failures, f"{posture}: links that did not open:\n  " + "\n  ".join(failures)


def test_every_recorded_link_opens_by_clicking_for_the_administrator(authed_page):
    _click_through(authed_page, "signed_in_admin")


def test_every_recorded_link_opens_by_clicking_for_a_member(user_authed_page):
    _click_through(user_authed_page, "signed_in_member")


@pytest.fixture
def two_boundaries():
    made = []
    try:
        for _ in range(2):
            boundary = create_boundary()
            made.append((boundary, create_ssp(boundary["id"])))
        yield made
    finally:
        for boundary, ssp in made:
            delete_doc("ssp_documents", ssp["slug"])
            delete_doc("authorization_boundaries", boundary["slug"])


def test_switching_boundary_moves_the_lists_and_counts(authed_page, two_boundaries):
    page = authed_page
    record_csp(page)
    for boundary, ssp in two_boundaries:
        _open(page, f"/authorization_boundaries/{boundary['slug']}")
        tab = page.locator("[data-testid=shell-bar] [data-testid=shell-tab][data-tab=ssp]")
        expect(tab).to_be_visible()
        expect(tab.locator(".sparc-counter")).to_have_text("1")
        tab.click()
        page.wait_for_url(f"**/ssp_documents?authorization_boundary_id={boundary['id']}*")
        others = [s["name"] for b, s in two_boundaries if b is not boundary]
        body = page.locator("main, body > .container").first
        expect(body).to_contain_text(ssp["name"])
        for other in others:
            expect(body).not_to_contain_text(other)
        assert_no_csp_violations(page, during=f"the SSPs tab inside {boundary['name']}")


def test_on_a_phone_every_tab_and_menu_is_reachable(authed_page):
    page = authed_page
    page.set_viewport_size({"width": 390, "height": 844})
    record_csp(page)
    _open(page, "/")

    tabs = page.locator("[data-testid=shell-bar] [data-testid=shell-tab]")
    hrefs = tabs.evaluate_all("els => els.map(e => e.getAttribute('href'))")
    assert hrefs, "no tabs on the phone"
    for href in hrefs:
        _open(page, "/")
        tab = page.locator(f"[data-testid=shell-bar] [data-testid=shell-tab][href='{href}']")
        tab.scroll_into_view_if_needed()
        expect(tab).to_be_in_viewport()
        tab.click()
        want = urlparse(href).path
        page.wait_for_url(lambda u, w=want: urlparse(u).path == w, timeout=15_000)

    _open(page, "/")
    for menu in ("shell-create", "shell-library", "shell-help"):
        toggle = page.locator(f"{SHELL_HEADER} [data-testid={menu}] > .dropdown-toggle")
        if toggle.count() == 0:
            continue
        toggle.click()
        box = page.locator(f"[data-testid={menu}] .dropdown-menu").bounding_box()
        assert box and box["x"] >= 0 and box["x"] + box["width"] <= 390 + 1, (
            f"{menu} opens off-screen: {box}"
        )
        toggle.click()
    overflow = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
    assert overflow <= 0, f"the phone page scrolls sideways by {overflow}px"
    assert_no_csp_violations(page, during="tabs and menus on a phone")
