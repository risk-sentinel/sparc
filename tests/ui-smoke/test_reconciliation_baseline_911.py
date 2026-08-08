"""UI smoke: catalog-lineage banner and the Set baseline control (#911 layer 2).

An SSP that cannot name the profile its controls descend from is refused edits
by the reconciliation gate. That refusal is only fair if the remedy is
reachable, so the banner carries an inline "Set baseline" form posting to
``PATCH /ssp_documents/:id/set_baseline``.

This is the new-navigation check for that control: the banner renders, the
select offers the loaded profiles, submitting it succeeds, and the banner is
gone afterwards — with zero CSP violations on interaction. Render-time checks
alone would not catch inline-handler/CSP breakage, which only shows on click.

The demo seed creates SSPs from ``demo_acme_*.xlsx``, which carries no OSCAL
lineage, so an unreconciled SSP is the expected state of a freshly seeded
instance rather than something this test has to manufacture.

Selectors verified against app/views/shared/_reconciliation_banner.html.erb.
The admin report at /admin/reconciliation is covered for page-load in pages.py.
"""

from __future__ import annotations

import os
from urllib.parse import urlparse

import httpx
import pytest
from playwright.sync_api import expect

import helpers
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

BANNER = ".alert:has-text('Baseline not set')"
SELECT = "select[name='ssp_document[profile_document_id]']"
SUBMIT = ".alert input[type='submit'][value='Set baseline']"


def _unreconciled_ssp(page, base_url):
    """URL of an SSP showing the baseline banner.

    Discovery goes through ``helpers.first_show_href`` deliberately. A
    hand-rolled ``a[href^='/ssp_documents/']`` walk does NOT work here: SPARC
    document URLs are slug-based (FriendlyId), and a naive walk also picks up
    collection routes like ``/ssp_documents/new``. The first version of this
    test did exactly that, found nothing, and skipped itself on every run —
    reporting success while exercising none of the feature it was written for.

    Raises AssertionError when an SSP exists but discovery yields nothing, so a
    future discovery break fails loudly instead of quietly skipping again.
    """
    href = helpers.first_show_href(page, f"{base_url}/ssp_documents", "/ssp_documents")
    if href is None:
        return None  # genuinely no SSP on this deployment

    page.goto(f"{base_url}{href}", wait_until="domcontentloaded")
    if page.locator(BANNER).count() > 0:
        return f"{base_url}{href}"
    return None


def test_banner_states_the_problem_and_offers_the_fix(authed_page, base_url):
    page = authed_page
    record_csp(page)
    url = _unreconciled_ssp(page, base_url)
    if url is None:
        pytest.skip("no unreconciled SSP on this deployment — nothing to exercise")

    banner = page.locator(BANNER).first
    assert banner.is_visible()
    # The consequence, not just the fact.
    assert "OSCAL export will be incomplete" in banner.inner_text()
    assert_no_csp_violations(page, during="reconciliation banner render")


def test_set_baseline_resolves_the_document(authed_page, base_url):
    page = authed_page
    record_csp(page)
    url = _unreconciled_ssp(page, base_url)
    if url is None:
        pytest.skip("no unreconciled SSP on this deployment — nothing to exercise")

    select = page.locator(SELECT)
    if select.count() == 0:
        # No profile is loaded, so SPARC correctly offers nothing rather than
        # inventing a baseline. That is the documented behaviour, not a failure.
        assert "will not create one" in page.locator(BANNER).first.inner_text()
        pytest.skip("no profile loaded to choose from — banner correctly offers no control")

    # CSS has no `!=` operator — `option[value!='']` throws a SyntaxError in
    # the browser, which surfaced as a Playwright Error rather than a clean
    # assertion failure.
    options = select.locator("option:not([value=''])")
    assert options.count() > 0, "a loaded profile must be offerable"
    select.select_option(index=1)

    page.click(SUBMIT)
    page.wait_for_load_state("domcontentloaded")

    assert_no_csp_violations(page, during="set baseline submit")

    # Assert on the page the SUBMIT landed us on, rather than navigating to the
    # document again.
    #
    # The earlier version did `page.goto(url)` and then looked for the banner.
    # That failed under the full suite while passing in isolation, and the cause
    # was NOT timing: the DB was already correct (profile set, blocks=false, the
    # audit event written) while the re-fetched page still showed the banner
    # through 24 retries over 10s. The preceding test in this file `goto`s the
    # same URL and primes a cached response; the second navigation re-served it.
    #
    # `set_baseline` already redirects back to the document, so the post-submit
    # render IS the document page — freshly generated, no second fetch, and it
    # is exactly what a user sees after clicking. Asserting here removes the
    # cache from the picture instead of trying to out-wait it.
    expect(page.locator(BANNER)).to_have_count(0, timeout=10_000)

    # And the user is actually told it worked. Asserted separately because a
    # silent success is its own defect class here: SPARC has previously shipped
    # controllers whose `notice:` rendered NOWHERE because the flash key was
    # missing from FLASH_CLASSES, so "the write succeeded" and "the user can
    # tell the write succeeded" are genuinely different claims.
    assert "Baseline set" in page.content(), "setting a baseline must confirm itself to the user"

    # Put it back. This test CONSUMES its own precondition: each run reconciles
    # one more document, so without a restore it would quietly exhaust the
    # unreconciled documents on the deployment and skip forever afterwards —
    # reporting success while exercising nothing. That is the same silent-skip
    # failure this file already hit once.
    #
    # Clearing is permitted precisely because the document is reconciled right
    # now: the gate only refuses updates to UNresolved documents.
    _clear_baseline(url)


def _clear_baseline(show_url: str) -> None:
    """Restore the document to its unreconciled state via the API."""
    token = os.environ.get("SPARC_SMOKE_SA_TOKEN")
    if not token:
        return

    slug = urlparse(show_url).path.rsplit("/", 1)[-1]
    httpx.patch(
        f"{urlparse(show_url).scheme}://{urlparse(show_url).netloc}/api/v1/ssp_documents/{slug}",
        json={"ssp_document": {"profile_document_id": None}},
        headers={"Authorization": f"Bearer {token}"},
        verify=helpers.smoke_tls_verify(),
        timeout=30,
    )
