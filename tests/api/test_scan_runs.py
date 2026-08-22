"""Tests for /api/v1/authorization_boundaries/:id/scan_runs (#447), swept for #995.

Three endpoints, nested under a boundary:

  GET  .../scan_runs        list, most recent first
  GET  .../scan_runs/:uuid  one run, with the detail the list omits
  POST .../scan_runs        ingest an HDF document

Ingest is the only way scanner findings come into SPARC, so this is the front
door for `test_scanner_findings.py` and `test_finding_dispositions.py` as well.

`create` accepts the document TWO ways — a multipart `file` upload or a raw HDF
JSON body — and they are not equivalent: only the multipart form can record a
`source_filename`. Both are exercised, because a contract with two documented
input modes and one tested mode is a contract half tested.

Counts are asserted against what the fixture DECLARES rather than against
whatever came back.
"""

from __future__ import annotations

import json
import uuid
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.findings, pytest.mark.phase2]

BOUNDARIES_PATH = "/api/v1/authorization_boundaries"
_SAMPLE_HDF = Path(__file__).parent / "fixtures" / "sample.hdf.json"

# What fixtures/sample.hdf.json declares: one control, one failing result.
DECLARED_FINDINGS = 1
DECLARED_FAILED = 1
DECLARED_SCANNER = "sparc-sample-profile"


def _runs_path(boundary_id: int) -> str:
    return f"{BOUNDARIES_PATH}/{boundary_id}/scan_runs"


@pytest.fixture(scope="module")
def boundary(admin_client: httpx.Client) -> Iterator[dict[str, Any]]:
    """This module's own boundary, so the index assertions can count."""
    suffix = uuid.uuid4().hex[:8]
    response = admin_client.post(
        BOUNDARIES_PATH,
        json={
            "authorization_boundary": {
                "name": f"phase2-scan-runs-{suffix}",
                "description": "#995 scan run sweep",
            }
        },
    )
    assert response.status_code in (200, 201), response.text
    created = response.json().get("data") or response.json()
    try:
        yield created
    finally:
        admin_client.delete(f"{BOUNDARIES_PATH}/{created['id']}")


@pytest.mark.happy
class TestIngest:
    def test_a_raw_hdf_body_is_ingested_with_the_counts_it_declares(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.post(
            _runs_path(boundary["id"]), json=json.loads(_SAMPLE_HDF.read_text())
        )

        assert response.status_code == 201, response.text
        run = response.json()["data"]
        assert run["scanner"] == DECLARED_SCANNER, run
        assert run["finding_count"] == DECLARED_FINDINGS, run
        assert run["failed_count"] == DECLARED_FAILED, run
        assert run["uuid"], "a run with no uuid cannot be addressed by show"

    def test_a_multipart_upload_records_the_filename_a_raw_body_cannot(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        """The difference between the two documented input modes.

        A raw JSON body carries no filename, so `source_filename` is null; the
        multipart form carries one and it is kept. An operator looking at a list
        of runs needs to know which uploaded file each came from.
        """
        raw = admin_client.post(
            _runs_path(boundary["id"]), json=json.loads(_SAMPLE_HDF.read_text())
        )
        assert raw.status_code == 201, raw.text
        assert raw.json()["data"]["source_filename"] is None, raw.text

        uploaded = admin_client.post(
            _runs_path(boundary["id"]),
            files={"file": ("sample.hdf.json", _SAMPLE_HDF.read_bytes(), "application/json")},
        )

        assert uploaded.status_code == 201, uploaded.text
        assert uploaded.json()["data"]["source_filename"] == "sample.hdf.json"

    def test_an_independent_read_returns_the_run_that_was_ingested(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        created = admin_client.post(
            _runs_path(boundary["id"]), json=json.loads(_SAMPLE_HDF.read_text())
        )
        assert created.status_code == 201, created.text
        run = created.json()["data"]

        fetched = admin_client.get(f"{_runs_path(boundary['id'])}/{run['uuid']}")

        assert fetched.status_code == 200, fetched.text
        data = fetched.json()["data"]
        assert data["uuid"] == run["uuid"]
        assert data["finding_count"] == DECLARED_FINDINGS

    def test_show_adds_the_provenance_the_list_omits(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        """Why `show` exists as well as `index` — the detail an auditor needs to
        tie a run back to the document it came from."""
        created = admin_client.post(
            _runs_path(boundary["id"]), json=json.loads(_SAMPLE_HDF.read_text())
        )
        run = created.json()["data"]

        data = admin_client.get(f"{_runs_path(boundary['id'])}/{run['uuid']}").json()["data"]

        assert len(data["raw_hdf_digest"]) == 64, data["raw_hdf_digest"]
        assert data["created_by"], "a run with no recorded ingester"
        assert "file_attached" in data


@pytest.mark.happy
class TestIndex:
    def test_lists_the_runs_ingested_into_this_boundary(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        created = admin_client.post(
            _runs_path(boundary["id"]), json=json.loads(_SAMPLE_HDF.read_text())
        )
        run_uuid = created.json()["data"]["uuid"]

        listed = admin_client.get(_runs_path(boundary["id"]), params={"items": 200})

        assert listed.status_code == 200, listed.text
        body = listed.json()
        assert set(body["meta"]) >= {"page", "pages", "count", "items"}
        assert any(row["uuid"] == run_uuid for row in body["data"]), (
            "a run that was just ingested is not in its boundary's list"
        )


@pytest.mark.validation
class TestRefusals:
    def test_a_document_with_no_hdf_controls_is_refused_by_name(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        before = admin_client.get(_runs_path(boundary["id"]), params={"items": 1})
        before_count = before.json()["meta"]["count"]

        response = admin_client.post(_runs_path(boundary["id"]), json={"not": "hdf"})

        assert_error_envelope(response, expected_status=422)
        assert "HDF" in response.json()["error"], response.text

        after = admin_client.get(_runs_path(boundary["id"]), params={"items": 1})
        assert after.json()["meta"]["count"] == before_count, (
            "a refused ingest still created a scan run"
        )

    def test_an_unknown_run_uuid_is_a_json_404(
        self, admin_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = admin_client.get(f"{_runs_path(boundary['id'])}/{uuid.uuid4()}")

        assert_error_envelope(response, expected_status=404)

    def test_an_unknown_boundary_is_a_json_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(_runs_path(0))

        assert_error_envelope(response, expected_status=404)


@pytest.mark.authz
class TestAuthorization:
    def test_a_non_admin_cannot_ingest_and_nothing_is_created(
        self,
        admin_client: httpx.Client,
        user_client: httpx.Client,
        boundary: dict[str, Any],
    ) -> None:
        before = admin_client.get(_runs_path(boundary["id"]), params={"items": 1})
        before_count = before.json()["meta"]["count"]

        response = user_client.post(
            _runs_path(boundary["id"]), json=json.loads(_SAMPLE_HDF.read_text())
        )

        assert response.status_code == 403, response.text
        after = admin_client.get(_runs_path(boundary["id"]), params={"items": 1})
        assert after.json()["meta"]["count"] == before_count, (
            "a refused caller still ingested a scan run"
        )

    def test_a_non_admin_cannot_list_the_runs(
        self, user_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = user_client.get(_runs_path(boundary["id"]))

        assert response.status_code == 403, response.text


@pytest.mark.auth
class TestAuthentication:
    def test_ingest_refuses_an_anonymous_caller(
        self, anon_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        response = anon_client.post(
            _runs_path(boundary["id"]), json=json.loads(_SAMPLE_HDF.read_text())
        )

        assert response.status_code == 401, response.text

    def test_index_refuses_an_anonymous_caller(
        self, anon_client: httpx.Client, boundary: dict[str, Any]
    ) -> None:
        assert anon_client.get(_runs_path(boundary["id"])).status_code == 401
