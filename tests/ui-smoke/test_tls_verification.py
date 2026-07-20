"""Fail-closed TLS verification (#773 / #774).

The functional smoke runs with TLS verification disabled (SPARC_SMOKE_INSECURE_TLS)
so the browser can exercise the app against a local self-signed stack — that
proves the app works, but says nothing about whether TLS verification has teeth.
These transport-layer checks assert the security-critical behavior directly:

  * NEGATIVE (fail-closed): with verification ON and the stack's CA NOT trusted,
    the connection MUST be rejected. This is the assertion that gives the LDAP
    cert-verification (#773) and container custom-CA trust (#774) meaning — a
    stack that silently accepted an untrusted cert would pass every functional
    test while being MITM-open.
  * POSITIVE: with the stack's real CA trusted, verification succeeds.

Deterministic (httpx only, no browser — Chromium can't be handed a local private
CA). Runs only against a self-signed stack (SPARC_SMOKE_SELF_SIGNED=1), e.g. the
local UBI9 prod image behind caddy; against a public-CA deployment the negative
case would (correctly) not reject, so the module skips.
"""

from __future__ import annotations

import os
import ssl

import httpx
import pytest

BASE_URL = os.environ.get(
    "SPARC_SMOKE_BASE_URL", "https://sparc.risk-sentinel.org"
).rstrip("/")
SELF_SIGNED = os.environ.get("SPARC_SMOKE_SELF_SIGNED") == "1"
CA_BUNDLE = os.environ.get("SPARC_SMOKE_CA_BUNDLE")

pytestmark = pytest.mark.skipif(
    not SELF_SIGNED,
    reason="fail-closed TLS checks require a self-signed stack (set SPARC_SMOKE_SELF_SIGNED=1)",
)


def test_untrusted_cert_is_rejected_when_verifying():
    """verify ON + the stack's CA not in the trust store => connection rejected.

    Proves TLS fails closed. If this ever PASSES (a 2xx/redirect comes back), the
    stack is accepting an untrusted certificate — exactly the #773 class of bug.
    """
    with pytest.raises((ssl.SSLError, httpx.TransportError)):
        httpx.get(f"{BASE_URL}/login", verify=True, timeout=10.0)


@pytest.mark.skipif(
    not CA_BUNDLE,
    reason="positive check needs SPARC_SMOKE_CA_BUNDLE (the stack's real CA)",
)
def test_valid_cert_verifies_against_its_ca():
    """verify ON + the stack's real CA trusted => succeeds (login renders)."""
    ctx = ssl.create_default_context(cafile=CA_BUNDLE)
    resp = httpx.get(f"{BASE_URL}/login", verify=ctx, timeout=10.0)
    assert resp.status_code == 200, f"expected 200, got {resp.status_code}"
