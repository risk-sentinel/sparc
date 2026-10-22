# API Tokens API

Issue and revoke the Bearer tokens that authenticate against `/api/v1`.

Added in [#1016](https://github.com/risk-sentinel/sparc/issues/1016). Before it,
the credential the API itself authenticates with could be created and revoked
only through a browser session, so rotating a token required a human — including
for the service accounts that exist precisely so automation need not involve one.
The gap was found by the missing-endpoint axis of
[#995](https://github.com/risk-sentinel/sparc/issues/995): a route-list sweep
cannot surface an endpoint that was never written.

## Base URL

```
https://sparc.example.com/api/v1/users/:user_id/api_tokens
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

**Instance admin only**, for every action including the read. A token is a
credential; listing another user's tokens tells you what access exists and when
it was last exercised.

## The plaintext is shown once

`ApiToken.generate!` stores only a SHA-256 digest. The plaintext exists in the
`create` response and nowhere else — it cannot be recovered, re-sent, or read
back by `index`. Copy it at creation or issue a new one.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/users/:user_id/api_tokens` | List a user's tokens — metadata only, never a token value |
| `POST` | `/api/v1/users/:user_id/api_tokens` | Issue a token; the plaintext is in this response only |
| `POST` | `/api/v1/users/:user_id/api_tokens/:id/renew` | Issue a replacement with the same limits; the old token keeps working for the grace window (#1176) |
| `POST` | `/api/v1/users/:user_id/api_tokens/:id/reissue` | Revoke the token now and issue a replacement with the same limits (#1176) |
| `PATCH` | `/api/v1/users/:user_id/api_tokens/:id` | Change the token's endpoint and CIDR limits in place; the token keeps its value (#1233) |
| `DELETE` | `/api/v1/users/:user_id/api_tokens/:id` | Revoke a token immediately |

## Lifetime (#1176)

- **A service account's token must expire.** No path can issue one without an
  expiry: this endpoint, `/api/v1/service_accounts`, and both admin screens all
  create through the same model rule. The expiry may be at most
  `SPARC_API_TOKEN_MAX_DAYS` away (default 365). Asking for more, or for `0`
  ("never"), is refused with `422`; it is never quietly shortened.
- **A person's token may still never expire.** Send `0`, or leave
  `expires_in_days` out.
- **Existing never-expiring tokens keep working.** Upgrading revokes nothing.
  `never_expires: true` marks them in every token listing; renew one to replace
  it with a token that expires.
- **`expiring_soon`** is true for a live token within 14 days of expiry, the
  same window as the owner's warning e-mail.

### POST /api/v1/users/:user_id/api_tokens

#### Request Body

Every field is optional, so an empty `api_token` object is a valid request.
Any other field is **refused** with `422`, not discarded — see
[errors.md](../errors.md).

| Field | Type | Description |
|---|---|---|
| `name` | string | Label for the token. Defaults to `API Token <n>` |
| `expires_in_days` | integer | Whole days until expiry. For a person, omit or send `0` for a token that never expires. For a service account, omitting it gives 90 days, and `0` is refused |
| `allowed_endpoints` | array | What the token may reach. Entries are `"<group>:read"` / `"<group>:write"` from [`GET /api/v1/api_endpoints`](api-endpoints.md), or `"*"` for every endpoint. Omitted or empty: every endpoint. An entry that names nothing is refused with `422` |
| `allowed_cidrs` | array | Source addresses the token may be used from. Omitted or empty: any address |

```json
{
  "api_token": {
    "name": "CI Pipeline",
    "expires_in_days": 90,
    "allowed_endpoints": ["ssp_documents:read", "evidences:write"],
    "allowed_cidrs": ["10.0.0.0/8"]
  }
}
```

A path pattern such as `"/api/v1/ssp_documents*"`, the form used before
#1176, is still accepted and grants Read **and** Write on the paths it
matches. A pattern that matches no route is refused.

#### Response Body

```json
{
  "data": {
    "id": 42,
    "name": "CI Pipeline",
    "user_id": 7,
    "expires_at": "2026-11-18T14:22:18Z",
    "expired": false,
    "never_expires": false,
    "expiring_soon": false,
    "allowed_endpoints": ["ssp_documents:read", "evidences:write"],
    "allowed_endpoints_summary": ["Evidence: Write", "System security plans (SSP): Read"],
    "allowed_cidrs": ["10.0.0.0/8"],
    "last_used_at": null,
    "created_at": "2026-08-20T14:22:18Z",
    "token": "sparc_1cd71cd7f27dd7c7f15a77c7a395aad693204cf6dbcba8ee602028d32cba052e",
    "warning": "Copy this token now. It is not stored and cannot be retrieved again."
  }
}
```

#### Status Codes

| Status | Description |
|---|---|
| `201 Created` | Token issued; `data.token` carries the plaintext |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller is not an instance admin |
| `404 Not Found` | No user matches `:user_id` |
| `422 Unprocessable Entity` | A field this endpoint does not accept; a lifetime a service account may not have; an `allowed_endpoints` entry that names nothing; `expires_in_days` that is not a whole number |

### POST /api/v1/users/:user_id/api_tokens/:id/renew

Issues a new token with the same name, `allowed_endpoints`, `allowed_cidrs`
and lifetime. The old token keeps working until `replaced_token_expires_at`:
`SPARC_API_TOKEN_RENEWAL_GRACE_DAYS` from now (default 7), or its own expiry
if that is sooner. Renewal never extends the old token. Automation switches to
the new token inside that window.

A service-account token that never expired gets a 90-day lifetime on renewal.
A carried-over lifetime longer than today's `SPARC_API_TOKEN_MAX_DAYS` is cut
to the cap.

```json
{
  "data": {
    "id": 43,
    "name": "CI Pipeline",
    "expires_at": "2027-01-17T09:00:00Z",
    "allowed_endpoints": ["ssp_documents:read"],
    "token": "sparc_sa_…",
    "replaced_token_id": 42,
    "replaced_token_expires_at": "2026-10-26T09:00:00Z",
    "warning": "Copy this token now. It is not stored and cannot be retrieved again."
  }
}
```

`201 Created` on success; `403` for a non-admin; `404` for a token that is not
this user's.

### POST /api/v1/users/:user_id/api_tokens/:id/reissue

Revokes the token **now** and issues a replacement with the same name, limits
and lifetime. Use it when the token may be exposed. The response carries the
new plaintext and `revoked_token_id`. `201 Created` on success.

### PATCH /api/v1/users/:user_id/api_tokens/:id

Changes what an existing token may reach, **without reissuing it**: no client
has to swap credentials (#1233). The new limits apply from the token's next
request. Instance admins only.

```json
{
  "api_token": {
    "allowed_endpoints": ["ssp_documents:read", "control_catalogs:read"],
    "allowed_cidrs": ["10.0.0.0/8"]
  }
}
```

- Send either field or both. A field left out keeps its current value; an
  empty list means every endpoint, or any address, as at creation.
- Entries are validated exactly as at creation: an unknown entry is refused
  with `422` and nothing changes. `GET /api/v1/api_endpoints`
  lists what may be named.
- No other field is accepted (`422` for one). Rename, lifetime and value
  changes are `renew` / `reissue`.
- An expired token is refused with `422`: renew or reissue it.

`200 OK` returns the token's metadata, as `GET` lists it. No token value is
returned.

### GET /api/v1/users/:user_id/api_tokens

Paginated list of the user's tokens, newest first. Carries `id`, `name`,
`user_id`, `expires_at`, `expired`, `never_expires`, `expiring_soon`,
`allowed_endpoints`, `allowed_endpoints_summary`, `allowed_cidrs`,
`last_used_at` and `created_at` — and no token value, because none is stored.

### DELETE /api/v1/users/:user_id/api_tokens/:id

Revokes immediately: the token stops authenticating rather than merely
disappearing from the list.

```json
{
  "data": { "id": 42, "name": "CI Pipeline", "revoked": true }
}
```

A token belonging to a different user returns `404` and is left untouched.

## Audit

| Action | When |
|---|---|
| `api_token_created` | A token is issued; metadata carries `token_name` |
| `api_token_revoked` | A token is revoked; metadata carries `token_name` |
| `api_token_renewed` | A token is renewed; metadata carries `replaced_token_id`, `new_token_id` and `old_token_expires_at` |
| `api_token_reissued` | A token is reissued; metadata carries `revoked_token_id` and `new_token_id` |
| `api_token_limits_changed` | A token's limits are edited; metadata carries `token_id`, `token_name`, and `before` / `after` (`allowed_endpoints`, `allowed_cidrs`) |

## NIST 800-53 Controls

- **IA-5** Authenticator Management — plaintext shown once, SHA-256 digest at rest; a service account's token must expire within `SPARC_API_TOKEN_MAX_DAYS`; renewal overlaps for a grace window (#1176)
- **AC-3 / AC-6** Access Enforcement / Least Privilege — instance-admin only; per-resource Read/Write limits (#1176)
- **AU-12** Audit Record Generation — issue and revoke are both audited
