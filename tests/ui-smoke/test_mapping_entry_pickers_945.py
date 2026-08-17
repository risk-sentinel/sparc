"""Mapping entries must be picked from the mapped catalogs, not typed (#945).

A mapping *shell* could always be created — name, source catalog, target
catalog — but the entries, the control-to-control relationships the mapping
exists to record, could only be entered by typing raw identifiers as free text.

So both catalogs were already chosen, SPARC already held every control in each,
and it still asked the user to remember and retype the ids. `AC-2(1)`, `ac-2.1`
and `AC-02(01)` are all plausible spellings of the same thing, and an entry
pointing at a control that does not exist looked identical to a correct one in
the table — then flowed into `download_oscal`, so an unusable mapping reached a
consumer that trusted it.

Page-load coverage cannot catch this: the screen returned 200 and rendered a
perfectly good text input. The defect is in what the input ACCEPTS, so this
drives the form instead of the page.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

INDEX = "/control_mappings"
SOURCE_INPUT = "input[name='control_mapping_entry[source_control_id]']"
TARGET_INPUT = "input[name='control_mapping_entry[target_control_id]']"


def _first_mapping_path(page):
    """Path of the first mapping in the index, or None."""
    return page.evaluate(
        """() => {
            const link = [...document.querySelectorAll("a[href*='/control_mappings/']")]
                .map(a => a.getAttribute("href"))
                .find(h => h && !h.endsWith("/control_mappings")
                             && !h.includes("/new")
                             && !h.includes("/edit"));
            return link || null;
        }"""
    )


def _open_a_mapping(page):
    page.goto(INDEX)
    page.wait_for_load_state("networkidle")
    path = _first_mapping_path(page)
    if not path:
        pytest.skip("no control mapping seeded on this deployment")
    page.goto(path)
    page.wait_for_load_state("networkidle")
    return path


def test_entry_form_offers_controls_from_the_mapped_catalogs(authed_page):
    """The source and target inputs are bound to a list of real controls."""
    record_csp(authed_page)
    _open_a_mapping(authed_page)

    if authed_page.locator(SOURCE_INPUT).count() == 0:
        pytest.skip("current user cannot write mappings on this deployment")

    # `list` binds the input to a datalist of the catalog's own controls.
    list_id = authed_page.get_attribute(SOURCE_INPUT, "list")
    assert list_id, (
        "the source control field offers no list of catalog controls — "
        "it is still free text, which is the #945 defect"
    )

    options = authed_page.locator(f"datalist#{list_id} option").count()
    assert options > 0, (
        f"datalist#{list_id} is empty, so the picker offers nothing to pick"
    )

    target_list = authed_page.get_attribute(TARGET_INPUT, "list")
    assert target_list, "the target control field is still free text"
    assert authed_page.locator(f"datalist#{target_list} option").count() > 0

    assert_no_csp_violations(authed_page, during="mapping entry form render")


def test_the_two_sides_offer_different_catalogs(authed_page):
    """Source and target must not be pointed at the same list.

    If both sides offered the same controls, an entry mapping a catalog to
    itself would look valid — and the mapping's whole purpose is to relate two
    DIFFERENT catalogs.
    """
    _open_a_mapping(authed_page)

    if authed_page.locator(SOURCE_INPUT).count() == 0:
        pytest.skip("current user cannot write mappings on this deployment")

    source_list = authed_page.get_attribute(SOURCE_INPUT, "list")
    target_list = authed_page.get_attribute(TARGET_INPUT, "list")

    if not source_list or not target_list:
        pytest.skip("mapping has no catalog on one side; picker falls back to free text")

    assert source_list != target_list, (
        "both sides of the mapping are bound to the same control list"
    )


def test_submitting_a_control_that_does_not_exist_is_refused(authed_page):
    """Typing a bogus id must not silently store an untraceable entry."""
    record_csp(authed_page)
    _open_a_mapping(authed_page)

    if authed_page.locator(SOURCE_INPUT).count() == 0:
        pytest.skip("current user cannot write mappings on this deployment")

    authed_page.fill(SOURCE_INPUT, "zz-not-a-real-control")
    authed_page.fill(TARGET_INPUT, "zz-also-not-real")

    relationship = "select[name='control_mapping_entry[relationship]']"
    if authed_page.locator(relationship).count():
        authed_page.select_option(relationship, "equivalent")

    authed_page.click("input[type='submit'][value='Add Entry']")
    authed_page.wait_for_load_state("networkidle")

    body = authed_page.locator("body").inner_text()
    assert "zz-not-a-real-control" not in body or "not a control" in body.lower(), (
        "an entry naming a control that exists in neither catalog was accepted "
        "and is now stored — it will export as though it were real"
    )

    assert_no_csp_violations(authed_page, during="rejected mapping entry submit")
