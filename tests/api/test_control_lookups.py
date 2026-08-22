"""Tests for /api/v1/controls — cross-catalog control lookup (#902 follow-up).

Two endpoints:

  GET /api/v1/controls?q=ac-2       search every loaded catalog
  GET /api/v1/controls/resolve?id=  resolve one identifier to its canonical form

These exist to close a specific defect: SPARC displays the PADDED form (AC-02)
while catalogs store the CANONICAL one (ac-2), so a user typing what they saw
produced a link that matched nothing, silently — every seeded evidence link was
dead that way. So the assertions below are mostly about identifier equivalence:
the three legitimate spellings of one control must all arrive at the same
control, or the endpoint is not doing the job it was added for.

The index returns `meta: {total, limit, scoped_to_profile, profile_title}`
rather than the paginated `{page, pages, count, items}` envelope used elsewhere.
That is deliberate — this is a lookup, not a collection read — and it is pinned
here so the difference is a documented decision rather than a surprise.
"""

from __future__ import annotations

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.catalogs, pytest.mark.phase2]

INDEX_PATH = "/api/v1/controls"
RESOLVE_PATH = "/api/v1/controls/resolve"

# One control, spelled the three ways a caller might legitimately supply it.
# Canonical, padded (what the UI shows), and the spaced enhancement form.
CANONICAL = "ac-2"
PADDED = "AC-02"
ENHANCEMENT_SPELLINGS = ["AC-2 (1)", "ac-2.1", "AC-02.01"]


def _resolve(client: httpx.Client, identifier: str) -> httpx.Response:
    return client.get(RESOLVE_PATH, params={"id": identifier})


@pytest.mark.happy
class TestResolve:
    def test_the_canonical_form_resolves(self, admin_client: httpx.Client) -> None:
        response = _resolve(admin_client, CANONICAL)

        assert response.status_code == 200, response.text
        data = response.json()["data"]
        assert data["control_id"] == CANONICAL
        assert data["resolved"] is True
        assert data["submitted"] == CANONICAL, "the endpoint did not echo what was asked"

    def test_the_padded_form_resolves_to_the_same_control(self, admin_client: httpx.Client) -> None:
        """The defect this endpoint closes.

        AC-02 is what SPARC shows a user; ac-2 is what the catalog stores.
        Typing the former used to match nothing, silently.
        """
        canonical = _resolve(admin_client, CANONICAL).json()["data"]
        padded = _resolve(admin_client, PADDED)

        assert padded.status_code == 200, padded.text
        data = padded.json()["data"]
        assert data["control_id"] == canonical["control_id"], (
            f"{PADDED} and {CANONICAL} resolved to different controls"
        )
        assert data["title"] == canonical["title"]
        assert data["submitted"] == PADDED, "the echo lost the caller's spelling"

    def test_both_forms_are_offered_back(self, admin_client: httpx.Client) -> None:
        """A validating client needs the canonical form to store and the padded
        form to display, so the answer carries both."""
        data = _resolve(admin_client, PADDED).json()["data"]

        assert data["control_id"] == CANONICAL
        assert data["padded_id"] == PADDED
        assert data["display_id"], data

    @pytest.mark.parametrize("spelling", ENHANCEMENT_SPELLINGS)
    def test_every_enhancement_spelling_reaches_the_same_enhancement(
        self, admin_client: httpx.Client, spelling: str
    ) -> None:
        """An enhancement has three spellings too, and the spaced one is what a
        person types."""
        response = _resolve(admin_client, spelling)

        assert response.status_code == 200, f"{spelling!r}: {response.text}"
        data = response.json()["data"]
        assert data["control_id"] == "ac-2.1", f"{spelling!r} resolved to {data['control_id']}"
        assert data["enhancement"] is True, data

    def test_an_enhancement_is_not_confused_with_its_base_control(
        self, admin_client: httpx.Client
    ) -> None:
        """Both directions. Resolving the base must not return the enhancement,
        or the equivalence above would be matching too eagerly."""
        base = _resolve(admin_client, CANONICAL).json()["data"]

        assert base["control_id"] == CANONICAL
        assert base["enhancement"] is False, base


@pytest.mark.validation
class TestUnknownIdentifier:
    def test_an_unknown_identifier_is_refused_and_says_what_it_tried(
        self, admin_client: httpx.Client
    ) -> None:
        """SI-10 — a caller cannot invent an identifier. The refusal has to be
        distinguishable from a match, and has to say what was submitted, or a
        client cannot tell a typo from an unloaded catalog.
        """
        response = _resolve(admin_client, "not-a-control")

        assert_error_envelope(response, expected_status=404)
        body = response.json()
        assert body["data"]["resolved"] is False, body
        assert body["data"]["submitted"] == "not-a-control", body
        assert body["details"], "the refusal named no reason"


@pytest.mark.happy
class TestIndex:
    def test_returns_the_lookup_envelope(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(INDEX_PATH)

        assert response.status_code == 200, response.text
        body = response.json()
        assert isinstance(body["data"], list)
        assert set(body["meta"]) >= {"total", "limit", "scoped_to_profile"}, body["meta"]

    def test_a_search_narrows_the_result(self, admin_client: httpx.Client) -> None:
        """Both directions: the search must return fewer than everything, and
        must return the control searched for. Asserting only the second would
        pass against a `q` the endpoint ignored."""
        everything = admin_client.get(INDEX_PATH).json()
        searched = admin_client.get(INDEX_PATH, params={"q": CANONICAL}).json()

        assert searched["meta"]["total"] < everything["meta"]["total"], (
            f"q={CANONICAL} returned {searched['meta']['total']} of "
            f"{everything['meta']['total']} — the search did not narrow anything"
        )
        assert any(row["control_id"] == CANONICAL for row in searched["data"]), (
            f"q={CANONICAL} did not return {CANONICAL}"
        )

    def test_the_limit_is_respected_and_reported(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(INDEX_PATH, params={"family": "AC", "limit": 3})

        body = response.json()
        assert len(body["data"]) == 3, f"limit=3 returned {len(body['data'])} rows"
        assert body["meta"]["limit"] == 3, body["meta"]
        assert body["meta"]["total"] > 3, (
            "meta.total collapsed to the page size, so a client cannot tell how "
            "many matches there really are"
        )

    def test_a_family_filter_returns_only_that_family(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(INDEX_PATH, params={"family": "AC", "limit": 50})

        rows = response.json()["data"]
        assert rows, "family=AC matched nothing"
        offenders = [r["control_id"] for r in rows if r["family_code"] != "AC"]
        assert not offenders, f"family=AC also returned {offenders}"


@pytest.mark.authz
class TestNonAdminAccess:
    def test_a_non_admin_may_look_controls_up(self, user_client: httpx.Client) -> None:
        """The allow leg, on a genuinely non-admin token.

        Catalog content is global read-only reference data, per the controller's
        AC-3 note, and the whole point of the endpoint is that a caller
        belonging to no catalog can validate an identifier. Pinned in this
        direction so a later blanket tightening fails here rather than quietly
        breaking evidence linking for everyone but admins.
        """
        assert user_client.get(INDEX_PATH, params={"q": CANONICAL}).status_code == 200
        assert _resolve(user_client, PADDED).status_code == 200


@pytest.mark.auth
class TestAuthentication:
    def test_index_refuses_an_anonymous_caller(self, anon_client: httpx.Client) -> None:
        assert anon_client.get(INDEX_PATH).status_code == 401

    def test_resolve_refuses_an_anonymous_caller(self, anon_client: httpx.Client) -> None:
        assert _resolve(anon_client, CANONICAL).status_code == 401
