"""A triaged boundary, for the HDF triage export endpoints (#447, #809).

The amendments export, the signed package and the aggregation all need the same
thing in front of them: a boundary that has had a scan ingested and at least one
finding triaged. Building that is four requests, and building it three times in
three modules is how three modules end up disagreeing about what "triaged"
means.

The flow, which is also the product's flow:

    create boundary -> POST scan_runs (ingest HDF) -> read the finding
                    -> POST disposition (triage it)

`inherited` is the disposition kind used because every kind must link a subject
of a specific class (`FindingDispositionService::LINKAGE`) and that one links an
AuthorizationBoundary, which we already have — no evidence file, attestation or
POA&M finding has to exist first.

Underscore-prefixed file name signals "internal to the test suite". The
inventory generator reads helpers a module imports, so an endpoint covered
through this file is still credited to the module that imports it.
"""

from __future__ import annotations

import json
import uuid
from pathlib import Path
from typing import Any

import httpx

BOUNDARIES_PATH = "/api/v1/authorization_boundaries"
FINDINGS_PATH = "/api/v1/scanner_findings"

_SAMPLE_HDF = Path(__file__).parent / "fixtures" / "sample.hdf.json"


def create_boundary(admin_client: httpx.Client, label: str) -> dict[str, Any]:
    suffix = uuid.uuid4().hex[:8]
    response = admin_client.post(
        BOUNDARIES_PATH,
        json={
            "authorization_boundary": {
                "name": f"phase2-{label}-{suffix}",
                "description": "#995 HDF triage sweep",
            }
        },
    )
    assert response.status_code in (200, 201), response.text
    return response.json().get("data") or response.json()


def triaged_boundary(admin_client: httpx.Client, label: str) -> dict[str, Any]:
    """A boundary with one ingested scan and one triaged finding.

    Every step is asserted. A later export test that found nothing to export
    would otherwise pass while proving nothing, which is the failure mode this
    whole sweep exists to remove.
    """
    boundary = create_boundary(admin_client, label)

    ingested = admin_client.post(
        f"{BOUNDARIES_PATH}/{boundary['id']}/scan_runs",
        json=json.loads(_SAMPLE_HDF.read_text()),
    )
    assert ingested.status_code == 201, ingested.text

    listed = admin_client.get(f"{BOUNDARIES_PATH}/{boundary['id']}/scanner_findings")
    assert listed.status_code == 200, listed.text
    findings = listed.json()["data"]
    assert findings, "the scan ingested no findings, so there is nothing to triage"
    finding = findings[0]

    dispositioned = admin_client.post(
        f"{FINDINGS_PATH}/{finding['uuid']}/disposition",
        json={
            "kind": "inherited",
            "reason": "#995 HDF triage sweep",
            "linked_subject_type": "AuthorizationBoundary",
            "linked_subject_id": boundary["id"],
        },
    )
    assert dispositioned.status_code == 201, dispositioned.text

    return {
        "boundary": boundary,
        "finding": finding,
        "disposition": dispositioned.json()["data"],
    }


def delete_boundary(admin_client: httpx.Client, boundary: dict[str, Any]) -> None:
    admin_client.delete(f"{BOUNDARIES_PATH}/{boundary['id']}")
