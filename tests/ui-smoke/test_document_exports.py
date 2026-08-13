"""Export/download smoke — every document type, every format.

Closes a systemic coverage gap: nothing in this suite ever exercised a download.
Page-load checks passed happily while XML export of every control catalog raised
TypeError (Kernel#select vs the OSCAL <select> element) — a 500 for any customer
clicking "Download XML", shipped across many releases undetected.

Page-load coverage is not export coverage. These tests fetch each export endpoint
through the authenticated browser context and PARSE the payload, so a 500, an
HTML error page, or malformed output all fail. XML is parsed strictly because
that is the format where a stray character or a bad element name makes the
artefact unusable to the customer's downstream tooling.

Skips cleanly for document types the instance has no rows for.
"""

from __future__ import annotations

import json
import xml.etree.ElementTree as ET

import pytest

from helpers import first_show_href

# (label, index path, export actions). Every resource declaring download_xml in
# config/routes.rb is represented.
RESOURCES = [
    ("control_catalog", "/control_catalogs"),
    ("cdef_document", "/cdef_documents"),
    ("poam_document", "/poam_documents"),
    ("profile_document", "/profile_documents"),
    ("ssp_document", "/ssp_documents"),
    ("sar_document", "/sar_documents"),
    ("sap_document", "/sap_documents"),
]

# Actions a resource does not declare in config/routes.rb.
#
# `control_catalogs` exports OSCAL only — it has never had `download_json`,
# which is a non-OSCAL internal dump. The cross-product below used to generate
# that pair anyway and the `resp.status == 404` skip never caught it: an
# unrouted path raises ActionController::RoutingError, which development
# renders as a 500, so it read as a broken export rather than a route that does
# not exist. Assert what exists instead of generating a case that cannot pass.
UNSUPPORTED = {
    "control_catalog": {"download_json"},
}

# action -> how to validate the payload.
#
# `download_oscal_validated` is the one the OSCAL export dropdown's JSON option
# actually links, on every card, row and show page — it was missing here, and
# that gap hid a 500: it was the only one of the four validating actions with no
# rescue for OscalValidationError. The two entries above it cannot catch that,
# because `download_json` is a non-OSCAL internal dump the UI never links and
# `download_oscal_unvalidated` skips validation by design.
FORMATS = {
    "download_json": "json",
    "download_oscal_unvalidated": "json",
    "download_oscal_validated": "json",
    "download_yaml": "yaml",
    "download_xml": "xml",
}


def _assert_parses(fmt: str, body: bytes, where: str):
    assert body, f"{where}: empty body"
    text = body.decode("utf-8", errors="replace")
    lowered = text.lstrip()[:200].lower()
    assert not lowered.startswith("<!doctype html"), (
        f"{where}: got an HTML page, not a {fmt} export — likely an error page"
    )

    if fmt == "json":
        try:
            json.loads(text)
        except ValueError as exc:
            raise AssertionError(f"{where}: invalid JSON — {exc}") from exc
    elif fmt == "xml":
        # Strict parse: this is exactly what the catalog export failed.
        try:
            ET.fromstring(text)
        except ET.ParseError as exc:
            raise AssertionError(f"{where}: malformed XML — {exc}") from exc
    elif fmt == "yaml":
        # No YAML parser in this suite's deps; assert it is not HTML/JSON noise
        # and carries a mapping-ish first line.
        assert ":" in text[:400], f"{where}: does not look like YAML"


EXPORT_CASES = [
    (label, index_path, action, fmt)
    for label, index_path in RESOURCES
    for action, fmt in sorted(FORMATS.items())
    if action not in UNSUPPORTED.get(label, set())
]


@pytest.mark.parametrize(
    "label,index_path,action,fmt",
    EXPORT_CASES,
    ids=[f"{c[0]}-{c[2]}" for c in EXPORT_CASES],
)
def test_export_endpoint_returns_parseable_payload(
    authed_page, base_url, label, index_path, action, fmt
):
    """Each export endpoint returns a parseable artefact, not a 500 or HTML."""
    page = authed_page
    href = first_show_href(page, index_path, index_path)
    if not href:
        pytest.skip(f"no {label} on this instance")

    url = f"{base_url}{href}/{action}"
    # Do NOT follow redirects: the app answers an export it cannot produce with a
    # 302 back to the show page carrying ?oscal_validation_failed=1. Following it
    # yields an HTML page and reports a misleading "malformed XML".
    resp = page.request.get(url, max_redirects=0)

    # 404 is acceptable only when the type genuinely lacks that action.
    if resp.status == 404:
        pytest.skip(f"{label} has no {action}")

    if resp.status in (301, 302, 303, 307, 308):
        location = resp.headers.get("location", "")
        assert "oscal_validation_failed" not in location, (
            f"{label} {action}: the UI offers this export but the document fails "
            f"OSCAL validation, so the user is bounced back with an error instead "
            f"of an artefact ({location})"
        )
        pytest.fail(f"{label} {action} redirected unexpectedly to {location}")

    assert resp.status == 200, (
        f"{label} {action} returned {resp.status} "
        f"(body starts: {resp.body()[:160]!r})"
    )
    _assert_parses(fmt, resp.body(), f"{label} {action}")


def test_catalog_xml_export_is_well_formed_oscal(authed_page, base_url):
    """Regression for the catalog XML TypeError.

    Catalogs are the only exported model containing OSCAL <select> (inside
    <param>), the element whose name collides with a real Ruby method. Asserts
    the document parses AND that a <select> is present and carries how-many as an
    ATTRIBUTE — it previously rendered as a child element, which is schema-invalid.
    """
    page = authed_page
    href = first_show_href(page, "/control_catalogs", "/control_catalogs")
    if not href:
        pytest.skip("no control catalog on this instance")

    resp = page.request.get(f"{base_url}{href}/download_xml")
    assert resp.status == 200, f"catalog XML export returned {resp.status}"

    root = ET.fromstring(resp.body().decode("utf-8"))
    ns = {"o": "http://csrc.nist.gov/ns/oscal/1.0"}

    selects = root.findall(".//o:select", ns)
    if not selects:
        pytest.skip("this catalog declares no parameters with <select>")

    assert "select_" not in resp.body().decode("utf-8"), (
        "disambiguating underscore leaked into element names"
    )
    with_attr = [s for s in selects if s.get("how-many")]
    assert with_attr, (
        "no <select> carries a how-many ATTRIBUTE — it is being emitted as a "
        "child element, which is schema-invalid OSCAL"
    )


def test_xml_download_control_is_wired(authed_page, base_url):
    """The real user path: open Export OSCAL, click XML, get a parseable file.

    The control is NOT a plain link — it is a dropdown item driven by Stimulus
    (`click->oscal-export#download`), which validates first and then downloads or
    falls back. An href-based selector matched nothing and skipped silently,
    which is how a 500 on this exact button went unnoticed. Driving the dropdown
    exercises the validate-then-download flow a customer actually performs.
    """
    page = authed_page
    href = first_show_href(page, "/control_catalogs", "/control_catalogs")
    if not href:
        pytest.skip("no control catalog on this instance")

    page.goto(f"{base_url}{href}", wait_until="networkidle")

    toggle = page.get_by_role("button", name="Export OSCAL").first
    assert toggle.count() > 0, "Export OSCAL control missing from the catalog screen"
    toggle.click()

    xml_item = page.locator(
        "a.dropdown-item[data-oscal-export-download-url-param*='download_xml']"
    ).first
    assert xml_item.count() > 0, "XML item missing from the Export OSCAL menu"

    with page.expect_download(timeout=90000) as dl:
        xml_item.click()

    path = dl.value.path()
    assert path, "download produced no file"
    with open(path, "rb") as fh:
        root = ET.fromstring(fh.read().decode("utf-8"))
    assert root is not None
