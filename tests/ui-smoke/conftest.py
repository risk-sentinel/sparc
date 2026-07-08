"""Pytest + Playwright configuration for the SPARC UI smoke suite.

Targets a live deployment (default: the build environment at
https://sparc.risk-sentinel.org). Unauthenticated tests (login page, CSP)
run with no credentials; authenticated tests acquire a Rails session by
bridging a service-account bearer token through the v1.8.4 cookie-bridge
endpoint POST /api/v1/sessions/from_token (#573).
"""

from __future__ import annotations

import os
from urllib.parse import urlparse

import httpx
import pytest

BASE_URL = os.environ.get(
    "SPARC_SMOKE_BASE_URL", "https://sparc.risk-sentinel.org"
).rstrip("/")
SA_TOKEN = os.environ.get("SPARC_SMOKE_SA_TOKEN")
# Optional second (non-admin) identity, used by the review/approval flows that
# need a submitter distinct from the approver (separation of duties, #643).
# Tests that need it skip when it's unset.
USER_TOKEN = os.environ.get("SPARC_SMOKE_USER_TOKEN")
# Optional override. When unset, the session cookie is auto-detected from the
# bridge response — Rails derives the name from the app module, which is
# `_ssp_tpr_manager_session` for SPARC's legacy module name. Auto-detection
# keeps the suite correct if that ever changes.
SESSION_COOKIE_NAME = os.environ.get("SPARC_SESSION_COOKIE_NAME")


@pytest.fixture(scope="session")
def base_url() -> str:
    return BASE_URL


@pytest.fixture
def browser_context_args(browser_context_args):
    """Resolve relative page.goto() paths against the target deployment."""
    return {**browser_context_args, "base_url": BASE_URL}


def _bridge_token_to_cookie(token: str) -> dict:
    """Exchange a bearer token for a Rails session cookie via #573."""
    resp = httpx.post(
        f"{BASE_URL}/api/v1/sessions/from_token",
        headers={"Authorization": f"Bearer {token}"},
        timeout=30.0,
    )
    assert resp.status_code == 204, (
        f"cookie-bridge POST /api/v1/sessions/from_token returned "
        f"{resp.status_code} (expected 204): {resp.text[:200]}"
    )
    available = list(resp.cookies.keys())
    name = SESSION_COOKIE_NAME
    if not name:
        # The bridge sets exactly the Rails session cookie; pick it.
        session_cookies = [n for n in available if n.endswith("_session")]
        name = (session_cookies or available or [None])[0]
    value = resp.cookies.get(name) if name else None
    assert value, f"no session cookie in bridge response; got cookies: {available}"
    return {"name": name, "value": value}


def _cookie_spec(cookie: dict, base_url: str) -> dict:
    return {
        "name": cookie["name"],
        "value": cookie["value"],
        "domain": urlparse(base_url).hostname,
        "path": "/",
        "httpOnly": True,
        "secure": base_url.startswith("https"),
        "sameSite": "Lax",
    }


@pytest.fixture(scope="session")
def session_cookie() -> dict:
    """Bridge the primary service-account token to a Rails session cookie (#573).

    Skips authenticated tests when no token is configured so the
    unauthenticated login-page smoke can still run standalone.
    """
    if not SA_TOKEN:
        pytest.skip("SPARC_SMOKE_SA_TOKEN not set — skipping authenticated smoke")
    return _bridge_token_to_cookie(SA_TOKEN)


@pytest.fixture(scope="session")
def user_session_cookie() -> dict:
    """Bridge the second (non-admin) identity — the submitter in review flows.

    Skips when SPARC_SMOKE_USER_TOKEN is unset, so single-identity runs still
    work; the two-identity approval flows (#643) require it.
    """
    if not USER_TOKEN:
        pytest.skip("SPARC_SMOKE_USER_TOKEN not set — skipping two-identity flows")
    return _bridge_token_to_cookie(USER_TOKEN)


@pytest.fixture
def authed_page(context, session_cookie, base_url):
    """A Playwright page carrying the primary (SA) session cookie."""
    context.add_cookies([_cookie_spec(session_cookie, base_url)])
    return context.new_page()


@pytest.fixture
def user_authed_page(browser, user_session_cookie, base_url):
    """A second Playwright page on its own context, carrying the non-admin
    session cookie — for flows that need submitter ≠ approver in one test."""
    ctx = browser.new_context(base_url=base_url)
    ctx.add_cookies([_cookie_spec(user_session_cookie, base_url)])
    page = ctx.new_page()
    yield page
    ctx.close()
