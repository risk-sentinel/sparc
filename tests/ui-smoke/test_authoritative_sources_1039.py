"""#1039 — the authoritative-sources lifecycle, driven the way a person does it.

The surface used to be create-only: a typo in an href was permanent, provenance
could not be recorded, and the controls a source supports were invisible on the
screen that shows the source.

These are interaction checks, not render checks. Every one asserts zero CSP
violations, because render-time checks cannot see inline-handler breakage — it
only shows up on click.
"""

from __future__ import annotations

import re

import pytest

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

INDEX = "/authoritative_sources"


def _first_source(page):
    """The index links each source; take the first show URL it offers."""
    page.goto(INDEX)
    page.wait_for_load_state("networkidle")
    link = page.locator(f"a[href^='{INDEX}/']").first
    if link.count() == 0:
        pytest.skip("no authoritative sources on this instance")
    href = link.get_attribute("href")
    # skip /new — it is not a record
    if href.endswith("/new"):
        links = page.locator(f"a[href^='{INDEX}/']")
        for i in range(links.count()):
            h = links.nth(i).get_attribute("href")
            if h and not h.endswith("/new"):
                return h
        pytest.skip("no source records on this instance")
    return href


def test_a_source_can_be_edited_and_the_change_sticks(authed_page):
    """The core of #1039: the surface was create-only, so nothing could be fixed."""
    record_csp(authed_page)
    href = _first_source(authed_page)

    authed_page.goto(f"{href}/edit")
    assert authed_page.locator("#back_matter_resource_title").count() == 1, \
        "the edit screen must exist — this whole issue is that it did not"

    marker = "Platform Security Engineering"
    authed_page.fill("#back_matter_resource_provided_by_team", marker)
    authed_page.fill("#back_matter_resource_provided_by_contact", "soc@agency.gov")
    authed_page.click("input[type=submit][value='Save changes']")
    authed_page.wait_for_load_state("networkidle")

    # Read it back from a FRESH load. Asserting against the page the form
    # redirected to would pass on a form that echoed input without saving.
    authed_page.goto(f"{href}/edit")
    assert authed_page.input_value("#back_matter_resource_provided_by_team") == marker, \
        "provided_by_team did not persist"
    assert_no_csp_violations(authed_page)


def test_the_contact_field_ghosts_its_expected_shape(authed_page):
    """Owner-specified: the field hints email-or-phone rather than validating it.

    An external provider's contact is frequently neither, and a validation that
    rejects a real answer is worse than none.
    """
    record_csp(authed_page)
    authed_page.goto(f"{INDEX}/new")

    placeholder = authed_page.get_attribute("#back_matter_resource_provided_by_contact", "placeholder")
    assert placeholder, "the contact field must ghost its expected shape"
    assert "@" in placeholder and re.search(r"\d", placeholder), \
        f"the ghost should show BOTH an email and a phone shape, got {placeholder!r}"

    field_type = authed_page.get_attribute("#back_matter_resource_provided_by_contact", "type")
    assert field_type == "text", \
        "the contact must NOT be type=email — a phone number is equally valid"
    assert_no_csp_violations(authed_page)


def test_show_surfaces_provenance_and_dates(authed_page):
    """The data existed and was never displayed. 'Is this current?' is the
    difference between a citation and a guess."""
    record_csp(authed_page)
    href = _first_source(authed_page)

    authed_page.goto(href)
    body = authed_page.locator("body").inner_text()
    for label in ("Provided by", "Contact", "Added", "Last updated"):
        assert label in body, f"the show page must surface {label!r}"
    assert_no_csp_violations(authed_page)


def test_archive_is_reversible_and_says_archive_not_delete(authed_page):
    """The ruling: destroy ARCHIVES. A label must not promise something the
    system deliberately does not do, and Restore has to be reachable or archive
    is a one-way door."""
    record_csp(authed_page)
    href = _first_source(authed_page)
    authed_page.goto(href)

    archive = authed_page.get_by_role("button", name=re.compile(r"^Archive$"))
    if archive.count() == 0:
        pytest.skip("this account cannot write authoritative sources")

    assert authed_page.get_by_role("button", name=re.compile(r"^Delete$")).count() == 0, \
        "the control must be labelled Archive — it does not delete"

    archive.first.click()
    # `turbo_confirm` renders SPARC's CSP-safe Bootstrap modal, NOT a native
    # dialog — the app removed inline handlers in #650, so `page.on("dialog")`
    # never fires here and the click appears to do nothing.
    confirm = authed_page.locator("#sparc-confirm-modal-confirm")
    confirm.wait_for(state="visible", timeout=5000)
    # Turbo submits the archive as a fetch, and `networkidle` can resolve before
    # the server has processed it — the next `goto` then renders the STILL-ACTIVE
    # source and the Restore assertion fails against a stale page. Synchronise on
    # the archive response itself.
    # `button_to method: :delete` posts a form with a `_method` override, so the
    # wire method is POST — matching on DELETE waits for a request that never
    # happens.
    with authed_page.expect_response(
        lambda r: r.request.method == "POST" and "/authoritative_sources/" in r.url
    ):
        confirm.click()
    authed_page.wait_for_load_state("networkidle")

    authed_page.goto(href)
    restore = authed_page.get_by_role("button", name=re.compile(r"^Restore$"))
    assert restore.count() == 1, \
        "an archived source must still be reachable and offer Restore"

    with authed_page.expect_response(
        lambda r: r.request.method == "POST" and "/restore" in r.url
    ):
        restore.first.click()
    authed_page.wait_for_load_state("networkidle")
    authed_page.goto(href)
    assert authed_page.get_by_role("button", name=re.compile(r"^Archive$")).count() == 1, \
        "restore did not return the source to active"
    assert_no_csp_violations(authed_page)


def test_edit_offers_catalog_scoped_control_references(authed_page):
    """The edit screen promised "which controls it supports" and offered no way
    to set them — linking existed only on `show`. It also asked for a raw row id
    ("e.g. 4821") and named no catalog, which is unanswerable with Rev 4 and
    Rev 5 both loaded.
    """
    record_csp(authed_page)
    href = _first_source(authed_page)
    authed_page.goto(f"{href}/edit")
    authed_page.wait_for_load_state("networkidle")

    assert authed_page.locator("#control_catalog_id").count() == 1, \
        "edit has no catalog selector — a control id alone is ambiguous across revisions"
    assert authed_page.locator("#control_identifier").count() == 1, \
        "edit has no control-id field"

    # The raw-row-id prompt must be gone: an assessor types AC-2, not 4821.
    placeholder = authed_page.locator("#control_identifier").get_attribute("placeholder") or ""
    assert "4821" not in placeholder, f"still prompting for a database id: {placeholder!r}"

    # The catalog select must actually be populated, or the field is decoration.
    options = authed_page.locator("#control_catalog_id option")
    assert options.count() >= 1, "catalog selector is empty"

    assert_no_csp_violations(authed_page)


def test_source_url_carries_a_readable_slug(authed_page):
    """/authoritative_sources/2500/edit named nothing. The path now carries an
    `id-slug`, and the bare id must still resolve so stored links keep working.
    """
    record_csp(authed_page)
    href = _first_source(authed_page)
    assert re.search(r"/authoritative_sources/\d+-[a-z0-9-]+$", href), \
        f"index still links a bare numeric id: {href}"

    numeric = re.sub(r"^(/authoritative_sources/\d+).*$", r"\1", href)
    authed_page.goto(numeric)
    authed_page.wait_for_load_state("networkidle")
    assert authed_page.locator("h1, h2").first.count() == 1, "bare numeric id no longer resolves"

    assert_no_csp_violations(authed_page)


def test_a_control_reference_can_actually_be_added(authed_page):
    """Presence of the fields is not the feature. This types a control id the way
    an assessor would — "AC-2", not a row id — and checks the reference lands
    with the catalog it came from, which is what disambiguates Rev 4 from Rev 5.
    """
    record_csp(authed_page)
    href = _first_source(authed_page)
    authed_page.goto(f"{href}/edit")
    authed_page.wait_for_load_state("networkidle")

    if authed_page.locator("#control_identifier").count() == 0:
        pytest.skip("this account cannot write authoritative sources")

    catalog = authed_page.locator("#control_catalog_id")
    catalog_label = catalog.locator("option").first.inner_text().strip()
    catalog.select_option(index=0)
    authed_page.locator("#control_identifier").fill("AC-2")

    with authed_page.expect_response(
        lambda r: r.request.method == "POST" and "/link_control" in r.url
    ):
        authed_page.get_by_role("button", name=re.compile(r"^Add reference$")).click()

    # Re-fetch rather than trusting the post-redirect render: Turbo settles the
    # navigation asynchronously and `networkidle` can return on the pre-submit
    # page, which reads as "nothing happened" when the row was in fact created.
    authed_page.goto(f"{href}/edit")
    authed_page.wait_for_load_state("networkidle")

    body = authed_page.locator("body").inner_text()
    assert "No control references yet." not in body, \
        "AC-2 did not resolve in the selected catalog — the reference was not added"

    # Re-running must not break on the uniqueness rule, so this asserts the end
    # state (the reference is listed), not that this run created it.
    assert re.search(r"AC-2", body, re.I), "the reference is not listed after adding it"
    assert catalog_label.split()[0] in body, \
        f"reference added but its catalog ({catalog_label!r}) is not shown beside it"

    assert_no_csp_violations(authed_page)
