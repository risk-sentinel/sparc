"""Shared contract for the bulk field-import pair (#995, #716).

Four document types publish the same two endpoints:

    POST /api/v1/<type>_documents/:slug/fields/import/preview
    POST /api/v1/<type>_documents/:slug/fields/import/confirm

Eight endpoints, one behaviour, and until now no shared test. The properties
that matter are not the status codes:

  1. **PREVIEW WRITES NOTHING.** That is the entire promise of a preview, and it
     is invisible in the response — a preview that quietly applied its changes
     would return exactly the same body. Only an independent read before and
     after can tell. This is the check the pair exists for.
  2. **CONFIRM APPLIES**, confirmed by an independent read of the field, not by
     the `applied` count the write reports about itself. #994 reported
     `parameters_updated: 1` for zero writes.
  3. **PREVIEW AND CONFIRM AGREE.** A preview that reports one set of changes
     while confirm applies another is worse than no preview: it is a promise the
     caller acts on. `apply` calls `preview` internally today, so this holds
     structurally — asserting it is what stops that quietly changing.
  4. A missing or malformed file is refused with a named reason, not counted as
     an empty import.
  5. **THE WRITE LANDS ON THE CONTROL THE CALLER NAMED** (#1028). The key is not
     always unique: on a CDEF, `control_id` holds the NIST reference a Converter
     resolved at ingest, so two components implementing the same control produce
     two rows with the same id. Addressing by `uuid` must hit that exact row and
     leave its siblings alone.

Subclass `FieldImportContract`, set `PATH`, and implement `_document_slug` and
`_target`, which returns the control to write: its `uuid` (how the read finds
it), the `key` the payload addresses it by, and the `field` name.

Underscore-prefixed file name signals "internal to the test suite".
"""

from __future__ import annotations

import json
import uuid

import httpx
import pytest


class FieldImportContract:
    PATH: str = ""

    def _document_slug(self, admin_client: httpx.Client) -> str:
        raise NotImplementedError

    def _target(self, admin_client: httpx.Client) -> dict:
        """{"uuid": ..., "key": ..., "field": ...} for the control to write."""
        raise NotImplementedError

    # ── helpers ──────────────────────────────────────────────────────────────

    def _import_path(self, admin_client: httpx.Client, action: str) -> str:
        return f"{self.PATH}/{self._document_slug(admin_client)}/fields/import/{action}"

    def _payload_file(self, key: str, field: str, value: str):
        # A MAP of control id -> field updates, as endpoints/field-import.md
        # publishes. Not an array: `FieldImportService.parse`'s @return comment
        # describes the shape it RETURNS, which is an array of
        # {control_id:, fields:}, and reading that as the input format gets a
        # 422. The endpoint doc is the one to follow.
        body = {"controls": {key: {field: value}}}
        return {"file": ("import.json", json.dumps(body).encode(), "application/json")}

    def _read_field(self, admin_client: httpx.Client, control_uuid: str, field: str):
        """Independent read of one field, via the document's EXPORT.

        `show` reports `controls_count` but carries no `controls` array, so the
        export is the only endpoint that exposes a document control's field
        values. It is a genuinely independent read — a different endpoint from
        the one under test — but it is worth noting that reading one field costs
        a full document export.
        """
        slug = self._document_slug(admin_client)
        response = admin_client.get(f"{self.PATH}/{slug}/export")
        assert response.status_code == 200, response.text

        body = response.json()
        controls = body.get("controls") or body.get("data", {}).get("controls") or []
        for control in controls:
            # #1028 — matched on `uuid`, not `control_id`. On a CDEF the latter
            # names more than one row, so a read keyed on it can report a
            # sibling's value and call the write a success.
            if str(control.get("uuid")) != str(control_uuid):
                continue
            for entry in control.get("fields") or []:
                if entry.get("field_name") == field:
                    return entry.get("field_value")
            return None
        return None

    # ── the contract ─────────────────────────────────────────────────────────

    @pytest.mark.happy
    def test_preview_writes_nothing(self, admin_client: httpx.Client) -> None:
        """The promise a preview makes, and the one its response cannot show."""
        target = self._target(admin_client)
        field = target["field"]
        before = self._read_field(admin_client, target["uuid"], field)
        value = f"preview-must-not-persist-{uuid.uuid4().hex[:8]}"

        response = admin_client.post(
            self._import_path(admin_client, "preview"),
            files=self._payload_file(target["key"], field, value),
        )
        assert response.status_code == 200, response.text

        after = self._read_field(admin_client, target["uuid"], field)
        assert after == before, (
            f"preview CHANGED {target['key']}.{field}: {before!r} -> {after!r}. "
            f"A preview that writes is not a preview, and its response looks "
            f"identical either way."
        )
        # The preview SHOULD describe the change — that is its job. What it must
        # not do is persist it, which the assertion above is what tests.
        rows = response.json()["data"]["rows"]
        assert any(row.get("new_value") == value for row in rows), (
            f"the preview did not report the change it was asked to preview: {rows[:3]}"
        )

    @pytest.mark.happy
    def test_confirm_applies_confirmed_by_an_independent_read(
        self, admin_client: httpx.Client
    ) -> None:
        target = self._target(admin_client)
        field = target["field"]
        before = self._read_field(admin_client, target["uuid"], field)
        value = f"imported-{uuid.uuid4().hex[:8]}"
        assert before != value, "the value the test sets is already there"

        response = admin_client.post(
            self._import_path(admin_client, "confirm"),
            files=self._payload_file(target["key"], field, value),
        )
        assert response.status_code == 200, response.text

        after = self._read_field(admin_client, target["uuid"], field)
        assert after == value, (
            f"confirm reported {response.json().get('data', {}).get('applied')!r} applied "
            f"but an independent read shows {target['key']}.{field} is {after!r}"
        )

        # #1028 — and it says which control it wrote, so the caller can tell a
        # sibling row was not hit instead.
        assert response.json()["data"]["rows"][0]["resolved_uuid"] == target["uuid"]

    @pytest.mark.happy
    def test_preview_and_confirm_report_the_same_change(
        self, admin_client: httpx.Client
    ) -> None:
        """A preview the caller acts on must describe what confirm will do."""
        target = self._target(admin_client)
        field = target["field"]
        value = f"agreement-{uuid.uuid4().hex[:8]}"

        preview = admin_client.post(
            self._import_path(admin_client, "preview"),
            files=self._payload_file(target["key"], field, value),
        )
        assert preview.status_code == 200, preview.text
        previewed = preview.json()["data"]["stats"]

        confirm = admin_client.post(
            self._import_path(admin_client, "confirm"),
            files=self._payload_file(target["key"], field, value),
        )
        assert confirm.status_code == 200, confirm.text
        applied = confirm.json()["data"]["stats"]

        assert previewed == applied, (
            f"preview promised {previewed} and confirm did {applied}"
        )

    @pytest.mark.happy
    def test_the_write_lands_on_the_control_named_and_not_a_sibling(
        self, admin_client: httpx.Client
    ) -> None:
        """#1028 — every OTHER control's value for this field is unchanged.

        The defect this replaces was not a failed write. `confirm` returned
        `applied: 1`, a row really was written, and it was the wrong row — so
        the only check that could see it is one that looks at the rows the
        caller did NOT name.
        """
        target = self._target(admin_client)
        field = target["field"]
        slug = self._document_slug(admin_client)

        def field_values_by_uuid() -> dict:
            body = admin_client.get(f"{self.PATH}/{slug}/export").json()
            controls = body.get("controls") or body.get("data", {}).get("controls") or []
            return {
                str(c.get("uuid")): next(
                    (f.get("field_value") for f in (c.get("fields") or [])
                     if f.get("field_name") == field),
                    None,
                )
                for c in controls
            }

        before = field_values_by_uuid()
        value = f"exact-row-{uuid.uuid4().hex[:8]}"

        response = admin_client.post(
            self._import_path(admin_client, "confirm"),
            files=self._payload_file(target["key"], field, value),
        )
        assert response.status_code == 200, response.text

        after = field_values_by_uuid()
        assert after[target["uuid"]] == value

        moved = {
            u: (before.get(u), after.get(u))
            for u in after
            if u != target["uuid"] and before.get(u) != after.get(u)
        }
        assert not moved, (
            f"addressing {target['key']!r} also changed {len(moved)} control(s) "
            f"the caller never named: {moved}"
        )

    @pytest.mark.validation
    def test_a_request_with_no_file_is_refused_by_name(
        self, admin_client: httpx.Client
    ) -> None:
        for action in ("preview", "confirm"):
            response = admin_client.post(self._import_path(admin_client, action))

            assert response.status_code == 422, f"{action}: {response.text[:200]}"
            assert "file" in response.json()["error"].lower(), (
                f"{action} refused without naming the missing file: {response.text[:200]}"
            )

    @pytest.mark.validation
    def test_an_unsupported_format_is_refused_by_name(
        self, admin_client: httpx.Client
    ) -> None:
        response = admin_client.post(
            self._import_path(admin_client, "preview"),
            files={"file": ("import.txt", b"not structured at all", "text/plain")},
        )

        assert response.status_code == 422, response.text
        assert "format" in response.json()["error"].lower(), response.text

    @pytest.mark.auth
    def test_both_endpoints_refuse_an_anonymous_caller(
        self, anon_client: httpx.Client, admin_client: httpx.Client
    ) -> None:
        target = self._target(admin_client)
        for action in ("preview", "confirm"):
            response = anon_client.post(
                self._import_path(admin_client, action),
                files=self._payload_file(target["key"], target["field"], "anonymous"),
            )
            assert response.status_code == 401, f"{action} answered {response.status_code}"
