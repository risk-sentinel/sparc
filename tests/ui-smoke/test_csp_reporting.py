"""CSP violation report sink smoke test (#528, epic #650).

Validates the server half of the CSP net: the `report-uri` endpoint accepts a
violation report and answers 204, without auth or CSRF. The client half (a
browser firing `securitypolicyviolation` on interaction) is asserted by the
`helpers.assert_no_csp_violations` / `click_and_assert_clean` checks used in the
interaction tests.

Runs against whatever `SPARC_SMOKE_BASE_URL` points to — local container first
(http://localhost:3000), then the deployment.
"""

from __future__ import annotations

import json
import os

import httpx
import pytest

BASE_URL = os.environ.get(
    "SPARC_SMOKE_BASE_URL", "https://sparc.risk-sentinel.org"
).rstrip("/")

REPORT = {
    "csp-report": {
        "document-uri": f"{BASE_URL}/cdef_documents/1",
        "violated-directive": "script-src-attr",
        "effective-directive": "script-src-attr",
        "blocked-uri": "inline",
        "source-file": f"{BASE_URL}/cdef_documents/1",
        "line-number": 42,
        "disposition": "enforce",
    }
}


def test_report_uri_present_in_csp_header():
    """The enforced CSP must advertise the report-uri so violations are sent."""
    resp = httpx.get(f"{BASE_URL}/login", timeout=30.0)
    csp = resp.headers.get("content-security-policy", "")
    assert "report-uri" in csp, f"no report-uri in CSP header: {csp!r}"
    assert "/security/csp-violations" in csp


def test_collector_accepts_report_without_auth():
    """A report-uri envelope is accepted with 204 and no credentials."""
    resp = httpx.post(
        f"{BASE_URL}/security/csp-violations",
        content=json.dumps(REPORT),
        headers={"Content-Type": "application/csp-report"},
        timeout=30.0,
    )
    assert resp.status_code == 204, f"expected 204, got {resp.status_code}: {resp.text[:200]}"


def test_collector_tolerates_garbage():
    """Malformed bodies never raise — the beacon always answers 204."""
    resp = httpx.post(
        f"{BASE_URL}/security/csp-violations",
        content="not-json{{{",
        headers={"Content-Type": "application/csp-report"},
        timeout=30.0,
    )
    assert resp.status_code == 204
