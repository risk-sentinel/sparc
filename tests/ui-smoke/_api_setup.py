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
from helpers import smoke_tls_verify


def _client() -> httpx.Client:
    return httpx.Client(
        base_url=BASE_URL,
        headers={
            "Authorization": f"Bearer {SA_TOKEN}",
            "Accept": "application/json",
        },
        timeout=httpx.Timeout(connect=5.0, read=30.0, write=10.0, pool=5.0),
        follow_redirects=False,
        verify=smoke_tls_verify(),
    )


def _name(kind: str) -> str:
    return f"phase2-ui-{kind}-{uuid.uuid4().hex[:8]}"


def create_cdef(*, with_controls: bool = True) -> dict[str, Any]:
    """Create a component definition fixture, WITH a control basis by default.

    A CDEF created from metadata alone has no controls, and a CDEF with no
    controls cannot produce valid OSCAL — `implemented-requirements` must be
    non-empty, so every export of it 302s back carrying
    `oscal_validation_failed=1`.

    Eight test files call this and nothing cleans the documents up, so they
    accumulate on an instance until one lands first on an index. That is what
    made `test_document_exports` fail three cases on documents it had never
    heard of: the fixture, not the app. Populating from a published profile
    makes the fixture resemble a real component definition instead of a shell.

    Pass `with_controls=False` when a test specifically needs the empty-shell
    state (content-completeness gates, populate-from-profile flows).
    """
    with _client() as c:
        r = c.post(
            "/api/v1/cdef_documents",
            json={"cdef_document": {"name": _name("cdef"), "description": "ui-smoke"}},
        )
        r.raise_for_status()
        cdef = r.json()["data"]

        if not with_controls:
            return cdef

        profile = _first_published_profile(c)
        if profile is None:
            # Nothing to populate from; return the shell rather than failing a
            # fixture for a reason unrelated to the test that asked for it.
            return cdef

        populated = c.post(
            f"/api/v1/cdef_documents/{cdef['slug']}/source_from_profile",
            json={"source_profile_id": profile["id"]},
        )
        if populated.status_code == 200:
            return populated.json()["data"]
        return cdef


def _first_published_profile(c: httpx.Client) -> dict[str, Any] | None:
    """A published profile to give CDEF fixtures a control basis, or None."""
    r = c.get("/api/v1/profile_documents", params={"lifecycle_status": "published"})
    if r.status_code != 200:
        return None
    for item in r.json().get("data", []):
        if item.get("lifecycle_status") == "published":
            return item
    return None


def create_boundary() -> dict[str, Any]:
    with _client() as c:
        r = c.post(
            "/api/v1/authorization_boundaries",
            json={"authorization_boundary": {"name": _name("ab"), "description": "ui-smoke"}},
        )
        r.raise_for_status()
        return r.json()["data"]


def create_catalog() -> dict[str, Any]:
    """Create a control catalog (id-addressed). Unlike CDEF/SSP/profile, a fresh
    catalog is submittable for review without controls, so it's the reliable
    fixture for the review-queue flow."""
    with _client() as c:
        r = c.post(
            "/api/v1/control_catalogs",
            json={
                "control_catalog": {
                    "name": _name("catalog"),
                    "description": "ui-smoke",
                    "version": "0.0.1",
                    "source": "ui-smoke",
                }
            },
        )
        r.raise_for_status()
        return r.json()["data"]


def create_profile() -> dict[str, Any]:
    """A DRAFT profile, for tests that need editable OSCAL metadata panels.

    Created rather than discovered. `first_show_href` returns whatever happens
    to be first on the index, which is a published document on any real
    deployment — so the metadata-edit smoke skipped its own assertions
    ("non-draft — expand-only check") while reporting as passed, and scanning a
    large index for a candidate is also what made it time out. A fixture the
    test owns is draft by construction and reachable by a known URL.
    """
    with _client() as c:
        r = c.post(
            "/api/v1/profile_documents",
            # No lifecycle_status: the default is the unpublished, EDITABLE state.
            # `Lifecycle::LIFECYCLE_STATUSES` is `started / in_progress /
            # published` — there is no "draft", and sending one 422s.
            json={
                "profile_document": {
                    "name": _name("profile"),
                    "description": "ui-smoke",
                }
            },
        )
        r.raise_for_status()
        return r.json()["data"]


def create_tailorable_profile() -> dict[str, Any]:
    """#997 — an EDITABLE profile carrying real catalog controls with parameters.

    `create_profile()` is deliberately bare (no catalog, no controls), so it has
    nothing to tailor and the parameter panel legitimately renders nothing. A
    seeded baseline has the controls but is published, which is exactly the
    state that hides the editing controls — so neither fixture exercises the
    write path this issue adds.

    This one links a seeded catalog and selects controls that carry ODPs, so the
    form is present by construction rather than by luck of what the instance
    happens to hold.
    """
    with _client() as c:
        catalogs = c.get("/api/v1/control_catalogs", params={"per_page": 50})
        catalogs.raise_for_status()
        rows = catalogs.json().get("data", [])
        def _is_rev5(row: dict[str, Any]) -> bool:
            # `"5" in name` was the original second test and it is vacuous —
            # "800-53" contains a "5", so every 800-53 catalog matched and the
            # fixture silently took whichever row sorted first, Rev 4 included.
            # Match the revision explicitly instead.
            name = str(row.get("name", "")).lower()
            if "800-53" not in name:
                return False
            return "rev 5" in name or "revision 5" in name or "rev5" in name

        rev5 = next((row for row in rows if _is_rev5(row)), rows[0] if rows else None)
        if not rev5:
            raise RuntimeError("no control catalog on this instance to tailor against")

        created = c.post(
            "/api/v1/profile_documents",
            json={
                "profile_document": {
                    "name": _name("tailorable-profile"),
                    "description": "ui-smoke #997",
                    "control_catalog_id": rev5["id"],
                }
            },
        )
        created.raise_for_status()
        profile = created.json()["data"]

        # ac-1 and ac-2 carry ODPs in every Rev 5 catalog SPARC seeds.
        applied = c.put(
            f"/api/v1/profile_documents/{profile['slug']}/controls",
            json={"control_ids": ["ac-1", "ac-2"]},
        )
        applied.raise_for_status()
        return profile


def create_back_matter_resource(resourceable_type: str, resourceable_id: Any) -> dict[str, Any]:
    """A managed back-matter resource on a document.

    The back-matter edit smoke needs one to exist: a freshly created draft has
    no resources, so the per-resource Edit toggle it exercises never renders and
    the test used to skip its own assertion.
    """
    with _client() as c:
        r = c.post(
            "/api/v1/back_matter_resources",
            json={
                "back_matter_resource": {
                    "title": _name("back-matter"),
                    "description": "ui-smoke",
                    "href": "https://example.com/ui-smoke.pdf",
                    "media_type": "application/pdf",
                    "resourceable_type": resourceable_type,
                    "resourceable_id": resourceable_id,
                }
            },
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


def create_evidence(title: str | None = None) -> dict[str, Any]:
    """Evidence submitted by the smoke service account (#934).

    Collection provenance is never sent — the server stamps `collected_at`,
    `collected_by` and `collected_by_user_id` from the token's account, which is
    what the "Added by" smoke then looks for on screen. A record created here is
    therefore attributed to the service account, not to its owner.

    #947 — this used to be metadata-only, which no longer creates: evidence must
    support at least one control, and an artefact type must carry its file. Both
    rules live on the model, so they apply to the API exactly as they do to the
    form — a rule enforced only on the form was the defect #947 was filed about.
    So the record and its artefact are sent together, multipart.
    """
    with _client() as c:
        r = c.post(
            "/api/v1/evidences",
            data={
                "evidence[title]": title or _name("evidence"),
                "evidence[description]": "ui-smoke",
                "evidence[evidence_type]": "artifact",
                "evidence[status]": "collected",
                "evidence[source]": "ui-smoke",
                "evidence[control_ids]": "ac-2",
            },
            files={"evidence[file]": ("evidence.txt", b"ui-smoke artifact", "text/plain")},
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


def delete_evidences_titled(prefix: str) -> None:
    """Delete every evidence record whose title starts with `prefix`.

    #902's UI smoke creates evidence by driving the form, so there is no id to
    hold onto for teardown. These records carry files and publish to a public
    wiki when screenshots are captured, so they are swept by title instead of
    left for the janitor.
    """
    with _client() as c:
        resp = c.get("/api/v1/evidences", params={"q": prefix, "per_page": 100})
        if resp.status_code >= 400:
            return
        for item in resp.json().get("data", []):
            if str(item.get("title", "")).startswith(prefix):
                c.delete(f"/api/v1/evidences/{item['slug']}")


def deactivate_user(user_id: Any) -> None:
    """Cleanup for users created by the admin-create smoke. DELETE deactivates
    (soft) — the only teardown the API offers — mirroring the API suite."""
    with _client() as c:
        c.delete(f"/api/v1/users/{user_id}")
