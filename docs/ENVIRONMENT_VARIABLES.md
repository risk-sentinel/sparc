# Environment Variables Configuration

## Database Configuration

SPARC uses PostgreSQL as the primary database. The preferred way to configure is via `DATABASE_URL`, but individual variables are supported for flexibility.

| Variable              | Description                                                                 | Default          | Example                                      | Required? |
|-----------------------|-----------------------------------------------------------------------------|------------------|----------------------------------------------|-----------|
| DATABASE_URL          | Full PostgreSQL connection URI (preferred method)                           | (none)           | `postgres://user:pass@host:5432/sparc_prod`  | Yes (if no individual vars) |
| SPARC_DB_HOST         | Database host (fallback if DATABASE_URL not set)                            | localhost        | `db.example.com`                             | No        |
| SPARC_DB_PORT         | Database port                                                               | 5432             | `5433`                                       | No        |
| SPARC_DB_NAME         | Database name                                                               | sparc            | `sparc_production`                           | No        |
| SPARC_DB_USER         | Database username                                                           | (none)           | `sparc_app`                                  | No        |
| SPARC_DB_PASSWORD     | Database password (use secrets manager in prod)                             | (none)           | `super-secure-pass-123`                      | No        |
| SPARC_DB_SSLMODE      | SSL mode for connection (disable, prefer, require, verify-full)            | prefer           | `require`                                    | No        |

### OIDC / OAuth2 (Generic & Provider-Agnostic)

These variables configure OpenID Connect login delegation (Okta, Entra ID, Keycloak, Auth0, etc.).

| Variable                        | Description                                                                                     | Default | Example                                                                 | Required? |
|---------------------------------|-------------------------------------------------------------------------------------------------|---------|-------------------------------------------------------------------------|-----------|
| SPARC_ENABLE_OIDC               | Enable OIDC-based SSO login                                                                     | false   | true                                                                    | No        |
| SPARC_OIDC_ISSUER_URL           | OIDC Issuer URL (used for auto-discovery of .well-known/openid-configuration)                   | (none)  | `https://login.microsoftonline.com/{tenant-id}/v2.0`                    | Yes (if enabled) |
| SPARC_OIDC_CLIENT_ID            | Client ID registered with the IdP                                                               | (none)  | `0oa123abc456def789ghi`                                                 | Yes       |
| SPARC_OIDC_CLIENT_SECRET        | Client secret (keep secret; use vault/env secret in prod)                                       | (none)  | `super-long-random-secret-string`                                       | Yes       |
| SPARC_OIDC_REDIRECT_URI         | Callback URL registered with IdP (must match exactly)                                           | (auto)  | `https://sparc.yourdomain.com/auth/oidc/callback`                       | Yes       |
| SPARC_OIDC_SCOPES               | Space-separated OIDC scopes to request                                                          | `openid profile email` | `openid profile email groups offline_access`                            | No        |
| SPARC_OIDC_PROVIDER_TITLE       | Display name shown on login button                                                              | "SSO"   | "Corporate Login (Okta)"                                                | No        |
| SPARC_OIDC_FORCE_MFA            | Enforce MFA via ACR/amr claim validation (if IdP supports it)                                   | false   | true                                                                    | No        |

## General Application & Logging

| Variable                     | Description                                                                 | Default     | Example                              | Required? |
|------------------------------|-----------------------------------------------------------------------------|-------------|--------------------------------------|-----------|
| SPARC_APP_URL                | Base public URL of the application (used in emails, links, redirects)       | (none)      | `https://sparc.example.com`          | Yes (prod) |
| SPARC_APP_NAME               | Human-readable name of the platform                                         | SPARC       | "SPARC Compliance Platform"          | No        |
| SPARC_LOG_TO_STDOUT          | Send logs to stdout (recommended for containers)                           | false       | true                                 | No        |
| SPARC_STRUCTURED_LOGGING     | Output logs in JSON format (CloudWatch, ELK, Splunk friendly)              | false       | true                                 | No        |
| SPARC_LOG_LEVEL              | Logging verbosity (debug, info, warn, error)                               | info        | debug                                | No        |
| SPARC_CONTACT_EMAIL          | Support/admin email shown in UI and error pages                             | (none)      | `compliance-team@yourorg.com`        | No        |

## Email / SMTP Configuration

Required for user registration confirmation, password resets, notifications, etc.

| Variable                  | Description                                                                 | Default | Example                              | Required? |
|---------------------------|-----------------------------------------------------------------------------|---------|--------------------------------------|-----------|
| SPARC_ENABLE_SMTP         | Enable SMTP email delivery                                                  | false   | true                                 | No        |
| SPARC_SMTP_ADDRESS        | SMTP server hostname                                                        | (none)  | `smtp.sendgrid.net`                  | Yes (if enabled) |
| SPARC_SMTP_PORT           | SMTP server port                                                            | 587     | 2525                                 | No        |
| SPARC_SMTP_USERNAME       | SMTP authentication username                                                | (none)  | `apikey`                             | Yes       |
| SPARC_SMTP_PASSWORD       | SMTP authentication password                                                | (none)  | `SG.xxx.your-sendgrid-api-key`       | Yes       |
| SPARC_SMTP_AUTH           | Authentication method (plain, login, cram_md5)                              | plain   | plain                                | No        |
| SPARC_SMTP_STARTTLS_AUTO  | Use STARTTLS if available                                                   | true    | false                                | No        |
| SPARC_SMTP_FROM_ADDRESS   | From: address for outgoing emails                                           | (none)  | `no-reply@sparc.yourdomain.com`      | Yes       |

