"""Shared helpers for the SPARC UI smoke suite."""

from __future__ import annotations

from urllib.parse import urlparse

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
