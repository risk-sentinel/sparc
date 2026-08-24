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

from helpers import smoke_tls_verify

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
    args = {**browser_context_args, "base_url": BASE_URL}
    if os.environ.get("SPARC_SMOKE_INSECURE_TLS") == "1":
        args["ignore_https_errors"] = True
    return args


def _bridge_token_to_cookie(token: str) -> dict:
    """Exchange a bearer token for a Rails session cookie via #573."""
    resp = httpx.post(
        f"{BASE_URL}/api/v1/sessions/from_token",
        headers={"Authorization": f"Bearer {token}"},
        timeout=30.0,
        verify=smoke_tls_verify(),
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
    insecure = os.environ.get("SPARC_SMOKE_INSECURE_TLS") == "1"
    extra = {"ignore_https_errors": True} if insecure else {}
    ctx = browser.new_context(base_url=base_url, **extra)
    ctx.add_cookies([_cookie_spec(user_session_cookie, base_url)])
    page = ctx.new_page()
    yield page
    ctx.close()


# ── Posture accounting (#885) ────────────────────────────────────────────────
#
# A posture-gated check must never SILENTLY skip. Six checks in this suite are
# gated on a deployment posture the harness may or may not supply — PIV mTLS,
# both-directions TLS, FIDO2, the publish-approval gate — and when the posture
# is absent they skip. A headline of "324 passed, 12 skipped" then reads as
# verification of things that never executed.
#
# That is not hypothetical: the release-grade smoke run for PR #884 was reported
# as release verification while PIV/CAC, fail-closed TLS and FIDO2 were entirely
# unproven.
#
# So the run now always ends with a named, counted UNPROVEN section, and
# SPARC_SMOKE_REQUIRE_POSTURES turns "unproven" into a failure for a release
# run, where the posture is supposed to be supplied.
#
# Mark a posture-gated module or test with:
#     pytestmark = pytest.mark.posture("piv_mtls")
# The marker is metadata only — the existing skipif still decides whether the
# test runs. This records WHAT was not proven, and by which name.

_POSTURE_SKIPS: dict[str, list[str]] = {}
_POSTURE_PASSES: dict[str, list[str]] = {}


def pytest_configure(config):
    config.addinivalue_line(
        "markers",
        "posture(name): the deployment posture this check proves; reported as "
        "UNPROVEN when it skips, and failed when named in "
        "SPARC_SMOKE_REQUIRE_POSTURES",
    )


def pytest_runtest_logreport(report):
    if report.when not in ("call", "setup"):
        return
    postures = getattr(report, "_sparc_postures", None)
    if not postures:
        return
    for name in postures:
        if report.skipped:
            _POSTURE_SKIPS.setdefault(name, []).append(report.nodeid)
        elif report.passed:
            _POSTURE_PASSES.setdefault(name, []).append(report.nodeid)


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    report = outcome.get_result()
    # Marker lookup must happen on the ITEM; the report does not carry markers.
    names = [m.args[0] for m in item.iter_markers(name="posture") if m.args]
    if names:
        report._sparc_postures = names


def pytest_terminal_summary(terminalreporter, exitstatus, config):
    required = os.environ.get("SPARC_SMOKE_REQUIRE_POSTURES", "").strip()
    proven = {p for p in _POSTURE_PASSES if p not in _POSTURE_SKIPS}
    unproven = sorted(_POSTURE_SKIPS)

    terminalreporter.write_sep("=", "posture accounting (#885)")
    if proven:
        for name in sorted(proven):
            terminalreporter.write_line(
                f"PROVEN    {name}: {len(_POSTURE_PASSES[name])} check(s) ran"
            )
    for name in unproven:
        terminalreporter.write_line(
            f"UNPROVEN  {name}: {len(_POSTURE_SKIPS[name])} check(s) skipped — posture not supplied"
        )
    if not proven and not unproven:
        terminalreporter.write_line("no posture-gated checks collected")

    terminalreporter.write_line(
        f"postures proven: {len(proven)}    UNPROVEN: {len(unproven)}"
    )

    if not required:
        if unproven:
            terminalreporter.write_line(
                "NOTE: a green run does NOT cover the UNPROVEN postures above. "
                "Set SPARC_SMOKE_REQUIRE_POSTURES to fail instead of reporting "
                "(release runs should)."
            )
        return

    wanted = (
        set(unproven) | proven
        if required == "all"
        else {p.strip() for p in required.split(",") if p.strip()}
    )
    missing = sorted(wanted & set(unproven))
    if missing:
        terminalreporter.write_line("")
        terminalreporter.write_line(
            f"FAILED: SPARC_SMOKE_REQUIRE_POSTURES demanded {sorted(wanted)} and "
            f"these were not proven: {missing}"
        )


def pytest_sessionfinish(session, exitstatus):
    """Turn a required-but-unproven posture into a non-zero exit.

    Done here rather than in pytest_terminal_summary because the session exit
    status is what a caller actually reads, and a run that skipped a posture the
    operator explicitly demanded must not exit 0 — that is the whole defect
    #885 describes.
    """
    required = os.environ.get("SPARC_SMOKE_REQUIRE_POSTURES", "").strip()
    if not required:
        return

    unproven = set(_POSTURE_SKIPS)
    if required == "all":
        missing = unproven
    else:
        wanted = {p.strip() for p in required.split(",") if p.strip()}
        missing = wanted & unproven

    if missing and exitstatus == 0:
        session.exitstatus = 1
