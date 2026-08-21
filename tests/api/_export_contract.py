"""Shared contract for the `export` endpoints (#995).

Seven groups publish an `export` action — SSP, SAR, baseline parameters,
converters, KSI validations, attestations and authoritative sources — and until
now each was tested, if at all, on its own terms. That is how seven
implementations of one idea come to disagree.

What an export must do, beyond answering 200:

  1. Return JSON, not an HTML error page and not an empty body.
  2. **Contain the record it claims to export.** This is the check worth having:
     an export that returns a well-formed but EMPTY document answers 200 and
     passes any status-only test. #988 shipped exactly that — every SSP export
     was broken while 5,548 examples stayed green — and #999 returned a
     resolved catalog with 0 of 182 enhancements.
  3. Refuse an unauthenticated caller, like every other endpoint.

Subclass `ExportContract`, set `EXPORT_PATH` (or override `_export_path`), and
implement `_expected_content` returning a string that MUST appear in the export
— usually the record's own title or identifier. That string is what turns "it
returned something" into "it returned this record".

Underscore-prefixed file name signals "internal to the test suite".
"""

from __future__ import annotations

import httpx
import pytest


class ExportContract:
    EXPORT_PATH: str = ""
    # Some exports offer ?format=; leave empty to take the default.
    EXPORT_FORMATS: tuple[str, ...] = ()

    def _export_path(self, admin_client: httpx.Client) -> str:
        return self.EXPORT_PATH

    def _expected_content(self, admin_client: httpx.Client) -> str:
        raise NotImplementedError

    @pytest.mark.happy
    def test_export_returns_json_rather_than_an_error_page(
        self, admin_client: httpx.Client
    ) -> None:
        response = admin_client.get(self._export_path(admin_client))

        assert response.status_code == 200, response.text
        assert response.headers.get("content-type", "").startswith("application/json"), (
            f"export answered with content-type "
            f"{response.headers.get('content-type')!r}: {response.text[:160]}"
        )
        assert response.text.strip(), "the export body is empty"

    @pytest.mark.happy
    def test_the_export_contains_the_record_it_claims_to_export(
        self, admin_client: httpx.Client
    ) -> None:
        """The check a status-only test cannot make.

        A well-formed but empty document answers 200 and satisfies every
        assertion about shape. #988 shipped precisely that.
        """
        expected = self._expected_content(admin_client)
        response = admin_client.get(self._export_path(admin_client))

        assert response.status_code == 200, response.text
        assert expected in response.text, (
            f"the export does not contain {expected!r}, so it is not an export OF "
            f"this record — {len(response.text)} bytes returned"
        )

    @pytest.mark.auth
    def test_export_refuses_an_anonymous_caller(
        self, anon_client: httpx.Client, admin_client: httpx.Client
    ) -> None:
        response = anon_client.get(self._export_path(admin_client))

        assert response.status_code == 401, (
            f"export answered {response.status_code} to an unauthenticated caller"
        )

    @pytest.mark.happy
    def test_every_declared_format_exports_the_same_record(
        self, admin_client: httpx.Client
    ) -> None:
        """A format that silently falls back to another is not a format.

        Skipped only when the endpoint declares none, which is a property of the
        endpoint rather than a decision to check less.
        """
        if not self.EXPORT_FORMATS:
            return

        expected = self._expected_content(admin_client)
        for fmt in self.EXPORT_FORMATS:
            response = admin_client.get(self._export_path(admin_client), params={"format": fmt})
            assert response.status_code == 200, f"format={fmt}: {response.text[:200]}"
            assert expected in response.text, (
                f"format={fmt} returned {len(response.text)} bytes not containing "
                f"{expected!r}"
            )
