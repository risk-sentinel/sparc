"""Sidebar navigation smoke (#951).

The left navigation was built for a small estate and degraded as organizations
and boundaries multiplied: it scrolled with the page rather than in its own
pane, so a long organization tree pushed the Compliance Library, Resources and
Help sections off the bottom of the document.

These are the checks that would have caught that, plus the ones covering the
controls this change adds. Every interaction asserts zero CSP violations —
render-time checks cannot see inline-handler breakage, which only manifests on
click.

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

SIDEBAR = ".sparc-sidebar"


def _sidebar(authed_page):
    record_csp(authed_page)
    authed_page.goto("/")
    sidebar = authed_page.locator(SIDEBAR)
    if sidebar.count() == 0:
        pytest.skip("sidebar is hidden at this viewport (<=991.98px)")
    return sidebar


def test_the_sidebar_scrolls_in_its_own_pane(authed_page):
    """The property the issue exists for.

    Bounded height plus `overflow-y: auto` is what makes the pane scrollable.
    It was `min-height`, which lets the box grow with its content, so the
    overflow never engaged and the whole document scrolled instead.
    """
    sidebar = _sidebar(authed_page)

    box = sidebar.evaluate(
        "el => { const s = getComputedStyle(el);"
        " return { overflowY: s.overflowY, position: s.position,"
        "          clientH: el.clientHeight, scrollH: el.scrollHeight,"
        "          viewportH: window.innerHeight }; }"
    )

    assert box["overflowY"] in ("auto", "scroll"), box
    assert box["position"] == "sticky", box
    # Bounded: the pane must not be taller than the viewport, or it is the
    # document that scrolls and the bottom sections walk off the page.
    assert box["clientH"] <= box["viewportH"], box


def test_the_bottom_sections_are_reachable(authed_page):
    """Compliance Library, Resources and Help sit below the organization tree.

    They are the sections a long estate pushed out of reach, so their presence
    in the pane is the acceptance criterion, not a decoration.
    """
    sidebar = _sidebar(authed_page)
    text = sidebar.inner_text()

    for section in ("Compliance Library", "Resources", "Help & Guides"):
        assert section in text, f"{section!r} missing from the sidebar: {text[:400]}"


def test_boundary_documents_follow_the_implementation_then_assessment_order(authed_page):
    """A boundary's documents are implementation, then assessment.

    Profiles are deliberately absent: a profile is a baseline SELECTION
    referenced by many boundaries, not a per-boundary artefact, and it remains
    reachable from the Controls navigation.
    """
    sidebar = _sidebar(authed_page)

    # `#sidebarOrgs` (plural) is the SECTION toggle and `#sidebarOrg<id>` is one
    # organization. A prefix match catches both, and clicking the section one
    # collapses the whole tree, which is why every boundary button then reported
    # itself hidden.
    toggles = sidebar.locator(
        "button[data-bs-target^='#sidebarOrg']"
        ":not([data-bs-target='#sidebarOrgs'])"
        ":not([data-bs-target*='More'])"
    )
    if toggles.count() == 0:
        pytest.skip("no organizations on this instance")

    # Find an organization that actually HAS a boundary, and stay inside it.
    # Taking "the first boundary toggle in the sidebar" after expanding "the
    # first organization" picks up a boundary belonging to a still-collapsed
    # organization, which is never clickable.
    panel_id = None
    for i in range(toggles.count()):
        target = toggles.nth(i).get_attribute("data-bs-target")
        if authed_page.locator(f"{target} button[data-bs-target^='#sidebarAb']").count():
            toggles.nth(i).click()
            assert_no_csp_violations(authed_page, during="expanding an organization")
            panel_id = target
            break
    if panel_id is None:
        pytest.skip("no organization on this instance has a boundary")

    boundary_toggle = authed_page.locator(f"{panel_id} button[data-bs-target^='#sidebarAb']").first
    boundary_toggle.wait_for(state="visible")
    boundary_panel = boundary_toggle.get_attribute("data-bs-target")
    boundary_toggle.click()
    assert_no_csp_violations(authed_page, during="expanding a boundary")

    leaves = authed_page.locator(f"{boundary_panel} .sparc-sidebar-leaf")
    leaves.first.wait_for(state="visible")
    labels = [leaves.nth(i).inner_text().strip() for i in range(leaves.count())]

    assert labels == ["CDEFs", "SSP", "SAP", "Evidence", "SAR", "Amendments", "POA&Ms"], labels


def test_the_oscal_reference_links_are_nested(authed_page):
    """Nine external links in one flat list is what pushed Help & Guides down."""
    sidebar = _sidebar(authed_page)

    sidebar.locator("button[data-bs-target='#sidebarResources']").first.click()
    assert_no_csp_violations(authed_page, during="expanding Resources")

    nest = sidebar.locator("button[data-bs-target='#sidebarOscalRef']")
    assert nest.count() == 1, "the OSCAL reference group is not nested under Resources"

    nest.first.click()
    assert_no_csp_violations(authed_page, during="expanding OSCAL Reference")

    links = sidebar.locator("#sidebarOscalRef .sparc-sidebar-leaf")
    assert links.count() > 0, "the OSCAL reference group expanded to nothing"


def test_the_navigation_dropdown_is_bounded(authed_page):
    """#951 — measured at 800px tall with no bound, so it overflowed any
    viewport under ~864px and left 87px of it unreachable at 777px."""
    record_csp(authed_page)
    authed_page.set_viewport_size({"width": 1280, "height": 777})
    authed_page.goto("/")

    menu = authed_page.locator(".sparc-dropdown-menu").first
    if menu.count() == 0:
        pytest.skip("no dropdown menu rendered on this page")

    style = menu.evaluate(
        "el => { const s = getComputedStyle(el);"
        " return { maxHeight: s.maxHeight, overflowY: s.overflowY,"
        "          viewportH: window.innerHeight }; }"
    )

    assert style["overflowY"] in ("auto", "scroll"), style
    assert style["maxHeight"] != "none", "the dropdown has no max-height; it can run off screen"


@pytest.mark.parametrize("width,height", [(1440, 900), (1280, 777), (1024, 768)])
def test_the_sidebar_stays_bounded_across_breakpoints(authed_page, width, height):
    """The responsive audit the issue asks for, as a standing check.

    Below 992px the sidebar is hidden by design, so the assertion is that it is
    either absent or bounded — never present and taller than the viewport.
    """
    record_csp(authed_page)
    authed_page.set_viewport_size({"width": width, "height": height})
    authed_page.goto("/")

    sidebar = authed_page.locator(SIDEBAR)
    if sidebar.count() == 0 or not sidebar.first.is_visible():
        return

    measured = sidebar.first.evaluate(
        "el => ({ clientH: el.clientHeight, viewportH: window.innerHeight })"
    )
    assert measured["clientH"] <= measured["viewportH"], (
        f"{width}x{height}: sidebar is {measured['clientH']}px in a "
        f"{measured['viewportH']}px viewport, so the page scrolls instead of the pane"
    )


def test_the_boundary_name_is_a_link_to_the_boundary(authed_page):
    """The name navigates; the chevron only expands.

    Before this the whole row was a collapse toggle, so the boundary — the
    record every one of those documents hangs off — was the one thing in the
    tree you could not open.
    """
    sidebar = _sidebar(authed_page)
    toggles = sidebar.locator(
        "button[data-bs-target^='#sidebarOrg']"
        ":not([data-bs-target='#sidebarOrgs'])"
        ":not([data-bs-target*='More'])"
    )

    panel_id = None
    for i in range(toggles.count()):
        target = toggles.nth(i).get_attribute("data-bs-target")
        if authed_page.locator(f"{target} .sparc-sidebar-boundary-link").count():
            toggles.nth(i).click()
            panel_id = target
            break
    if panel_id is None:
        pytest.skip("no organization on this instance has a boundary")

    link = authed_page.locator(f"{panel_id} .sparc-sidebar-boundary-link").first
    link.wait_for(state="visible")
    href = link.get_attribute("href")

    assert href.startswith("/authorization_boundaries/"), href
    # Addressed by slug, not id — `to_param` is the slug, and a numeric URL
    # would be a different (and less readable) contract.
    assert not href.rstrip("/").split("/")[-1].isdigit(), f"numeric id, expected slug: {href}"

    with authed_page.expect_navigation():
        link.click()
    assert "/authorization_boundaries/" in authed_page.url, authed_page.url
    assert_no_csp_violations(authed_page, during="clicking a boundary name")


def test_the_name_stays_readable_while_the_documents_are_expanded(authed_page):
    """Regression: the flex row must wrap ONLY the chevron and the name.

    With the collapse panel inside the row, the seven document leaves became a
    third flex item and squeezed the name to one character per line — a tall
    vertical column of letters. It was invisible while the panel was collapsed,
    which is the state the layout was first measured in, so the check has to
    open the panel before it measures.
    """
    sidebar = _sidebar(authed_page)
    toggles = sidebar.locator(
        "button[data-bs-target^='#sidebarOrg']"
        ":not([data-bs-target='#sidebarOrgs'])"
        ":not([data-bs-target*='More'])"
    )

    panel_id = None
    for i in range(toggles.count()):
        target = toggles.nth(i).get_attribute("data-bs-target")
        if authed_page.locator(f"{target} .sparc-sidebar-boundary-toggle").count():
            toggles.nth(i).click()
            panel_id = target
            break
    if panel_id is None:
        pytest.skip("no organization on this instance has a boundary")

    chevron = authed_page.locator(f"{panel_id} .sparc-sidebar-boundary-toggle").first
    chevron.wait_for(state="visible")
    documents = chevron.get_attribute("data-bs-target")
    chevron.click()
    authed_page.locator(f"{documents} .sparc-sidebar-leaf").first.wait_for(state="visible")

    box = authed_page.locator(f"{panel_id} .sparc-sidebar-boundary-link").first.bounding_box()

    assert box["width"] > 120, f"the name column collapsed while expanded: {box}"
    assert box["height"] < 120, f"the name is wrapping per character: {box}"


# ── #1042 — the navbar breakpoint ────────────────────────────────────────
#
# The #951 responsive audit (responsive_audit_951.py, 63 pages x 5 breakpoints)
# found the main navbar overflowing the viewport from 992px to ~1400px on every
# page: 992px -> a 1215px document, 1280px -> a 1328px document, 61 of 62 pages
# each time. 138 horizontal-overflow occurrences and 1,431 off-screen elements
# came down to that one cause.
#
# Four things fired at 992px at once — `navbar-expand-lg` stopped collapsing,
# five `d-none d-lg-block` items appeared, `.sparc-navbar-logo` grew 44px -> 52px
# (sparc-theme.css:662), and the sidebar returned (sparc-theme.css:2256).
#
# The fix moves the navbar's transition to `-xxl` (>=1400px), which is where the
# expanded bar demonstrably fits — 1440px never overflowed in any audit run. An
# intermediate `-xl` (>=1200px) was tried first and measured INSUFFICIENT: it
# cleared 992px but left 1280px overflowing on 62 pages, because 1200 sits
# inside the broken range rather than past it. These assertions pin the
# breakpoint that actually broke, so that mistake cannot come back silently.

NAV_COLLAPSE = "#navbarNav"


# The audit allows SLACK_PX = 4 for sub-pixel rounding and scrollbar gutters.
# Match it, so this check and the acceptance instrument cannot disagree.
SLACK_PX = 4


@pytest.mark.parametrize("width,height", [(992, 768), (1280, 800), (1440, 900)])
def test_the_navbar_does_not_overflow_the_viewport(authed_page, width, height):
    """#1042 — the navbar must not extend past the viewport at any width.

    Scoped to the navbar rather than to `document.scrollWidth` deliberately.
    The audit named this exact element — "div#navbarNav.collapse.navbar-collapse
    extends to 1328px (viewport 1280px)", 63 pages — so it is the thing #1042
    fixed and the thing that must stay fixed.

    A document-wide assertion was tried first and rejected: `/` carries an
    unrelated 62px overflow at 992px from a `d-flex.gap-2.flex-shrink-0` row of
    action buttons that `flex-shrink-0` stops from shrinking. Asserting
    document width here would fail on that instead, which would make this check
    about someone else's defect and get it weakened or deleted the first time it
    fired.
    """
    record_csp(authed_page)
    authed_page.set_viewport_size({"width": width, "height": height})
    authed_page.goto("/")

    measured = authed_page.locator(NAV_COLLAPSE).first.evaluate(
        "el => ({ right: Math.round(el.getBoundingClientRect().right),"
        "         viewport: window.innerWidth })"
    )
    assert measured["right"] <= measured["viewport"] + SLACK_PX, (
        f"{width}x{height}: the navbar extends to {measured['right']}px in a "
        f"{measured['viewport']}px viewport. This is #1042 — check that the bar "
        "is still `navbar-expand-xxl` and the items still `d-none d-xxl-block`."
    )
    assert_no_csp_violations(authed_page)


def test_the_nav_items_are_reachable_below_the_expand_breakpoint(authed_page):
    """The other direction: hiding the items must not LOSE them.

    Below 1400px the bar collapses, so About/Resources/OSCAL/Help live behind
    the toggler. If this passed while the items were simply gone, the overflow
    assertion above would be satisfied by deleting the navigation.
    """
    record_csp(authed_page)
    authed_page.set_viewport_size({"width": 1280, "height": 777})
    authed_page.goto("/")

    collapse = authed_page.locator(NAV_COLLAPSE)
    assert collapse.count() == 1, "the navbar collapse container is missing entirely"

    toggler = authed_page.locator("button.navbar-toggler")
    assert toggler.count() == 1 and toggler.first.is_visible(), (
        "at 1280px the bar is collapsed, so the toggler must be visible — "
        "without it the nav items are unreachable, not merely hidden"
    )

    toggler.first.click()
    authed_page.wait_for_timeout(400)  # Bootstrap collapse transition

    about = collapse.locator("a.nav-link", has_text="About").first
    assert about.is_visible(), (
        "after opening the toggler the nav items must be visible; "
        "hidden-and-unreachable is a regression, not a fix"
    )
    assert_no_csp_violations(authed_page)


def test_the_nav_items_are_in_the_bar_at_the_expand_breakpoint(authed_page):
    """And above it, they are back in the bar without a click.

    Pins the breakpoint from the other side: if someone moves the navbar to a
    breakpoint wider than 1400px, the items stop appearing at 1440 and this
    fails.
    """
    record_csp(authed_page)
    authed_page.set_viewport_size({"width": 1440, "height": 900})
    authed_page.goto("/")

    about = authed_page.locator(f"{NAV_COLLAPSE} a.nav-link", has_text="About").first
    assert about.is_visible(), (
        "at 1440px the bar is expanded, so About should be visible without "
        "opening a toggler"
    )
    assert_no_csp_violations(authed_page)
