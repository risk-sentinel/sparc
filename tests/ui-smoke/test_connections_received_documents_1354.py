"""UI smoke: Settings → Connections and a boundary's Received documents (#1354).

Owner, 2026-11-20: connections are registered in Settings, by administrators,
under their own permission; received documents and their reviews live in the
boundary's evidence area. Every document, pulled or uploaded, is validated
(its schema, and every required field filled in); one that fails is stored
with its errors, shown. Only a byte-identical re-delivery skips review, and
the person who uploaded a version cannot decide it.

These checks never reach the internet. The connection they create points at
a `.invalid` host (RFC 6761: never resolves), so Test connection and Pull now
fail fast at DNS and the test asserts the recorded error is shown.

Everything created is `phase2-ui-*` named and removed in teardown: the
connection through its own Delete button, then the boundary (which removes
its received documents) through the API.

Request-layer proof of both directions of every guard, the write-only
credential and separation of duties: spec/requests/exchange_connections_web_spec.rb
and spec/requests/received_documents_web_spec.rb.

Selectors verified against app/views/admin/exchange_connections/*.html.erb,
app/views/received_documents/*.html.erb and the Evidence section of
app/views/authorization_boundaries/show.html.erb.
"""

from __future__ import annotations

import json
import re
import tempfile
import uuid

import pytest

from _api_setup import create_boundary, delete_doc, get_json
from helpers import assert_no_csp_violations, click_and_assert_clean, record_csp

pytestmark = pytest.mark.authenticated

UNREACHABLE_ROOT = "https://phase2-smoke-1354.invalid/"
THROWAWAY_TOKEN = "phase2-smoke-throwaway-token"  # gitleaks:allow


def _vdr(description: str) -> dict:
    """A FedRAMP Vulnerability Detail Report, complete unless `description` is blank."""
    return {
        "certificationPackageOverviewUri": "https://provider.example/package/cpo.json",
        "reportPeriod": {"from": "2026-10-01T00:00:00Z", "to": "2026-10-31T23:59:59Z"},
        "vulnerabilities": [
            {
                "providerTrackingId": "VULN-1",
                "detection": {"detectedAt": "2026-10-02T10:00:00Z", "detectionSource": "scanner"},
                "vulnerabilityDescription": description,
            }
        ],
    }


def _vdr_file(description: str) -> str:
    with tempfile.NamedTemporaryFile("w", suffix=".json", prefix="vdr-", delete=False) as f:
        json.dump(_vdr(description), f)
        return f.name


def _accept_dialogs(page) -> None:
    """Pull now and Delete ask for confirmation (data-turbo-confirm)."""
    page.on("dialog", lambda dialog: dialog.accept())


def _upload(page, boundary_id, path: str) -> None:
    """Upload through the dropzone on the boundary's Received documents page."""
    page.goto(f"/authorization_boundaries/{boundary_id}/received_documents")
    page.wait_for_load_state("networkidle")
    form = page.locator("[data-testid='received-upload-form']")
    assert form.count() == 1, "the upload card is not offered to an exchange.upload holder"
    form.locator("input[type='file']").set_input_files(path)
    with page.expect_navigation(wait_until="networkidle"):
        page.locator("[data-testid='received-upload-submit']").click()
    opened = re.search(r"/received_documents/\d+$", page.url)
    assert opened, f"upload did not open the version: {page.url}"


def _delete_connection(page, connection_id) -> None:
    if not connection_id:
        return
    page.goto(f"/admin/exchange_connections/{connection_id}")
    page.wait_for_load_state("networkidle")
    delete = page.get_by_role("button", name="Delete")
    if delete.count() == 0:
        return
    with page.expect_navigation(wait_until="networkidle"):
        delete.first.click()


def test_connections_screens_render_clean(authed_page):
    page = authed_page
    record_csp(page)
    page.goto("/admin/exchange_connections")
    page.wait_for_load_state("networkidle")
    assert page.get_by_role("heading", name="Connections").count() == 1
    assert page.locator("[data-testid='connections-table']").count() == 1

    click_and_assert_clean(page, "[data-testid='new-connection']", during="opening New Connection")
    page.wait_for_load_state("networkidle")
    assert page.url.endswith("/admin/exchange_connections/new"), page.url
    assert page.locator("[data-testid='connection-form']").count() == 1
    assert "not set" in page.locator("[data-testid='credential-state']").inner_text()
    assert_no_csp_violations(page, during="the Connections screens")


def test_connections_are_offered_in_settings(authed_page):
    """The admin dropdown leads here, next to Roles (owner, 2026-11-20: dropdown only)."""
    page = authed_page
    record_csp(page)
    page.goto("/")
    page.wait_for_load_state("networkidle")
    link = page.locator("nav.navbar a.dropdown-item[href='/admin/exchange_connections']")
    assert link.count() == 1, "the admin dropdown's Connections item is missing"
    assert page.locator("nav.sparc-sidebar a[href='/admin/exchange_connections']").count() == 0, (
        "Connections belongs in the admin dropdown only, not the sidebar"
    )
    menu = page.locator(
        "nav.navbar li.dropdown:has(a.dropdown-item[href='/admin/exchange_connections'])"
    )
    menu.locator(":scope > .dropdown-toggle").first.click()
    link.wait_for(state="visible", timeout=5000)
    with page.expect_navigation(wait_until="networkidle"):
        link.click()
    assert page.url.rstrip("/").endswith("/admin/exchange_connections"), page.url
    assert_no_csp_violations(page, during="reaching Connections from the navigation")


def test_create_connection_test_and_pull_record_the_error(authed_page):
    page = authed_page
    _accept_dialogs(page)
    record_csp(page)
    boundary = create_boundary()
    name = f"phase2-ui-conn-{uuid.uuid4().hex[:8]}"
    connection_id = None
    try:
        page.goto("/admin/exchange_connections/new")
        page.wait_for_load_state("networkidle")
        page.fill("#exchange_connection_name", name)
        page.select_option("#exchange_connection_authorization_boundary_id", str(boundary["id"]))
        page.fill("#exchange_connection_fedramp_id", "FR2401234567")
        page.select_option("#exchange_connection_certification_class", "B")
        page.select_option("#exchange_connection_certification_type", "20x")
        page.fill("#exchange_connection_root_url", UNREACHABLE_ROOT)
        page.select_option("#exchange_connection_auth_scheme", "bearer")
        page.fill("#exchange_connection_credential", THROWAWAY_TOKEN)
        with page.expect_navigation(wait_until="networkidle"):
            page.locator("[data-testid='save-connection']").click()

        match = re.search(r"/admin/exchange_connections/(\d+)$", page.url)
        assert match, f"create did not land on the connection: {page.url}"
        connection_id = match.group(1)
        settings = page.locator("[data-testid='connection-settings']").inner_text()
        assert "FR2401234567" in settings
        assert "phase2-smoke-1354.invalid" in settings, "the root host is not a pinned host"
        assert page.locator("[data-testid='credential-state']").inner_text().strip() == "Set"
        assert THROWAWAY_TOKEN not in page.content(), "the credential was rendered"

        # Register one document to pull.
        page.fill("#exchange_document_source_url", f"{UNREACHABLE_ROOT}package/vdr.json")
        page.select_option("#exchange_document_source_format", "fedramp")
        with page.expect_navigation(wait_until="networkidle"):
            page.locator("[data-testid='add-source']").click()
        sources = page.locator("[data-testid='document-sources']").inner_text()
        assert "package/vdr.json" in sources, "the added document is not listed"

        # Test connection: fetches, stores nothing, shows why it failed.
        with page.expect_navigation(wait_until="networkidle"):
            page.locator("[data-testid='test-connection']").click()
        result = page.locator("[data-testid='test-result']")
        assert result.count() == 1, "no connection-test result shown"
        assert "Not reached" in result.inner_text()

        # Pull now: the failure is recorded on the document and the connection.
        with page.expect_navigation(wait_until="networkidle"):
            page.locator("[data-testid='pull-now']").click()
        page.wait_for_load_state("networkidle")
        error = page.locator("[data-testid='source-last-error']")
        assert error.count() == 1 and error.inner_text().strip(), "the pull's error is not shown"
        assert page.locator("[data-testid='connection-last-error']").count() == 1
        assert_no_csp_violations(page, during="creating, testing and pulling a connection")
    finally:
        _delete_connection(page, connection_id)
        delete_doc("authorization_boundaries", boundary.get("slug") or boundary["id"])


def test_received_documents_upload_valid_and_invalid(authed_page):
    page = authed_page
    record_csp(page)
    boundary = create_boundary()
    try:
        # Reached from the boundary page's Evidence section, as a user would.
        page.goto(f"/authorization_boundaries/{boundary['id']}")
        page.wait_for_load_state("networkidle")
        link = page.locator("[data-boundary-action='received_documents']")
        assert link.count() == 1, "the Evidence section's Received documents link is missing"
        with page.expect_navigation(wait_until="networkidle"):
            link.click()
        assert page.url.endswith("/received_documents"), page.url
        assert page.get_by_role("heading", name="Received documents").count() == 1
        dropzone = page.locator("[data-controller='dropzone']")
        assert dropzone.count() == 1, "the shared dropzone is missing"

        description = f"Outdated library {uuid.uuid4().hex[:8]}"
        _upload(page, boundary["id"], _vdr_file(description))
        assert "Pending review" in page.locator("[data-testid='received-metadata']").inner_text()
        assert page.locator("[data-testid='validation-errors']").count() == 0
        sha = page.locator("[data-testid='received-sha256']").inner_text().strip()
        assert re.fullmatch(r"[0-9a-f]{64}", sha), sha

        page.goto(f"/authorization_boundaries/{boundary['id']}/received_documents")
        page.wait_for_load_state("networkidle")
        assert page.locator("[data-testid='received-stream']").count() >= 1
        assert "vulnerability-detail-report" in page.locator("body").inner_text()

        # A required field left blank: stored, invalid, its error shown.
        _upload(page, boundary["id"], _vdr_file("   "))
        assert "Invalid" in page.locator("[data-testid='received-metadata']").inner_text()
        errors = page.locator("[data-testid='validation-errors']")
        assert errors.count() == 1, "the invalid version's errors are not shown"
        assert "/vulnerabilities/0/vulnerabilityDescription" in errors.inner_text()
        assert page.locator("[data-testid='review-accept']").count() == 0, (
            "an invalid version is offered for acceptance"
        )
        assert_no_csp_violations(page, during="uploading received documents")
    finally:
        delete_doc("authorization_boundaries", boundary.get("slug") or boundary["id"])


# ── separation of duties, as a genuine non-administrator ───────────────────


def _second_identity_id(user_page) -> int:
    user_page.goto("/profile/edit")
    user_page.wait_for_load_state("domcontentloaded")
    email = user_page.locator(".sparc-avatar + div .text-body-secondary").first.inner_text().strip()
    assert "@" in email, f"could not read the second identity's email: {email!r}"
    match = next((u for u in get_json(f"/api/v1/users?email={email}") if u["email"] == email), None)
    assert match, f"no user found for {email}"
    assert not match["admin"], "SPARC_SMOKE_USER_TOKEN must be a non-administrator for this check"
    return match["id"]


def _uploader_role_id() -> int:
    """A built-in boundary role that uploads AND reviews, so the page has to
    withhold the decision from the uploader rather than from a non-reviewer."""
    roles = get_json("/api/v1/roles?scope=authorization_boundary&items=100")
    fallback = None
    for role in roles:
        permissions = get_json(f"/api/v1/roles/{role['id']}")["permissions"]
        if "exchange.upload" in permissions and "evidence.read" in permissions:
            if "exchange.review" in permissions:
                return role["id"]
            fallback = fallback or role["id"]
    if fallback is None:
        pytest.skip("no boundary role holds exchange.upload on this instance")
    return fallback


def _grant(admin_page, user_id: int, boundary_id: int, role_id: int) -> None:
    admin_page.goto(f"/admin/users/{user_id}/edit")
    admin_page.wait_for_load_state("networkidle")
    field = "select[name='user[authorization_boundary_roles][][{}]']"
    admin_page.select_option(field.format("authorization_boundary_id"), str(boundary_id))
    admin_page.select_option(field.format("role_id"), str(role_id))
    with admin_page.expect_navigation(wait_until="networkidle"):
        admin_page.get_by_role("button", name="Save Changes").click()


def _revoke(admin_page, user_id: int, boundary_name: str) -> None:
    admin_page.goto(f"/admin/users/{user_id}/edit")
    admin_page.wait_for_load_state("networkidle")
    keep = admin_page.locator(f"input[aria-label^='Keep '][aria-label$=' on {boundary_name}']")
    if keep.count() == 0:
        return
    for i in range(keep.count()):
        keep.nth(i).set_checked(False)
    with admin_page.expect_navigation(wait_until="networkidle"):
        admin_page.get_by_role("button", name="Save Changes").click()


def test_review_is_withheld_from_the_uploader(authed_page, user_authed_page):
    admin, user = authed_page, user_authed_page
    role_id = _uploader_role_id()
    user_id = _second_identity_id(user)
    boundary = create_boundary()
    try:
        _grant(admin, user_id, boundary["id"], role_id)

        record_csp(user)
        _upload(user, boundary["id"], _vdr_file(f"Uploader's finding {uuid.uuid4().hex[:8]}"))
        version_url = user.url
        assert "Pending review" in user.locator("[data-testid='received-metadata']").inner_text()
        for control in ("review-accept", "review-respond", "review-reject"):
            assert user.locator(f"[data-testid='{control}']").count() == 0, (
                f"{control} is offered to the person who uploaded the version"
            )
        assert_no_csp_violations(user, during="the uploader viewing their own version")

        # Someone else may decide it: the controls exist, so their absence
        # above is the rule and not a broken page.
        record_csp(admin)
        admin.goto(version_url)
        admin.wait_for_load_state("networkidle")
        assert admin.locator("[data-testid='review-accept']").count() == 1, (
            "a reviewer who did not upload the version is not offered Accept"
        )
        assert_no_csp_violations(admin, during="a reviewer viewing a pending version")
    finally:
        _revoke(admin, user_id, boundary["name"])
        delete_doc("authorization_boundaries", boundary.get("slug") or boundary["id"])
