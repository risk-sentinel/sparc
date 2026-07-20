"""Shared helpers for the SPARC UI smoke suite."""

from __future__ import annotations

import os
from urllib.parse import urlparse


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
    if os.environ.get("SPARC_SMOKE_INSECURE_TLS") == "1":
        return False
    return os.environ.get("SPARC_SMOKE_CA_BUNDLE") or True

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
        path = h.split("?")[0]
        if not path.startswith(prefix + "/"):
            continue
        seg = path[len(prefix) + 1:]
        if "/" in seg or seg in RESERVED_SEGMENTS:
            continue
        return path
    return None


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
