# Authentication

## Overview

All API requests require a Bearer token in the `Authorization` header:

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

Requests without a valid token receive a `401 Unauthorized` response.

## Token Types

SPARC supports three token formats. The token prefix determines how the server validates it.

### SPARC Tokens (prefix `sparc_`)

Standard API tokens generated via the Admin UI or Rails console. Suitable for development and interactive use.

```
Authorization: Bearer sparc_abc123def456...
```

### Service Account Tokens (prefix `sparc_sa_`)

Tokens bound to a service account rather than a human user. Designed for CI/CD pipelines, automation scripts, and machine-to-machine integrations. Service accounts support optional endpoint and CIDR restrictions.

```
Authorization: Bearer sparc_sa_pipeline_xyz789...
```

### OIDC JWTs (prefix `eyJ`)

JSON Web Tokens issued by an external OIDC provider such as Okta. The server validates the JWT signature and claims against the configured provider.

```
Authorization: Bearer eyJhbGciOiJSUzI1NiIs...
```

## Auth Modes

The `SPARC_API_AUTH` environment variable controls which token types the server accepts.

| Mode | `SPARC_API_AUTH` | Accepts | Best For |
|---|---|---|---|
| local (default) | `local` | SPARC tokens only | Development |
| oidc | `oidc` | JWTs only | Full Okta integration |
| hybrid | `hybrid` | JWTs (humans) + SPARC tokens (service accounts) | Production |

When `SPARC_API_AUTH` is not set, the server defaults to `local` mode.

## Generating Tokens

### Via Rails Console

```ruby
bin/rails console

user = User.find_by(email: "admin@example.com")
token = user.api_tokens.create!(name: "My API Token")
puts token.token  # => "sparc_abc123def456..."
```

### Via Admin UI

1. Sign in as an administrator.
2. Navigate to **Admin > API Tokens**.
3. Click **New Token**, provide a name, and click **Create**.
4. Copy the token immediately -- it is only displayed once.

## Service Accounts

Service accounts provide scoped, non-human access for automation.

### Creating a Service Account

1. Navigate to **Admin > Service Accounts**.
2. Click **New Service Account** and provide a name and description.
3. Optionally restrict access:
   - **Endpoint scoping**: limit the account to specific API endpoints (e.g., only `GET /api/v1/ssp_documents`).
   - **CIDR scoping**: limit requests to specific IP ranges (e.g., `10.0.0.0/8`).
4. Click **Create** and copy the generated token.

## cURL Examples

### Local mode (SPARC token)

```bash
curl -s https://sparc.example.com/api/v1/ssp_documents \
  -H "Authorization: Bearer sparc_abc123def456"
```

### OIDC mode (JWT)

```bash
curl -s https://sparc.example.com/api/v1/ssp_documents \
  -H "Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### Hybrid mode (service account token)

```bash
curl -s https://sparc.example.com/api/v1/ssp_documents \
  -H "Authorization: Bearer sparc_sa_pipeline_xyz789"
```

## Common Auth Errors

| Status | Error Message | Cause |
|---|---|---|
| 401 | `Missing authorization token` | No `Authorization` header provided |
| 401 | `Invalid or expired token` | Token is malformed, revoked, or expired |
| 403 | `Endpoint not allowed for this service account` | Service account does not have access to the requested endpoint |
| 403 | `Request origin not in allowed CIDR range` | Client IP is outside the service account's allowed CIDR blocks |
