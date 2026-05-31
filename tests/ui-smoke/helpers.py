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


def collect_console_errors(page) -> list[str]:
    """Attach a console-error collector; returns the list it fills."""
    errors: list[str] = []
    page.on(
        "console",
        lambda msg: errors.append(msg.text) if msg.type == "error" else None,
    )
    page.on("pageerror", lambda exc: errors.append(f"pageerror: {exc}"))
    return errors


def same_origin(url: str, base_url: str) -> bool:
    """True if `url` is on the same host as `base_url` (or a relative path)."""
    target = urlparse(url)
    if not target.netloc:
        return True
    return target.hostname == urlparse(base_url).hostname
