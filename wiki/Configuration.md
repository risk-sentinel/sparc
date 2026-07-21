# Configuration Reference

SPARC is configured via environment variables — most prefixed with `SPARC_`. All authentication features default to **disabled** (whitelist approach); enable one or more to activate the login page. This page (current for **v1.13.0**) is a curated operator/consumer reference. For the exhaustive list of every variable, including advanced deployment options, see [docs/ENVIRONMENT_VARIABLES.md](https://github.com/risk-sentinel/sparc/blob/main/docs/ENVIRONMENT_VARIABLES.md).

## Application

| Variable | Default | Description |
|----------|---------|-------------|
| `SECRET_KEY_BASE` | (required in prod) | Rails secret key for session/cookie encryption (`bin/rails secret`) |
| `RAILS_ENV` | `development` | Rails environment (development, test, production) |
| `RAILS_MAX_THREADS` | `5` | Puma thread pool + DB connection pool size |
| `FORCE_SSL` | `true` (prod) | Enforce HTTPS redirects + HSTS header |
| `SPARC_APP_URL` | `http://localhost:3000` | Application base public URL (used in emails, links, redirects) |
| `SPARC_APP_NAME` | `SPARC` | Application display name |
| `SPARC_WELCOME_TEXT` | `Welcome to SPARC` | Custom welcome text on the login page |
| `SPARC_CONTACT_EMAIL` | (none) | Support/admin contact email shown in UI |
| `SPARC_RESOURCES` | (built-in defaults) | JSON array of external resource links for the Resources page |

## Database

`DATABASE_URL` takes priority over individual variables when set.

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | (none) | Full PostgreSQL connection URL (preferred) |
| `SPARC_DB_HOST` | `localhost` | Database host |
| `SPARC_DB_PORT` | `5432` | Database port |
| `SPARC_DB_NAME` | `sparc` | Database name |
| `SPARC_DB_USER` | (none) | Database user |
| `SPARC_DB_PASSWORD` | (none) | Database password (use a secrets manager in prod) |
| `SPARC_DB_SSLMODE` | `prefer` | PostgreSQL SSL mode (disable, prefer, require, verify-full) |

## Authentication

All auth features default to **disabled**. Enable one or more to activate `/login`.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_ENABLE_LOCAL_LOGIN` | `false` | Enable email/password login |
| `SPARC_ENABLE_EMAIL_CONFIRMATION` | `false` | Require email confirmation for new local accounts |
| `SPARC_ENABLE_OIDC` | `false` | Enable OpenID Connect SSO |
| `SPARC_ENABLE_LDAP` | `false` | Enable LDAP directory login |
| `SPARC_FIDO2_ENABLED` | `false` | Enable FIDO2/WebAuthn security-key sign-in (passwordless; key + PIN = app-native MFA). Adds a **Security Keys** enrollment page + a "Sign in with a security key" option (#779) |
| `SPARC_ENABLE_PIV` | `false` | Enable PIV / CAC smart-card sign-in (cert + PIN → NIST IA-2(12)). The mTLS + DoD-PKI validation happen at the proxy/ALB; SPARC consumes the forwarded validated cert and fails closed. Only enable behind a correctly-configured mTLS gateway (#779) |
| `SPARC_ENABLE_USER_REGISTRATION` | `false` | Allow self-service registration (usually `false` in prod) |
| `SPARC_SESSION_TIMEOUT_MINUTES` | `60` | Session inactivity timeout (minutes) |
| `SPARC_ADMIN_EMAIL` | `admin@sparc.local` | Email for the bootstrapped admin account |
| `SPARC_PUBLIC_CATALOGS` | `false` | Make the Controls layer (catalogs, baselines, mappings) publicly readable without signing in. Secure-by-default off; enable only when SPARC is fronted by your own network auth (e.g. VPN) |

> **Admin password rotation** is an operational concern managed via your secrets manager (AWS Secrets Manager on ECS), not a value you set as consumer config. See the deployment/rotation docs.

> **FIDO2 & PIV/CAC** have a dedicated operator guide — see [Authentication and MFA](Authentication-and-MFA) for the WebAuthn RP-ID/origin, the PIV forwarded-cert header contract, and mTLS gateway requirements ([sparc-iac#559](https://github.com/risk-sentinel/sparc-iac/issues/559)).

## OIDC / SSO

Requires `SPARC_ENABLE_OIDC=true`. Provider-agnostic — compatible with Okta, Keycloak, Entra ID, Auth0. See [docs/OKTA_DEV_SETUP.md](https://github.com/risk-sentinel/sparc/blob/main/docs/OKTA_DEV_SETUP.md) for an Okta walkthrough.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_OIDC_ISSUER_URL` | (required) | OIDC issuer URL (auto-discovers `.well-known/openid-configuration`) |
| `SPARC_OIDC_CLIENT_ID` | (required) | OIDC client ID |
| `SPARC_OIDC_CLIENT_SECRET` | (required) | OIDC client secret |
| `SPARC_OIDC_REDIRECT_URI` | (auto) | Callback URL (auto-derived from `SPARC_APP_URL`) |
| `SPARC_OIDC_SCOPES` | `openid profile email` | Space-separated OIDC scopes |
| `SPARC_OIDC_PROVIDER_TITLE` | `SSO` | Login-button/tab display name |
| `SPARC_OIDC_FORCE_MFA` | `false` | Require MFA via ACR/amr claim validation |

### API Authentication Mode

Controls which auth method the REST API accepts (mutually exclusive).

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_API_AUTH` | `local` | API auth mode: `local`, `oidc`, or `hybrid` |
| `SPARC_API_OIDC_AUDIENCE` | `SPARC_OIDC_CLIENT_ID` | Expected `aud` claim in OIDC JWTs (oidc/hybrid only) |

`hybrid` is recommended for production: humans authenticate via OIDC JWT (MFA enforced by IdP), CI/CD pipelines use SPARC service-account tokens.

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
| `SPARC_LDAP_CA_FILE` | (none) | PEM CA file to verify the directory server certificate; omit to trust the container/system CA store (add a private CA via `SPARC_EXTRA_CA_CERTS`) (#773) |
| `SPARC_LDAP_TLS_VERIFY` | `true` | Verify the directory server's TLS certificate. **Leave `true`** — `false` encrypts but does not authenticate the server (MITM-open) and is logged loudly on every connection (#773) |

## Outbound TLS Trust & Egress Proxy

For locked-down enterprise or DoD environments (private CAs, a mandated TLS egress proxy). Outbound TLS verification stays **on**; these only add trust or routing (#774, #775).

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_EXTRA_CA_CERTS` | (none) | Path (file, or directory of `.crt`/`.pem`/`.cer`) to custom/private CA certs to trust for **outbound** TLS — LDAPS, OIDC behind a private CA, a TLS-intercepting proxy, or DoD-PKI endpoints. Appended to the system bundle at startup so every outbound client benefits (public CAs stay trusted). Or bake CAs in at build time via `certs/` |
| `HTTPS_PROXY` / `HTTP_PROXY` | (none) | Egress proxy for outbound HTTP(S) (OIDC discovery/JWKS, federation sync, content refreshers). Honored scheme-strictly — `HTTPS_PROXY` for `https://`. Lowercase also works |
| `NO_PROXY` | (none) | Comma-separated hosts/domains that bypass the proxy (e.g. internal federation peers). Lowercase also works |

## OAuth Providers

Auto-enabled when the client ID is present (no separate enable flag needed).

### GitHub

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_GITHUB_CLIENT_ID` | (none) | GitHub OAuth app client ID (auto-enables when set) |
| `SPARC_GITHUB_CLIENT_SECRET` | (none) | GitHub OAuth app client secret |

### GitLab

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_GITLAB_CLIENT_ID` | (none) | GitLab application ID (auto-enables when set) |
| `SPARC_GITLAB_CLIENT_SECRET` | (none) | GitLab application secret |
| `SPARC_GITLAB_SITE` | `https://gitlab.com` | GitLab instance URL (for self-hosted) |

## Consent Banner & Environment Header

### Login Consent Banner

Shows a mandatory consent/warning modal before login options appear. The banner HTML is loaded from the file at `SPARC_BANNER_MESSAGE` (resolved against `Rails.root`) and sanitized for XSS. Sample files live in `docs/banners/`.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_BANNER_ENABLED` | `false` | Show the mandatory consent banner on the login page |
| `SPARC_BANNER_MESSAGE` | (none) | File path to the banner HTML body (required if enabled) |

### Environment / Rules-of-Behavior Header (NIST AC-8)

Shows a configurable header bar on **every screen** describing the deployment environment and its rules of behavior (e.g. `PRODUCTION — Authorized use only`). Default-off: an empty/unset `SPARC_HEADER_TEXT` renders no header. Text is escaped plain text (full UTF-8 supported). Maps to NIST **AC-8 (System Use Notification)**.

> Colors are operator-defined and **contrast is not enforced** — you are responsible for readable contrast. Values are validated against a strict hex/`rgb()` grammar; a malformed value falls back to the default. Built-in defaults pass WCAG AA.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_HEADER_TEXT` | (none) | Short environment/rules text shown on all screens; empty hides the header |
| `SPARC_HEADER_TEXT_COLOR` | `#ffffff` | Header text color (hex or `rgb()`/`rgba()`); invalid falls back to default |
| `SPARC_HEADER_HIGHLIGHT_COLOR` | `#1f6fa5` | Header highlight/background color; invalid falls back to default |

## Email / SMTP

Required for registration confirmation, password resets, and notifications.

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
| `SPARC_LOG_TO_STDOUT` | `false` (`true` in prod) | Log to STDOUT (for container logs) |
| `SPARC_STRUCTURED_LOGGING` | `false` | Emit JSON logs (CloudWatch/ELK/Splunk friendly) |
| `SPARC_LOG_LEVEL` | `info` | Log level (debug, info, warn, error) |

## Storage & Uploads

By default SPARC stores uploads on local disk. Set `ACTIVE_STORAGE_SERVICE=amazon` to use S3.

> **Production S3 access uses the ECS task IAM role** — no static AWS keys are configured as app environment variables. Grant the task role S3 permissions on your bucket via your deployment infrastructure.

| Variable | Default | Description |
|----------|---------|-------------|
| `ACTIVE_STORAGE_SERVICE` | `local` | Storage backend (`local` or `amazon`) |
| `SPARC_PERSIST_S3_BLOB` | `true` (retain) | Keep the original upload blob after a successful parse so exported documents keep durable back-matter artifacts. Set `false` to purge-after-parse |
| `SPARC_MAX_UPLOAD_MB` | `50` | Max upload size (MB) for all document types; also caps uncompressed zip totals (zip-bomb defense) |
| `SPARC_MAX_AVATAR_MB` | `2` | Max user-avatar upload size (MB), separate from document uploads |

Align your reverse-proxy body cap to roughly `SPARC_MAX_UPLOAD_MB + 10 MB` so the proxy fails fast on oversized requests.

### Cookieless User-Data Subdomain

User-uploaded blobs are served from a separate cookieless hostname so injected scripts can never read the SPARC session cookie.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_USERDATA_HOST` | (derived) | Override hostname for serving ActiveStorage blobs; when unset, derived as `userdata.<host>` from `SPARC_APP_URL`. Most operators don't need to set this |

## Rate Limiting

Rack::Attack throttle thresholds. Defaults are conservative; tighten for high-security tenants. Throttled requests get HTTP `429` with `Retry-After`.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_RATE_LIMITING_ENABLED` | `true` | Master kill switch for all throttles (set `false` for emergency triage) |
| `SPARC_RATE_LIMIT_UPLOADS_PER_5MIN_PER_IP` | `30` | Per-IP cap on upload endpoints |
| `SPARC_RATE_LIMIT_UPLOADS_PER_HOUR_PER_USER` | `100` | Per-user cap on upload endpoints |
| `SPARC_RATE_LIMIT_API_WRITES_PER_MINUTE` | `300` | Per-token cap on `/api/v1` write methods |
| `SPARC_RATE_LIMIT_LOGIN_FAILURES_PER_MIN` | `5` | Per-IP cap on login failures (credential-stuffing defense) |
| `SPARC_RATE_LIMIT_SAFELIST_CIDRS` | `127.0.0.1,::1` | CIDRs that bypass all throttles (health checks, NLB targets) |

## Document Lifecycle & Workflow

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_REQUIRE_DOCUMENT_APPROVAL` | `false` | Require documents to pass an approval workflow before finalization |
| `SPARC_INACTIVITY_DAYS` | `30` | Days of user inactivity before an account is auto-deactivated |
| `SPARC_PASSWORD_EXPIRY_DAYS` | `30` | Days before a local-auth password expires (SSO users exempt) |
| `SPARC_SA_INACTIVITY_DAYS` | `90` | Days of inactivity before a service account is auto-disabled |
| `SPARC_PROCESSING_STUCK_MINUTES` | `5` | Minutes after which a stuck document stops auto-refreshing its show page |

## Artifact Retention

Controls automatic cleanup of orphaned upload artifacts and per-version copies.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_ARTIFACT_REAPER_ENABLED` | `true` | Enable the recurring artifact-reaper job that prunes orphaned blobs |
| `SPARC_ARTIFACT_REAPER_INTERVAL_DAYS` | `7` | How often the artifact-reaper job runs |
| `SPARC_ARTIFACT_COPY_PER_VERSION` | `true` | Keep a distinct artifact copy per document version for durable back-matter |

## Dynamic Roles

Comma-separated lists overriding the built-in defaults. Set these **before** inviting members — existing assignments are not migrated.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_ORGANIZATION_ROLES` | (built-in agency roles) | Role names available to organization members (plus the always-present "Org Admin") |
| `SPARC_AUTH_BOUNDARY_ROLES` | (built-in ATO roles) | Role names available to authorization-boundary members |
| `SPARC_ENVIRONMENTS_LIST` | DEV, TEST, STAG, UAT, QA, PROD | Selectable environments for boundaries as `Name:CODE` pairs, e.g. `Development:DEV,Production:PROD` |

## OSCAL Organization Metadata

Default values embedded in generated OSCAL exports (SSP, SAR, CDEF). Empty values are omitted from exports.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_ORG_NAME` | `Default Organization` | Organization name in OSCAL metadata |
| `SPARC_ORG_DESCRIPTION` | (none) | Organization description |
| `SPARC_ORG_ADDRESS` | (none) | Organization address |
| `SPARC_ORG_CONTACT_PERSON` | (none) | Primary contact person |
| `SPARC_ORG_CONTACT_EMAIL` | (none) | Primary contact email |

## HDF Normalization

Controls how Heimdall Data Format (HDF) inputs are normalized during SAR/POAM conversion.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_HDF_ALLOWED_VERSIONS` | (accept bundled) | Comma-separated list of accepted hdf-cli versions; unset accepts whatever the image bakes |

## DISA CCI Catalog Retrieval

Source URL and revision set used when SPARC fetches the DISA CCI list for NIST 800-53 mapping. Override the URL for air-gapped or mirror environments.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_DISA_CCI_URL` | DISA cyber.mil ZIP URL | Source URL for the DISA CCI list ZIP |
| `SPARC_CCI_REVS` | `4,5` | Comma-separated NIST 800-53 revisions to extract from the CCI list |

## AWS Labs CDEF Ingestion

Runtime ingestion of OSCAL Component Definitions from [`awslabs/oscal-content-for-aws-services`](https://github.com/awslabs/oscal-content-for-aws-services). Off by default so air-gapped tenants are unaffected. Imported CDEFs are read-only; users click "Copy for editing" to amend.

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_AWS_LABS_CDEF_ENABLED` | `false` | Master switch for AWS Labs CDEF ingestion |
| `SPARC_AWS_LABS_CDEF_REPO` | `awslabs/oscal-content-for-aws-services` | Override source repo (internal fork/mirror) |
| `SPARC_AWS_LABS_CDEF_BRANCH` | `main` | Pin to a tag or branch for reproducibility |
| `SPARC_AWS_LABS_OSCAL_VERSIONS` | (auto-detect) | CSV of OSCAL spec versions to ingest |
| `SPARC_AWS_LABS_CDEF_REFRESH_INTERVAL_DAYS` | `7` | How often the recurring refresh job runs (clamped 1..90) |
| `SPARC_AWS_LABS_GITHUB_TOKEN` | (unset) | Optional GitHub PAT (`contents:read`) to raise the API rate limit 60→5000/hr |

## Redis / Background Jobs

**Solid Queue is the default background-job backend and needs no Redis.** Redis (with the optional Sidekiq adapter) is only required if you explicitly opt into Sidekiq.

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_URL` | `redis://localhost:6379/0` | Redis connection URL — required **only** when using the optional Sidekiq adapter |
| `SOLID_QUEUE_IN_PUMA` | (unset) | Run Solid Queue in-process with Puma (single-server deploys) |
| `JOB_CONCURRENCY` | `1` | Number of Solid Queue worker processes |

## Docker Compose Defaults

Development `docker-compose.yaml` uses offset host ports to avoid conflicts with local services:

| Service | Container Port | Host Port |
|---------|---------------|-----------|
| PostgreSQL | 5432 | **5433** |
| Redis (optional) | 6379 | **6380** |
| Web | 3000 | 3000 |

> The Redis container ships in the Compose file for convenience but is only exercised when you opt into the Sidekiq adapter; the default Solid Queue backend does not use it.

## Related

- [docs/ENVIRONMENT_VARIABLES.md](https://github.com/risk-sentinel/sparc/blob/main/docs/ENVIRONMENT_VARIABLES.md) — Exhaustive canonical reference (all variables, including advanced deployment options)
- [docs/AUTHENTICATION.md](https://github.com/risk-sentinel/sparc/blob/main/docs/AUTHENTICATION.md) — Auth provider setup guide
- [docs/OKTA_DEV_SETUP.md](https://github.com/risk-sentinel/sparc/blob/main/docs/OKTA_DEV_SETUP.md) — Okta OIDC configuration walkthrough
