"""Navigation inventory in a real browser (1.18.0-rf phase 0, #1286 / #1307).

`nav_inventory.json` records every link the header and sidebar offered on
v1.17.5, per viewer, before the navigation refactor. The request spec
(spec/requests/nav_inventory_spec.rb) checks the rendered HTML against it; this
module checks a live stack the way a user meets it:

  * the admin is offered exactly the recorded admin navigation;
  * the non-admin is offered nothing outside the recorded signed-in navigation,
    and every recorded member link;
  * every internal link opens by CLICKING it, through the menus that hold it,
    lands on its page signed in, and trips no CSP violation.

Entries are normalised exactly as spec/support/nav_inventory.rb does (the two
must agree; the rules are documented there). Entries carrying `when` depend on
the deployment: "resources" (SPARC_RESOURCES) is ignored here, "boundary" is
required when the viewer can see a boundary, "fido2" when the stack offers it.

Requires SPARC_SMOKE_SA_TOKEN (and SPARC_SMOKE_USER_TOKEN for the member check).
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import parse_qsl, urlparse

import pytest

from helpers import assert_no_csp_violations, record_csp, require_classic_header

pytestmark = [pytest.mark.authenticated, pytest.mark.posture("classic_nav")]


@pytest.fixture(autouse=True)
def _classic_header(request):
    """These check the classic navbar and sidebar (SPARC_NAV_SHELL off)."""
    name = "user_authed_page" if "user_authed_page" in request.fixturenames else "authed_page"
    require_classic_header(request.getfixturevalue(name))


POSTURES = json.loads((Path(__file__).parent / "nav_inventory.json").read_text())["postures"]
BOUNDARY = ":boundary"
GUIDE_LABEL = "(each user guide)"
SIGNED_IN = ("signed_in_member", "signed_in_admin")

# Mirrors NavInventory.extract: header links and forms, then sidebar links,
# each with its menu and its decoration-free label. Each element is tagged with
# data-navinv-id so a test can find it again to click it.
EXTRACT_JS = r"""
() => {
  const DECOR = ".badge, .sparc-dropdown-icon, .sparc-sidebar-dot, .sparc-fs-065";
  const squish = (s) => (s || "").replace(/\s+/g, " ").trim();
  const clean = (node) => {
    if (!node) return "";
    const copy = node.cloneNode(true);
    if (copy.querySelectorAll) copy.querySelectorAll(DECOR).forEach((n) => n.remove());
    const text = copy.tagName === "INPUT" ? copy.value : copy.textContent;
    return squish((text || "").replace(/[\p{So}\p{Sm}️]/gu, ""));
  };
  const out = [];
  const add = (el, menu, label, href, sidebar) => {
    el.setAttribute("data-navinv-id", String(out.length));
    out.push({ id: out.length, menu, label, href, sidebar,
               blank: el.getAttribute("target") === "_blank" });
  };
  document.querySelectorAll("nav.navbar a[href], nav.navbar form[action]").forEach((el) => {
    const isForm = el.tagName === "FORM";
    const href = isForm ? el.getAttribute("action") : el.getAttribute("href");
    if (!href || href.startsWith("#")) return;
    let menu = "Header";
    const dd = el.closest(".dropdown-menu");
    const toggle = dd && dd.parentElement.querySelector(":scope > .dropdown-toggle");
    if (toggle) menu = toggle.classList.contains("sparc-nav-user") ? "Account" : clean(toggle);
    let label = isForm ? clean(el.querySelector("button, input[type=submit]"))
                       : (clean(el) || squish(el.getAttribute("aria-label")));
    const boundaryLink = /^\/authorization_boundaries\/[^/?]+/.test(href);
    if (menu === "Enterprise" && boundaryLink) label = ":boundary";
    add(el, menu, label, href, false);
  });
  document.querySelectorAll("nav.sparc-sidebar a[href]").forEach((el) => {
    const href = el.getAttribute("href");
    if (el.closest(".sparc-sidebar-boundary")) {
      const leaf = clean(el) || squish(el.getAttribute("aria-label"));
      if (el.classList.contains("sparc-sidebar-boundary-link")) {
        add(el, "Organizations", ":boundary", href, true);
      } else {
        add(el, "Organizations > Boundary", leaf, href, true);
      }
      return;
    }
    const section = el.closest(".sparc-sidebar-section");
    const toggle = section && section.querySelector("button.sparc-sidebar-toggle");
    const menu = toggle ? clean(toggle) : "Sidebar";
    let label = clean(el) || squish(el.getAttribute("aria-label"));
    const guide = menu === "Help & Guides" && href.startsWith("/help/");
    if (guide && label !== "Getting Oriented") label = "(each user guide)";
    add(el, menu, label, href, true);
  });
  return out;
}
"""

# Marks, outermost first, every closed collapse and dropdown between the
# document and one tagged link, so the test can open them in order.
REVEAL_JS = r"""
(id) => {
  const el = document.querySelector(`[data-navinv-id="${id}"]`);
  const chain = [];
  for (let n = el.parentElement; n; n = n.parentElement) {
    if (n.classList.contains("dropdown-menu")) {
      const t = n.parentElement.querySelector(":scope > .dropdown-toggle");
      if (t) chain.unshift(t);
    } else if (n.classList.contains("collapse") && !n.classList.contains("show") && n.id) {
      const t = document.querySelector(`[data-bs-target="#${n.id}"]`);
      if (t) chain.unshift(t);
    }
  }
  chain.forEach((t, k) => t.setAttribute("data-navinv-open", String(k)));
  return chain.length;
}
"""


def normalize_path(href: str) -> str:
    if re.match(r"^https?://", href):
        return href
    url = urlparse(href)
    path = re.sub(
        r"^/authorization_boundaries/[^/]+", f"/authorization_boundaries/{BOUNDARY}", url.path
    )
    path = re.sub(r"^/help/[^/]+$", "/help/:guide", path)
    if not url.query:
        return path
    query = dict(parse_qsl(url.query, keep_blank_values=True))
    if "authorization_boundary_id" in query:
        query["authorization_boundary_id"] = BOUNDARY
    return path + "?" + "&".join(f"{k}={v}" for k, v in sorted(query.items()))


def condition_for(path: str) -> str | None:
    if re.match(r"^https?://", path):
        return "resources"
    if BOUNDARY in path:
        return "boundary"
    return "fido2" if path == "/webauthn_credentials" else None


def key(entry: dict) -> tuple[str, str, str]:
    return (entry["menu"], entry["label"], entry["path"])


def live_navigation(page) -> list[dict]:
    """The navigation `page` offers on the home screen, normalised."""
    page.goto("/")
    page.wait_for_load_state("networkidle")
    assert "/login" not in page.url, f"the smoke session is not signed in: {page.url}"
    raw = page.evaluate(EXTRACT_JS)
    for entry in raw:
        entry["path"] = normalize_path(entry["href"])
        entry["when"] = condition_for(entry["path"])
    return raw


def recorded(*postures: str) -> list[dict]:
    return [e for name in postures for e in POSTURES[name]]


def describe(keys) -> str:
    return "\n".join(f"  {m} | {label} | {p}" for m, label, p in sorted(keys))


def required_keys(entries: list[dict], live: list[dict]) -> set:
    """Recorded entries this stack must offer, given its data and config."""
    live_conditions = {e["when"] for e in live}
    return {
        key(e)
        for e in entries
        if e.get("when") is None or (e["when"] != "resources" and e["when"] in live_conditions)
    }


def offered_keys(live: list[dict]) -> set:
    return {key(e) for e in live if e["when"] != "resources"}


def test_admin_is_offered_exactly_the_recorded_navigation(authed_page):
    live = live_navigation(authed_page)
    admin = recorded("signed_in_admin")

    offered = offered_keys(live)
    allowed = {key(e) for e in admin}
    missing = required_keys(admin, live) - offered
    unexpected = offered - allowed

    assert not missing, f"recorded admin links no longer offered:\n{describe(missing)}"
    assert not unexpected, f"admin links offered but not in the inventory:\n{describe(unexpected)}"


def test_member_is_offered_only_recorded_signed_in_navigation(user_authed_page):
    live = live_navigation(user_authed_page)
    member = recorded("signed_in_member")

    offered = offered_keys(live)
    # The smoke member's grants vary by stack (federation, say), so anything
    # recorded for ANY signed-in viewer is allowed; the member's own recorded
    # links are required.
    allowed = {key(e) for e in recorded(*SIGNED_IN)}
    missing = required_keys(member, live) - offered
    unexpected = offered - allowed

    assert not missing, f"recorded member links no longer offered:\n{describe(missing)}"
    assert not unexpected, f"member links offered but not in the inventory:\n{describe(unexpected)}"
    assert not [e for e in live if e["menu"] == "Account" and e["path"].startswith("/admin/")], (
        "the non-admin is offered administrator screens"
    )


def _clickable(live: list[dict]) -> list[dict]:
    """Every internal link worth clicking, once per menu.

    Skipped: external links; Sign Out (it would end the session the rest of the
    suite uses); links that open a new tab or the help drawer (help guides,
    covered by test_help_drawer_880 / test_contextual_help); and every boundary
    after the first, since each boundary's links are the same shape.
    """
    first_boundary = next(
        (e["href"] for e in live if e["menu"] == "Organizations" and e["label"] == BOUNDARY), None
    )
    slug = first_boundary.rstrip("/").split("/")[-1] if first_boundary else None
    seen, picked = set(), []
    for e in live:
        if e["when"] == "resources" or e["path"] == "/logout" or e["blank"]:
            continue
        if e["when"] == "boundary" and (slug is None or slug not in e["href"]):
            continue
        if (e["menu"], e["path"]) in seen:
            continue
        seen.add((e["menu"], e["path"]))
        picked.append(e)
    return picked


def test_every_navigation_link_opens_by_clicking(authed_page):
    record_csp(authed_page)
    targets = _clickable(live_navigation(authed_page))
    assert targets, "no navigation links found to click"

    failures = []
    for target in targets:
        live = live_navigation(authed_page)
        match = next(
            (e for e in live if (e["menu"], e["href"]) == (target["menu"], target["href"])), None
        )
        if match is None:
            failures.append(f"{target['menu']} > {target['label']}: link not found on reload")
            continue

        for k in range(authed_page.evaluate(REVEAL_JS, match["id"])):
            toggle = authed_page.locator(f'[data-navinv-open="{k}"]')
            if toggle.is_visible():
                toggle.click()
        link = authed_page.locator(f'[data-navinv-id="{match["id"]}"]')
        link.wait_for(state="visible", timeout=5_000)

        expected = urlparse(match["href"])
        link.click()
        try:
            authed_page.wait_for_url(
                lambda u, p=expected.path: urlparse(u).path == p, timeout=15_000
            )
        except Exception:  # noqa: BLE001 - reported with the URL it reached
            failures.append(
                f"{match['menu']} > {match['label']}: clicked, landed on {authed_page.url}"
            )
            continue
        authed_page.wait_for_load_state("networkidle")

        if "/login" in authed_page.url:
            failures.append(f"{match['menu']} > {match['label']}: bounced to sign-in")
        status = authed_page.request.get(match["href"]).status
        if status >= 400:
            failures.append(
                f"{match['menu']} > {match['label']}: {match['href']} returned {status}"
            )
        assert_no_csp_violations(authed_page, during=f"{match['menu']} > {match['label']}")

    assert not failures, "navigation links that did not open:\n" + "\n".join(failures)
