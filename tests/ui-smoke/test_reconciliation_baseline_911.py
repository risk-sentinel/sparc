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

import pytest

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

BANNER = ".alert:has-text('Baseline not set')"
SELECT = "select[name='ssp_document[profile_document_id]']"
SUBMIT = ".alert input[type='submit'][value='Set baseline']"


def _first_unreconciled_ssp(page, base_url):
    """Return the URL of an SSP showing the banner, or None if all are clean."""
    page.goto(f"{base_url}/ssp_documents", wait_until="domcontentloaded")
    links = page.locator("a[href^='/ssp_documents/']")
    seen = []
    for i in range(min(links.count(), 12)):
        href = links.nth(i).get_attribute("href") or ""
        # Skip nested action routes; we want the show page itself.
        if href.count("/") == 2 and href not in seen:
            seen.append(href)
    for href in seen:
        page.goto(f"{base_url}{href}", wait_until="domcontentloaded")
        if page.locator(BANNER).count() > 0:
            return f"{base_url}{href}"
    return None


def test_banner_states_the_problem_and_offers_the_fix(page, base_url):
    record_csp(page)
    url = _first_unreconciled_ssp(page, base_url)
    if url is None:
        pytest.skip("no unreconciled SSP in this instance — nothing to exercise")

    banner = page.locator(BANNER).first
    assert banner.is_visible()
    # The consequence, not just the fact.
    assert "OSCAL export will be incomplete" in banner.inner_text()
    assert_no_csp_violations(page, during="reconciliation banner render")


def test_set_baseline_resolves_the_document(page, base_url):
    record_csp(page)
    url = _first_unreconciled_ssp(page, base_url)
    if url is None:
        pytest.skip("no unreconciled SSP in this instance — nothing to exercise")

    select = page.locator(SELECT)
    if select.count() == 0:
        # No profile is loaded, so SPARC correctly offers nothing rather than
        # inventing a baseline. That is the documented behaviour, not a failure.
        assert "will not create one" in page.locator(BANNER).first.inner_text()
        pytest.skip("no profile loaded to choose from — banner correctly offers no control")

    options = select.locator("option[value!='']")
    assert options.count() > 0, "a loaded profile must be offerable"
    select.select_option(index=1)

    page.click(SUBMIT)
    page.wait_for_load_state("domcontentloaded")

    assert_no_csp_violations(page, during="set baseline submit")

    # The document is reconciled, so the blocking banner is gone.
    page.goto(url, wait_until="domcontentloaded")
    assert page.locator(BANNER).count() == 0, "banner should clear once the baseline is set"
