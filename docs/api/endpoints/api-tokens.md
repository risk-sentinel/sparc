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
| `DELETE` | `/api/v1/users/:user_id/api_tokens/:id` | Revoke a token immediately |

### POST /api/v1/users/:user_id/api_tokens

#### Request Body

Both fields are optional, so an empty `api_token` object is a valid request.
Any other field is **refused** with `422`, not discarded — see
[errors.md](../errors.md).

| Field | Type | Description |
|---|---|---|
| `name` | string | Label for the token. Defaults to `API Token <n>` |
| `expires_in_days` | integer | Days until expiry. Omit, or send `0`, for a non-expiring token |

```json
{
  "api_token": {
    "name": "CI Pipeline",
    "expires_in_days": 90
  }
}
```

#### Response Body

```json
{
  "data": {
    "id": 42,
    "name": "CI Pipeline",
    "user_id": 7,
    "expires_at": "2026-11-18T14:22:18Z",
    "expired": false,
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
| `422 Unprocessable Entity` | The body carried a field this endpoint does not accept |

### GET /api/v1/users/:user_id/api_tokens

Paginated list of the user's tokens, newest first. Carries `id`, `name`,
`user_id`, `expires_at`, `expired`, `last_used_at` and `created_at` — and no
token value, because none is stored.

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

## NIST 800-53 Controls

- **IA-5** Authenticator Management — plaintext shown once, SHA-256 digest at rest
- **AC-3 / AC-6** Access Enforcement / Least Privilege — instance-admin only
- **AU-12** Audit Record Generation — issue and revoke are both audited
