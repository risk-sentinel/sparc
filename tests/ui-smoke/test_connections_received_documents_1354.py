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

Push and Class A: an administrator pins an Ed25519 public key (the connection
then accepts pushes, shown by its fingerprint), records a Class A framework
and date (expiring 12 months later), and adds a Class A material, which lands
on the boundary as a received document that is not schema-checked. The web
and API request specs (spec/requests/exchange_push_class_a_web_spec.rb,
spec/requests/api/v1/exchange_certification_materials_spec.rb) prove the
guards; the signed push itself is spec/requests/api/v1/exchange_pushes_spec.rb.

Selectors verified against app/views/admin/exchange_connections/*.html.erb,
app/views/received_documents/*.html.erb and the Evidence section of
app/views/authorization_boundaries/show.html.erb.
"""

from __future__ import annotations

import calendar
import datetime
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
# The public half of an Ed25519 key, as an administrator pastes it (PEM); its
# private half was discarded. SHA-256 of its raw 32 bytes begins with
# PUSH_KEY_FINGERPRINT, which is what the page shows instead of the key.
PUSH_KEY_PEM = (
    "-----BEGIN PUBLIC KEY-----\n"
    "MCowBQYDK2VwAyEAuWhxBteD/Eh0qu0ua2crDexSK4FZI9OGm+G/DiYWFq0=\n"
    "-----END PUBLIC KEY-----\n"
)
PUSH_KEY_FINGERPRINT = "fbe1cf1ce6bb49bf"


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


def _boundary_path(boundary) -> str:
    """Boundary pages are addressed by slug; the numeric id is a 404."""
    return f"/authorization_boundaries/{boundary.get('slug') or boundary['id']}"


def _confirm(page) -> None:
    """turbo_confirm opens SPARC's CSP-safe confirm modal, not a native dialog."""
    confirm = page.locator("#sparc-confirm-modal-confirm")
    confirm.wait_for(state="visible", timeout=5000)
    confirm.click()


def _upload(page, boundary, path: str) -> None:
    """Upload through the dropzone on the boundary's Received documents page."""
    page.goto(f"{_boundary_path(boundary)}/received_documents")
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
    delete.first.click()
    _confirm(page)
    page.wait_for_url("**/admin/exchange_connections", timeout=15000)


def test_connections_screens_render_clean(authed_page):
    page = authed_page
    record_csp(page)
    page.goto("/admin/exchange_connections")
    page.wait_for_load_state("networkidle")
    assert page.get_by_role("heading", name="Connections").count() == 1
    assert page.locator("[data-testid='connections-table']").count() == 1

    click_and_assert_clean(page, "[data-testid='new-connection']", during="opening New Connection")
    # Turbo Drive changes the address after its fetch, not as a navigation.
    page.wait_for_url("**/admin/exchange_connections/new", timeout=15000)
    page.wait_for_load_state("networkidle")
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
        page.locator("[data-testid='pull-now']").click()
        _confirm(page)
        error = page.locator("[data-testid='source-last-error']")
        error.first.wait_for(state="visible", timeout=30000)
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
        page.goto(_boundary_path(boundary))
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
        _upload(page, boundary, _vdr_file(description))
        assert "Pending review" in page.locator("[data-testid='received-metadata']").inner_text()
        assert page.locator("[data-testid='validation-errors']").count() == 0
        sha = page.locator("[data-testid='received-sha256']").inner_text().strip()
        assert re.fullmatch(r"[0-9a-f]{64}", sha), sha

        page.goto(f"{_boundary_path(boundary)}/received_documents")
        page.wait_for_load_state("networkidle")
        assert page.locator("[data-testid='received-stream']").count() >= 1
        assert "vulnerability-detail-report" in page.locator("body").inner_text()

        # A required field left blank: stored, invalid, its error shown.
        _upload(page, boundary, _vdr_file("   "))
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
        _upload(user, boundary, _vdr_file(f"Uploader's finding {uuid.uuid4().hex[:8]}"))
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


# ── push keys, Class A and its materials (#1354) ───────────────────────────


def _twelve_months_after(day: datetime.date) -> datetime.date:
    """Rails' `date + 12.months`: the same day next year, or the month's last day."""
    year = day.year + 1
    return day.replace(year=year, day=min(day.day, calendar.monthrange(year, day.month)[1]))


def _show_url(connection_id) -> re.Pattern:
    return re.compile(rf"/admin/exchange_connections/{connection_id}$")


def _new_connection(page, boundary, certification_class: str, **class_a) -> str:
    """Register a connection through the New Connection form; returns its id.

    `class_a` may carry `framework` and `certified_on` for a Class A connection.
    """
    page.goto("/admin/exchange_connections/new")
    page.wait_for_load_state("networkidle")
    page.fill("#exchange_connection_name", f"phase2-ui-conn-{uuid.uuid4().hex[:8]}")
    page.select_option("#exchange_connection_authorization_boundary_id", str(boundary["id"]))
    page.select_option("#exchange_connection_certification_class", certification_class)
    page.fill("#exchange_connection_root_url", UNREACHABLE_ROOT)
    page.select_option("#exchange_connection_auth_scheme", "none")
    if class_a:
        page.select_option("#exchange_connection_class_a_framework", class_a["framework"])
        page.fill("#exchange_connection_class_a_certified_on", class_a["certified_on"])
    click_and_assert_clean(
        page, "[data-testid='save-connection']", during="creating a connection"
    )
    page.wait_for_url(re.compile(r"/admin/exchange_connections/\d+$"), timeout=15000)
    page.wait_for_load_state("networkidle")
    return re.search(r"/admin/exchange_connections/(\d+)$", page.url).group(1)


def test_push_key_and_class_a_are_set_on_edit(authed_page):
    page = authed_page
    record_csp(page)
    boundary = create_boundary()
    connection_id = None
    certified_on = datetime.date.today() - datetime.timedelta(days=30)
    expires_on = _twelve_months_after(certified_on)
    try:
        connection_id = _new_connection(page, boundary, "B")
        push_card = page.locator("[data-testid='push-card']")
        assert "Not accepting pushes" in push_card.inner_text()
        assert "Not Class A" in page.locator("[data-testid='class-a-card']").inner_text()

        click_and_assert_clean(
            page,
            f"a[href$='/admin/exchange_connections/{connection_id}/edit']",
            during="opening Edit",
        )
        page.wait_for_url(f"**/admin/exchange_connections/{connection_id}/edit", timeout=15000)
        page.wait_for_load_state("networkidle")
        assert page.get_by_label("Ed25519 public keys").count() == 1

        page.select_option("#exchange_connection_certification_class", "A")
        page.select_option("#exchange_connection_class_a_framework", "fedramp_rev5")
        page.fill("#exchange_connection_class_a_certified_on", certified_on.isoformat())
        page.get_by_label("Ed25519 public keys").fill(PUSH_KEY_PEM)
        click_and_assert_clean(page, "[data-testid='save-connection']", during="saving the edit")
        page.wait_for_url(_show_url(connection_id), timeout=15000)
        page.wait_for_load_state("networkidle")
        assert "Connection updated." in page.locator(".flash-container .alert-success").inner_text()

        push = push_card.inner_text()
        assert "Accepting pushes" in push and "Not accepting pushes" not in push, push
        keys = page.locator("[data-testid='push-keys']").inner_text()
        assert re.search(r"SHA-256 [0-9a-f]{16}", keys), keys
        assert f"SHA-256 {PUSH_KEY_FINGERPRINT}" in keys, keys
        assert "BEGIN PUBLIC KEY" not in push, "the pasted PEM is shown instead of its fingerprint"

        class_a = page.locator("[data-testid='class-a-card']").inner_text()
        assert "FedRAMP Rev5" in class_a, class_a
        assert certified_on.isoformat() in class_a, class_a
        assert "Current" in class_a, class_a
        expiry = page.locator("[data-testid='class-a-expiry']").inner_text()
        assert expires_on.isoformat() in expiry, expiry
        assert re.search(r"\d+ days? left", expiry), expiry
        assert page.locator("[data-testid='class-a-material-form']").count() == 1, (
            "a Class A connection is not offered the materials form"
        )
        assert_no_csp_violations(page, during="setting a push key and Class A on a connection")
    finally:
        _delete_connection(page, connection_id)
        delete_doc("authorization_boundaries", boundary.get("slug") or boundary["id"])


def _material_file() -> str:
    with tempfile.NamedTemporaryFile("wb", suffix=".pdf", prefix="soc2-", delete=False) as f:
        f.write(f"%PDF-1.7\n% phase2 SOC 2 Type II report {uuid.uuid4().hex}\n%%EOF\n".encode())
        return f.name


def test_class_a_material_is_added_and_lands_unchecked(authed_page):
    page = authed_page
    record_csp(page)
    boundary = create_boundary()
    connection_id = None
    certified_on = datetime.date.today() - datetime.timedelta(days=10)
    try:
        connection_id = _new_connection(
            page, boundary, "A", framework="soc2_type2", certified_on=certified_on.isoformat()
        )
        # A fresh load, so the success flash asserted below is this add's.
        page.goto(f"/admin/exchange_connections/{connection_id}")
        page.wait_for_load_state("networkidle")
        assert page.locator("[data-testid='class-a-materials']").count() == 0

        form = page.locator("[data-testid='class-a-material-form']")
        assert form.count() == 1, "a Class A connection is not offered the materials form"
        form.locator("select[name='kind']").select_option("soc2_report")
        path = _material_file()
        form.locator("input[type='file'][name='file']").set_input_files(path)
        click_and_assert_clean(
            page, "[data-testid='add-class-a-material']", during="adding a Class A material"
        )
        # The redirect lands on this same page (at #class-a), so wait for what
        # it brings rather than for the address.
        flash = page.locator(".flash-container .alert-success", has_text="Added.")
        flash.wait_for(state="visible", timeout=15000)
        assert boundary["name"] in flash.inner_text(), flash.inner_text()
        assert page.locator(".flash-container .alert-danger").count() == 0

        materials = page.locator("[data-testid='class-a-materials']")
        assert materials.count() == 1, "the added material is not listed"
        listed = materials.inner_text()
        filename = path.rsplit("/", 1)[-1]
        assert "SOC 2 Type II complete report" in listed, listed
        assert filename in listed, listed
        assert "Pending review" in listed, listed

        # Its received-document page on the boundary: kept, not schema-checked.
        click_and_assert_clean(
            page, materials.get_by_role("link", name=filename), during="opening the material"
        )
        page.wait_for_url(re.compile(r"/received_documents/\d+$"), timeout=15000)
        page.wait_for_load_state("networkidle")
        assert page.locator("[data-testid='material-not-checked']").count() == 1, (
            "the material's page does not say it is not schema-checked"
        )
        heading = page.get_by_role("heading", level=1, name="SOC 2 Type II complete report")
        assert heading.count() == 1, "the material's page is not titled by its kind"
        assert "Pending review" in page.locator("[data-testid='received-metadata']").inner_text()
        assert page.locator("[data-testid='validation-errors']").count() == 0
        assert page.locator("[data-testid='received-push']").count() == 0, (
            "an uploaded material is shown as a push"
        )
        assert_no_csp_violations(page, during="adding a Class A material and opening it")
    finally:
        _delete_connection(page, connection_id)
        delete_doc("authorization_boundaries", boundary.get("slug") or boundary["id"])
