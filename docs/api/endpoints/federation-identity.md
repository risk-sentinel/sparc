# Federation Identity API

The two constants every peer in the federation derives object identity against: the **namespace URI** and the **federation namespace UUID**.

Added in #1155, before any peer generates fixtures. Both values are hashed inputs to every object UUID in the estate, so changing either afterwards re-keys every document in every fixture and every producing pipeline at once.

## Base URL

```
https://sparc.example.com/api/v1/federation/identity
```

## Authentication

Requires a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

Read-only, and **not permission-gated**. These values identify the federation rather than any tenant's data, so the response is identical for every authenticated caller — the same posture as [API discovery](../README.md). There is nothing here to scope.

## Why this endpoint exists

Object identity is UUIDv5 derived from natural keys:

```
Key(parts...) = uuidv5(FEDERATION_NAMESPACE, parts.join(SEP))
```

Two properties depend on every peer using the **same** namespace UUID:

- **Idempotent reruns** — the same natural key yields the same UUID, so regenerating produces identical identities.
- **Federated dedup without coordination** — peers deduplicate because they independently derive the same UUID from the same natural key.

The second fails *silently* when two peers disagree. Nothing errors; the same logical object simply arrives under a second identity and nothing reconciles it. Publishing the value here means a peer reads or verifies it instead of embedding its own copy.

## The UUID is derived, not random

It is the UUIDv5 of the namespace URI, deliberately:

```
uuidv5(URL_NAMESPACE, "https://sparc.risk-sentinel.org/ns")
  = 9f434272-f796-589b-b972-954790395630
```

So a peer never has to be *told* it — anyone holding the URI recomputes it, and anyone holding both can verify the UUID provably belongs to that namespace. A random UUID would have to be copied literally into every runtime, which is the failure mode #1155 was opened to prevent.

The response carries the recipe alongside the value so this is checkable rather than asserted.

## GET /api/v1/federation/identity

```bash
curl -s https://sparc.example.com/api/v1/federation/identity \
  -H "Authorization: Bearer $SPARC_API_TOKEN"
```

```json
{
  "data": {
    "namespace_uri": "https://sparc.risk-sentinel.org/ns",
    "federation_namespace_uuid": "9f434272-f796-589b-b972-954790395630",
    "derivation": {
      "method": "uuidv5",
      "namespace": "url",
      "name": "https://sparc.risk-sentinel.org/ns"
    }
  },
  "meta": {
    "instance_namespace": "https://sparc.risk-sentinel.org/ns",
    "api_version": "v1"
  }
}
```

### Fields

| Field | Notes |
|---|---|
| `data.namespace_uri` | The authority URI for SPARC's OSCAL property vocabulary. Identical in every deployment — it identifies an authority, not an install |
| `data.federation_namespace_uuid` | The namespace UUID for UUIDv5 object-identity derivation |
| `data.derivation.method` | `uuidv5` |
| `data.derivation.namespace` | `url` — the RFC 4122 URL namespace |
| `data.derivation.name` | The name hashed under that namespace. Always `namespace_uri`, never the deployment's local one |
| `meta.instance_namespace` | **A different thing.** The vocabulary *this deployment* defines locally (`SPARC_OSCAL_NS`). Defaults to SPARC's own entry, so the two usually coincide — do not read one as the other |

### Verifying the UUID rather than trusting it

Python:

```python
import uuid
uuid.uuid5(uuid.NAMESPACE_URL, "https://sparc.risk-sentinel.org/ns")
# UUID('9f434272-f796-589b-b972-954790395630')
```

Ruby:

```ruby
Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "https://sparc.risk-sentinel.org/ns")
# => "9f434272-f796-589b-b972-954790395630"
```

Both produce the same value, which is the cross-runtime agreement the UUIDv5 key grammar (#1161) depends on.

## Errors

| Status | When |
|---|---|
| `401` | Missing or invalid Bearer token |

## Related

- [Federation Peers](federation-peers.md) — the peers this identity is shared with
- #1159 — why dedup keys on `(object UUID, originating party)` rather than the UUID alone
- #1161 — the UUIDv5 key grammar and its shared test vectors
