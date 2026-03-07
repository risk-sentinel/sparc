# Environment Variables Configuration

Comprehensive reference for all `SPARC_*` environment variables.
Variables are loaded from the environment at boot time via the
`SparcConfig` module (`app/models/sparc_config.rb`). In development,
[dotenv-rails](https://github.com/bkeepers/dotenv) loads from `.env`
automatically.

Copy `.env.example` (development) or `.env.production.example`
(production) as a starting point.

---

## System Configuration

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SECRET_KEY_BASE | Rails session/cookie encryption key (generate with `bin/rails secret`) | (auto in dev) | `a1b2c3d4e5f6...` | Yes (prod) |
| FORCE_SSL | Force HTTPS redirect and Strict-Transport-Security header | true (prod) | `true` | No |
| RAILS_MAX_THREADS | Thread pool size for Puma and database connection pool | 5 | `10` | No |

---

## Database Configuration

SPARC uses PostgreSQL as the primary database. The preferred way to
configure is via `DATABASE_URL`, but individual variables are supported
for flexibility. `DATABASE_URL` always takes priority when set (Rails
auto-merges it over `database.yml` values).

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| DATABASE_URL | Full PostgreSQL connection URI (preferred method) | (none) | `postgres://user:pass@host:5432/sparc_prod` | Yes (if no individual vars) |
| SPARC_DB_HOST | Database host (fallback if DATABASE_URL not set) | localhost | `db.example.com` | No |
| SPARC_DB_PORT | Database port | 5432 | `5433` | No |
| SPARC_DB_NAME | Database name | sparc | `sparc_production` | No |
| SPARC_DB_USER | Database username | (none) | `sparc_app` | No |
| SPARC_DB_PASSWORD | Database password (use secrets manager in prod) | (none) | `super-secure-pass-123` | No |
| SPARC_DB_SSLMODE | SSL mode for connection (disable, prefer, require, verify-full) | prefer | `require` | No |

---

## Authentication

All authentication methods default to **disabled** (whitelist
approach). Enable one or more to activate the login page at `/login`.

### Local Login

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_ENABLE_LOCAL_LOGIN | Enable email/password login | false | `true` | No |
| SPARC_ENABLE_EMAIL_CONFIRMATION | Require email confirmation for new local accounts | false | `true` | No |
| SPARC_SESSION_TIMEOUT_MINUTES | Inactivity timeout in minutes | 60 | `30` | No |
| SPARC_ADMIN_EMAIL | Email for the bootstrapped admin account | admin@sparc.local | `admin@yourorg.com` | No |

### User Registration

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_ENABLE_USER_REGISTRATION | Allow self-service account creation (often false in prod) | false | `true` | No |

### GitHub OAuth

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_GITHUB_CLIENT_ID | GitHub OAuth App Client ID (auto-enables GitHub login when set) | (none) | `Iv1.abc123def456` | No |
| SPARC_GITHUB_CLIENT_SECRET | GitHub OAuth App Client Secret | (none) | `1234567890abcdef` | Yes (if GitHub) |

Create an OAuth App at `https://github.com/organizations/YOUR_ORG/settings/applications`. Set the callback URL to `http://localhost:3000/auth/github/callback`.

### GitLab OAuth

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_GITLAB_CLIENT_ID | GitLab Application ID (auto-enables GitLab login when set) | (none) | `abc123...` | No |
| SPARC_GITLAB_CLIENT_SECRET | GitLab Application Secret | (none) | `def456...` | Yes (if GitLab) |
| SPARC_GITLAB_SITE | GitLab instance URL (for self-hosted) | `https://gitlab.com` | `https://gitlab.yourorg.com` | No |

Create an application at `https://gitlab.com/-/user_settings/applications`. Set the callback URL to `http://localhost:3000/auth/gitlab/callback` with `read_user` scope.

### OIDC / OAuth2 (Generic & Provider-Agnostic)

These variables configure OpenID Connect login delegation
(Okta, Entra ID, Keycloak, Auth0, etc.). See `docs/OKTA_DEV_SETUP.md` for
an Okta-specific configuration guide.

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_ENABLE_OIDC | Enable OIDC-based SSO login | false | `true` | No |
| SPARC_OIDC_ISSUER_URL | OIDC Issuer URL (used for auto-discovery of .well-known/openid-configuration) | (none) | `https://login.microsoftonline.com/{tenant-id}/v2.0` | Yes (if enabled) |
| SPARC_OIDC_CLIENT_ID | Client ID registered with the IdP | (none) | `0oa123abc456def789ghi` | Yes (if enabled) |
| SPARC_OIDC_CLIENT_SECRET | Client secret (keep secret; use vault/env secret in prod) | (none) | `super-long-random-secret-string` | Yes (if enabled) |
| SPARC_OIDC_REDIRECT_URI | Callback URL registered with IdP (must match exactly) | (auto) | `https://sparc.yourdomain.com/auth/oidc/callback` | Yes (if enabled) |
| SPARC_OIDC_SCOPES | Space-separated OIDC scopes to request | `openid profile email` | `openid profile email groups offline_access` | No |
| SPARC_OIDC_PROVIDER_TITLE | Display name shown on login button and tab | SSO | `Corporate Login (Okta)` | No |
| SPARC_OIDC_FORCE_MFA | Enforce MFA via ACR/amr claim validation (if IdP supports it) | false | `true` | No |

### LDAP

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_ENABLE_LDAP | Enable LDAP authentication | false | `true` | No |
| SPARC_LDAP_HOST | LDAP server hostname | (none) | `ldap.example.com` | Yes (if enabled) |
| SPARC_LDAP_PORT | LDAP server port | 636 | `389` | No |
| SPARC_LDAP_ENCRYPTION | Connection encryption (plain, start_tls, simple_tls) | simple_tls | `start_tls` | No |
| SPARC_LDAP_BIND_DN | Bind DN for service account | (none) | `cn=sparc-svc,ou=services,dc=example,dc=com` | Yes (if enabled) |
| SPARC_LDAP_BIND_PASSWORD | Bind password (use secrets manager in prod) | (none) | `ldap-service-password` | Yes (if enabled) |
| SPARC_LDAP_BASE | Search base DN | (none) | `ou=people,dc=example,dc=com` | Yes (if enabled) |
| SPARC_LDAP_ATTRIBUTE | User lookup attribute | uid | `sAMAccountName` | No |

---

## General Application & Logging

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_APP_URL | Base public URL of the application (used in emails, links, redirects) | `http://localhost:3000` | `https://sparc.example.com` | Yes (prod) |
| SPARC_APP_NAME | Human-readable name of the platform | SPARC | `SPARC Compliance Platform` | No |
| SPARC_WELCOME_TEXT | Message displayed on the login page | Welcome to SPARC | `Welcome to ACME Compliance` | No |
| SPARC_CONTACT_EMAIL | Support/admin email shown in UI and login page | (none) | `compliance-team@yourorg.com` | No |
| SPARC_LOG_TO_STDOUT | Send logs to stdout (recommended for containers) | false | `true` | No |
| SPARC_STRUCTURED_LOGGING | Output logs in JSON format (CloudWatch, ELK, Splunk friendly) | false | `true` | No |
| SPARC_LOG_LEVEL | Logging verbosity (debug, info, warn, error) | info | `debug` | No |

---

## Email / SMTP Configuration

Required for user registration confirmation, password resets,
notifications, etc.

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_ENABLE_SMTP | Enable SMTP email delivery | false | `true` | No |
| SPARC_SMTP_ADDRESS | SMTP server hostname | (none) | `smtp.sendgrid.net` | Yes (if enabled) |
| SPARC_SMTP_PORT | SMTP server port | 587 | `2525` | No |
| SPARC_SMTP_USERNAME | SMTP authentication username | (none) | `apikey` | Yes (if enabled) |
| SPARC_SMTP_PASSWORD | SMTP authentication password | (none) | `SG.xxx.your-sendgrid-api-key` | Yes (if enabled) |
| SPARC_SMTP_AUTH | Authentication method (plain, login, cram_md5) | plain | `login` | No |
| SPARC_SMTP_STARTTLS_AUTO | Use STARTTLS if available | true | `false` | No |
| SPARC_SMTP_FROM_ADDRESS | From: address for outgoing emails | (none) | `no-reply@sparc.yourdomain.com` | Yes (if enabled) |

---

## AWS / Storage

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| ACTIVE_STORAGE_SERVICE | Active Storage backend (local or amazon) | local | `amazon` | No |
| AWS_ACCESS_KEY_ID | AWS access key for S3 storage | (none) | `AKIA...` | Yes (if amazon) |
| AWS_SECRET_ACCESS_KEY | AWS secret key for S3 storage | (none) | `wJalr...` | Yes (if amazon) |
| AWS_REGION | AWS region for S3 bucket | (none) | `us-east-1` | Yes (if amazon) |
| AWS_BUCKET | S3 bucket name for file uploads | (none) | `sparc-uploads` | Yes (if amazon) |

---

## Redis & Background Jobs

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| REDIS_URL | Redis connection URL for Sidekiq | `redis://localhost:6379/0` | `redis://redis:6379/0` | Yes |
| SOLID_QUEUE_IN_PUMA | Run Solid Queue in-process with Puma (single-server deploys) | (unset) | `true` | No |
| JOB_CONCURRENCY | Number of Solid Queue worker processes | 1 | `3` | No |
