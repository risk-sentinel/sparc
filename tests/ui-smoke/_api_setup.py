"""Minimal /api/v1 helpers to provision UI-smoke fixtures.

The UI-smoke suite drives the browser, but several #643 flows need a document
in a specific state (empty, or submitted-for-review) that is tedious to build
click-by-click. We create/tear those down through the REST API using the same
service-account token the cookie-bridge uses (``SPARC_SMOKE_SA_TOKEN``), then
drive the UI against them. Every created record is ``phase2-*`` named so the
API suite's session janitor (#635) sweeps any strays.

Underscore-prefixed file name signals "internal to the test suite".
"""

from __future__ import annotations

import uuid
from typing import Any

import httpx

from conftest import BASE_URL, SA_TOKEN


def _client() -> httpx.Client:
    return httpx.Client(
        base_url=BASE_URL,
        headers={
            "Authorization": f"Bearer {SA_TOKEN}",
            "Accept": "application/json",
        },
        timeout=httpx.Timeout(connect=5.0, read=30.0, write=10.0, pool=5.0),
        follow_redirects=False,
    )


def _name(kind: str) -> str:
    return f"phase2-ui-{kind}-{uuid.uuid4().hex[:8]}"


def create_cdef() -> dict[str, Any]:
    with _client() as c:
        r = c.post(
            "/api/v1/cdef_documents",
            json={"cdef_document": {"name": _name("cdef"), "description": "ui-smoke"}},
        )
        r.raise_for_status()
        return r.json()["data"]


def create_boundary() -> dict[str, Any]:
    with _client() as c:
        r = c.post(
            "/api/v1/authorization_boundaries",
            json={"authorization_boundary": {"name": _name("ab"), "description": "ui-smoke"}},
        )
        r.raise_for_status()
        return r.json()["data"]


def create_ssp(boundary_id: int) -> dict[str, Any]:
    with _client() as c:
        r = c.post(
            "/api/v1/ssp_documents",
            json={
                "ssp_document": {
                    "name": _name("ssp"),
                    "description": "ui-smoke",
                    "authorization_boundary_id": boundary_id,
                }
            },
        )
        r.raise_for_status()
        return r.json()["data"]


def submit_for_review(resource: str, ident: Any) -> int:
    """Submit a document for review. Returns the HTTP status (200 on success)."""
    with _client() as c:
        return c.post(f"/api/v1/{resource}/{ident}/submit_for_review").status_code


def published_profile_slug() -> Any | None:
    """id/slug of any published profile on the instance, else None."""
    with _client() as c:
        r = c.get("/api/v1/profile_documents", params={"items": 100})
        if r.status_code != 200:
            return None
        for item in r.json().get("data", []):
            status = item.get("lifecycle_status") or item.get("status")
            if status == "published":
                return item.get("slug") or item.get("id")
    return None


def delete_doc(resource: str, ident: Any) -> None:
    with _client() as c:
        c.delete(f"/api/v1/{resource}/{ident}")
