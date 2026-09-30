"""Shared contract for OSCAL export over the API (#1181, #1154).

`GET /api/v1/<documents>/:id/export?format=oscal|oscal-yaml|oscal-xml` serves
the OSCAL document through one shared body (OscalApiExport) for CDEF, SSP, SAP,
SAR, POA&M and mapping collections. `_export_contract.ExportContract` proves the
DEFAULT export contains its record; this proves the OSCAL formats do, per type:

  1. `format=oscal` returns the OSCAL document under the model's root key, and
     it is THIS record — `metadata.title` is the record's name.
  2. The validated path either conforms (200) or refuses with a 422 that names
     the way out. Demo data is not guaranteed to conform, so either answer is
     correct; a 500, or a 200 without the root key, is not.
  3. YAML and XML are real serialisations of the same document (or, where XML
     is not offered, it is refused by name).
  4. Conditional GET: a strong ETag, and 304 for a matching If-None-Match.
  5. An unknown format is a 422 listing what is accepted; anonymous is 401.

`validate=false` is used wherever the test is about the SHAPE, so a demo
document that does not conform still proves the serialisation.

Subclass `OscalExportContract`, set `PATH` and `ROOT_KEY`, and override
`_document` if the first index row is not a usable record.
"""

from __future__ import annotations

import xml.etree.ElementTree as ET
from typing import Any

import httpx
import pytest

OSCAL_NS = "http://csrc.nist.gov/ns/oscal/1.0"


class OscalExportContract:
    PATH: str = ""
    ROOT_KEY: str = ""
    # The type offers `fields` (SPARC's own JSON) as its default format.
    FIELDS_DEFAULT: bool = True
    # The type offers `oscal-xml`. Mapping collections do not: no XSD is carried.
    XML: bool = True

    def _document(self, admin_client: httpx.Client) -> dict[str, Any]:
        rows = admin_client.get(self.PATH, params={"items": 1}).json()["data"]
        assert rows, f"no record at {self.PATH} on this instance to export"
        return rows[0]

    def _path(self, doc: dict[str, Any]) -> str:
        return f"{self.PATH}/{doc.get('slug') or doc['id']}/export"

    def _expected(self) -> list[str]:
        formats = (["fields"] if self.FIELDS_DEFAULT else []) + ["oscal", "oscal-yaml"]
        return formats + (["oscal-xml"] if self.XML else [])

    @pytest.mark.happy
    def test_oscal_is_the_oscal_document_of_this_record(self, admin_client: httpx.Client) -> None:
        doc = self._document(admin_client)
        response = admin_client.get(self._path(doc),
                                    params={"format": "oscal", "validate": "false"})

        assert response.status_code == 200, response.text[:300]
        body = response.json()
        assert list(body) == [self.ROOT_KEY], f"root keys {list(body)!r}"
        assert body[self.ROOT_KEY]["metadata"]["title"] == doc["name"], (
            "the OSCAL export is not an export OF this record"
        )

    @pytest.mark.happy
    def test_validated_oscal_conforms_or_refuses_by_name(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(self._path(self._document(admin_client)),
                                    params={"format": "oscal"})

        if response.status_code == 200:
            assert self.ROOT_KEY in response.json()
        else:
            assert response.status_code == 422, response.text[:300]
            payload = response.json()
            assert "OSCAL schema" in payload["error"]
            assert "validate=false" in payload["hint"]

    @pytest.mark.happy
    def test_default_format(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(self._path(self._document(admin_client)),
                                    params={} if self.FIELDS_DEFAULT else {"validate": "false"})

        assert response.status_code == 200, response.text[:300]
        if self.FIELDS_DEFAULT:
            assert self.ROOT_KEY not in response.json(), "the default must stay SPARC's field JSON"
        else:
            assert self.ROOT_KEY in response.json()

    @pytest.mark.happy
    def test_yaml_is_the_same_document(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(self._path(self._document(admin_client)),
                                    params={"format": "oscal-yaml", "validate": "false"})

        assert response.status_code == 200, response.text[:300]
        assert response.headers.get("content-type", "").startswith("application/x-yaml")
        assert f"{self.ROOT_KEY}:" in response.text

    @pytest.mark.happy
    def test_xml_is_oscal_namespaced_or_refused_by_name(self, admin_client: httpx.Client) -> None:
        response = admin_client.get(self._path(self._document(admin_client)),
                                    params={"format": "oscal-xml", "validate": "false"})

        if self.XML:
            assert response.status_code == 200, response.text[:300]
            root = ET.fromstring(response.content)
            assert root.tag == f"{{{OSCAL_NS}}}{self.ROOT_KEY}", root.tag
        else:
            assert response.status_code == 422, response.text[:300]
            assert "oscal-xml" not in response.json()["expected"]
            assert response.json().get("reason"), "an unoffered XML must say why"

    @pytest.mark.happy
    def test_unchanged_export_answers_304(self, admin_client: httpx.Client) -> None:
        path = self._path(self._document(admin_client))
        params = {"format": "oscal", "validate": "false"}
        first = admin_client.get(path, params=params)
        etag = first.headers.get("etag")

        assert first.status_code == 200, first.text[:300]
        assert etag and not etag.startswith("W/"), f"expected a strong ETag, got {etag!r}"

        again = admin_client.get(path, params=params, headers={"If-None-Match": etag})
        assert again.status_code == 304, again.text[:300]

        other = admin_client.get(path, params={**params, "format": "oscal-yaml"},
                                 headers={"If-None-Match": etag})
        assert other.status_code == 200, "a different format must not match the ETag"

    @pytest.mark.validation
    def test_unknown_format_is_refused_with_the_accepted_list(
        self, admin_client: httpx.Client
    ) -> None:
        response = admin_client.get(self._path(self._document(admin_client)),
                                    params={"format": "carrier_pigeon"})

        assert response.status_code == 422, response.text[:300]
        assert response.json()["expected"] == self._expected()

    @pytest.mark.auth
    def test_anonymous_caller_is_refused(self, anon_client: httpx.Client,
                                         admin_client: httpx.Client) -> None:
        response = anon_client.get(self._path(self._document(admin_client)),
                                   params={"format": "oscal"})

        assert response.status_code == 401
