"""PIV / CAC smart-card sign-in over a real mTLS gateway (#790).

Folds the end-to-end PIV proof into the standard smoke suite. Runs only when a
local nginx mTLS proxy + software-PIV certificate are available — set up by
`bin/smoke-piv-setup`, which mints the CA/cert, provisions the matching user +
PIV identity, and exports:

    SPARC_SMOKE_PIV_PROXY_URL   e.g. https://localhost:8443
    SPARC_SMOKE_PIV_CERT_DIR    dir holding ca.crt, client.crt, client.key

Against a target with no PIV gateway (prod, plain local) it skips — you cannot
present a smart card to a deployment that has no mTLS front door.

What no unit spec can prove, and this does: the header contract with a real
gateway, and the trust-boundary strip (a client cannot forge the verify header).

    bin/smoke-piv-setup ./tmp/piv-certs   # then:
    uv run pytest test_piv_mtls.py
"""

from __future__ import annotations

import os
import ssl
from pathlib import Path

import httpx
import pytest

PROXY = os.environ.get("SPARC_SMOKE_PIV_PROXY_URL")
CERT_DIR = os.environ.get("SPARC_SMOKE_PIV_CERT_DIR")
# Which card this stack is configured for. The DoD leg runs the default
# edipi_cn source with a CAC-shaped cert; the Non-DoD leg runs subject_cn +
# SPARC_PIV_UID_PATTERN with a corporate cert. They are separate stack shapes
# (SPARC_PIV_IDENTITY_SOURCE is per-container), hence separate ceremony legs.
MODE = os.environ.get("SPARC_SMOKE_PIV_MODE", "dod").lower()

pytestmark = pytest.mark.skipif(
    not PROXY or not CERT_DIR,
    reason="requires a local PIV mTLS proxy (run bin/smoke-piv-setup; sets "
    "SPARC_SMOKE_PIV_PROXY_URL + SPARC_SMOKE_PIV_CERT_DIR)",
)


def _paths():
    d = Path(CERT_DIR)
    # The valid card for the leg under test. Both are signed by the same test CA,
    # so the gateway trusts both; only the app-side identity mapping differs.
    client = "client-nondod" if MODE == "nondod" else "client"
    return d / "ca.crt", d / f"{client}.crt", d / f"{client}.key"


def _ssl_context(*, present_cert: bool) -> ssl.SSLContext:
    ca, crt, key = _paths()
    ctx = ssl.create_default_context(cafile=str(ca))
    # Cap at TLS 1.2. With nginx `ssl_verify_client optional` under TLS 1.3 the
    # client cert is requested POST-handshake, so $ssl_client_verify can be
    # evaluated before the cert lands — a flaky verify=NONE. TLS 1.2 requests the
    # cert in-handshake, which is what a real gateway/CAC pairing does anyway.
    ctx.maximum_version = ssl.TLSVersion.TLSv1_2
    if present_cert:
        ctx.load_cert_chain(certfile=str(crt), keyfile=str(key))
    return ctx


def _get(*, present_cert: bool, headers: dict | None = None) -> httpx.Response:
    with httpx.Client(verify=_ssl_context(present_cert=present_cert), timeout=10.0) as client:
        # Do NOT follow the redirect — the redirect target IS the assertion.
        return client.get(f"{PROXY}/auth/piv", headers=headers or {}, follow_redirects=False)


def _redirect_target(resp: httpx.Response) -> str:
    return resp.headers.get("location", "")


def test_valid_software_piv_establishes_a_session():
    """A verified card signs in: redirected somewhere OTHER than /login.

    Runs for whichever leg the stack is configured for (DoD edipi_cn, or Non-DoD
    subject_cn + pattern) — same end-to-end flow, different identity mapping.

    The redirect target is the discriminator, not the cookie — Rails sets a
    session cookie on the failure path too (to carry the flash), so a cookie
    proves nothing. Success (start_session) redirects to root/return_to; every
    failure redirects to /login.
    """
    resp = _get(present_cert=True)
    assert resp.status_code in (302, 303), f"expected a redirect, got {resp.status_code}"

    target = _redirect_target(resp)
    assert target and "/login" not in target, (
        f"valid PIV card did not sign in — bounced to {target!r}. Check the "
        "gateway forwarded verify=SUCCESS and the identity is provisioned."
    )


def test_no_client_certificate_is_rejected_fail_closed():
    """No card → fail closed to /login. The PIV route must never open without a cert."""
    resp = _get(present_cert=False)
    assert resp.status_code in (302, 303)
    assert "/login" in _redirect_target(resp), (
        "a request with no client certificate was not rejected to /login"
    )


def test_forged_verify_header_is_stripped_and_rejected():
    """The trust-boundary strip: a client cannot forge the gateway's verify result.

    We send X-SSL-Client-Verify: SUCCESS with NO certificate. The proxy overwrites
    it from the (empty) handshake, so SPARC sees NONE and fails closed. If this
    ever passes into a session, the whole PIV trust model is broken.
    """
    resp = _get(
        present_cert=False,
        headers={"X-SSL-Client-Verify": "SUCCESS", "X-SSL-Client-Cert": "forged-pem"},
    )
    assert resp.status_code in (302, 303)
    assert "/login" in _redirect_target(resp), (
        "a forged verify header was TRUSTED — the proxy did not strip the "
        "client-supplied header (critical trust-boundary failure)"
    )
