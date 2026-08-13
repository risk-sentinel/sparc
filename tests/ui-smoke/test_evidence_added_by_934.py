"""The evidence "Added by" filter (#934).

#908 shipped the filter mechanism but could not ship this facet: provenance was
a free-text `collected_by` name with no reference to an account, so a dropdown
built on it would not resolve to users and would go stale on any rename. #934
added `collected_by_user_id` and the facet with it.

The request specs cover narrowing on both surfaces. What a browser adds is that
the control is actually DRAWN and usable on the screen — and, specifically, that
evidence submitted through the API by a service account is attributable there.
That is the case the whole issue turns on: a name string cannot answer "what did
this pipeline provide", and it is the reason the column exists.

Unlike test_index_filters_908.py, this does not skip when the corpus lacks the
facet. It CREATES the evidence it needs through the API — two records from the
smoke service account — so the dropdown is guaranteed to have a value to offer
rather than the test being a hostage to seed data.

Requires SPARC_SMOKE_SA_TOKEN; skipped otherwise.
    uv run pytest test_evidence_added_by_934.py --browser chromium
"""

from __future__ import annotations

import pytest

import _api_setup
from helpers import csp_violations, record_csp

pytestmark = pytest.mark.authenticated

TITLE_PREFIX = "phase2-ui-addedby"


@pytest.fixture
def submitted_evidence():
    """Two evidence records submitted by the smoke service account, via the API.

    Created through the API on purpose: this is the service-account submission
    path, and the point of the test is that what it submits is attributable on
    screen. Swept by title afterwards, like #902's evidence smoke.
    """
    created = [
        _api_setup.create_evidence(f"{TITLE_PREFIX}-{n}") for n in ("one", "two")
    ]
    yield created
    _api_setup.delete_evidences_titled(TITLE_PREFIX)


def _added_by_select(page):
    return page.locator("form select[name='collected_by_user_id']")


def test_added_by_is_offered_and_narrows(authed_page, submitted_evidence):
    record_csp(authed_page)

    # Filter by the account the API says collected these records, not by
    # whichever option happens to sort first. Picking arbitrarily would filter
    # to some other collector and then assert our evidence is present, which is
    # either a false failure or a pass that proves nothing.
    value = str(submitted_evidence[0]["collected_by_user_id"])
    assert value and value != "None", (
        "the API reported no collected_by_user_id for evidence it just created — "
        "the submission path is not recording the account"
    )

    # Arrive with the facet ALREADY applied rather than selecting it from the
    # dropdown.
    #
    # CollectionBrowseQuery hides a select whose value set has cardinality 1 —
    # a dropdown offering one choice is noise (#908) — but always renders one
    # the user has already set, or the control that set it would vanish while
    # its effect remained. An instance where a single account has collected
    # everything is therefore a legitimate state in which the dropdown is
    # correctly absent, and the earlier version of this test failed there while
    # the product was behaving exactly as designed.
    resp = authed_page.goto(f"/evidences?per_page=50&view=list&collected_by_user_id={value}")
    assert resp is not None and resp.status < 400
    authed_page.wait_for_load_state("networkidle")

    select = _added_by_select(authed_page)
    assert select.count() == 1, (
        "the Added by filter is not drawn even though it is applied in the URL — "
        "an active facet must stay visible or its control disappears while it is "
        "still narrowing the list"
    )

    option_values = [
        select.locator("option").nth(i).get_attribute("value")
        for i in range(select.locator("option").count())
    ]
    assert value in option_values, (
        f"the account that collected this evidence ({value}) is not offered in "
        f"Added by; offered: {option_values}"
    )
    assert select.input_value() == value, (
        "the applied account is not the selected option, so the control does not "
        "reflect the filter actually in force"
    )

    url = authed_page.url
    assert f"collected_by_user_id={value}" in url, f"the filter did not reach the URL: {url}"
    assert "per_page=50" in url, f"filtering by Added by dropped per_page: {url}"
    assert "view=list" in url, f"filtering by Added by dropped the view mode: {url}"

    # The evidence this test submitted was collected by the service account the
    # browser is signed in as, so filtering to that account must still show it.
    body = authed_page.content()
    assert TITLE_PREFIX in body, (
        "evidence submitted by this service account is not returned when "
        "filtering by that account — the submission recorded no usable collector"
    )

    chips = authed_page.locator("a.sparc-chip")
    assert chips.count() >= 1, "an applied Added by filter must show a removable chip"

    assert not csp_violations(authed_page), (
        f"CSP violations during Added by interaction: {csp_violations(authed_page)}"
    )


def test_added_by_shows_a_collector_on_the_record(authed_page, submitted_evidence):
    """API-submitted evidence must not read as "Collected By: N/A".

    The auto-fetch path produced exactly that — a record in the corpus with no
    recorded collector at all — which is the defect #934 was filed for.
    """
    record_csp(authed_page)

    slug = submitted_evidence[0].get("slug") or submitted_evidence[0]["id"]
    resp = authed_page.goto(f"/evidences/{slug}")
    assert resp is not None and resp.status < 400
    authed_page.wait_for_load_state("networkidle")

    body = authed_page.content()
    assert "Collected By" in body, "the record does not show a Collected By row at all"

    row = authed_page.locator("tr", has_text="Collected By").first
    assert "N/A" not in row.inner_text(), (
        "evidence submitted through the API shows no collector — provenance was "
        "not stamped on that path"
    )

    assert not csp_violations(authed_page)
