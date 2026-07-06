"""Shared contract for the admin-only bulk-destroy endpoints (#629).

`DELETE /api/v1/<resource>/bulk` with an ``{"ids": [...]}`` body is backed by
the shared ``BulkDestroyService`` and is **partial-success, not
all-or-nothing**: unassociated records delete, referential-integrity-blocked
records are reported with a reason, unknown ids are reported as missing, and
one blocked row never stops the others. Response:

    {data: {deleted: [{id, name}], blocked: [{id, name, reason}], missing: [id]},
     meta: {deleted: N, blocked: N, missing: N}}

Subclass ``BulkDestroyContract``, set ``PATH``, and implement ``_create_id``
returning the integer DB id of a freshly-created, unassociated record (the
service resolves by numeric id, so slugs will not match).

Note: HTTP DELETE with a body must go through ``client.request("DELETE", ...)``
— httpx's ``client.delete()`` does not accept a JSON body.

Underscore-prefixed file name signals "internal to the test suite".
"""

from __future__ import annotations

import httpx
import pytest

from conftest import assert_error_envelope

# An id that will never exist, used to exercise the "missing" partial-success path.
BOGUS_ID = 999_999_999


class BulkDestroyContract:
    PATH: str = ""

    def _create_id(self, admin_client: httpx.Client) -> int:
        raise NotImplementedError

    def _bulk(self, client: httpx.Client, ids: list) -> httpx.Response:
        return client.request("DELETE", f"{self.PATH}/bulk", json={"ids": ids})

    @pytest.mark.happy
    def test_admin_bulk_deletes(self, admin_client: httpx.Client) -> None:
        ids = [self._create_id(admin_client), self._create_id(admin_client)]
        resp = self._bulk(admin_client, ids)
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["meta"]["deleted"] == 2, body
        deleted_ids = {d["id"] for d in body["data"]["deleted"]}
        assert set(ids) <= deleted_ids, f"{ids} not all in {deleted_ids}"

    @pytest.mark.happy
    def test_partial_success_reports_missing(self, admin_client: httpx.Client) -> None:
        real = self._create_id(admin_client)
        resp = self._bulk(admin_client, [real, BOGUS_ID])
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["meta"]["deleted"] == 1, body
        assert body["meta"]["missing"] == 1, body
        assert str(BOGUS_ID) in [str(m) for m in body["data"]["missing"]], body

    def test_empty_ids_is_noop(self, admin_client: httpx.Client) -> None:
        resp = self._bulk(admin_client, [])
        assert resp.status_code == 200, resp.text
        meta = resp.json()["meta"]
        assert meta["deleted"] == meta["blocked"] == meta["missing"] == 0, meta

    @pytest.mark.authz
    def test_non_admin_forbidden(self, user_client: httpx.Client) -> None:
        # Admin-gated regardless of body (before_action :authorize_admin!).
        assert self._bulk(user_client, []).status_code in (401, 403)

    @pytest.mark.auth
    def test_requires_token(self, anon_client: httpx.Client) -> None:
        assert_error_envelope(self._bulk(anon_client, []), expected_status=401)
