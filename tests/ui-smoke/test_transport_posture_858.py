"""Record — and prove — which TLS posture a smoke run actually exercised (#858).

The release smoke ran ONE posture and a green result did not say which. Neither
result implies the other:

- **TLS on** exercises HSTS, secure-cookie flags, the proxy hop, and absolute-URL
  generation against the real scheme.
- **TLS off** is what a developer runs locally, what a bare ``docker run``
  produces, and what an operator gets before their terminator is in front of it.

These plug into the posture accounting added by #885 rather than inventing a
parallel mechanism, so a run ends with ``PROVEN transport_https`` or
``UNPROVEN transport_http``, and a release run can demand both:

    SPARC_SMOKE_REQUIRE_POSTURES=transport_https,transport_http

Each leg needs its own stack configuration — ``SPARC_APP_URL`` has to match the
scheme being exercised — which is exactly why one run cannot cover both, and why
the accounting has to name what it did.

These assert something real about the posture rather than merely observing the
URL scheme. A test that only reads ``BASE_URL`` back would report PROVEN without
touching the target, which is the vacuous pass this milestone exists to remove.
"""

from __future__ import annotations

from urllib.parse import urlparse

import httpx
import pytest

from conftest import BASE_URL
from helpers import smoke_tls_verify

SCHEME = urlparse(BASE_URL).scheme
IS_HTTPS = SCHEME == "https"


def _root_response() -> httpx.Response:
    return httpx.get(
        BASE_URL, follow_redirects=False, timeout=30.0, verify=smoke_tls_verify()
    )


@pytest.mark.posture("transport_https")
@pytest.mark.skipif(
    not IS_HTTPS,
    reason=(
        "TLS-on posture needs an https SPARC_SMOKE_BASE_URL against a stack "
        "configured with a matching https SPARC_APP_URL"
    ),
)
def test_tls_on_posture_is_coherent_and_secure():
    """Over TLS: the app must keep you on TLS and mark its session cookie secure."""
    resp = _root_response()
    assert resp.status_code < 500, f"target erroring: {resp.status_code}"

    location = resp.headers.get("location", "")
    if location.startswith(("http://", "https://")):
        assert location.startswith("https://"), (
            f"served over TLS but redirects to {location} — a downgrade to "
            f"plaintext, which no TLS posture should ever emit"
        )

    # A session cookie issued over TLS without `secure` is transmissible in
    # cleartext, and it is exactly the kind of flag that only differs between
    # the two postures — the reason one leg cannot vouch for the other.
    #
    # GATED ON WHETHER THE APP IS ACTUALLY ENFORCING SSL, not on the connection
    # being TLS. In Rails one switch — `config.force_ssl` — turns on BOTH HSTS
    # and the Secure cookie flag, so HSTS is a faithful proxy for "this app
    # intends to be https-only".
    #
    # This matters because the local UBI9 validation stack deliberately sets
    # FORCE_SSL=false (so the plaintext :3000 path stays usable) while still
    # being served over TLS on :3443. Asserting Secure unconditionally would
    # fail every local TLS run and report a configuration choice as a defect —
    # measured on that stack: TLS connection, no HSTS, no Secure flag. In
    # production FORCE_SSL defaults to "true", so the assertion does bind where
    # it counts.
    forcing_ssl = bool(resp.headers.get("strict-transport-security"))
    if forcing_ssl:
        session_cookies = [
            c for c in resp.headers.get_list("set-cookie") if "_session=" in c
        ]
        for cookie in session_cookies:
            assert "secure" in cookie.lower(), (
                f"app is enforcing SSL (HSTS present) but issued a session "
                f"cookie without the Secure flag: {cookie[:120]}"
            )


@pytest.mark.posture("transport_http")
@pytest.mark.skipif(
    IS_HTTPS,
    reason=(
        "TLS-off posture needs an http SPARC_SMOKE_BASE_URL against a stack "
        "configured with a matching http SPARC_APP_URL"
    ),
)
def test_tls_off_posture_is_coherent():
    """Over plaintext: the app must not upgrade you to a scheme nothing serves.

    This is the v1.15.3 failure in assertion form. With SPARC_APP_URL set to an
    https origin while the app is served on a plaintext port, the app answers
    ``Location: https://<host>:<same-port>/login`` — and following it is
    ERR_SSL_PROTOCOL_ERROR, because nothing terminates TLS there.

    The session-level coherence check in conftest refuses to start a run in that
    state. This is the same property asserted as a first-class result, so the
    TLS-off leg has something it actually proves rather than only a scheme
    reading.
    """
    resp = _root_response()
    assert resp.status_code < 500, f"target erroring: {resp.status_code}"

    location = resp.headers.get("location", "")
    if location.startswith(("http://", "https://")):
        target = urlparse(location)
        want = urlparse(BASE_URL)
        same_host_and_port = (
            target.hostname == want.hostname and target.port == want.port
        )
        assert not (target.scheme == "https" and same_host_and_port), (
            f"served on {BASE_URL} but redirecting to {location} — an https "
            f"upgrade on the same port, which nothing is listening for. "
            f"SPARC_APP_URL disagrees with how the app is actually served."
        )
