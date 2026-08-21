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

Subclass `FieldImportContract`, set `PATH`, and implement `_document_slug` and
`_control_and_field` returning a (control_id, field_name) pair that exists on
that document.

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

    def _control_and_field(self, admin_client: httpx.Client) -> tuple[str, str]:
        raise NotImplementedError

    # ── helpers ──────────────────────────────────────────────────────────────

    def _import_path(self, admin_client: httpx.Client, action: str) -> str:
        return f"{self.PATH}/{self._document_slug(admin_client)}/fields/import/{action}"

    def _payload_file(self, control_id: str, field: str, value: str):
        # A MAP of control id -> field updates, as endpoints/field-import.md
        # publishes. Not an array: `FieldImportService.parse`'s @return comment
        # describes the shape it RETURNS, which is an array of
        # {control_id:, fields:}, and reading that as the input format gets a
        # 422. The endpoint doc is the one to follow.
        body = {"controls": {control_id: {field: value}}}
        return {"file": ("import.json", json.dumps(body).encode(), "application/json")}

    def _read_field(self, admin_client: httpx.Client, control_id: str, field: str):
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
            if str(control.get("control_id")).lower() != control_id.lower():
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
        control_id, field = self._control_and_field(admin_client)
        before = self._read_field(admin_client, control_id, field)
        value = f"preview-must-not-persist-{uuid.uuid4().hex[:8]}"

        response = admin_client.post(
            self._import_path(admin_client, "preview"),
            files=self._payload_file(control_id, field, value),
        )
        assert response.status_code == 200, response.text

        after = self._read_field(admin_client, control_id, field)
        assert after == before, (
            f"preview CHANGED {control_id}.{field}: {before!r} -> {after!r}. "
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
        control_id, field = self._control_and_field(admin_client)
        before = self._read_field(admin_client, control_id, field)
        value = f"imported-{uuid.uuid4().hex[:8]}"
        assert before != value, "the value the test sets is already there"

        response = admin_client.post(
            self._import_path(admin_client, "confirm"),
            files=self._payload_file(control_id, field, value),
        )
        assert response.status_code == 200, response.text

        after = self._read_field(admin_client, control_id, field)
        assert after == value, (
            f"confirm reported {response.json().get('data', {}).get('applied')!r} applied "
            f"but an independent read shows {control_id}.{field} is {after!r}"
        )

    @pytest.mark.happy
    def test_preview_and_confirm_report_the_same_change(
        self, admin_client: httpx.Client
    ) -> None:
        """A preview the caller acts on must describe what confirm will do."""
        control_id, field = self._control_and_field(admin_client)
        value = f"agreement-{uuid.uuid4().hex[:8]}"

        preview = admin_client.post(
            self._import_path(admin_client, "preview"),
            files=self._payload_file(control_id, field, value),
        )
        assert preview.status_code == 200, preview.text
        previewed = preview.json()["data"]["stats"]

        confirm = admin_client.post(
            self._import_path(admin_client, "confirm"),
            files=self._payload_file(control_id, field, value),
        )
        assert confirm.status_code == 200, confirm.text
        applied = confirm.json()["data"]["stats"]

        assert previewed == applied, (
            f"preview promised {previewed} and confirm did {applied}"
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
        control_id, field = self._control_and_field(admin_client)
        for action in ("preview", "confirm"):
            response = anon_client.post(
                self._import_path(admin_client, action),
                files=self._payload_file(control_id, field, "anonymous"),
            )
            assert response.status_code == 401, f"{action} answered {response.status_code}"
