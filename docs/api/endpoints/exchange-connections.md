# Exchange Connections API

A connection is another system SPARC pulls FedRAMP, OSCAL, HDF or XCCDF documents from (#1354). It records who the provider is, the boundary its documents land in, its root trust-center address, how SPARC authenticates there, and the trust pins every fetch is held to. Each document SPARC pulls is set on the connection explicitly as a **document source**: SPARC can crawl the root address to list candidates (`discover`), but it pulls only the documents set here.

Every fetch is HTTPS only, to a pinned host, with the address resolved first and refused when it is private, loopback, link-local or cloud metadata (unless inside the connection's own `allowed_cidrs`). Redirects are never followed, size and time are capped, and with `spki_sha256` pins the server's TLS public key must match one of them before the request (and its credential) is written.

What a pulled document becomes is the [Received Documents API](received-documents.md).

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/exchange_connections` | List connections |
| POST | `/api/v1/exchange_connections` | Register a connection |
| GET | `/api/v1/exchange_connections/:id` | One connection, with its document sources |
| PATCH / PUT | `/api/v1/exchange_connections/:id` | Update a connection |
| DELETE | `/api/v1/exchange_connections/:id` | Remove a connection |
| POST | `/api/v1/exchange_connections/:id/pull` | Pull every enabled document now |
| POST | `/api/v1/exchange_connections/:id/discover` | List the root's document links; stores nothing |
| POST | `/api/v1/exchange_connections/:id/test_connection` | Fetch and validate each document; stores nothing |
| GET | `/api/v1/exchange_connections/:exchange_connection_id/document_sources` | A connection's document sources |
| POST | `/api/v1/exchange_connections/:exchange_connection_id/document_sources` | Add a document source |
| PATCH / PUT | `/api/v1/exchange_connections/:exchange_connection_id/document_sources/:id` | Update a document source |
| DELETE | `/api/v1/exchange_connections/:exchange_connection_id/document_sources/:id` | Remove a document source |

## Authentication and authorization

A valid Bearer token whose user holds **`connections.manage` across the instance**, or an instance administrator. A grant of `connections.manage` on a single boundary is not enough: a connection decides which outside hosts SPARC reaches and where their documents land. Every endpoint on this page needs it, `discover` and `test_connection` included.

## The credential is write-only

`credential` is accepted on create and update, stored encrypted, and **never returned**. Responses carry `credential_set: true|false` only. On update, sending `credential` replaces it (an empty string clears it); leaving it out keeps it. Audit events record that it changed, never its value.

## Fields

Body root `exchange_connection`.

| Field | Type | Description |
|---|---|---|
| `name` | string, required, unique | |
| `authorization_boundary_id` | id or slug, required | The boundary the connection's documents land in |
| `fedramp_id` | string | The provider's FedRAMP ID (`F` or `FR` and ten digits, optional suffix; upper-cased) |
| `certification_class` | `A` \| `B` \| `C` \| `D` | |
| `certification_type` | `20x` \| `Rev5` | |
| `root_url` | https URL | The root trust-center address `discover` reads |
| `auth_scheme` | `none` \| `bearer` \| `header` | Default `none` |
| `auth_header_name` | string | Required when `auth_scheme` is `header` |
| `credential` | string, write-only | The bearer token or header value |
| `spki_sha256` | array of hex SHA-256 | Up to two (the current key and the next) |
| `allowed_cidrs` | array of CIDR ranges | When set, every resolved address must be in one |
| `enabled` | boolean | Default `true`. A disabled connection is not pulled |

A field the endpoint does not accept is refused with `422`, and nothing changes.

Responses add `pinned_hosts` (the hosts of the root and every document address; no other host is ever reached), `last_pulled_at`, `last_pull_status`, `last_error`, `document_source_count`, and, on `show`, create and update, `document_sources`.

## `GET /api/v1/exchange_connections`

Paginated (`page`, `items`). Optional `authorization_boundary_id` (id or slug) filter.

## `GET /api/v1/exchange_connections/:id`

## `POST /api/v1/exchange_connections`

```bash
curl -X POST https://sparc.example.com/api/v1/exchange_connections \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"exchange_connection": {"name": "Provider A", "authorization_boundary_id": "my-system",
       "root_url": "https://trust.provider.example/", "auth_scheme": "bearer", "credential": "…",
       "fedramp_id": "FR2400000001", "spki_sha256": ["<64 hex>"]}}'
```

`201` with the connection. Audited as `exchange_connection_created`.

## `PATCH /api/v1/exchange_connections/:id`

`200` with the connection. Audited as `exchange_connection_updated`, with the names of the fields that changed and whether the credential did.

## `DELETE /api/v1/exchange_connections/:id`

Removes the connection and its document sources. Versions already received stay on record; their connection is cleared. Audited as `exchange_connection_deleted`.

```json
{ "data": { "id": 7, "deleted": true } }
```

## `POST /api/v1/exchange_connections/:id/pull`

Pulls every enabled document source of the connection **now**, whether or not its interval has passed, and returns each result. Each is also recorded on its source, on the connection and in the audit log (`exchange_pull_completed` / `exchange_pull_failed`).

```json
{
  "data": {
    "connection": { "id": 7, "last_pull_status": "stored", "...": "..." },
    "results": [
      { "document_source_id": 3, "url": "https://trust.provider.example/package/vdr.json", "status": "stored", "error": null,
        "received_document": { "id": 41, "state": "pending_review", "sha256": "…", "valid": true,
                               "url": "/api/v1/authorization_boundaries/12/received_documents/41" } }
    ]
  }
}
```

`status` is `stored` (a new version), `unchanged` (the stream already holds these bytes) or `failed` (with `error`). A failed fetch is that document's result, not a failed request. `422` when the connection is disabled or has no enabled document.

## `POST /api/v1/exchange_connections/:id/discover`

Fetches the root trust-center address under the same rules as a pull and **lists** the document links in it on a pinned host. Nothing is pulled and nothing is registered. Audited as `exchange_connection_discovered`.

```json
{
  "data": {
    "root_url": "https://trust.provider.example/",
    "candidates": [
      { "url": "https://trust.provider.example/package/vdr.json", "hint_format": "json", "registered": true },
      { "url": "https://trust.provider.example/package/sdr.json", "hint_format": "json", "registered": false }
    ]
  }
}
```

`422` when the connection has no `root_url` or cannot be fetched with as configured (`reason: "configuration"`). `502` when the trust center cannot be reached or refuses (`reason` is the fetcher's: `blocked_address`, `host_not_allowed`, `pin_mismatch`, `tls`, `redirect`, `status`, `too_large`, `timeout`, `dns`, `connection`).

## `POST /api/v1/exchange_connections/:id/test_connection`

Fetches the root address and each document source, and checks each document with the validator ([Document Validations](document-validations.md)), exactly as a pull would reach them. **It stores nothing**: no version, and nothing on the connection or its sources. Audited as `exchange_connection_tested`.

```json
{
  "data": {
    "root": { "url": "https://trust.provider.example/", "reachable": true, "status": 200, "content_type": "text/html",
              "bytes": 5120, "sha256": "…", "peer_ip": "203.0.113.10", "spki_sha256": "…" },
    "sources": [
      { "document_source_id": 3, "enabled": true, "url": "https://trust.provider.example/package/vdr.json",
        "reachable": true, "status": 200, "content_type": "application/json", "bytes": 2048, "sha256": "…",
        "peer_ip": "203.0.113.10", "spki_sha256": "…",
        "validation": { "valid": true, "format": "fedramp", "document_type": "vulnerability-detail-report",
                        "error_count": 0, "errors": [], "warnings_total": 3 } },
      { "document_source_id": 4, "enabled": true, "url": "https://trust.provider.example/package/sdr.json",
        "reachable": false, "status": null, "reason": "pin_mismatch", "error": "…", "validation": null }
    ]
  }
}
```

`root` is `null` when the connection has no `root_url`. A document that cannot be reached is reported in its row; the request is still `200`. `422` (`reason: "configuration"`) when the connection cannot be fetched with at all.

## Document sources

Body root `exchange_document_source`.

| Field | Type | Description |
|---|---|---|
| `url` | https URL, required, unique per connection | The document's address. Its host becomes one of the connection's pinned hosts |
| `format` | `fedramp` \| `oscal` \| `hdf` \| `xccdf`, required | |
| `document_type` | string | e.g. `vulnerability-detail-report`, `ssp`, `results` |
| `pull_interval_hours` | integer 1–744 | Default 24. The hourly job pulls a document when its interval has passed |
| `enabled` | boolean | Default `true` |

Responses add `last_pulled_at`, `last_status`, `last_sha256` and `last_error`.

### `GET /api/v1/exchange_connections/:exchange_connection_id/document_sources`

The whole list (`meta.pages` is 1).

### `POST /api/v1/exchange_connections/:exchange_connection_id/document_sources`

`201`. Audited as `exchange_document_source_created`.

### `PATCH /api/v1/exchange_connections/:exchange_connection_id/document_sources/:id`

`200`. Audited as `exchange_document_source_updated`.

### `DELETE /api/v1/exchange_connections/:exchange_connection_id/document_sources/:id`

`200 {"data": {"id": 3, "deleted": true}}`. Versions already received stay on record. Audited as `exchange_document_source_deleted`.

## Errors

| Status | When |
|---|---|
| `401` | No token, or an invalid one |
| `403` | No instance-wide `connections.manage` |
| `404` | No such connection, or a document source of another connection |
| `422` | Validation failed, an unrecognised field, or (pull, discover, test) a connection that cannot be fetched with |
| `502` | Discover: the trust center could not be reached or refused |

## NIST SP 800-53

CA-3 (information exchange), SA-9 (external system services), AC-3 / AC-6 (instance-level permission), IA-5 (the credential is write-only and encrypted at rest), IA-9 (host and TLS key pins), SC-7 (internal addresses refused), SC-8, SI-10 (each document validated), AU-12 (every change, pull, discover and test is audited).
