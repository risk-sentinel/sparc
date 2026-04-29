# Admin Credentials

Out-of-band rotation entry point for the SPARC instance admin password. The endpoint is designed to be called by a sparc-iac-managed Lambda that has already written the new password to AWS Secrets Manager (`AWSPENDING`); SPARC bcrypts the value into the admin user's `password_digest` and the Lambda is responsible for promoting `AWSPENDING` → `AWSCURRENT` after a successful 200. The contract is documented in [Rebel-Raiders/sparc-iac#197](https://github.com/Rebel-Raiders/sparc-iac/issues/197) and the operator runbook lives in `docs/ADMIN_CREDENTIAL_ROTATION.md`.

The endpoint is **disabled by default** to fail closed in environments that have not opted in to remote rotation. Set `SPARC_ADMIN_REFRESH_ENABLED=true` on the SPARC ECS task definition to enable it.

## Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `POST` | `/api/v1/admin/refresh_credentials` | Update the admin user's password from a Lambda-supplied plaintext | `admin.rotate_credentials` permission |

## Authentication

Bearer token authentication using a SPARC service account API token (`sparc_sa_*`). The token's owning service account must hold the `admin.rotate_credentials` permission. CIDR allowlisting (`allowed_cidrs`) and endpoint scoping (`allowed_endpoints`) on the service account token are recommended; both are documented in `docs/ADMIN_CREDENTIAL_ROTATION.md`.

```
Authorization: Bearer sparc_sa_YOUR_TOKEN_HERE
```

Admin user Bearer tokens are also accepted (since admins implicitly hold every permission) but the operational pattern is to use a dedicated rotation-Lambda service account, not a personal admin token.

---

### POST /api/v1/admin/refresh_credentials

Bcrypt the supplied plaintext password into the admin user's `password_digest`. Idempotent — submitting the value the admin already has returns `200 unchanged` rather than re-mutating, so a Lambda or operator can safely retry without re-rotating.

#### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `password` | string | Yes | The new plaintext password. Must be non-empty. |

```json
{
  "password": "Tr0ub4dor&3-temporary-staging-only"
}
```

#### Response Body — Rotation applied

```json
{
  "status": "ok",
  "audit_event_id": 4231,
  "rotated_at": "2026-04-29T14:22:18Z"
}
```

#### Response Body — No-op (password already matches)

```json
{
  "status": "unchanged",
  "audit_event_id": 4232,
  "rotated_at": "2026-04-15T08:11:03Z"
}
```

The `audit_event_id` is the `id` of the row written to `audit_events`. Use it (along with the `version_id` returned by Secrets Manager) to correlate the SPARC-side audit trail with the Lambda's CloudWatch log entry.

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Password applied (`status: "ok"`) or already matched (`status: "unchanged"`) |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Token's service account lacks the `admin.rotate_credentials` permission |
| `404 Not Found` | `SPARC_ADMIN_EMAIL` does not match any user in this instance |
| `422 Unprocessable Entity` | `password` field is missing or empty |
| `503 Service Unavailable` | `SPARC_ADMIN_REFRESH_ENABLED` is not set to `true` |

#### Side effects

A successful call writes one row to `audit_events`:

- `action`: `admin_credential_rotated`
- `metadata.source`: `"api"`
- `metadata.actor_token_id`: id of the calling service account's `ApiToken`
- `metadata.outcome`: `"unchanged"` on no-op, omitted on actual rotation

The plaintext password is **never** written to the audit row, the Rails log, the response body, or any header.

#### cURL Example

```bash
curl -X POST "https://sparc.example.com/api/v1/admin/refresh_credentials" \
  -H "Authorization: Bearer sparc_sa_YOUR_ROTATION_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"password":"new-plaintext-password"}'
```

---

## Common Errors

| Status | Body | Cause |
|--------|------|-------|
| `401 Unauthorized` | `{"error": "Unauthorized"}` | Bearer token missing, expired, or invalid |
| `403 Forbidden` | `{"error": "Token lacks admin.rotate_credentials permission"}` | Service account's role does not include `admin.rotate_credentials` |
| `404 Not Found` | `{"error": "Admin user not found"}` | The user identified by `SPARC_ADMIN_EMAIL` has been deleted or that env var is unset |
| `422 Unprocessable Entity` | `{"error": "password is required"}` | Request body was empty, malformed JSON, or `password` was an empty string |
| `503 Service Unavailable` | `{"error": "Admin credential refresh endpoint is disabled. Set SPARC_ADMIN_REFRESH_ENABLED=true to enable."}` | Feature flag not enabled on this instance |

## NIST 800-53 mapping

| Control | How this endpoint addresses it |
|---|---|
| `AC-3` Access Enforcement | Permission check (`admin.rotate_credentials`) before any state change |
| `AC-17` Remote Access | CIDR allowlist on the service account token; TLS in transit |
| `AU-2` Audit Events | Every call (success and no-op) writes an `admin_credential_rotated` `AuditEvent` |
| `IA-5` Authenticator Management | The endpoint exists specifically to propagate Secrets Manager rotation into the running app |
| `SC-13` Cryptographic Protection | Plaintext only ever lives in memory; storage is bcrypt; transport is TLS |
| `SI-10` Information Input Validation | Empty / missing password rejected before any side effect |

## Related documentation

- [`ADMIN_CREDENTIAL_ROTATION.md`](../../ADMIN_CREDENTIAL_ROTATION.md) — operator runbook covering the full Path A / B / C flows
- [`SPARC_HASH_ROTATION.md`](../../SPARC_HASH_ROTATION.md) — sibling runbook for rotating the `SPARC_HASH` master secret
- SPARC issues [#402](https://github.com/Rebel-Raiders/sparc/issues/402) and [#403](https://github.com/Rebel-Raiders/sparc/issues/403) — the original feature requests
- [Rebel-Raiders/sparc-iac#197](https://github.com/Rebel-Raiders/sparc-iac/issues/197) — sparc-iac counterpart (task-def secrets injection + IAM delta + rotation Lambda)
