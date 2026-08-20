# Service Accounts API

Service accounts are the API-only identities that pipelines, CI systems and
third-party integrations authenticate as. They carry `sparc_sa_` tokens and
cannot sign in through the web UI.

Added in [#1013](https://github.com/risk-sentinel/sparc/issues/1013). Before it,
every part of the lifecycle was browser-only — so provisioning automation could
not provision the identity it was going to run as, and rotating a compromised
credential required a human with a browser session. Found by the
missing-endpoint axis of
[#995](https://github.com/risk-sentinel/sparc/issues/995).

## Base URL

```
https://sparc.example.com/api/v1/service_accounts
```

## Authorization

**Instance admin only**, reads included.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/service_accounts` | List service accounts, `?q=` searchable |
| `POST` | `/api/v1/service_accounts` | Create an account **and issue its first token** |
| `GET` | `/api/v1/service_accounts/:id` | Show one, with its token metadata |
| `PATCH`/`PUT` | `/api/v1/service_accounts/:id` | Update attributes |
| `POST` | `/api/v1/service_accounts/:id/disable` | Disable, with an optional `reason` |
| `POST` | `/api/v1/service_accounts/:id/enable` | Re-enable |
| `POST` | `/api/v1/service_accounts/:id/regenerate_token` | Revoke every token and issue a new one |
| `DELETE` | `/api/v1/service_accounts/:id` | **Deactivate** — see below |

### POST /api/v1/service_accounts

Creates the account and its first token in one call. An account with no token
cannot do anything, so splitting the two would make a second request mandatory
every time.

| Field | Type | Description |
|---|---|---|
| `email` | string | Required |
| `first_name`, `last_name`, `display_name` | string | Identifying detail |
| `owner_id` | integer | The human accountable for the account |
| `admin` | boolean | Opt-in only, never implicit (AC-6) |
| `expires_in_days` | integer | Token lifetime. **Defaults to 90** |
| `allowed_endpoints` | array | Restrict the token to these paths (AC-3) |
| `allowed_cidrs` | array | Restrict the token to these networks (AC-17) |

`allowed_endpoints` and `allowed_cidrs` accept a JSON array — the natural API
shape — or the web form's comma/newline-separated string.

**The token expiry defaults to 90 days rather than never.** A non-expiring
credential for an unattended identity is the one most likely to outlive its
purpose.

The response carries `token` **once**. Only the SHA-256 digest is stored; it
cannot be retrieved again by any endpoint.

### POST /api/v1/service_accounts/:id/regenerate_token

**Revokes every existing token before issuing the new one.** Rotation that
leaves the old credential working is not rotation. The response reports
`tokens_revoked` alongside the new `token`.

### DELETE /api/v1/service_accounts/:id

**Deactivates rather than deletes**, exactly as the web path does. A service
account is the actor on audit events; deleting the row would orphan the record
of what it did. The response says so explicitly in `note`.

## Status Codes

| Status | Description |
|---|---|
| `200 OK` | Read, update, lifecycle action, or deactivation succeeded |
| `201 Created` | Account created; `data.token` carries the plaintext |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller is not an instance admin |
| `404 Not Found` | No service account matches the id (human users are never matched) |
| `422 Unprocessable Entity` | Validation failed, or the body carried a field this endpoint does not accept |

## Audit

| Action | When |
|---|---|
| `service_account_created` | Account created |
| `service_account_updated` | Attributes changed; metadata carries the diff |
| `service_account_disabled` | Disabled; metadata carries the reason |
| `service_account_enabled` | Re-enabled |
| `service_account_token_regenerated` | Rotated; metadata carries the new prefix and how many were revoked |
| `service_account_deleted` | Deactivated |

## NIST 800-53 Controls

- **AC-2** Account Management · **AC-3** Access Enforcement · **AC-6** Least Privilege
- **AC-17** Remote Access — CIDR allowlist
- **IA-4** Identifier Management · **IA-5** Authenticator Management
- **AU-12** Audit Record Generation
