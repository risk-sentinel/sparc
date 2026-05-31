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


@pytest.fixture(scope="session")
def session_cookie() -> dict:
    """Bridge a service-account token to a Rails session cookie (#573).

    Skips authenticated tests when no token is configured so the
    unauthenticated login-page smoke can still run standalone.
    """
    if not SA_TOKEN:
        pytest.skip("SPARC_SMOKE_SA_TOKEN not set — skipping authenticated smoke")

    resp = httpx.post(
        f"{BASE_URL}/api/v1/sessions/from_token",
        headers={"Authorization": f"Bearer {SA_TOKEN}"},
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
    assert value, (
        f"no session cookie in bridge response; got cookies: {available}"
    )
    return {"name": name, "value": value}


@pytest.fixture
def authed_page(context, session_cookie, base_url):
    """A Playwright page carrying the bridged session cookie."""
    context.add_cookies(
        [
            {
                "name": session_cookie["name"],
                "value": session_cookie["value"],
                "domain": urlparse(base_url).hostname,
                "path": "/",
                "httpOnly": True,
                "secure": base_url.startswith("https"),
                "sameSite": "Lax",
            }
        ]
    )
    return context.new_page()
