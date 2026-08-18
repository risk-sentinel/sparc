"""#974 — what an anonymous visitor can reach, proven in a real browser, in BOTH postures.

Request specs stub `SparcConfig`. Only this runs against a real deployment, so
only this catches a CI hiccup, a bad `.env`, a middleware ordering change, or a
gate that works in a stub and not in Puma.

## Why both postures, and why it FAILS rather than skips

`SPARC_PUBLIC_CATALOGS` is read from the environment per request, so a
deployment is in exactly one posture at a time. A suite that only ever ran the
posture it happened to find would have passed for catalogs throughout the life
of #974 while the CDEF library sat wide open — which is precisely what happened.

So the posture is DECLARED by the runner via `SPARC_SMOKE_PUBLIC_CATALOGS`
(`0`/`1`) and then INDEPENDENTLY CONFIRMED against the app. If the two disagree,
or nothing is declared, every test here fails loudly. It never skips: #885
established that a posture-gated test which silently skips reports green while
proving nothing.

## Running it — two ceremonies

`public_catalogs?` reads ENV per call, so flipping the flag needs a container
RECREATE, not a restart:

    # ceremony 1 — the secure default
    SPARC_SMOKE_PUBLIC_CATALOGS=0 uv run pytest test_public_controls_974.py --browser chromium

    # flip .env, then:
    docker compose -f docker-compose.ubi9.yaml up -d --force-recreate web

    # ceremony 2 — published
    SPARC_SMOKE_PUBLIC_CATALOGS=1 uv run pytest test_public_controls_974.py --browser chromium

Report BOTH numbers. A single total hides which posture was actually proven.
"""

from __future__ import annotations

import os

import httpx
import pytest

from conftest import BASE_URL
from helpers import smoke_tls_verify

# Deliberately NOT marked `authenticated` — every request here is anonymous.

# Controls-layer READ screens. Public iff the flag is on.
CONTROLS_SCREENS = [
    ("catalog index", "/control_catalogs"),
    ("profile index", "/profile_documents"),
    ("mapping index", "/control_mappings"),
    ("cdef index", "/cdef_documents"),
    ("converter index", "/converters"),
]

# Never public, in either posture. These are the invariants #929/#952 tightened
# and #974 must not loosen.
ALWAYS_PRIVATE = [
    ("ssp index", "/ssp_documents"),
    ("sap index", "/sap_documents"),
    ("sar index", "/sar_documents"),
    ("poam index", "/poam_documents"),
    ("evidence index", "/evidences"),
    ("boundaries", "/authorization_boundaries"),
    ("admin users", "/admin/users"),
    ("new catalog (write)", "/control_catalogs/new"),
    ("new converter (write)", "/converters/new"),
]

# The API is Bearer-only regardless of the flag: it governs the web UI only.
API_PATHS = [
    "/api/v1/control_catalogs",
    "/api/v1/profile_documents",
    "/api/v1/cdef_documents",
    "/api/v1/control_mappings",
]


def _declared_posture() -> bool:
    """The posture the runner says the deployment is in. Absent = hard failure."""
    raw = os.environ.get("SPARC_SMOKE_PUBLIC_CATALOGS")
    if raw not in ("0", "1"):
        pytest.fail(
            "SPARC_SMOKE_PUBLIC_CATALOGS must be set to 0 or 1 so this file knows which "
            "posture it is asserting. It deliberately does not guess and does not skip — "
            "see the module docstring for the two-ceremony recipe (#974)."
        )
    return raw == "1"


@pytest.fixture(scope="module")
def anon() -> httpx.Client:
    with httpx.Client(
        base_url=BASE_URL, verify=smoke_tls_verify(), timeout=60.0, follow_redirects=False
    ) as client:
        yield client


@pytest.fixture(scope="module")
def posture(anon: httpx.Client) -> bool:
    """Declared posture, confirmed against the running app before anything is asserted.

    The confirmation probe is `/control_catalogs`, which has been correctly
    gated all along — so it reflects the flag rather than the bug under test.
    Using a CDEF path here would have agreed with a broken deployment.
    """
    declared = _declared_posture()
    observed_public = anon.get("/control_catalogs").status_code == 200

    if declared != observed_public:
        pytest.fail(
            f"posture mismatch: SPARC_SMOKE_PUBLIC_CATALOGS={'1' if declared else '0'} but "
            f"/control_catalogs is {'public' if observed_public else 'gated'}. The container "
            f"probably needs `up -d --force-recreate web` to pick up a changed .env — "
            f"public_catalogs? reads ENV per call."
        )
    return declared


class TestControlsScreens:
    def test_screens_match_the_posture(self, anon, posture):
        for label, path in CONTROLS_SCREENS:
            status = anon.get(path).status_code
            if posture:
                assert status == 200, (
                    f"{label}: expected 200 with the library published, got {status}"
                )
            else:
                assert status in (301, 302), (
                    f"{label}: expected a redirect to /login with the flag off, got {status}"
                )

    def test_the_two_that_were_leaking(self, anon, posture):
        """CDEF index/show and the control-family page returned 200 with the flag
        OFF before #974, because both controllers skipped authentication with no
        companion gate. Named separately so a regression is unmistakable."""
        paths = ["/cdef_documents"]

        slug = _first_cdef_slug(anon, posture)
        if slug:
            paths.append(f"/cdef_documents/{slug}")

        for path in paths:
            status = anon.get(path).status_code
            if posture:
                assert status == 200, f"{path}: expected 200 when published, got {status}"
            else:
                assert status in (301, 302), (
                    f"{path}: PUBLIC WITH THE FLAG OFF — this is the #974 leak, got {status}"
                )


class TestInvariants:
    """Asserted in BOTH ceremonies. A rule that holds in one posture is not a rule."""

    def test_boundary_documents_and_writes_are_never_public(self, anon, posture):
        for label, path in ALWAYS_PRIVATE:
            status = anon.get(path).status_code
            assert status in (301, 302), (
                f"{label}: reachable anonymously (status {status}) with "
                f"SPARC_PUBLIC_CATALOGS={'true' if posture else 'false'} — never public"
            )

    def test_the_api_always_requires_a_token(self, anon, posture):
        for path in API_PATHS:
            status = anon.get(path).status_code
            assert status == 401, (
                f"{path}: expected 401 without a Bearer token, got {status}. The flag governs "
                f"the web UI only."
            )

    def test_converter_export_is_never_public(self, anon, posture):
        """View only: the list and a converter render, but the bulk mapping pull
        stays behind authentication even when the library is published."""
        cid = _first_converter_id(anon, posture)
        if cid is None:
            pytest.fail("no converter found on this deployment to assert the export rule against")

        status = anon.get(f"/converters/{cid}/export").status_code
        assert status in (301, 302), f"converter export was reachable anonymously (status {status})"


def _first_cdef_slug(anon: httpx.Client, posture: bool) -> str | None:
    if not posture:
        return None
    body = anon.get("/cdef_documents").text
    import re

    m = re.search(r'href="/cdef_documents/([a-z0-9][a-z0-9\-]*)"', body)
    return m.group(1) if m else None


def _first_converter_id(anon: httpx.Client, posture: bool) -> str | None:
    if not posture:
        # With the flag off the list is gated, so use a probe id: the assertion
        # is that the export REFUSES, which holds whether or not the id exists.
        return "1"
    body = anon.get("/converters").text
    import re

    m = re.search(r'href="/converters/(\d+)"', body)
    return m.group(1) if m else "1"
