"""Admin-issued password recovery (#841).

A forgotten local-login password used to be unrecoverable: an admin could not
set one, no self-service flow existed, and the one password screen requires the
CURRENT password — which is exactly what has been lost. The only way back in was
a Rails console.

What this pins is the property that makes the fix safe, and which no unit test
can show on its own: the admin-issued temporary password **does not survive the
first sign-in**. The admin necessarily saw that credential, so the user must be
forced to replace it with one only they know before they can do anything.

Set-up runs through the API (`POST /api/v1/users/:id/password_reset`), which
also exercises the numeric-id addressing the admin UI uses, then the browser
drives the part that only a browser can prove — the forced-change redirect and
the old credential dying.

Needs SPARC_SMOKE_SA_TOKEN (admin) and skips without it.
"""

from __future__ import annotations

import os
import uuid
from collections.abc import Iterator

import httpx
import pytest

from helpers import smoke_tls_verify

SA_TOKEN = os.environ.get("SPARC_SMOKE_SA_TOKEN")

TEMP_PASSWORD_FIELD = "#current_password"
NEW_PASSWORD = "UserChosenPassword-2026!"


@pytest.fixture
def api(base_url: str) -> Iterator[httpx.Client]:
    if not SA_TOKEN:
        pytest.skip("SPARC_SMOKE_SA_TOKEN not set — skipping admin password recovery")

    with httpx.Client(
        base_url=base_url,
        headers={"Authorization": f"Bearer {SA_TOKEN}"},
        verify=smoke_tls_verify(),
        timeout=30,
    ) as client:
        yield client


@pytest.fixture
def target_user(api: httpx.Client) -> Iterator[dict]:
    """A throwaway local-login user to lock out and recover."""
    suffix = uuid.uuid4().hex[:8]
    payload = {
        "user": {
            "email": f"pwrecovery-{suffix}@example.gov",
            "first_name": "Password",
            "last_name": "Recovery",
            "password": f"InitialPassword-{suffix}!",
            "password_confirmation": f"InitialPassword-{suffix}!",
        }
    }
    resp = api.post("/api/v1/users", json=payload)
    if resp.status_code not in (200, 201):
        pytest.skip(f"could not create a test user ({resp.status_code}): {resp.text[:200]}")

    user = resp.json().get("data") or resp.json()
    try:
        yield user
    finally:
        api.delete(f"/api/v1/users/{user['id']}")


def _sign_in(page, base_url: str, email: str, password: str) -> None:
    """Sign in on the LOCAL tab.

    The login page carries one submit button per enabled auth method, so
    clicking "a submit button" can post the wrong form. Pressing Enter in the
    password field submits the form that field belongs to, whichever tab it is.
    """
    page.goto(f"{base_url}/login", wait_until="networkidle")

    proceed = page.locator("button[data-action='consent-banner#proceed']")
    if proceed.count():
        proceed.first.click()
        page.wait_for_timeout(400)

    # Scope to the LOCAL panel. The page renders one form per enabled auth
    # method, all with a submit button, so an unscoped click posts whichever
    # form happens to match first — which silently does nothing useful.
    local = page.locator("#tab-local")
    local.locator("#email").fill(email)
    local.locator("#password").fill(password)
    local.locator("form[action='/login'] button[type=submit]").first.click()

    # Turbo submits the form over fetch and applies the redirect itself, so
    # `networkidle` can settle while the URL is still /login. Wait for the
    # navigation to actually land — on failure it stays on /login and this
    # times out, which is the honest signal either way.
    try:
        page.wait_for_url(lambda url: "/login" not in url, timeout=10_000)
    except Exception:
        pass  # leave the assertion in the test to report what happened
    page.wait_for_load_state("networkidle")


def _set_new_password(page, current: str, new: str) -> None:
    """Complete the forced-change screen. Same Turbo caveat as _sign_in."""
    page.fill(TEMP_PASSWORD_FIELD, current)
    page.fill("#new_password", new)
    page.fill("#new_password_confirmation", new)
    page.locator("form[action='/password'] button[type=submit], form[action='/password'] input[type=submit]").first.click()
    try:
        page.wait_for_url(lambda url: "/password/edit" not in url, timeout=10_000)
    except Exception:
        pass
    page.wait_for_load_state("networkidle")


@pytest.mark.parametrize("mode", ["temporary"])
def test_admin_issued_password_must_be_changed_at_first_sign_in(
    page, base_url: str, api: httpx.Client, target_user: dict, mode: str
) -> None:
    # Addressed by numeric id, the same way the admin UI does.
    resp = api.post(f"/api/v1/users/{target_user['id']}/password_reset", json={"mode": mode})
    assert resp.status_code == 201, resp.text

    data = resp.json()["data"]
    temporary = data["temporary_password"]
    assert temporary, "the API returned no credential for the admin to hand over"
    assert data["must_change_at_next_login"] is True

    # 1. The temporary password works...
    _sign_in(page, base_url, target_user["email"], temporary)
    assert "/login" not in page.url, (
        f"the temporary password did not sign the user in (landed on {page.url})"
    )

    # 2. ...but only as far as the forced-change screen.
    assert "/password/edit" in page.url, (
        "the user was NOT forced to change an admin-issued password. The admin saw this "
        f"credential, so it must not survive first use (landed on {page.url})"
    )

    # 3. The user replaces it with one the admin never saw.
    _set_new_password(page, temporary, NEW_PASSWORD)
    assert "/password/edit" not in page.url, (
        f"setting a new password did not clear the forced-change state ({page.url})"
    )


def test_the_temporary_password_dies_once_replaced(
    page, base_url: str, api: httpx.Client, target_user: dict
) -> None:
    """The whole point: the credential the admin held stops working."""
    resp = api.post(f"/api/v1/users/{target_user['id']}/password_reset", json={"mode": "temporary"})
    assert resp.status_code == 201, resp.text
    temporary = resp.json()["data"]["temporary_password"]

    _sign_in(page, base_url, target_user["email"], temporary)
    _set_new_password(page, temporary, NEW_PASSWORD)

    # A fresh context so no session carries over.
    context = page.context.browser.new_context(ignore_https_errors=True)
    fresh = context.new_page()
    try:
        _sign_in(fresh, base_url, target_user["email"], temporary)
        assert "/login" in fresh.url, (
            "the admin-issued temporary password still works after the user replaced it"
        )
    finally:
        context.close()


def test_a_suspended_user_is_not_handed_a_working_credential(
    api: httpx.Client, target_user: dict
) -> None:
    """Reactivating is a deliberate act; issuing a credential must not bypass it."""
    api.patch(f"/api/v1/users/{target_user['id']}", json={"user": {"status": "suspended"}})

    resp = api.post(f"/api/v1/users/{target_user['id']}/password_reset", json={"mode": "temporary"})

    assert resp.status_code == 422, (
        f"a suspended account was issued a working password ({resp.status_code})"
    )
