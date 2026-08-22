"""Tests for /api/v1/guides (#784).

Two read-only endpoints serving the User Guides bundled into the image:

  GET /api/v1/guides         list — slug, title, summary
  GET /api/v1/guides/:slug   one guide, with rendered HTML

The content is the wiki User Guides shipped in the deployment, so these assert
the CONTRACT and the relationship between the two endpoints rather than any
particular guide's text — a guide renamed in the wiki must not fail the API
suite.

Deliberately omitted from `/api/v1/available`; see the note in
`discovery_controller.rb`. That is why this module resolves a slug from the
index rather than from discovery.
"""

from __future__ import annotations

import httpx
import pytest

from conftest import assert_error_envelope

pytestmark = [pytest.mark.phase2]


PATH = "/api/v1/guides"


@pytest.fixture(scope="module")
def listed(admin_client: httpx.Client) -> dict[str, object]:
    response = admin_client.get(PATH)
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.happy
class TestIndex:
    def test_returns_the_documented_collection_envelope(self, listed: dict) -> None:
        assert isinstance(listed["data"], list)
        assert set(listed["meta"]) >= {"count"}, listed["meta"]

    def test_ships_guides_and_describes_each_one(self, listed: dict) -> None:
        rows = listed["data"]
        assert rows, "the image shipped no user guides at all"
        assert listed["meta"]["count"] == len(rows), (
            f"meta.count says {listed['meta']['count']} for {len(rows)} rows"
        )
        for row in rows:
            assert set(row) == {"slug", "title", "summary"}, row
            assert row["slug"] and row["title"], row

    def test_slugs_are_unique(self, listed: dict) -> None:
        """The slug addresses the guide in `show`, so a duplicate makes one of
        them unreachable."""
        slugs = [row["slug"] for row in listed["data"]]
        assert len(slugs) == len(set(slugs)), sorted(slugs)


@pytest.mark.happy
class TestShow:
    def test_every_listed_guide_can_be_fetched(
        self, admin_client: httpx.Client, listed: dict
    ) -> None:
        """The index advertises these slugs; each must resolve.

        Checked across every guide rather than a sampled one — the failure this
        catches is a single guide that the library lists but cannot render.
        """
        for row in listed["data"]:
            response = admin_client.get(f"{PATH}/{row['slug']}")

            assert response.status_code == 200, (
                f"{row['slug']} is listed by the index but {response.status_code} on show"
            )
            body = response.json()["data"]
            assert body["slug"] == row["slug"]
            assert body["title"] == row["title"], (
                f"{row['slug']}: index and show disagree about the title"
            )

    def test_show_adds_the_rendered_html_the_index_omits(
        self, admin_client: httpx.Client, listed: dict
    ) -> None:
        """Why `show` exists as well as `index`."""
        first = listed["data"][0]

        body = admin_client.get(f"{PATH}/{first['slug']}").json()["data"]

        assert body.get("html"), f"{first['slug']} rendered no html"
        assert set(first) == {"slug", "title", "summary"}, (
            "the index now returns html too; this test's premise is stale"
        )

    def test_show_wraps_its_payload_like_every_other_resource_read(
        self, admin_client: httpx.Client, listed: dict
    ) -> None:
        """#1036 — `show` used to return the guide at the TOP LEVEL.

        `index` wraps in `data` and so does every other resource read in this
        API, so an integrator with one response handler got `data` everywhere
        and nil here. The inconsistency was invisible because both guides
        endpoints were undocumented. Resolved by wrapping, since nothing in the
        application consumed the endpoint — the in-app Help Center is a thin
        client of `UserGuideLibrary`, not of the API.
        """
        body = admin_client.get(f"{PATH}/{listed['data'][0]['slug']}").json()

        assert "data" in body, "guides#show is unwrapped again — see #1036"
        assert set(body["data"]) == {"slug", "title", "summary", "html"}, body["data"]


@pytest.mark.validation
class TestUnknownGuide:
    def test_an_unknown_slug_is_a_json_404(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(f"{PATH}/phase2-no-such-guide-exists")

        assert_error_envelope(response, expected_status=404)


@pytest.mark.auth
class TestAuthentication:
    def test_index_refuses_an_anonymous_caller(self, anon_client: httpx.Client) -> None:
        """Product documentation, but still behind the API's auth boundary —
        an unauthenticated reader must not learn what this instance ships."""
        assert anon_client.get(PATH).status_code == 401

    def test_show_refuses_an_anonymous_caller(
        self, anon_client: httpx.Client, listed: dict
    ) -> None:
        response = anon_client.get(f"{PATH}/{listed['data'][0]['slug']}")

        assert response.status_code == 401, response.text


@pytest.mark.authz
class TestNonAdminAccess:
    def test_a_non_admin_may_read_the_guides(self, user_client: httpx.Client, listed: dict) -> None:
        """The allow leg, on a genuinely non-admin token.

        These are shipped product docs with no record data — the controller's
        NIST note says as much — so any authenticated user may read them. Pinned
        in this direction so a later blanket tightening shows up as a failing
        test rather than as help silently disappearing for everyone but admins.
        """
        assert user_client.get(PATH).status_code == 200

        slug = listed["data"][0]["slug"]
        assert user_client.get(f"{PATH}/{slug}").status_code == 200
