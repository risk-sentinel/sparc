"""Shared helpers for document-shaped controllers (SSP, SAR, SAP, POAM, CDEF, Profile).

Every document controller follows the same surface:
    GET    /api/v1/<resource>            (paginated list)
    GET    /api/v1/<resource>/:slug      (show)
    POST   /api/v1/<resource>            (create)
    PUT    /api/v1/<resource>/:slug      (update)
    DELETE /api/v1/<resource>/:slug      (destroy / soft-delete)
    GET    /api/v1/<resource>/:slug/export

SSP and SAR add ``convert`` (Excel upload) and ``update_fields`` (bulk
edit). The shared helpers below factor out the pieces that are identical
across all six modules; each test module supplies path + param_key and
tests its own controller-specific behavior on top.

Underscore-prefixed file name signals "internal to the test suite" — not
imported anywhere outside ``tests/api/``.
"""

from __future__ import annotations

import uuid
from typing import Any

import httpx


def make_payload(param_key: str, fields: dict[str, Any] | None = None) -> dict[str, Any]:
    """Build a minimum-viable create payload.

    The standard required fields across document types are ``name`` and
    a parent reference (authorization_boundary_id, profile_document_id,
    etc.). Each controller's required fields are passed in via
    ``fields``; this helper just adds a unique-suffix name.
    """
    suffix = uuid.uuid4().hex[:8]
    body = dict(fields or {})
    body.setdefault("name", f"phase2-test-{param_key}-{suffix}")
    body.setdefault("description", "Created by Phase 2 pytest suite")
    return {param_key: body}


def create_doc(client: httpx.Client, path: str, payload: dict[str, Any]) -> dict[str, Any]:
    """POST and return the serialized document."""
    response = client.post(path, json=payload)
    assert response.status_code in (200, 201), (
        f"Create failed at {path}: {response.status_code} {response.text[:300]}"
    )
    return response.json()["data"]


def delete_doc(client: httpx.Client, path: str, slug: str) -> None:
    """Delete a document by slug. 404 is treated as a successful cleanup."""
    response = client.delete(f"{path}/{slug}")
    assert response.status_code in (200, 404), (
        f"Delete failed at {path}/{slug}: {response.status_code} {response.text[:300]}"
    )
