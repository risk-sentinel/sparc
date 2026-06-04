# Sessions (Token → Cookie Bridge) API

A single endpoint that exchanges a SPARC API Bearer token for a Rails **session cookie** (#573). This lets headless test runners (Playwright, Cypress, headless Chromium) drive the SPARC **UI** as an authenticated user without screen-scraping the login form. It is the Layer-2 prerequisite of the UI testing umbrella (#572).

## Base URL

```
https://sparc.example.com/api/v1
```

## Authentication

Bearer token only — a SPARC service-account token (`sparc_sa_…`) or an OIDC JWT, depending on the configured `SPARC_API_AUTH` mode. The same token validation pipeline as every other `/api/v1/` endpoint applies (revocation, expiry, scope, and CIDR allowlist are all enforced).

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

No CSRF token is required (the caller presents a Bearer, not a cookie).

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/sessions/from_token` | Exchange the Bearer token for a Rails session cookie |

---

### POST `from_token` — bridge a token to a session cookie

```
POST /api/v1/sessions/from_token
```

On a valid token, starts a Rails session for the token's user and returns **`204 No Content`** with a `Set-Cookie: _sparc_session=…` header. The bridged session inherits `SPARC_SESSION_TIMEOUT_MINUTES` — it is no longer-lived than a normal form-login session.

**Request**

```bash
curl -i -X POST https://sparc.example.com/api/v1/sessions/from_token \
  -H "Authorization: Bearer $TOKEN"
```

**Response** `204 No Content`

```
HTTP/2 204
Set-Cookie: _sparc_session=…; path=/; HttpOnly; SameSite=Lax
```

The returned cookie can then be sent on subsequent requests to drive the authenticated UI.

## Errors

| Status | When |
|--------|------|
| `401 Unauthorized` | Missing/blank `Authorization` header (`reason: missing_token`) |
| `401 Unauthorized` | Invalid, expired, or revoked token (`reason: invalid_token`) |

Failures emit an `api_session_bridge_failed` audit event (with the reason); successes emit `api_session_bridged`. No `Set-Cookie` is sent on failure. Errors follow the standard SPARC error envelope; see [errors.md](../errors.md).

## NIST 800-53 controls

`IA-2` (Bearer auth — same pipeline as all `/api/v1/`), `AC-12` (session inherits the standard inactivity timeout), `AU-12` (bridge success/failure audit-logged alongside `login_failure` events).
