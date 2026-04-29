# Authoritative Sources

Federation export / import for authoritative back-matter resources between SPARC instances. Used by leveraging-side instances to pre-populate cross-instance leveraged-authorization references (#396) without operators having to copy OSCAL files by hand.

Bundles are exchanged as **HMAC-SHA256-signed envelopes** keyed off a per-peer `signing_secret`. Both sides must already have a registered [`FederationPeer`](federation-peers.md) record for the other side; the peer's `signing_secret` is the shared trust anchor and is provisioned out-of-band.

## Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `GET` | `/api/v1/authoritative_sources/export` | Build and return a signed bundle of this instance's authoritative resources for the calling peer | `back_matter.federate` permission |
| `POST` | `/api/v1/authoritative_sources/import` | Verify and ingest a signed bundle from a configured peer | `back_matter.federate` permission |

## Authentication

Standard SPARC API Bearer token authentication. The token's owning user (or service account) must hold the `back_matter.federate` permission. Admins implicitly have it.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

The bundle's HMAC signature is **separate** from API authentication — the Bearer token authorizes the caller to invoke the endpoint, the per-peer signature binds the *contents* of the bundle to a specific known peer.

---

## Bundle envelope format

Both export and import work on the same envelope:

```json
{
  "alg": "HMAC-SHA256-base64url",
  "payload": "<base64url-encoded JSON payload>",
  "signature": "<hex HMAC-SHA256 of the base64url payload>",
  "key_id": "<peer name — metadata only, not trust>"
}
```

The `signature` covers the `payload` field exactly as it appears in the envelope (a base64url-encoded byte string), so middleboxes that re-encode JSON cannot break verification. `key_id` is logging metadata; trust comes from the receiver looking up `peer.signing_secret` by their own configuration of the calling peer.

The decoded `payload` is:

```json
{
  "bundle_version": 1,
  "metadata": {
    "instance_url": "https://exporter.sparc.example.gov",
    "bundle_uuid": "abc12345-...",
    "generated_at": "2026-04-29T14:00:00Z",
    "since": "2026-04-15T00:00:00Z",
    "scope": "authoritative",
    "resource_count": 12
  },
  "resources": [ /* serialized BackMatterResource entries */ ]
}
```

---

### GET /api/v1/authoritative_sources/export

Builds a signed envelope for the named peer.

#### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `peer` | string | Yes | The `name` of the registered `FederationPeer` requesting the bundle. Must match an existing peer; otherwise 422. |
| `since` | ISO-8601 timestamp | No | If supplied, the bundle includes only resources updated at or after this time (incremental export). Malformed timestamps are silently treated as `nil` (full export). |

#### Response Body

The full envelope (above). The receiving peer is responsible for verifying `signature` against its own configured copy of the originator's `signing_secret` before trusting any of the contents.

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Envelope returned |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Token lacks `back_matter.federate` permission |
| `422 Unprocessable Entity` | `peer` query param does not match a registered `FederationPeer` |

#### Side effects

A successful call writes one row to `audit_events`:

- `action`: `authoritative_sources_export`
- `metadata.peer`: the peer's name
- `metadata.bundle_uuid`: the encoded payload identifier (lets export and import audit rows be correlated across instances)

#### cURL Example

```bash
curl -s -X GET "https://exporter.sparc.example.gov/api/v1/authoritative_sources/export?peer=leveraging-side-prod&since=2026-04-15T00:00:00Z" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -o bundle.json
```

The bundle on disk can then be POSTed to a leveraging-side instance's `/import` endpoint, or pushed to the same envelope-handling path that `POST /api/v1/federation_peers/:id/sync` exercises.

---

### POST /api/v1/authoritative_sources/import

Accepts a signed envelope from a known peer, verifies the signature, and upserts each contained resource into this instance's `BackMatterResource` table with the appropriate federated-source markers.

#### Request Body

The full envelope (see "Bundle envelope format" above) under the `envelope` key, plus a `peer` field naming the originator. The `peer` query/body field can be omitted when the envelope's `key_id` matches a registered peer; the envelope's `key_id` is then used to look up the peer.

```json
{
  "peer": "exporter-prod",
  "envelope": {
    "alg": "HMAC-SHA256-base64url",
    "payload": "...",
    "signature": "...",
    "key_id": "exporter-prod"
  }
}
```

#### Response Body — success

```json
{
  "data": {
    "bundle_uuid": "abc12345-...",
    "imported": [ /* serialized BackMatterResource entries */ ],
    "skipped":  [ "duplicate: <original-uuid>", "..." ],
    "errors":   [ ]
  }
}
```

`imported`, `skipped`, `errors` are independent — a partially successful import returns 200 with non-empty `errors` so the caller can react per resource.

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Bundle was verified and import was attempted (per-resource outcomes are in the response body) |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Token lacks `back_matter.federate` permission |
| `422 Unprocessable Entity` | Envelope structure invalid, signature does not verify, or `peer` not registered |
| `502 Bad Gateway` | Reserved for the related sync path; not emitted by this endpoint directly |

#### Side effects

A successful call writes one row to `audit_events`:

- `action`: `authoritative_sources_import`
- `metadata.peer`: peer name
- `metadata.imported` / `metadata.skipped` / `metadata.errors`: per-bucket counts
- `metadata.bundle_uuid`: matches the originating export's audit row

Each successfully imported resource also gets its own federated-source marker in `BackMatterResourceChange` so future re-runs from the same `bundle_uuid` are deduplicated.

#### cURL Example

```bash
curl -s -X POST "https://leveraging.sparc.example.gov/api/v1/authoritative_sources/import" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  --data-binary @bundle.json
```

---

## Common Errors

| Status | Body | Cause |
|--------|------|-------|
| `401 Unauthorized` | `{"error": "Unauthorized"}` | Bearer token missing, expired, or invalid |
| `403 Forbidden` | `{"error": "Not authorized to federate authoritative sources"}` | User/service account lacks `back_matter.federate` |
| `422 Unprocessable Entity` | `{"error": "Unknown peer \"<name>\""}` | The `peer` parameter (or envelope `key_id`) doesn't match any registered `FederationPeer` |
| `422 Unprocessable Entity` | `{"error": "Signature does not verify"}` | The envelope's signature failed HMAC verification — peer's `signing_secret` is wrong, the bundle was tampered with, or the wrong peer was named |
| `422 Unprocessable Entity` | `{"error": "Unsupported algorithm"}` | The envelope's `alg` field is not `HMAC-SHA256-base64url` |

## NIST 800-53 mapping

| Control | How these endpoints address it |
|---|---|
| `AC-3` Access Enforcement | `back_matter.federate` permission gates both endpoints |
| `AC-4` Information Flow | The peer registry is an explicit allowlist; only registered peers participate |
| `AC-20` Use of External Systems | Each cross-instance flow is auditable and per-peer scoped |
| `AU-2` / `AU-10` Audit Events / Non-Repudiation | Every export and import writes a peer-named audit row; the HMAC signature ties the bundle to the peer |
| `SC-8` / `SC-13` Transmission Confidentiality / Cryptographic Protection | TLS in transit; HMAC-SHA256 over base64url payload |
| `SC-12` Cryptographic Key Establishment | Per-peer `signing_secret` derived from `SPARC_HASH` master secret via `SparcKeyDerivation` |

## Related documentation

- [Federation Peers](federation-peers.md) — peer CRUD + sync pull endpoints
- [Back-Matter Resources](back-matter-resources.md) — the resource model these bundles ship
- SPARC issue [#372](https://github.com/Rebel-Raiders/sparc/issues/372) — the original feature request
- [`SPARC_HASH_ROTATION.md`](../../SPARC_HASH_ROTATION.md) — operator runbook for rotating the master secret that derives every peer's `signing_secret`
