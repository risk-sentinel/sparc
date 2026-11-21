# Received Documents API

Every FedRAMP, OSCAL, HDF or XCCDF document a boundary receives, pulled from a [connection](exchange-connections.md) or uploaded by a person, is kept as a **version** that is never overwritten (#1354). Its bytes, SHA-256, format and origin are fixed when it is stored; only the review fields change afterwards.

Each arrival goes the same way:

1. **Validate** it ([Document Validations](document-validations.md): schema and completeness).
2. **Store** it, once. Bytes its stream already holds are not stored again: the answer is `unchanged`, and the version in effect stays in effect.
3. **Compare** it with the version in effect for its stream, change by change, classed as regression, improvement or neutral.
4. **Review.** Only a byte-identical re-delivery needs no person (owner, 2026-11-20), and step 2 already records that as `unchanged`. Every other valid version, an improvement included, waits for a reviewer. A version that fails validation is stored with its errors, shown, and can never be accepted.

Two other kinds of arrival take the same path:

- **A provider's push** ([Exchange Connections: Push](exchange-connections.md#push)). SPARC confirms it by pulling the document fresh from its registered address. When the bytes match, the pulled version is received and carries `push_confirmed: true`. When they do not, or the address cannot be reached, the pushed bytes are received with `source: "push"` and `push_confirmed: false`: an **unconfirmed push**, flagged, never auto-accepted. `push_confirmed` is `null` for a version that no push announced.
- **A Class A material** ([Exchange Connections: Class A materials](exchange-connections.md#class-a-materials)), `format: "class_a_material"`, `document_type` its kind. It is a file FedRAMP gives no schema for, so step 1 does not apply (`validation.checked: false`) and step 3 compares nothing; it is reviewed as a whole. Materials are added on the connection, not through the upload below, and never listed in the exchange index.

A **stream** is one pulled document address, or a boundary's uploads of one format, document type and FedRAMP ID. Each stream has at most one version in effect (`accepted`). A document belongs to the boundary only once the boundary accepts it; an accepted HDF document also goes through the existing ingest into the boundary's findings.

| State | Meaning |
|---|---|
| `pending_review` | Waiting for a reviewer |
| `accepted` | In effect for its stream |
| `responded` | The reviewer asked the provider for information; not in effect |
| `rejected` | On record, never in effect |
| `superseded` | Was accepted; a later version replaced it |
| `invalid` | Failed validation; on record with its errors |

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/authorization_boundaries/:authorization_boundary_id/received_documents` | List the boundary's received versions |
| POST | `/api/v1/authorization_boundaries/:authorization_boundary_id/received_documents` | Upload a document |
| GET | `/api/v1/authorization_boundaries/:authorization_boundary_id/received_documents/:id` | One version, with its validation, delta and review |
| GET | `/api/v1/authorization_boundaries/:authorization_boundary_id/received_documents/:id/file` | The exact bytes received |
| POST | `/api/v1/authorization_boundaries/:authorization_boundary_id/received_documents/:id/accept` | Accept: the version takes effect |
| POST | `/api/v1/authorization_boundaries/:authorization_boundary_id/received_documents/:id/respond` | Ask the provider for information |
| POST | `/api/v1/authorization_boundaries/:authorization_boundary_id/received_documents/:id/reject` | Reject: on record, never in effect |

## Authentication and authorization

A valid Bearer token. Permissions are checked against the boundary in the path (a grant on that boundary, or across the instance), or the caller is an instance administrator:

| Action | Permission |
|---|---|
| list, show, download | `evidence.read` |
| upload | `exchange.upload` |
| accept, respond, reject | `exchange.review` |

**Separation of duties:** the person who uploaded a version cannot accept, respond to or reject it; that is `403`. The instance administrator is exempt, as elsewhere in SPARC. Pulled versions have no uploader.

The boundary may be named by id, slug or UUID.

## `GET /api/v1/authorization_boundaries/:authorization_boundary_id/received_documents`

Paginated, newest first. Filters:

| Parameter | Description |
|---|---|
| `state` | One state, or several comma-separated (`pending_review,responded`) |
| `document_format` | `fedramp`, `oscal`, `hdf`, `xccdf` or `class_a_material` (not `format`, which Rails keeps for the response format) |
| `document_type` | |
| `stream` | A stream key, as each version returns it |
| `exchange_connection_id` | |

```json
{
  "data": [
    {
      "id": 41, "authorization_boundary_id": 12, "exchange_connection_id": null, "exchange_document_source_id": null,
      "source": "upload", "stream": "upload:boundary:12:fedramp:vulnerability-detail-report:-",
      "format": "fedramp", "document_type": "vulnerability-detail-report", "fedramp_id": null,
      "filename": "vdr.json", "content_type": "application/json",
      "sha256": "…", "byte_size": 2048, "state": "pending_review", "valid": true, "push_confirmed": null,
      "counts": { "regression": 1, "improvement": 0, "neutral": 2 },
      "received_at": "2026-11-20T15:02:11Z", "received_by": { "id": 5, "name": "Pat Uploader" },
      "review": { "action": null, "note": null, "reviewed_at": null, "reviewed_by": null },
      "scan_run_id": null,
      "links": { "self": "/api/v1/authorization_boundaries/12/received_documents/41",
                 "file": "/api/v1/authorization_boundaries/12/received_documents/41/file" }
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 1, "items": 25 }
}
```

## `GET .../received_documents/:id`

The list row plus:

- `validation`: `valid`, `schema`, `errors`, `warnings`, `warnings_total`;
- `delta`: `first_version`, `identical`, `truncated`, `counts` and `changes` (each `{kind, key, summary, before, after}`, regressions first);
- `in_effect_version_id`: the version now in effect for its stream (this one when accepted);
- `may_decide`: whether the caller may decide this version now (it is open and they did not upload it);
- `links.accept`, `links.respond`, `links.reject`.

## `GET .../received_documents/:id/file`

The exact bytes received, with their stored content type, as an attachment. The `X-Content-SHA256` header carries the SHA-256 recorded at receipt, so a caller can check what they got. Each download is audited as `received_document_downloaded` (who, when, which version), for FedRAMP's access logs (CDS-TRC-ACL).

## `POST /api/v1/authorization_boundaries/:authorization_boundary_id/received_documents`

Upload. The document goes as a `multipart/form-data` field named `file`, or as the raw request body.

| Parameter | Required | Description |
|---|---|---|
| `document_format` | no | `fedramp`, `oscal`, `hdf` or `xccdf`. Detected when omitted |
| `document_type` | no | As for [Document Validations](document-validations.md) |

```bash
curl -X POST https://sparc.example.com/api/v1/authorization_boundaries/my-system/received_documents \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@vulnerability-detail-report.json"
```

| Status | Body | When |
|---|---|---|
| `201 Created` | `{"status": "stored", "data": {…version, detailed…}}` | A new version, **valid or not**. An invalid one has `state: "invalid"` and its errors under `validation.errors` |
| `200 OK` | `{"status": "unchanged", "data": {…the version already held…}}` | The stream already holds these exact bytes. Nothing new is stored |
| `422` | `{"error": "…"}` | No document, an unknown `document_format`, an empty or over-limit document, or one that is not a format SPARC reads |

Audited as `received_document_stored`.

## Review

Each takes an optional JSON body `{"note": "…"}`; `respond` and `reject` require one. Each answers `200` with the version (detailed) and is audited (`received_document_accepted`, `received_document_responded`, `received_document_rejected`) with who decided and the note.

### `POST .../received_documents/:id/accept`

The version takes effect for its stream; the one it replaces becomes `superseded`. An HDF document is also ingested into the boundary's findings (`scan_run_id` is set); if that ingest fails, the acceptance fails with `422`.

### `POST .../received_documents/:id/respond`

Ask the provider for information. The version moves to `responded` and stays out of effect; the version in effect stays in effect. A responded version can still be accepted or rejected.

### `POST .../received_documents/:id/reject`

The version stays on record and never takes effect.

### Errors

| Status | When |
|---|---|
| `403` | No `exchange.review` on the boundary, or the caller uploaded this version (`{"error": "A received document cannot be decided by the person who uploaded it"}`) |
| `404` | No such version on this boundary |
| `422` | The version already decided, accepting one that failed validation, `respond` / `reject` without a note, or a failed HDF ingest |

## Errors (all endpoints)

| Status | When |
|---|---|
| `401` | No token, or an invalid one |
| `403` | The permission above is missing on this boundary |
| `404` | No such boundary, or no such version on it |

## NIST SP 800-53

AC-3 / AC-6 (boundary-scoped permissions), AC-5 (separation of duties), CA-3 (information exchange), CA-7 (each delivery compared with the last accepted), SI-10 (validated on receipt), SI-7 and AU-10 (bytes and SHA-256 fixed at receipt; downloads carry the SHA-256), AU-12 (uploads, decisions and downloads audited).
