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
