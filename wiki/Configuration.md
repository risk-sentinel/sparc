# Configuration Reference

SPARC is configured via environment variables prefixed with `SPARC_`. All authentication features default to **disabled** (whitelist approach). See [docs/ENVIRONMENT_VARIABLES.md](https://github.com/risk-sentinel/sparc/blob/main/docs/ENVIRONMENT_VARIABLES.md) for the canonical reference.

## Application

| Variable | Default | Description |
|----------|---------|-------------|
| `SECRET_KEY_BASE` | (required) | Rails secret key for session encryption |
| `RAILS_ENV` | `development` | Rails environment (development, test, production) |
| `RAILS_MAX_THREADS` | `3` | Puma thread count |
| `SPARC_APP_URL` | `http://localhost:3000` | Application base URL |
| `SPARC_APP_NAME` | `SPARC` | Application display name |
| `SPARC_CONTACT_EMAIL` | (none) | Contact email shown in UI |
| `SPARC_WELCOME_TEXT` | (none) | Custom welcome text for login page |
| `FORCE_SSL` | `true` (prod) | Enforce HTTPS redirects |

## Database

`DATABASE_URL` takes priority over individual variables when set.

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | (none) | Full PostgreSQL connection URL |
| `SPARC_DB_HOST` | `localhost` | Database host |
| `SPARC_DB_PORT` | `5432` | Database port |
| `SPARC_DB_NAME` | `sparc` | Database name |
| `SPARC_DB_USER` | (none) | Database user |
| `SPARC_DB_PASSWORD` | (none) | Database password |
| `SPARC_DB_SSLMODE` | (none) | PostgreSQL SSL mode |

## Authentication

All auth features default to **disabled**. Set any of the following to `true` to enable.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_ENABLE_LOCAL_LOGIN` | `false` | Enable email/password login |
| `SPARC_ENABLE_OIDC` | `false` | Enable OpenID Connect SSO |
| `SPARC_ENABLE_LDAP` | `false` | Enable LDAP directory login |
| `SPARC_ENABLE_USER_REGISTRATION` | `false` | Allow self-service registration |
| `SPARC_SESSION_TIMEOUT_MINUTES` | `60` | Session inactivity timeout |

## OIDC / SSO

Requires `SPARC_ENABLE_OIDC=true`. Compatible with Okta, Keycloak, Entra ID, Auth0.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_OIDC_ISSUER_URL` | (required) | OIDC issuer URL (auto-discovers .well-known) |
| `SPARC_OIDC_CLIENT_ID` | (required) | OIDC client ID |
| `SPARC_OIDC_CLIENT_SECRET` | (required) | OIDC client secret |
| `SPARC_OIDC_REDIRECT_URI` | (auto) | Callback URL (auto-generated from APP_URL) |
| `SPARC_OIDC_SCOPES` | `openid profile email` | OIDC scopes to request |
| `SPARC_OIDC_PROVIDER_TITLE` | `SSO` | Button text on login page |
| `SPARC_OIDC_FORCE_MFA` | `false` | Require MFA via ACR/amr claims |

## LDAP

Requires `SPARC_ENABLE_LDAP=true`.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_LDAP_HOST` | (required) | LDAP server hostname |
| `SPARC_LDAP_PORT` | `636` | LDAP server port |
| `SPARC_LDAP_ENCRYPTION` | `simple_tls` | Encryption method (simple_tls, start_tls, plain) |
| `SPARC_LDAP_BIND_DN` | (required) | Service account distinguished name |
| `SPARC_LDAP_BIND_PASSWORD` | (required) | Service account password |
| `SPARC_LDAP_BASE` | (required) | Search base DN |
| `SPARC_LDAP_ATTRIBUTE` | `uid` | User lookup attribute |

## OAuth Providers

Auto-enabled when client ID is present (no separate enable flag needed).

### GitHub

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_GITHUB_CLIENT_ID` | (none) | GitHub OAuth app client ID |
| `SPARC_GITHUB_CLIENT_SECRET` | (none) | GitHub OAuth app client secret |

### GitLab

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_GITLAB_CLIENT_ID` | (none) | GitLab OAuth app client ID |
| `SPARC_GITLAB_CLIENT_SECRET` | (none) | GitLab OAuth app client secret |
| `SPARC_GITLAB_SITE` | `https://gitlab.com` | GitLab instance URL (for self-hosted) |

## Email / SMTP

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_ENABLE_SMTP` | `false` | Enable SMTP email delivery |
| `SPARC_SMTP_ADDRESS` | (none) | SMTP server address |
| `SPARC_SMTP_PORT` | `587` | SMTP server port |
| `SPARC_SMTP_USERNAME` | (none) | SMTP username |
| `SPARC_SMTP_PASSWORD` | (none) | SMTP password |
| `SPARC_SMTP_AUTH` | `plain` | Auth method (plain, login, cram_md5) |
| `SPARC_SMTP_STARTTLS_AUTO` | `true` | Auto-negotiate STARTTLS |
| `SPARC_SMTP_FROM_ADDRESS` | (none) | Default sender address |

## Logging

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_LOG_TO_STDOUT` | `true` (prod) | Log to STDOUT (for container logs) |
| `SPARC_STRUCTURED_LOGGING` | `false` | Enable structured JSON log format |
| `SPARC_LOG_LEVEL` | `info` | Log level (debug, info, warn, error, fatal) |

## Storage

| Variable | Default | Description |
|----------|---------|-------------|
| `ACTIVE_STORAGE_SERVICE` | `local` | Storage backend (local or amazon) |
| `AWS_ACCESS_KEY_ID` | (none) | AWS access key (for S3 storage) |
| `AWS_SECRET_ACCESS_KEY` | (none) | AWS secret key |
| `AWS_REGION` | (none) | AWS region |
| `AWS_BUCKET` | (none) | S3 bucket name |

## Redis / Background Jobs

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_URL` | `redis://localhost:6379/0` | Redis connection URL (required only when using the optional Sidekiq adapter; Solid Queue is the default and needs no Redis) |

## Docker Compose Defaults

Development `docker-compose.yaml` uses offset ports to avoid conflicts with local services:

| Service | Container Port | Host Port |
|---------|---------------|-----------|
| PostgreSQL | 5432 | **5433** |
| Redis | 6379 | **6380** |
| Web | 3000 | 3000 |

## Related

- [docs/ENVIRONMENT_VARIABLES.md](https://github.com/risk-sentinel/sparc/blob/main/docs/ENVIRONMENT_VARIABLES.md) -- Canonical reference
- [docs/AUTHENTICATION.md](https://github.com/risk-sentinel/sparc/blob/main/docs/AUTHENTICATION.md) -- Auth provider setup guide
- [docs/OKTA_DEV_SETUP.md](https://github.com/risk-sentinel/sparc/blob/main/docs/OKTA_DEV_SETUP.md) -- Okta OIDC configuration walkthrough
- [Issue #38](https://github.com/risk-sentinel/sparc/issues/38) -- Environment variables configuration reference
