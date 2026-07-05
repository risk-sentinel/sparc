"""Shared pytest fixtures for the SPARC API test suite (issue #413 Phase 2).

Fixtures fall into three groups:

1. **Configuration** — read from env vars at session start. Fail fast with a
   clear message if any required value is missing, so CI / local runs do not
   silently produce confusing 401 / connection errors.

2. **HTTP clients** — pre-authenticated httpx clients for each role:
   ``admin_client``, ``user_client``, ``anon_client``. Tests use whichever
   role they are exercising; the auth-failure tests use ``anon_client`` or
   build their own client with a deliberately bad token.

3. **Test data helpers** — factories that build minimum-viable request
   bodies for create / update operations. Each test module can override
   them locally if it needs a more specific shape.

The suite expects a running SPARC instance, identified by
``SPARC_TEST_BASE_URL``. Tests are written to be safe against shared state:
each module that creates resources cleans up after itself in a fixture
teardown step. Tests that read existing data (catalogs, KSI indicators)
treat what they find as an opaque list and assert on shape, not content.
"""

from __future__ import annotations

import os
from collections.abc import Iterator
from typing import Any

import httpx
import pytest
from dotenv import load_dotenv

# Load .env from the tests/api/ directory at import time. Lets developers
# keep their local tokens in tests/api/.env (which is gitignored) without
# having to source it manually before each pytest run.
load_dotenv()


# ── Configuration fixtures ────────────────────────────────────────────────

def _required_env(key: str) -> str:
    value = os.environ.get(key)
    if not value:
        pytest.exit(
            f"Missing required env var {key}. "
            f"See tests/api/README.md for the full list. "
            f"Local default location: tests/api/.env",
            returncode=2,
        )
    return value


@pytest.fixture(scope="session")
def base_url() -> str:
    """Root URL of the SPARC instance under test, no trailing slash."""
    return _required_env("SPARC_TEST_BASE_URL").rstrip("/")


@pytest.fixture(scope="session")
def admin_token() -> str:
    """Bearer token for a user with the admin role."""
    return _required_env("SPARC_TEST_ADMIN_TOKEN")


@pytest.fixture(scope="session")
def user_token() -> str:
    """Bearer token for a non-admin user with read-level permissions only.

    Tests use this to assert that authorization gates reject privilege
    escalation attempts (e.g. a non-admin POSTing to ``/users``).
    """
    return _required_env("SPARC_TEST_USER_TOKEN")


# ── HTTP client fixtures ──────────────────────────────────────────────────

def _build_client(base_url: str, token: str | None = None) -> httpx.Client:
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return httpx.Client(
        base_url=base_url,
        headers=headers,
        timeout=httpx.Timeout(connect=5.0, read=30.0, write=10.0, pool=5.0),
        follow_redirects=False,
    )


@pytest.fixture(scope="session")
def admin_client(base_url: str, admin_token: str) -> Iterator[httpx.Client]:
    with _build_client(base_url, admin_token) as client:
        yield client


@pytest.fixture(scope="session")
def user_client(base_url: str, user_token: str) -> Iterator[httpx.Client]:
    with _build_client(base_url, user_token) as client:
        yield client


@pytest.fixture(scope="session")
def anon_client(base_url: str) -> Iterator[httpx.Client]:
    """Client with no Authorization header. Use for 401 coverage."""
    with _build_client(base_url, token=None) as client:
        yield client


@pytest.fixture(scope="session")
def bad_token_client(base_url: str) -> Iterator[httpx.Client]:
    """Client with a syntactically valid but unrecognized Bearer token.

    Distinct from ``anon_client`` because some controllers distinguish
    "no token" from "wrong token" — both should return 401, and the
    distinction lets tests assert that.
    """
    with _build_client(base_url, token="sparc_invalid_token_for_test") as client:
        yield client


# ── Smoke test the instance is reachable ─────────────────────────────────

@pytest.fixture(scope="session", autouse=True)
def _instance_is_alive(admin_client: httpx.Client) -> None:
    """Fail fast at session start if the instance is unreachable.

    Saves ~30s per run when the SPARC service is down — tests would
    otherwise each timeout individually with confusing connection errors.
    """
    try:
        response = admin_client.get("/api/v1/available")
    except httpx.HTTPError as exc:
        pytest.exit(
            f"SPARC instance unreachable at {admin_client.base_url}: {exc}. "
            f"Verify SPARC_TEST_BASE_URL points at a running instance.",
            returncode=2,
        )
    if response.status_code == 401:
        pytest.exit(
            "SPARC_TEST_ADMIN_TOKEN was rejected by /api/v1/available "
            "(401). Verify the token is current and has not been revoked.",
            returncode=2,
        )
    if not response.is_success:
        pytest.exit(
            f"Smoke check against /api/v1/available returned "
            f"{response.status_code}: {response.text[:200]}",
            returncode=2,
        )


# ── Session janitor: sweep orphaned test resources (#635) ─────────────────

# Every resource the suite creates is named with this prefix
# (see tests/api/_document_helpers.py). The janitor deletes ONLY resources whose
# name starts with it — never real data.
_TEST_NAME_PREFIX = "phase2-"

# Top-level, slug-addressable resource collections the suite creates. Nested
# resources (e.g. ksi_validations, attestations) cascade-delete with their
# parent boundary/evidence, so sweeping the parents is sufficient.
_JANITOR_ENDPOINTS = (
    "/api/v1/authorization_boundaries",  # incl. phase2-boundary-* and phase2-ksi-parent-*
    "/api/v1/ssp_documents",
    "/api/v1/sar_documents",
    "/api/v1/sap_documents",
    "/api/v1/poam_documents",
    "/api/v1/cdef_documents",
    "/api/v1/profile_documents",
    "/api/v1/control_catalogs",
    "/api/v1/control_mappings",
    "/api/v1/federation_peers",
)


def _sweep_orphans(client: httpx.Client) -> int:
    """Delete every resource whose name starts with the test prefix.

    Returns the number deleted. Safe by construction: it only issues DELETEs for
    items matching ``_TEST_NAME_PREFIX``, so real (non-test) data is never
    touched. Tolerant of individual endpoint/page failures so one bad collection
    can't abort the sweep.
    """
    deleted = 0
    for path in _JANITOR_ENDPOINTS:
        page = 1
        while True:
            try:
                resp = client.get(path, params={"page": page})
            except httpx.HTTPError:
                break
            if not resp.is_success:
                break
            payload = resp.json()
            if not isinstance(payload, dict):
                break
            for item in payload.get("data", []):
                name = str(item.get("name", ""))
                slug = item.get("slug") or item.get("id")
                if name.startswith(_TEST_NAME_PREFIX) and slug:
                    try:
                        d = client.delete(f"{path}/{slug}")
                        if d.status_code in (200, 202, 204, 404):
                            deleted += 1
                    except httpx.HTTPError:
                        pass
            meta = payload.get("meta", {})
            if page >= int(meta.get("pages", 1) or 1):
                break
            page += 1
    return deleted


@pytest.fixture(scope="session", autouse=True)
def _janitor(admin_client: httpx.Client, _instance_is_alive: None) -> Iterator[None]:
    """Sweep orphaned ``phase2-*`` test resources at session start AND end (#635).

    Per-module teardown is correct but not resilient: an interrupted or failed
    run skips it, so orphans (100+ ``phase2-boundary-*`` / ``phase2-ksi-parent-*``
    were found on prod) accumulate on any persistent instance. This makes cleanup
    self-healing — the pre-sweep clears leftovers from prior runs, the post-sweep
    catches anything this run missed. Deletes only test-prefixed resources.
    """
    _sweep_orphans(admin_client)  # pre-sweep: heal orphans from prior interrupted runs
    yield
    _sweep_orphans(admin_client)  # post-sweep: final cleanup regardless of test outcomes


# ── Response-shape helpers ────────────────────────────────────────────────

def assert_paginated_envelope(payload: Any) -> None:
    """Validate a list-endpoint response against the SPARC pagination contract.

    The contract is documented in ``docs/api/pagination.md``: every list
    endpoint returns ``{"data": [...], "meta": {"page", "pages", "count",
    "items"}}``. Helper rather than fixture because pytest fixtures cannot
    take payload arguments.
    """
    assert isinstance(payload, dict), f"Expected dict, got {type(payload).__name__}"
    assert "data" in payload, "Paginated response missing 'data' key"
    assert isinstance(payload["data"], list), "'data' must be a list"
    assert "meta" in payload, "Paginated response missing 'meta' key"
    meta = payload["meta"]
    for key in ("page", "pages", "count", "items"):
        assert key in meta, f"Paginated meta missing '{key}'"


def assert_error_envelope(response: httpx.Response, *, expected_status: int) -> None:
    """Validate an error response against SPARC's error contract.

    Documented in ``docs/api/errors.md``: every non-2xx response carries
    ``{"error": "<message>"}`` and may include ``"details": [...]`` for
    422 validation errors.
    """
    assert response.status_code == expected_status, (
        f"Expected {expected_status}, got {response.status_code}: {response.text[:200]}"
    )
    payload = response.json()
    assert isinstance(payload, dict), "Error response is not a JSON object"
    assert "error" in payload, f"Error response missing 'error' key: {payload}"
    assert isinstance(payload["error"], str) and payload["error"], (
        "'error' field must be a non-empty string"
    )
