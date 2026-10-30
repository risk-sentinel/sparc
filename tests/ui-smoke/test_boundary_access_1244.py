"""UI smoke: a non-administrator sees and opens only the boundaries they may (v1.17.2).

#1244 — every boundary action checks the caller against that boundary. Before
it, any signed-in user who knew a slug could open, edit or delete a boundary.
#1245 / #1247 — the list, the sidebar and the Enterprise menu show only the
boundaries the user may see, and only the actions they may take.

Driven as the harness's second identity (SPARC_SMOKE_USER_TOKEN), a genuine
non-administrator, against a boundary that identity has no role on, found
through the administrator's API. Nothing is created or changed.

Selectors verified against app/views/authorization_boundaries/index.html.erb
and app/views/shared/_main_nav.html.erb.
"""

from __future__ import annotations

import os

import pytest

from helpers import SHELL_HEADER, assert_no_csp_violations, nav_shell_on, record_csp

pytestmark = pytest.mark.authenticated

ENTERPRISE_MENU = ".sparc-nav-boundaries + .dropdown-menu"
# 1.18.0-rf — with SPARC_NAV_SHELL on, those links live in the shell header
# (Library menu, switcher) and the tab bar (Settings) instead.
SHELL_NAV = f"{SHELL_HEADER}, [data-testid=shell-bar]"
# Boundary links on the list: the classic table's, or the Boundaries tab's rows.
LISTED = (
    "table a[href^='/authorization_boundaries/'], [data-testid=boundary-row] a.sparc-repo-row__name"
)


def _all_boundary_slugs(page, base_url) -> list[str]:
    token = os.environ.get("SPARC_SMOKE_SA_TOKEN")
    if not token:
        pytest.skip("SPARC_SMOKE_SA_TOKEN not set — cannot list every boundary")
    resp = page.request.get(
        f"{base_url}/api/v1/authorization_boundaries?items=100",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.ok, resp.text()
    return [b["slug"] for b in resp.json()["data"]]


def _listed_slugs(page) -> list[str]:
    hrefs = page.locator(LISTED).evaluate_all("els => els.map(e => e.getAttribute('href'))")
    return sorted({h.split("/")[2] for h in hrefs if h.count("/") == 2})


def test_non_admin_list_shows_only_openable_boundaries(user_authed_page, base_url):
    page = user_authed_page
    record_csp(page)
    page.goto(f"{base_url}/authorization_boundaries?view=list")
    page.wait_for_load_state("domcontentloaded")
    assert "/authorization_boundaries" in page.url, f"the list itself was refused: {page.url}"

    # No administrator-only action on any row.
    deletes = "form[action^='/authorization_boundaries/'] input[value='delete']"
    assert page.locator(deletes).count() == 0

    for slug in _listed_slugs(page):
        page.goto(f"{base_url}/authorization_boundaries/{slug}")
        page.wait_for_load_state("domcontentloaded")
        assert page.url.rstrip("/").endswith(f"/authorization_boundaries/{slug}"), (
            f"the list offered {slug}, which refused this user ({page.url})"
        )

    assert_no_csp_violations(page, during="opening the boundaries the list offers")


def test_non_admin_is_refused_a_boundary_it_cannot_see(user_authed_page, base_url):
    page = user_authed_page
    page.goto(f"{base_url}/authorization_boundaries?view=list")
    page.wait_for_load_state("domcontentloaded")
    hidden = sorted(set(_all_boundary_slugs(page, base_url)) - set(_listed_slugs(page)))
    if not hidden:
        pytest.skip("this identity can see every boundary — nothing hidden to probe")

    page.goto(f"{base_url}/authorization_boundaries/{hidden[0]}")
    page.wait_for_load_state("domcontentloaded")
    assert f"/authorization_boundaries/{hidden[0]}" not in page.url, (
        f"#1244: a boundary hidden from the list opened anyway: {page.url}"
    )


def _navigation_html(page) -> str:
    if nav_shell_on(page):
        return "".join(page.locator(SHELL_NAV).evaluate_all("els => els.map(e => e.innerHTML)"))
    return page.locator(ENTERPRISE_MENU).inner_html()


def test_enterprise_menu_offers_admin_screens_only_to_admins(
    authed_page, user_authed_page, base_url
):
    user = user_authed_page
    user.goto(f"{base_url}/")
    user.wait_for_load_state("domcontentloaded")
    user_menu = _navigation_html(user)
    assert "/federation_peers" not in user_menu
    assert "/admin/organizations" not in user_menu

    admin = authed_page
    admin.goto(f"{base_url}/")
    admin.wait_for_load_state("domcontentloaded")
    admin_menu = _navigation_html(admin)
    assert "/federation_peers" in admin_menu
    assert "/admin/organizations" in admin_menu
