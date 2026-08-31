"""Pytest + Playwright configuration for the SPARC UI smoke suite.

Targets a live deployment (default: the build environment at
https://sparc.risk-sentinel.org). Unauthenticated tests (login page, CSP)
run with no credentials; authenticated tests acquire a Rails session by
bridging a service-account bearer token through the v1.8.4 cookie-bridge
endpoint POST /api/v1/sessions/from_token (#573).
"""

from __future__ import annotations

import os
import re
from urllib.parse import urlparse

import httpx
import pytest

from helpers import smoke_flag, smoke_tls_verify

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


# ── The harness must agree with the target before anything runs (#858) ────────
#
# During v1.15.3 verification this suite was pointed at http://localhost:3000
# while the stack was configured with SPARC_APP_URL=https://localhost:3443 and
# caddy behind an unstarted `profiles: [tls]` guard. Result: 78 failures, every
# one `net::ERR_SSL_PROTOCOL_ERROR`.
#
# Those were read as a PRODUCT defect — "the app requests HTTPS subresources
# even with FORCE_SSL=false" — and they were nothing of the kind. The app was
# correctly emitting absolute URLs to its CONFIGURED public URL; it was being
# served on a scheme and port it had never been told about.
#
# So the expensive failure here was not a missing test. It was an incoherent
# harness that LOOKED like a product bug, and cost a diagnosis. A startup
# assertion kills that class permanently, which is why #858 calls it the
# highest-value item in the issue.
#
# The signal is deliberately narrow: SAME hostname, DIFFERENT scheme or port.
# That is the misconfiguration signature exactly. A genuinely different host is
# an external resource (fonts, CDN) and is none of our business.
def _origin(url: str) -> tuple[str, str, int | None]:
    p = urlparse(url)
    port = p.port
    if port is None:
        port = {"http": 80, "https": 443}.get(p.scheme)
    return (p.scheme, p.hostname or "", port)


@pytest.fixture(scope="session", autouse=True)
def _assert_harness_matches_target() -> None:
    """Refuse to run when the target thinks it lives somewhere else."""
    if smoke_flag("SPARC_SMOKE_SKIP_COHERENCE_CHECK"):
        return

    want = _origin(BASE_URL)
    want_scheme, want_host, want_port = want
    try:
        # NOT following redirects: the redirect target is the signal. Following
        # it is what BREAKS — under the real incident the app answers
        # `Location: https://localhost:3000/login` while nothing terminates TLS
        # on that port, so the follow dies with an SSL error and the cause is
        # buried in a transport exception instead of being named.
        resp = httpx.get(
            BASE_URL,
            follow_redirects=False,
            timeout=30.0,
            verify=smoke_tls_verify(),
        )
    except Exception as exc:  # noqa: BLE001 — any transport failure is fatal here
        raise RuntimeError(
            f"SPARC_SMOKE_BASE_URL={BASE_URL} is not reachable: {exc}\n"
            f"The suite cannot prove anything about a target it cannot open."
        ) from exc

    mismatched = set()

    # PRIMARY SIGNAL — where the target sends you.
    # Verified against a real mis-posture: with SPARC_APP_URL=https://localhost:3443
    # and the suite pointed at http://localhost:3000, the app answers
    # `Location: https://localhost:3000/login` — same host and port, upgraded
    # scheme — and following that is `ERR_SSL_PROTOCOL_ERROR` (curl exit 35),
    # which is precisely the 78 failures of the v1.15.3 incident. Pointed at
    # https://localhost:3443 the same app answers https://localhost:3443/login
    # and the origins agree.
    location = resp.headers.get("location", "")
    if location.startswith(("http://", "https://")):
        scheme, host, port = _origin(location)
        if host and host == want_host and (scheme, port) != (want_scheme, want_port):
            mismatched.add(f"{scheme}://{host}:{port}")

    # SECONDARY — absolute URLs the body emits to a different scheme/port on the
    # same host. The landing page currently uses relative URLs so this finds
    # nothing there, but authenticated pages and mailer-style absolute links can
    # carry them, and it costs one pass over the response.
    for match in re.finditer(r"""["'(](https?://[^"'()\s>]+)""", resp.text):
        scheme, host, port = _origin(match.group(1))
        if host and host == want_host and (scheme, port) != (want_scheme, want_port):
            mismatched.add(f"{scheme}://{host}:{port}")

    if mismatched:
        raise RuntimeError(
            f"HARNESS/TARGET MISMATCH — refusing to run.\n"
            f"  SPARC_SMOKE_BASE_URL : {BASE_URL}\n"
            f"  target points at     : {', '.join(sorted(mismatched))}\n"
            f"  (from its redirect Location and/or absolute URLs in the page)\n"
            f"\n"
            f"The target is configured (SPARC_APP_URL) for a different scheme or "
            f"port than the one you pointed this suite at. Every subresource will "
            f"fail to load and the run will report dozens of console errors that "
            f"look like a product defect — that is #858's whole subject.\n"
            f"\n"
            f"Fix the harness, not the app: point SPARC_SMOKE_BASE_URL at the "
            f"origin the target was configured with, or reconfigure SPARC_APP_URL. "
            f"If the TLS terminator is behind a compose profile, it may simply not "
            f"be running (`--profile tls`)."
        )


@pytest.fixture
def browser_context_args(browser_context_args):
    """Resolve relative page.goto() paths against the target deployment."""
    args = {**browser_context_args, "base_url": BASE_URL}
    if smoke_flag("SPARC_SMOKE_INSECURE_TLS"):
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
    insecure = smoke_flag("SPARC_SMOKE_INSECURE_TLS")
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
    # #968 — stash the phase report so the navigation-diagnostics fixture can see
    # whether the test actually failed. Extends this hook rather than declaring a
    # second one: pytest would keep both, but a duplicate definition in the same
    # module silently replaces the posture accounting above.
    setattr(item, f"_smoke_rep_{report.when}", report)


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


# ---------------------------------------------------------------------------
# Navigation-timeout diagnostics (#968)
#
# Three separate `Timeout 30000ms exceeded` failures were seen in one session —
# two browsers, three different pages, each passing on its own afterwards. The
# server was never the cause: the slowest request in the whole 14-minute window
# was 4.19s, and the page that "timed out" answered in 0.096s when asked
# directly. Playwright was waiting on the `load` event, which never fired.
#
# The failure as reported names the PAGE but not the RESOURCE, so every
# occurrence cost a manual re-run to decide whether it was real. This records
# which requests were still in flight when the test failed — the ones that could
# hold `load` open — so the next occurrence identifies itself.
#
# Diagnostics only. It changes no timeout and fails no test that would otherwise
# pass; a test that fails still fails, with more to read.
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def _navigation_diagnostics(request):
    """Report in-flight requests and console errors when a browser test fails."""
    # Only engage where a browser context is already in play — never pull one
    # into a test that did not ask for it.
    if "context" not in request.fixturenames:
        yield
        return

    context = request.getfixturevalue("context")
    inflight: dict[object, str] = {}
    console_errors: list[str] = []

    def _started(req):
        inflight[req] = req.url

    def _settled(req):
        inflight.pop(req, None)

    def _console(msg):
        if msg.type in ("error", "warning"):
            console_errors.append(f"{msg.type}: {msg.text}"[:200])

    context.on("request", _started)
    context.on("requestfinished", _settled)
    context.on("requestfailed", _settled)
    context.on("console", _console)

    yield

    report = getattr(request.node, "_smoke_rep_call", None)
    if report is None or not report.failed:
        return

    pending = list(inflight.values())

    # Speak up for TIMEOUT failures even when nothing is pending — "the network
    # was idle and `load` still never fired" is itself the finding, and staying
    # silent there would reproduce the very gap this exists to close. Ordinary
    # assertion failures stay quiet unless there is something to show.
    is_timeout = "Timeout" in (report.longreprtext or "")
    if not pending and not console_errors and not is_timeout:
        return

    print("\n--- navigation diagnostics (#968) ---")
    if pending:
        print(f"  {len(pending)} request(s) still in flight when the test failed:")
        for url in pending[:10]:
            print(f"    PENDING  {url[:160]}")
        if len(pending) > 10:
            print(f"    ... and {len(pending) - 10} more")
        print("  A request that never settles holds the `load` event open, which is")
        print("  what a `Page.goto ... waiting until \"load\"` timeout is reporting.")
    else:
        print("  no requests were in flight — `load` was not blocked on the network")
    for line in console_errors[:5]:
        print(f"    CONSOLE  {line}")
    print("--- end diagnostics ---")
