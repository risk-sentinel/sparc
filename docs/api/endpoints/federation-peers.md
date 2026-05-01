# Federation Peers

CRUD + sync for the registry of peer SPARC instances this instance trusts. Each `FederationPeer` row carries the peer's HTTPS base URL, an enabled flag, and two encrypted secrets — `service_token` (the Bearer token this instance uses when calling the peer) and `signing_secret` (the HMAC key both sides use to sign and verify federation bundles).

Both encrypted columns are **write-only** in the API: they can be set on create or update but are never returned in any response. To find out whether a peer has secrets configured, check the `service_token_set` / `signing_secret_set` boolean flags on the response.

The encryption keys are derived from the `SPARC_HASH` master secret by `SparcKeyDerivation`. A rotation event (see [`SPARC_HASH_ROTATION.md`](../../SPARC_HASH_ROTATION.md)) re-encrypts these columns under the new master without exposing plaintext.

## Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `GET` | `/api/v1/federation_peers` | List all configured peers | `back_matter.federate` permission |
| `GET` | `/api/v1/federation_peers/:id` | Get one peer (with `public_metadata` detail) | `back_matter.federate` permission |
| `POST` | `/api/v1/federation_peers` | Register a new peer | `back_matter.federate` permission |
| `PATCH` / `PUT` | `/api/v1/federation_peers/:id` | Update a peer's `base_url`, `enabled`, `public_metadata`, or rotate its secrets | `back_matter.federate` permission |
| `DELETE` | `/api/v1/federation_peers/:id` | Remove a peer from the registry | `back_matter.federate` permission |
| `POST` | `/api/v1/federation_peers/:id/sync` | Pull authoritative resources from this peer (uses the peer's `service_token` to call its `/export` endpoint) | `back_matter.federate` permission |

## Authentication

Standard SPARC API Bearer token authentication. The token's owning user (or service account) must hold the `back_matter.federate` permission. Admins implicitly have it.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

---

## Resource shape

`GET` responses return a serialized peer with this structure (write-only fields are surfaced as `*_set` booleans rather than echoed):

```json
{
  "id": 7,
  "name": "exporter-prod",
  "base_url": "https://exporter.sparc.example.gov",
  "enabled": true,
  "last_synced_at": "2026-04-29T13:55:00Z",
  "last_sync_status": "success",
  "service_token_set": true,
  "signing_secret_set": true,
  "created_at": "2026-04-01T08:00:00Z",
  "updated_at": "2026-04-29T13:55:00Z"
}
```

Detailed responses (`show`, `create`, `update`) additionally include a `public_metadata` hash for any non-secret peer attributes the operator wants to record (e.g., a contact email, an environment label).

---

### GET /api/v1/federation_peers

Returns every registered peer ordered by `name`. Result is **not paginated** — the peer registry is expected to be small (single-digit count in most deployments).

#### Response Body

```json
{
  "data": [
    { "id": 1, "name": "exporter-prod", "base_url": "...", "enabled": true, ... },
    { "id": 2, "name": "leveraging-side-staging", "base_url": "...", "enabled": false, ... }
  ],
  "meta": { "count": 2 }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Peers returned |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Token lacks `back_matter.federate` |

---

### GET /api/v1/federation_peers/:id

Returns one peer with detail (`public_metadata` included).

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Numeric primary key from `index` |

#### Response Body

```json
{
  "data": {
    "id": 7,
    "name": "exporter-prod",
    "base_url": "https://exporter.sparc.example.gov",
    "enabled": true,
    "last_synced_at": "2026-04-29T13:55:00Z",
    "last_sync_status": "success",
    "service_token_set": true,
    "signing_secret_set": true,
    "public_metadata": {
      "contact_email": "ops@exporter.example.gov",
      "environment": "prod"
    },
    "created_at": "2026-04-01T08:00:00Z",
    "updated_at": "2026-04-29T13:55:00Z"
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Peer found |
| `404 Not Found` | No peer with that `id` |
| `401 Unauthorized` / `403 Forbidden` | Standard auth/authorization errors |

---

### POST /api/v1/federation_peers

Registers a new peer.

#### Request Body

```json
{
  "federation_peer": {
    "name": "exporter-prod",
    "base_url": "https://exporter.sparc.example.gov",
    "enabled": true,
    "public_metadata": {
      "contact_email": "ops@exporter.example.gov"
    },
    "service_token": "sparc_remote_token_value",
    "signing_secret": "shared-hmac-secret-from-out-of-band-channel"
  }
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | Yes | Unique peer identifier; appears in audit logs and bundle `key_id` |
| `base_url` | string | Yes | HTTPS URL; trailing slash optional. Must respond at `/api/v1/authoritative_sources/export` |
| `enabled` | bool | No | Defaults to `false`. Disabled peers cannot be `sync`ed |
| `public_metadata` | object | No | Free-form non-secret attributes |
| `service_token` | string | No | Bearer token this instance presents when calling the peer; encrypted at rest |
| `signing_secret` | string | No | HMAC key for envelope verification with the peer; encrypted at rest |

#### Response Body

The full detailed peer (same shape as `show`).

#### Status Codes

| Status | Description |
|--------|-------------|
| `201 Created` | Peer registered |
| `401 Unauthorized` / `403 Forbidden` | Standard auth/authorization errors |
| `422 Unprocessable Entity` | `name` missing or duplicate; `base_url` invalid |

#### Side effects

Writes `federation_peer_created` to `audit_events`. The `service_token` and `signing_secret` plaintext are not stored or logged in any form.

---

### PATCH/PUT /api/v1/federation_peers/:id

Updates a peer. `name` is **not** mutable post-create (it acts as the peer's stable identifier in audit logs and bundle metadata).

#### Request Body

Same shape as `POST` minus `name`. Submitting `service_token` / `signing_secret` rotates the secret; omitting them leaves the existing encrypted value alone (the API never re-emits them).

To **clear** a secret without setting a new value, submit an empty string.

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Peer updated |
| `404 Not Found` | No peer with that `id` |
| `422 Unprocessable Entity` | Validation failure (e.g., invalid `base_url`) |

#### Side effects

Writes `federation_peer_updated` to `audit_events`.

---

### DELETE /api/v1/federation_peers/:id

Hard-deletes the peer. There is no soft-delete state; deleting a peer immediately invalidates any in-flight sync that would have used its credentials.

#### Response Body

```json
{ "data": { "id": 7, "deleted": true } }
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Peer deleted |
| `404 Not Found` | No peer with that `id` |

#### Side effects

Writes `federation_peer_deleted` to `audit_events`.

---

### POST /api/v1/federation_peers/:id/sync

Pulls authoritative resources from the peer by calling its `/api/v1/authoritative_sources/export` endpoint with the peer's stored `service_token`, then verifies the resulting envelope against the peer's stored `signing_secret` and ingests the bundle.

The peer being pulled from must:

- Be `enabled: true`
- Have both `service_token_set` and `signing_secret_set` true
- Be reachable over HTTPS at the configured `base_url`
- Have already registered *this* instance as one of *its* peers with the matching shared `signing_secret`

#### Request Body

None — peer credentials and target URL are looked up from the registry.

#### Response Body — success

```json
{
  "data": {
    "peer": { /* serialized peer with refreshed last_synced_at */ },
    "imported": 12,
    "skipped":  3,
    "errors":   [],
    "bundle_uuid": "abc12345-..."
  }
}
```

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Sync completed (per-resource outcomes are in the response body) |
| `401 Unauthorized` / `403 Forbidden` | Standard auth/authorization errors |
| `422 Unprocessable Entity` | Peer disabled, secrets missing, signature verification failed, or envelope structure invalid |
| `502 Bad Gateway` | Peer unreachable, returned non-2xx, or returned a non-JSON body |

#### Side effects

Updates the peer's `last_synced_at` and `last_sync_status` columns; writes `federation_peer_synced` to `audit_events` with per-bucket counts and the imported bundle's `bundle_uuid` (so the import audit row can be correlated with the corresponding export audit row on the originating instance).

#### cURL Example

```bash
curl -s -X POST "https://leveraging.sparc.example.gov/api/v1/federation_peers/7/sync" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

---

## Common Errors

| Status | Body | Cause |
|--------|------|-------|
| `401 Unauthorized` | `{"error": "Unauthorized"}` | Bearer token missing, expired, or invalid |
| `403 Forbidden` | `{"error": "Not authorized to manage federation peers"}` | User/service account lacks `back_matter.federate` |
| `404 Not Found` | `{"error": "Not found"}` | No peer with that `id` |
| `422 Unprocessable Entity` | `{"error": "Validation failed", "details": [...]}` | Create/update validation failure |
| `502 Bad Gateway` | `{"error": "<peer fetch failure description>"}` | Sync called a peer that didn't respond cleanly |

## NIST 800-53 mapping

| Control | How these endpoints address it |
|---|---|
| `AC-3` Access Enforcement | `back_matter.federate` permission gates every method |
| `AC-4` Information Flow | The registry itself is an explicit allowlist; only listed peers can pull from or push to this instance |
| `AU-2` Audit Events | Every CRUD and sync operation writes a named audit row |
| `SC-12` Cryptographic Key Establishment | `service_token` / `signing_secret` encrypted under per-purpose keys derived from `SPARC_HASH` |
| `SC-13` Cryptographic Protection | AES-GCM at rest; TLS in transit; HMAC-SHA256 for bundle verification |
| `IA-5` Authenticator Management | Secrets can be rotated by submitting a new value via `PATCH`; the old value is overwritten and never recoverable |

## Related documentation

- [Authoritative Sources](authoritative-sources.md) — the federation export/import endpoints `sync` consumes
- [Back-Matter Resources](back-matter-resources.md) — what gets exchanged in the bundles
- [`SPARC_HASH_ROTATION.md`](../../SPARC_HASH_ROTATION.md) — operator runbook for rotating the master secret behind these encrypted columns
- SPARC issue [#372](https://github.com/risk-sentinel/sparc/issues/372) — the original feature request
