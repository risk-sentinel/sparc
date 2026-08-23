"""Tests for /api/v1/idp_grants (#860).

The unmatched-grant queue: entitlements an IdP asked for that this instance
could not grant. A grant naming an unknown organization, boundary or role is
recorded and surfaced, never created — auto-creating would let the identity
provider define the estate.

Recording without surfacing is the half nobody notices, so this endpoint is the
surfacing, and these tests are about it answering correctly rather than merely
answering.

api-inventory: covers idp_grants#unmatched
"""

from __future__ import annotations

import httpx
import pytest

pytestmark = [pytest.mark.admin, pytest.mark.phase2]

PATH = "/api/v1/idp_grants/unmatched"


class TestShape:
    def test_returns_data_and_meta(self, admin_client: httpx.Client) -> None:
        resp = admin_client.get(PATH)

        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert "data" in body and isinstance(body["data"], list)
        assert "meta" in body

    def test_meta_carries_the_window_and_a_grouped_summary(
        self, admin_client: httpx.Client
    ) -> None:
        resp = admin_client.get(PATH)

        meta = resp.json()["meta"]
        assert meta["window_days"] == 30, "the documented default window changed"
        assert isinstance(meta["summary"], list)

    def test_summary_rows_carry_distinct_user_counts(self, admin_client: httpx.Client) -> None:
        # affected_users counts DISTINCT users while occurrences counts sign-ins.
        # An administrator ranks their attention by the first, so if a row is
        # present it must carry both.
        rows = admin_client.get(PATH).json()["meta"]["summary"]
        if not rows:
            pytest.skip("no unmatched grants recorded on this instance")

        row = rows[0]
        assert {"reason", "occurrences", "affected_users", "example_grant"} <= set(row)
        assert row["occurrences"] >= row["affected_users"], (
            "occurrences counts sign-ins and cannot be fewer than the distinct "
            "users they came from"
        )


class TestWindow:
    def test_window_is_configurable(self, admin_client: httpx.Client) -> None:
        assert admin_client.get(PATH, params={"days": 7}).json()["meta"]["window_days"] == 7

    def test_window_is_clamped_to_a_year(self, admin_client: httpx.Client) -> None:
        # Not merely accepted and ignored — the response must SAY what window it
        # actually used, or a caller cannot trust the result they got back.
        assert admin_client.get(PATH, params={"days": 9999}).json()["meta"]["window_days"] == 365

    def test_window_floor_is_one_day(self, admin_client: httpx.Client) -> None:
        assert admin_client.get(PATH, params={"days": 0}).json()["meta"]["window_days"] == 1

    def test_a_narrower_window_cannot_return_more(self, admin_client: httpx.Client) -> None:
        # `count`, not `total_count` — the shared paginate envelope is
        # {page, pages, count, items}. Assumed the wrong key when this was
        # written; the live suite caught it and the docs were wrong too.
        wide = admin_client.get(PATH, params={"days": 365}).json()["meta"]["count"]
        narrow = admin_client.get(PATH, params={"days": 1}).json()["meta"]["count"]

        assert narrow <= wide, "a one-day window returned more than a one-year window"


class TestFiltering:
    def test_narrows_to_one_user(self, admin_client: httpx.Client) -> None:
        rows = admin_client.get(PATH, params={"days": 365}).json()["data"]
        with_user = [r for r in rows if r.get("user")]
        if not with_user:
            pytest.skip("no unmatched grants with an associated user on this instance")

        user_id = with_user[0]["user"]["id"]
        filtered = admin_client.get(PATH, params={"days": 365, "user_id": user_id}).json()["data"]

        assert filtered, "filtering by a user_id present in the data returned nothing"
        assert all(r["user"]["id"] == user_id for r in filtered)

    def test_an_unknown_user_id_returns_nothing_rather_than_everything(
        self, admin_client: httpx.Client
    ) -> None:
        # The failure that matters: a filter silently ignored looks like success
        # and leaks every user's refusals to a caller who asked about one.
        resp = admin_client.get(PATH, params={"user_id": 999_999_999})

        assert resp.status_code == 200, resp.text
        assert resp.json()["data"] == []


class TestAuthorization:
    def test_admin_is_allowed(self, admin_client: httpx.Client) -> None:
        assert admin_client.get(PATH).status_code == 200

    def test_non_admin_is_refused(self, user_client: httpx.Client) -> None:
        # The allow leg above is an admin and this deny leg is a real,
        # authenticated, permission-holding non-admin — both directions, per the
        # standing rule.
        assert user_client.get(PATH).status_code == 403

    def test_anonymous_is_unauthorized(self, anon_client: httpx.Client) -> None:
        assert anon_client.get(PATH).status_code == 401

    def test_a_bad_token_is_unauthorized(self, bad_token_client: httpx.Client) -> None:
        assert bad_token_client.get(PATH).status_code == 401
