# Document Validations API

Checks a document before SPARC sends it to another system, or after another system sends it to SPARC (#1354). It covers the four formats SPARC exchanges:

| Format | What it is | Checked against |
|---|---|---|
| `fedramp` | FedRAMP machine-readable package JSON (Consolidated Rules for 2026): the Certification Package Overview, Security Decision Record, Ongoing Certification Report, Vulnerability Detail Report and the others | FedRAMP's JSON Schemas, vendored from [FedRAMP/schemas](https://github.com/FedRAMP/schemas) and pinned by SHA-256 (`lib/data/fedramp/fedramp-schemas.provenance.json`) |
| `oscal` | OSCAL JSON or XML | NIST's OSCAL JSON Schemas or XSDs, as SPARC's OSCAL validation already does |
| `hdf` | Heimdall Data Format, v2 or v3 | `hdf validate`, the pinned hdf-libs CLI |
| `xccdf` | XCCDF 1.2 XML | NIST's XCCDF 1.2 XSD, vendored and pinned (`lib/data/xccdf/xccdf.provenance.json`) |

Two checks run:

1. **Schema:** is the document well formed by its schema?
2. **Completeness** (FedRAMP and OSCAL JSON): is every field the schema requires filled in, not just present? FedRAMP's schemas accept an empty string for a required field. SPARC does not: a required field holding only whitespace, an unwanted `null`, or an empty object the schema gives fields to is an error. An empty array is left to the schema, because some schemas define `[]` as an answer (an Ongoing Certification Report's `incidents: []` attests to no incidents).

FedRAMP documents also get a **warning** for each optional field left out or empty. Warnings never make a document invalid.

Nothing is stored. Each check is recorded in the audit log as `document_validated`, with the result and the document's SHA-256, never its content.

## Authentication and authorization

A valid Bearer token. Any authenticated caller may check a document: the endpoint reads and stores nothing of SPARC's.

## `POST /api/v1/document_validations`

The document goes as a `multipart/form-data` field named `file`, or as the raw request body.

| Parameter | Required | Description |
|---|---|---|
| `document_format` | no | `fedramp`, `oscal`, `hdf` or `xccdf`. Detected when omitted. (Not `format`, which Rails keeps for the response format.) |
| `document_type` | no | For FedRAMP, the schema to use when the document has no `$schema`, e.g. `vulnerability-detail-report`. For HDF, the `hdf validate --type` (default `results`). |

A FedRAMP document is matched to its schema by, in order: its own `$schema`; the `document_type` parameter; the one schema whose required top-level fields it has. When two schemas fit equally, SPARC asks for `document_type` rather than guess.

```bash
curl -X POST https://sparc.example.com/api/v1/document_validations \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@vulnerability-detail-report.json"
```

### `200 OK`: the document was checked

`valid` says whether it passed. An invalid document is still a `200`: the request worked.

```json
{
  "valid": false,
  "format": "fedramp",
  "document_type": "vulnerability-detail-report",
  "schema": {
    "name": "fedramp-vulnerability-detail-report-schema-2026-06-24.json",
    "id": "https://fedramp.gov/schemas/fedramp-vulnerability-detail-report-schema-2026-06-24.json",
    "version": "0.1.1",
    "sha256": "5e9499e8cb9d0367c888ce41040175270fc9f007ae4f61d0ced34cca81cfe497"
  },
  "errors": [
    { "check": "completeness", "pointer": "/vulnerabilities/0/vulnerabilityDescription", "message": "required field is blank" }
  ],
  "warnings": [
    { "pointer": "/vulnerabilities/0/finalDisposition", "message": "optional field is not filled in" }
  ],
  "warnings_total": 1
}
```

- `errors[].check` is `schema` or `completeness`. `pointer` is a JSON Pointer into the document (XCCDF and OSCAL XML errors carry a line number in `message` instead).
- At most 200 errors and 200 warnings are listed; `warnings_total` counts them all.

### `422 Unprocessable Content`: the document could not be checked

The body was empty, was neither JSON nor XML, named an unknown format or a `$schema` SPARC does not carry, or matched no schema SPARC could choose without guessing.

```json
{ "error": "The document could not be checked", "details": "Could not tell which FedRAMP document this is. Set $schema in the document, or name its document_type" }
```

### `401 Unauthorized`

No token, or an invalid one.

## NIST SP 800-53

SI-10 (information input validation), SI-7 and SR-4 (the schemas are pinned, vendored copies with recorded provenance), CA-3 (information exchange), AU-12 (each check is audited).
