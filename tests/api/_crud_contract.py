"""The #995 matrix, as a reusable contract for any CRUD resource.

The whole-surface sweep in `test_contract_sweep.py` covers the checks that need
no valid payload — authentication, refusals, envelopes, no-2xx-for-a-missing-id.
The rest of the matrix needs a real record, and those are here:

    write 1   the documented status comes back
    write 2   the response carries the fields that were sent
    write 3   an INDEPENDENT read confirms the write persisted
    write 6   after DELETE, gone from `show` AND from the parent's index
    read  2   the content read back equals what was written

Check 3 is the one that matters most and the one most often skipped. #994
answered `200 {"status":"updated"}` to a body it never parsed; the write's own
echo would have confirmed that lie, because an echo can be synthesised from the
request. Every assertion here re-reads through a separate GET.

Subclass `CrudContract`, set `PATH` and `PARAM_KEY`, and implement
`_payload()` returning a minimum-viable create body and `_update_fields()`
returning fields whose values differ from what `_payload` sets. Override
`IDENTIFIER` when the resource is addressed by something other than `slug`.

Underscore-prefixed file name signals "internal to the test suite".
"""

from __future__ import annotations

import uuid
from typing import Any

import httpx
import pytest


class CrudContract:
    PATH: str = ""
    PARAM_KEY: str = ""
    # Which field of the create response addresses the record in its URL.
    IDENTIFIER: str = "slug"
    # Fields sent on create that the show response is not expected to mirror
    # (write-only credentials, parent ids echoed under a different name).
    IGNORE_ON_READ_BACK: set[str] = frozenset()
    # Deletion is not one behaviour across this API, and the differences are
    # deliberate. Declare which one applies, with the reason — the contract then
    # asserts THAT, so a resource's actual promise is pinned rather than a
    # generic one nobody made.
    #
    #   neither set  -> DELETE removes the record: gone from show and from index
    #   SOFT         -> DELETE deactivates: the record SURVIVES and stays readable
    #   NONE         -> there is no destroy route at all; DELETE must not route
    DESTROY_IS_SOFT_BECAUSE: str | None = None
    NO_DESTROY_ROUTE_BECAUSE: str | None = None
    # A few resources are deliberately open to any authenticated caller — CDEF
    # is, per its controller's design comment and #575 Path D. Set the reason
    # string to declare it. The contract then asserts the OPPOSITE direction:
    # that a non-admin genuinely CAN write, so a later tightening is a failing
    # test rather than a silent change of who may edit what.
    #
    # A reason rather than a boolean on purpose. An unexplained `= True` here is
    # indistinguishable from someone switching it to make a red test go green.
    NON_ADMIN_MAY_WRITE_BECAUSE: str | None = None

    # ── subclass hooks ───────────────────────────────────────────────────────

    def _payload(self, admin_client: httpx.Client) -> dict[str, Any]:
        raise NotImplementedError

    def _update_fields(self) -> dict[str, Any]:
        return {"description": f"updated by the contract suite {uuid.uuid4().hex[:8]}"}

    # ── helpers ──────────────────────────────────────────────────────────────

    def _create(self, client: httpx.Client, body: dict[str, Any]) -> dict[str, Any]:
        response = client.post(self.PATH, json={self.PARAM_KEY: body})
        assert response.status_code in (200, 201), (
            f"create failed at {self.PATH}: {response.status_code} {response.text[:300]}"
        )
        return response.json()["data"]

    def _url(self, record: dict[str, Any]) -> str:
        return f"{self.PATH}/{record[self.IDENTIFIER]}"

    def _destroy(self, client: httpx.Client, record: dict[str, Any]) -> None:
        client.delete(self._url(record))

    # ── the matrix ───────────────────────────────────────────────────────────

    @pytest.mark.happy
    def test_create_returns_the_documented_status_and_echoes_the_fields(
        self, admin_client: httpx.Client
    ) -> None:
        """Matrix checks 1 and 2."""
        body = self._payload(admin_client)
        response = admin_client.post(self.PATH, json={self.PARAM_KEY: body})

        assert response.status_code in (200, 201), response.text
        record = response.json()["data"]
        try:
            mismatches = [
                f"{field}: sent {value!r}, response says {record.get(field)!r}"
                for field, value in body.items()
                if field not in self.IGNORE_ON_READ_BACK
                and field in record
                and record[field] != value
            ]
            assert not mismatches, "create response contradicts the request:\n" + "\n".join(
                f"  {m}" for m in mismatches
            )
        finally:
            self._destroy(admin_client, record)

    @pytest.mark.happy
    def test_create_persists_confirmed_by_an_independent_read(
        self, admin_client: httpx.Client
    ) -> None:
        """Matrix check 3, and read check 2.

        The write's own echo is not evidence — it can be synthesised from the
        request without anything reaching the database. This re-reads.
        """
        body = self._payload(admin_client)
        record = self._create(admin_client, body)

        try:
            shown = admin_client.get(self._url(record))
            assert shown.status_code == 200, shown.text
            data = shown.json()["data"]

            mismatches = [
                f"{field}: sent {value!r}, independent read says {data.get(field)!r}"
                for field, value in body.items()
                if field not in self.IGNORE_ON_READ_BACK
                and field in data
                and data[field] != value
            ]
            assert not mismatches, (
                "the create reported success but an independent read disagrees:\n"
                + "\n".join(f"  {m}" for m in mismatches)
            )
        finally:
            self._destroy(admin_client, record)

    @pytest.mark.happy
    def test_the_created_record_appears_in_the_index(
        self, admin_client: httpx.Client
    ) -> None:
        """A record that cannot be found by listing is only half-created."""
        record = self._create(admin_client, self._payload(admin_client))

        try:
            listing = admin_client.get(self.PATH, params={"items": 100})
            assert listing.status_code == 200, listing.text
            ids = [row.get("id") for row in listing.json()["data"]]
            assert record["id"] in ids, (
                f"{record['id']} was created but does not appear in {self.PATH}"
            )
        finally:
            self._destroy(admin_client, record)

    @pytest.mark.happy
    def test_update_persists_confirmed_by_an_independent_read(
        self, admin_client: httpx.Client
    ) -> None:
        """Matrix check 3 for updates — the #994 shape.

        The change is compared against the value the record held first, so an
        update that sets a field to what it already contained cannot pass by
        accident.
        """
        record = self._create(admin_client, self._payload(admin_client))

        try:
            before = admin_client.get(self._url(record)).json()["data"]
            changes = self._update_fields()

            vacuous = [f for f, v in changes.items() if before.get(f) == v]
            assert not vacuous, (
                f"these fields already held the value the test sets, so the check "
                f"would pass without a write: {vacuous}"
            )

            response = admin_client.patch(self._url(record), json={self.PARAM_KEY: changes})
            assert response.status_code in (200, 201, 202), response.text

            after = admin_client.get(self._url(record))
            assert after.status_code == 200, after.text
            data = after.json()["data"]

            mismatches = [
                f"{field}: sent {value!r}, independent read says {data.get(field)!r} "
                f"(was {before.get(field)!r})"
                for field, value in changes.items()
                if data.get(field) != value
            ]
            assert not mismatches, (
                f"the update returned {response.status_code} but an independent read "
                "disagrees:\n" + "\n".join(f"  {m}" for m in mismatches)
            )
        finally:
            self._destroy(admin_client, record)

    @pytest.mark.happy
    def test_delete_behaves_as_this_resource_declares(
        self, admin_client: httpx.Client
    ) -> None:
        """Matrix check 6, in whichever form the resource promises.

        A hard delete that still lists is not deleted; a soft delete that
        vanishes has lost the audit trail it exists to keep. Both are failures,
        of opposite kinds, so the contract has to be told which one is intended.
        """
        record = self._create(admin_client, self._payload(admin_client))
        response = admin_client.delete(self._url(record))

        if self.NO_DESTROY_ROUTE_BECAUSE:
            assert response.status_code in (404, 405), (
                f"{self.PATH} declares no destroy route "
                f"({self.NO_DESTROY_ROUTE_BECAUSE}), but DELETE answered "
                f"{response.status_code}"
            )
            still_there = admin_client.get(self._url(record))
            assert still_there.status_code == 200, "the record vanished anyway"
            return

        assert response.status_code in (200, 204), response.text
        shown = admin_client.get(self._url(record))
        listing = admin_client.get(self.PATH, params={"items": 100})
        assert listing.status_code == 200, listing.text
        ids = [row.get("id") for row in listing.json()["data"]]

        if self.DESTROY_IS_SOFT_BECAUSE:
            assert shown.status_code == 200, (
                f"{self.PATH} declares a soft delete "
                f"({self.DESTROY_IS_SOFT_BECAUSE}), but the record is gone from "
                f"show ({shown.status_code}) — the audit trail it exists to keep "
                f"went with it"
            )
            return

        assert shown.status_code == 404, (
            f"deleted, but {self._url(record)} still answers {shown.status_code}"
        )
        assert record["id"] not in ids, (
            f"{record['id']} was deleted but still appears in {self.PATH} — "
            "a delete that still lists is not a delete"
        )

    @pytest.mark.validation
    def test_an_unrecognized_field_is_refused_and_nothing_is_written(
        self, admin_client: httpx.Client
    ) -> None:
        """Matrix check 4 with a real payload, so the refusal is the only reason
        the request fails."""
        body = dict(self._payload(admin_client))
        body["a_field_this_endpoint_does_not_accept"] = "x"

        before = admin_client.get(self.PATH, params={"items": 100}).json()["meta"]["count"]
        response = admin_client.post(self.PATH, json={self.PARAM_KEY: body})

        assert response.status_code == 422, response.text
        assert "a_field_this_endpoint_does_not_accept" in " ".join(
            response.json().get("details", [])
        ), response.text

        after = admin_client.get(self.PATH, params={"items": 100}).json()["meta"]["count"]
        assert after == before, "a refused create wrote a record anyway"

    @pytest.mark.authz
    def test_the_declared_write_posture_holds_for_a_non_admin(
        self, admin_client: httpx.Client, user_client: httpx.Client
    ) -> None:
        """Matrix check 5, in whichever direction the resource declares.

        Refusing the request is not the same as refusing the write, and only
        re-reading tells them apart — so the closed case checks the record
        afterwards rather than trusting the status code. The open case is
        asserted just as firmly, because "any authenticated user may edit this"
        is a decision worth having a test behind.
        """
        record = self._create(admin_client, self._payload(admin_client))

        try:
            before = admin_client.get(self._url(record)).json()["data"]
            changes = self._update_fields()
            response = user_client.patch(self._url(record), json={self.PARAM_KEY: changes})
            after = admin_client.get(self._url(record)).json()["data"]

            if self.NON_ADMIN_MAY_WRITE_BECAUSE:
                assert response.status_code in (200, 201, 202), (
                    f"{self.PATH} declares that a non-admin may write "
                    f"({self.NON_ADMIN_MAY_WRITE_BECAUSE}), but the update was refused "
                    f"with {response.status_code}: {response.text[:200]}"
                )
                mismatches = [
                    f"{f}: sent {v!r}, read back {after.get(f)!r}"
                    for f, v in changes.items() if after.get(f) != v
                ]
                assert not mismatches, (
                    "the non-admin update reported success but did not persist:\n"
                    + "\n".join(f"  {m}" for m in mismatches)
                )
            else:
                assert response.status_code in (401, 403, 404), (
                    f"a non-admin was allowed to update {self._url(record)}: "
                    f"{response.status_code}. If that is intended, declare it with "
                    f"NON_ADMIN_MAY_WRITE_BECAUSE rather than loosening this check."
                )
                changed = [
                    k for k in before if before.get(k) != after.get(k) and k != "updated_at"
                ]
                assert not changed, f"a refused update changed {changed}"
        finally:
            self._destroy(admin_client, record)
