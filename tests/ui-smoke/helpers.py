"""Shared helpers for the SPARC UI smoke suite."""

from __future__ import annotations

import os
import ssl
from urllib.parse import urlparse

_TRUTHY = {"1", "true", "yes", "on"}
_FALSY = {"0", "false", "no", "off", ""}


def smoke_flag(name: str, default: bool = False) -> bool:
    """Read a SPARC_SMOKE_* boolean, accepting the usual spellings.

    #858 — every one of these flags was read as ``== "1"``, so the natural
    ``SPARC_SMOKE_INSECURE_TLS=true`` was silently treated as FALSE. Against a
    self-signed local stack that surfaces as ``CERTIFICATE_VERIFY_FAILED``,
    which reads like a broken certificate rather than a mistyped flag — and the
    operator's next move is to debug the cert.

    Unrecognised values RAISE rather than defaulting. A flag the runner clearly
    meant to set, silently ignored, is the same failure in a quieter form: the
    suite would run in the opposite posture from the one asked for and report a
    confident green about something it never tested.
    """
    raw = os.environ.get(name)
    if raw is None:
        return default
    value = raw.strip().lower()
    if value in _TRUTHY:
        return True
    if value in _FALSY:
        return False
    raise RuntimeError(
        f"{name}={raw!r} is not a recognised boolean. "
        f"Use one of {sorted(_TRUTHY)} or {sorted(_FALSY - {''})}. "
        f"Refusing to guess: this flag changes which posture the suite proves."
    )


def smoke_tls_verify():
    """TLS-verification setting for the suite's raw httpx calls.

    Mirrors the Playwright side (conftest ignore_https_errors) so every
    transport in the suite trusts the target the same way:

    - ``SPARC_SMOKE_INSECURE_TLS=1`` -> ``False``: the *insecure pass*, trusting
      a self-signed cert (the local UBI9 prod stack behind caddy on :3443).
    - else ``SPARC_SMOKE_CA_BUNDLE=<path>`` -> that path: the *secure pass*
      against the local stack, verifying the served chain against caddy's real
      root CA. Proves the chain is genuinely valid, not bypassed (and previews
      the #774 custom-CA trust path). NOTE: this covers the httpx transport only.
      Playwright's Chromium uses the OS trust store and does NOT honor
      NODE_EXTRA_CA_CERTS for a local private CA, so browser page navigations
      still hit ERR_CERT_AUTHORITY_INVALID under a self-signed local CA — run
      the browser layer via the insecure pass locally, or secure against a
      public-CA endpoint.
    - else ``True``: default public-CA verification (e.g. a real deployment).
    """
    if smoke_flag("SPARC_SMOKE_INSECURE_TLS"):
        return False
    ca = os.environ.get("SPARC_SMOKE_CA_BUNDLE")
    if ca:
        # An SSLContext (not a bare path string, which httpx has deprecated).
        return ssl.create_default_context(cafile=ca)
    return True

# JS injected before any document script runs. Records CSP violations into a
# window-global so a test can read them after interacting with the page. This
# is how we catch the #593 class of bug: a `form-action` violation fires a
# `securitypolicyviolation` event client-side instead of (silently) blocking
# the OAuth form submit.
CSP_RECORDER = (
    "window.__cspViolations = [];"
    "document.addEventListener('securitypolicyviolation', function (e) {"
    "  window.__cspViolations.push({"
    "    directive: e.violatedDirective,"
    "    blockedURI: e.blockedURI,"
    "    sourceFile: e.sourceFile"
    "  });"
    "});"
)


def record_csp(page) -> None:
    """Start recording CSP violations on `page` (call before goto)."""
    page.add_init_script(CSP_RECORDER)


def csp_violations(page) -> list[dict]:
    return page.evaluate("window.__cspViolations || []")


def assert_no_csp_violations(page, during: str = "") -> None:
    """Fail if any CSP violation has fired on `page`.

    The non-negotiable DoD assertion for epic #650: render-time CSP checks are
    insufficient because inline-handler breakage only manifests on interaction.
    Call AFTER clicking a control to prove the click did not trip a (silently
    blocked) inline-handler / form-action violation.
    """
    violations = csp_violations(page)
    context = f" during {during}" if during else ""
    assert not violations, f"CSP violation(s){context}: {violations}"


def click_and_assert_clean(page, selector, during: str = "") -> None:
    """Click `selector` (string or Locator) then assert zero CSP violations.

    The canonical interaction check: a control that relies on a blocked inline
    handler is inert AND fires a `securitypolicyviolation` — asserting on the
    recorded violations after the click catches it. Pair with an explicit
    behavior assertion (a DOM state change) at the call site.
    """
    locator = page.locator(selector) if isinstance(selector, str) else selector
    locator.click()
    assert_no_csp_violations(page, during=during or f"click {selector}")


def collect_console_errors(page) -> list[str]:
    """Attach a console-error collector; returns the list it fills."""
    errors: list[str] = []
    page.on(
        "console",
        lambda msg: errors.append(msg.text) if msg.type == "error" else None,
    )
    page.on("pageerror", lambda exc: errors.append(f"pageerror: {exc}"))
    return errors


# Collection routes that share a resource's show prefix but are NOT show pages.
RESERVED_SEGMENTS = {
    "new", "import", "wizard", "select_catalog", "select_profile", "select_ssp",
    "batch_new", "edit",
    # #881 — catalog-scoped nested routes. Without these, a href like
    # /control_catalogs/<uuid>/controls/ac-1 is mistaken for a catalog show URL
    # and every caller exercises the wrong screen while appearing to pass.
    "controls", "control_families",
}


def first_show_href(page, index_path: str, prefix: str):
    """First document show href on `index_path`, slug-aware.

    SPARC document URLs are slug-based (FriendlyId), e.g. /profile_documents/test
    or /control_catalogs/<slug> — NOT numeric ids. Matches `<prefix>/<segment>`
    while excluding collection routes (new/import/...) and nested paths
    (`/<slug>/edit`, `/<slug>/copy`). Returns the path or None.
    """
    resp = page.goto(index_path)
    if not (resp and resp.status < 400):
        return None
    page.wait_for_load_state("networkidle")
    for h in page.eval_on_selector_all(
        "a[href]", "els => els.map(e => e.getAttribute('href'))"
    ):
        if not h:
            continue
        # Strip BOTH the query and the fragment. Dropping only the query let
        # "/poam_documents/new#upload-poam" through as a segment of
        # "new#upload-poam", which is not in RESERVED_SEGMENTS — so the *new*
        # page was returned as though it were a document show page. Every caller
        # then exercised the wrong screen (and, for exports, a 404 error page)
        # while appearing to pass.
        path = h.split("?")[0].split("#")[0]
        if not path.startswith(prefix + "/"):
            continue
        seg = path[len(prefix) + 1:]
        if "/" in seg or seg in RESERVED_SEGMENTS:
            continue
        return path
    return None


def show_hrefs(page, index_path: str, prefix: str, limit: int = 8):
    """Up to `limit` document show hrefs on `index_path`, same rules as
    `first_show_href`.

    Exists because "the first document" is not always a document that can
    exercise the control under test. A CDEF index led by AWS Labs content is the
    case that forced this: those documents are read-only by design (#466), so
    their edit controls render but never become clickable, and a test that took
    the first href alone either timed out or degraded into a silent skip on any
    deployment with the AWS Labs ingest enabled.
    """
    resp = page.goto(index_path)
    if not (resp and resp.status < 400):
        return []
    page.wait_for_load_state("networkidle")

    found = []
    for h in page.eval_on_selector_all(
        "a[href]", "els => els.map(e => e.getAttribute('href'))"
    ):
        if not h:
            continue
        path = h.split("?")[0].split("#")[0]
        if not path.startswith(prefix + "/"):
            continue
        seg = path[len(prefix) + 1:]
        if "/" in seg or seg in RESERVED_SEGMENTS:
            continue
        if path not in found:
            found.append(path)
        if len(found) >= limit:
            break
    return found


def same_origin(url: str, base_url: str) -> bool:
    """True if `url` is on the same host as `base_url` (or a relative path)."""
    target = urlparse(url)
    if not target.netloc:
        return True
    return target.hostname == urlparse(base_url).hostname


def turbo_visit(page, path: str) -> None:
    """Navigate to `path` via **Turbo Drive** — an in-page fetch + <body> swap
    with NO document reload — and wait for it to land.

    This is the navigation real users perform (link clicks / form submits), and
    it is materially different from `page.goto()` (a full document load): Turbo
    re-executes the new body's inline <script>s by *cloning* them, and cloned
    scripts LOSE their per-request CSP nonce — tripping a script-src-elem
    violation under the enforced CSP that a full load never would (#712 / #528).
    Requires `window.Turbo` (turbo-rails).
    """
    page.evaluate("(p) => window.Turbo.visit(p)", path)
    page.wait_for_url(f"**{path}", timeout=10_000)
    page.wait_for_load_state("networkidle")
