"""Card / list collection views in a real browser (#887, #888).

The rspec request specs assert the markup; this asserts the thing a user
actually does — clicking the toggle and having the page change — which request
specs structurally cannot, and which the local rspec system specs skip entirely
when there is no Chrome on PATH.

It matters more than usual here because the toggle is a plain link, not a
JavaScript widget. That was a deliberate choice (state in the URL, works under
CSP, works without a mouse), and this is what proves the choice actually holds
end to end: the toggle navigates, the server honours it, the cookie remembers
it, and nothing throws on the way.

Every collection screen is covered, because the point of #888 is that they all
behave the same. A screen that renders neither a card grid nor a table is a
hard failure; a screen that is simply empty on this deployment is not.

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise.
"""

from __future__ import annotations

import os

import pytest

from helpers import collect_console_errors, csp_violations, record_csp

pytestmark = pytest.mark.authenticated

# Every screen #888 migrated. Kept here rather than derived from INDEX_PAGES:
# that list includes About and Help, which are pages, not collections.
COLLECTION_PAGES = [
    ("ssp", "/ssp_documents"),
    ("sar", "/sar_documents"),
    ("sap", "/sap_documents"),
    ("poam", "/poam_documents"),
    ("cdef", "/cdef_documents"),
    ("profile", "/profile_documents"),
    ("control_catalogs", "/control_catalogs"),
    ("control_mappings", "/control_mappings"),
    ("converters", "/converters"),
    ("authorization_boundaries", "/authorization_boundaries"),
    ("evidences", "/evidences"),
    ("authoritative_sources", "/authoritative_sources"),
    ("federation_peers", "/federation_peers"),
    ("leveraged_poams", "/leveraged_poam_documents"),
    ("promotion_queue", "/promotion_queue"),
    ("review_queue", "/review_queue"),
]

# #984 — the four screens that used to skip all three checks because a
# demo-seeded instance held no records for them. The demo seed now builds a
# fixture for each (db/seeds/collection_screens.rb), so the skips should be
# gone; `test_seeded_screens_are_populated` is what says so out loud instead of
# letting them quietly resume skipping.
SEEDED_SCREENS = [
    "review_queue",
    "promotion_queue",
    "leveraged_poams",
    "federation_peers",
    # Not one of the four #984 measured — the instance it was measured on had
    # curated rows — but a freshly seeded database has none and it would skip
    # there for the same reason. Seeded so a fresh install does not rediscover it.
    "authoritative_sources",
]

CARD = ".sparc-item-card"
GRID = ".sparc-card-grid"
TOGGLE = '[role="radiogroup"]'


def _demo_seeded() -> bool:
    """Is this deployment expected to carry the demo fixtures?

    Declared by the runner rather than sniffed, the way
    SPARC_SMOKE_PUBLIC_CATALOGS declares the catalog posture. Defaults to true
    because the gate ceremony seeds demo data (`SPARC_SEED_DEMO=true`); a
    deployment that deliberately has none sets it to 0.
    """
    return os.environ.get("SPARC_SMOKE_DEMO_SEEDED", "1").strip() not in ("0", "false", "")


def _populated(page) -> bool:
    """Does this screen have any records on this deployment?

    An empty collection is a legitimate state, not a failure — a non-seeded
    deployment genuinely has nothing to draw. Emptiness is judged by the absence
    of BOTH renderings, so a screen that has records but draws neither still
    fails.

    #984 kept this guard deliberately. What changed is that the four screens it
    used to fire on are now seeded, so it should no longer fire anywhere on a
    demo instance — and `test_seeded_screens_are_populated` fails if it does.
    """
    return page.locator(f"{CARD}, table tbody tr").count() > 0


def _load(page, path, *, during):
    console_errors = collect_console_errors(page)
    record_csp(page)

    resp = page.goto(path)
    assert resp is not None and resp.status < 400, (
        f"{during}: {path} returned HTTP {resp.status if resp else 'none'}"
    )
    assert "/login" not in page.url, f"{during}: {path} bounced to /login"
    page.wait_for_load_state("networkidle")

    assert csp_violations(page) == [], (
        f"{during}: CSP violations on {path}: {csp_violations(page)}"
    )
    assert console_errors == [], f"{during}: console errors on {path}: {console_errors}"


@pytest.mark.parametrize(("label", "path"), COLLECTION_PAGES, ids=[p[0] for p in COLLECTION_PAGES])
def test_card_view_renders(authed_page, label, path):
    """?view=card draws cards, not a table."""
    _load(authed_page, f"{path}?view=card", during=f"{label} card view")

    if not _populated(authed_page):
        pytest.skip(f"{label}: no records on this deployment")

    assert authed_page.locator(GRID).count() > 0, (
        f"{label}: ?view=card rendered no card grid"
    )
    assert authed_page.locator("table").count() == 0, (
        f"{label}: ?view=card still rendered a table"
    )


@pytest.mark.parametrize(("label", "path"), COLLECTION_PAGES, ids=[p[0] for p in COLLECTION_PAGES])
def test_list_view_renders(authed_page, label, path):
    """?view=list draws a table, not cards."""
    _load(authed_page, f"{path}?view=list", during=f"{label} list view")

    if not _populated(authed_page):
        pytest.skip(f"{label}: no records on this deployment")

    assert authed_page.locator("table").count() > 0, (
        f"{label}: ?view=list rendered no table"
    )
    assert authed_page.locator(CARD).count() == 0, (
        f"{label}: ?view=list still rendered cards"
    )


@pytest.mark.parametrize(("label", "path"), COLLECTION_PAGES, ids=[p[0] for p in COLLECTION_PAGES])
def test_toggle_switches_the_view(authed_page, label, path):
    """Clicking the toggle actually changes what is drawn.

    The assertion request specs cannot make: that the control is reachable,
    that clicking it navigates, and that the server honours the result.
    """
    _load(authed_page, f"{path}?view=card", during=f"{label} toggle")

    if not _populated(authed_page):
        pytest.skip(f"{label}: no records on this deployment")

    toggle = authed_page.locator(TOGGLE)
    assert toggle.count() == 1, f"{label}: expected one view toggle, found {toggle.count()}"

    # aria-checked is what a screen reader announces; it must agree with what
    # is on screen, or the announced state and the visual state have drifted.
    card_option = toggle.locator('[role="radio"]', has_text="Cards")
    list_option = toggle.locator('[role="radio"]', has_text="List")
    assert card_option.get_attribute("aria-checked") == "true", (
        f"{label}: card view is showing but Cards is not announced as checked"
    )

    # wait_for_url, not just networkidle: the toggle is a Turbo Drive visit, and
    # networkidle can resolve between the fetch and the <body> swap — which
    # reads as "the click did nothing" when the click was fine.
    list_option.click()
    authed_page.wait_for_url("**view=list**", timeout=10_000)
    authed_page.wait_for_load_state("networkidle")

    assert authed_page.locator("table").count() > 0, (
        f"{label}: clicking List did not produce a table"
    )
    assert authed_page.locator(CARD).count() == 0, (
        f"{label}: clicking List left cards on screen"
    )
    assert (
        authed_page.locator(TOGGLE).locator('[role="radio"]', has_text="List")
        .get_attribute("aria-checked")
        == "true"
    ), f"{label}: List is showing but is not announced as checked"


def test_the_choice_is_remembered_per_screen(authed_page):
    """A chosen view survives the next visit, and does not decide other screens.

    The per-screen scoping is the part worth proving in a browser: it rides on
    a cookie name derived from the screen, and a bug there would silently make
    one preference global.
    """
    _load(authed_page, "/ssp_documents?view=list", during="remember: choose list")

    _load(authed_page, "/ssp_documents", during="remember: revisit")
    assert authed_page.locator("table").count() > 0, (
        "SSP index forgot the chosen list view on the next visit"
    )

    # A different screen must be unaffected — still cards.
    _load(authed_page, "/cdef_documents", during="remember: other screen")
    if authed_page.locator(f"{CARD}, table tbody tr").count() > 0:
        assert authed_page.locator(GRID).count() > 0, (
            "choosing list on SSPs also changed the CDEF screen"
        )


def test_a_shared_link_shows_what_the_sender_saw(authed_page):
    """An explicit ?view= in a link beats the recipient's stored preference."""
    _load(authed_page, "/ssp_documents?view=list", during="shared link: store list")
    _load(authed_page, "/ssp_documents?view=card", during="shared link: open card link")

    if not _populated(authed_page):
        pytest.skip("no SSP records on this deployment")

    assert authed_page.locator(GRID).count() > 0, (
        "a ?view=card link did not override the stored list preference"
    )


def test_search_narrows_and_says_so(authed_page):
    """A search that matches nothing states it rather than rendering blank."""
    _load(
        authed_page,
        "/cdef_documents?q=zzz-no-such-component-zzz",
        during="empty search",
    )

    body = authed_page.locator("body").inner_text()
    assert "match the current filters" in body, (
        f"an empty result set said nothing about why: {body[:400]}"
    )


def test_facets_are_removable(authed_page):
    """An applied facet shows as a chip that drops it and keeps the rest."""
    _load(
        authed_page,
        "/cdef_documents?partition=aws-us-gov&capability=MFA",
        during="facet chips",
    )

    body = authed_page.locator("body").inner_text()
    if "filters active" not in body:
        pytest.skip("no CDEF component index on this deployment (facets inert)")

    assert "2 filters active" in body, f"facet count wrong: {body[:400]}"
    assert authed_page.get_by_text("Clear all").count() > 0, "no clear-all offered"

    # Dropping one chip must leave the other facet in the URL.
    authed_page.get_by_title("Remove the Partition filter").click()
    authed_page.wait_for_url(lambda url: "partition=" not in url, timeout=10_000)
    authed_page.wait_for_load_state("networkidle")

    assert "capability=MFA" in authed_page.url, (
        f"removing the partition facet also dropped the capability: {authed_page.url}"
    )
    assert "partition=" not in authed_page.url, (
        f"the removed facet is still in the URL: {authed_page.url}"
    )


def test_actions_are_present_in_both_views(authed_page):
    """The regression that shipped: cards with none of the row's actions.

    Asserted on CDEFs, which carry the fullest action set of any collection.
    """
    _load(authed_page, "/cdef_documents?view=list", during="actions: list")
    if not _populated(authed_page):
        pytest.skip("no CDEF records on this deployment")

    list_actions = {
        "view": authed_page.get_by_role("link", name="View").count(),
        "export": authed_page.locator('[data-controller="oscal-export"]').count(),
        "delete": authed_page.get_by_role("button", name="Delete").count(),
    }

    _load(authed_page, "/cdef_documents?view=card", during="actions: card")
    card_actions = {
        "view": authed_page.get_by_role("link", name="View").count(),
        "export": authed_page.locator('[data-controller="oscal-export"]').count(),
        "delete": authed_page.get_by_role("button", name="Delete").count(),
    }

    for action, count in list_actions.items():
        if count == 0:
            continue  # not offered to this user at all — fine, as long as neither view has it
        assert card_actions[action] > 0, (
            f"the card view is missing '{action}' that the list view offers "
            f"(list={count}, card={card_actions[action]})"
        )


@pytest.mark.parametrize("label", SEEDED_SCREENS)
def test_seeded_screens_are_populated(authed_page, label):
    """#984 — the four screens that used to skip all three checks have records.

    12 checks (4 screens x 3) skipped on a fully demo-seeded instance, so the
    card-versus-table assertions — the actual subject of this file — had never
    run there. Page load and console errors were still covered, which is what
    made it easy to miss: the screens were green, and green meant "loaded", not
    "renders correctly".

    This is the assertion that keeps them from quietly going back to skipping.
    A skip is invisible in a passing run; a failure is not.
    """
    if not _demo_seeded():
        pytest.skip("SPARC_SMOKE_DEMO_SEEDED=0 — deployment carries no demo fixtures")

    path = dict(COLLECTION_PAGES)[label]
    _load(authed_page, path, during=f"{label} seeded check")

    assert _populated(authed_page), (
        f"{label}: no records, so its card/list checks will skip and prove nothing. "
        f"Re-run the demo seed (SPARC_SEED_DEMO=true bin/rails db:seed) — the "
        f"demo_collection_screens section builds this screen's fixture (#984)."
    )
