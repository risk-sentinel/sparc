"""Every document type's API writes what its page's metadata forms write (#1267).

The pages edit a document's name and version, and in the OSCAL Metadata form
its OSCAL Version, Published Date, Description and the rest of its OSCAL
metadata (roles, parties, revisions, remarks, ...). Before #1267:

  - Published Date was writable on no API endpoint;
  - OSCAL Version not on SSP, SAR, SAP or POA&M, and SAR's version not at all;
  - the rest of the OSCAL metadata was returned as `oscal_metadata` but could
    not be written back.

Each case writes through PUT and confirms through an independent GET.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import httpx
import pytest

from _document_helpers import create_doc, make_payload

# (resource, param key, version field, needs a boundary, addressed by)
TYPES = [
    ("profile_documents", "profile_document", "profile_version", False, "slug"),
    ("cdef_documents", "cdef_document", "cdef_version", False, "slug"),
    ("ssp_documents", "ssp_document", "ssp_version", True, "slug"),
    ("sar_documents", "sar_document", "sar_version", True, "slug"),
    ("sap_documents", "sap_document", "sap_version", True, "slug"),
    ("poam_documents", "poam_document", "poam_version", True, "slug"),
    ("control_catalogs", "control_catalog", "version", False, "id"),
]

REVISIONS = [{"version": "1.0", "title": "phase2 first issue", "published": "2026-09-01T00:00:00Z"}]


@pytest.fixture(params=TYPES, ids=[t[0] for t in TYPES])
def document(
    request, admin_client: httpx.Client, seeded_boundary_id: int
) -> Iterator[dict[str, Any]]:
    resource, key, version_field, needs_boundary, ident = request.param
    fields: dict[str, Any] = {}
    if needs_boundary:
        fields["authorization_boundary_id"] = seeded_boundary_id
    if resource == "control_catalogs":
        fields.update({"version": "0.0.1", "source": "phase2-test"})
    path = f"/api/v1/{resource}"
    doc = create_doc(admin_client, path, make_payload(key, fields))
    # A test that renames the document moves its slug, and updates "path" to
    # match, so cleanup deletes through whatever the test left there.
    state = {"path": f"{path}/{doc[ident]}", "key": key, "version_field": version_field}
    try:
        yield state
    finally:
        response = admin_client.delete(state["path"])
        assert response.status_code in (200, 404), response.text[:300]


def _show(client: httpx.Client, path: str) -> dict[str, Any]:
    response = client.get(path)
    assert response.status_code == 200, response.text[:300]
    return response.json()["data"]


def test_put_writes_name_version_and_oscal_metadata(admin_client: httpx.Client, document) -> None:
    new_name = f"phase2-test-renamed-{uuid.uuid4().hex[:8]}"
    body = {
        document["key"]: {
            "name": new_name,
            document["version_field"]: "2.1",
            "oscal_version": "1.1.3",
            "published": "2026-10-01T00:00:00Z",
            "description": "phase2 description written through the API",
            "oscal_metadata": {"remarks": "phase2 remarks", "revisions": REVISIONS},
        }
    }
    response = admin_client.put(document["path"], json=body)
    assert response.status_code == 200, response.text[:400]

    # The slug follows the name, so read back through the URL the write returned.
    written = response.json()["data"]
    ident = (
        written["id"]
        if document["path"].startswith("/api/v1/control_catalogs")
        else written["slug"]
    )
    path = document["path"].rsplit("/", 1)[0] + f"/{ident}"
    document["path"] = path

    shown = _show(admin_client, path)
    assert shown["name"] == new_name
    assert shown[document["version_field"]] == "2.1"
    assert shown["oscal_version"] == "1.1.3"
    assert shown["published"] == "2026-10-01T00:00:00Z"
    assert shown["description"] == "phase2 description written through the API"
    assert shown["oscal_metadata"]["remarks"] == "phase2 remarks"
    assert shown["oscal_metadata"]["revisions"] == REVISIONS


def test_oscal_metadata_keys_left_out_are_kept(admin_client: httpx.Client, document) -> None:
    key = document["key"]
    first = admin_client.put(
        document["path"], json={key: {"oscal_metadata": {"revisions": REVISIONS}}}
    )
    assert first.status_code == 200, first.text[:400]
    second = admin_client.put(
        document["path"], json={key: {"oscal_metadata": {"remarks": "phase2 only remarks"}}}
    )
    assert second.status_code == 200, second.text[:400]

    metadata = _show(admin_client, document["path"])["oscal_metadata"]
    assert metadata["remarks"] == "phase2 only remarks"
    assert metadata["revisions"] == REVISIONS, "a key the request left out was dropped"


def test_unknown_oscal_metadata_key_is_refused(admin_client: httpx.Client, document) -> None:
    before = _show(admin_client, document["path"])
    response = admin_client.put(
        document["path"],
        json={
            document["key"]: {
                "description": "phase2 must not land",
                "oscal_metadata": {"not-an-oscal-key": 1},
            }
        },
    )
    assert response.status_code == 422, response.text[:400]
    assert "oscal_metadata.not-an-oscal-key" in response.text

    after = _show(admin_client, document["path"])
    assert after["description"] == before["description"], "a refused request changed the document"
