# Exchange Index API

What a boundary serves back out to the systems it exchanges with (#1354): one list of its current documents, each with its format, document type, when it last changed, and where to download it.

- **SPARC's own documents** for the boundary: its SSPs, assessment plans, assessment results and POA&Ms, the component definitions it uses (all through the existing OSCAL export endpoints), and the boundary as an HDF system document. These are built on request, so their `sha256` is `null`: the index would otherwise have to build every export each time it is read.
- **Its FedRAMP Vulnerability Detail Report and Accepted Vulnerability Info** ([FedRAMP Reports](fedramp-reports.md)), format `fedramp`, document types `vulnerability-detail-report` and `accepted-vulnerability-info`, listed only when the boundary has a FedRAMP Certification Package Overview address. They are built on request too, so their `sha256` is `null` and their `updated_at` is when the index was read.
- **Every received document the boundary has accepted** ([Received Documents](received-documents.md)), with the SHA-256 recorded at receipt. Class A certification materials are left out: they are the provider's to share, not the boundary's.

The download URLs are the existing authenticated endpoints, and each checks its own permission: a caller needs a token that may read each document it fetches. The other system typically reads the index with a service-account token scoped to the boundary.

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/authorization_boundaries/:id/exchange_index` | What the boundary serves back out |

## Authentication and authorization

A valid Bearer token whose user holds `evidence.read` on the boundary (or across the instance), or an instance administrator.

Every read is recorded in the audit log as `exchange_index_served`, with who read it, when, and how many documents it listed: FedRAMP's access logs and access inventory (CDS-TRC-ACL, CDS-TRC-AAI).

## `GET /api/v1/authorization_boundaries/:id/exchange_index`

The boundary may be named by id, slug or UUID.

```json
{
  "data": {
    "authorization_boundary": { "id": 12, "name": "My System" },
    "generated_at": "2026-11-20T16:00:00Z",
    "documents": [
      { "origin": "sparc", "format": "oscal", "document_type": "ssp", "id": 3, "name": "My System SSP",
        "updated_at": "2026-11-19T10:00:00Z", "sha256": null,
        "download_url": "/api/v1/ssp_documents/3/export?format=oscal" },
      { "origin": "sparc", "format": "hdf", "document_type": "system", "id": 12, "name": "My System",
        "updated_at": "2026-11-18T09:00:00Z", "sha256": null,
        "download_url": "/api/v1/authorization_boundaries/12/hdf_system" },
      { "origin": "received", "format": "fedramp", "document_type": "vulnerability-detail-report", "id": 41,
        "name": "vdr.json", "fedramp_id": "FR2400000001", "updated_at": "2026-11-20T15:10:00Z",
        "received_at": "2026-11-20T15:02:11Z", "sha256": "…",
        "download_url": "/api/v1/authorization_boundaries/12/received_documents/41/file" }
    ]
  }
}
```

| Field | Description |
|---|---|
| `origin` | `sparc` (SPARC's own export) or `received` (an accepted received version) |
| `format` | `oscal`, `hdf`, `fedramp` or `xccdf` |
| `document_type` | `ssp`, `assessment_plan`, `assessment_results`, `poam`, `component_definition`, `system`, `vulnerability-detail-report`, `accepted-vulnerability-info`, or a received document's own type |
| `updated_at` | When it last changed; for a received document, when it was accepted |
| `sha256` | The SHA-256 of a received version; `null` for SPARC's exports, which are built on request |
| `download_url` | The authenticated endpoint that serves it |

## Errors

| Status | When |
|---|---|
| `401` | No token, or an invalid one |
| `403` | No `evidence.read` on this boundary |
| `404` | No such boundary |

## NIST SP 800-53

CA-3 (information exchange), AC-3 / AC-6 (boundary-scoped permission; each download checks its own), AU-12 (each read audited).
