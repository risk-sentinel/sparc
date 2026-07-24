# Environment Variables Configuration

Comprehensive reference for all `SPARC_*` environment variables.
Variables are loaded from the environment at boot time via the
`SparcConfig` module (`app/models/sparc_config.rb`). In development,
[dotenv-rails](https://github.com/bkeepers/dotenv) loads from `.env`
automatically.

Copy `.env.example` (development) or `.env.production.example`
(production) as a starting point.

**For a security-focused operator hardening guide** (minimum-viable
configuration block, threat model, deployment-layer requirements,
v1.7.0 hardening checklist) see [PRODUCTION_SECURITY.md](PRODUCTION_SECURITY.md).

---

## Start here — you do not have to set most of this

This document lists every variable SPARC understands, which makes it look far
larger than the job actually is. **Almost every variable has a working default.**
The list below is long because it is a complete reference, not a checklist.

The variables fall into four groups, and only the first is something a customer
would recognise as "configuration":

### Tier 1 — Product configuration (you decide these)

This is the real list. Roughly a dozen entries.

| Variable | Why you set it |
|---|---|
| `SPARC_APP_URL` | Your public URL. Also derives the OIDC redirect URI and FIDO2 RP ID |
| `SECRET_KEY_BASE` | Rails master secret |
| `SPARC_HASH` | Per-instance master secret (≥32 chars) |
| `DATABASE_URL` | Your database |
| `SPARC_ADMIN_EMAIL` | The instance administrator account |
| `SPARC_CONTACT_EMAIL` | Where users are pointed for support |
| **One auth block** | `SPARC_ENABLE_LOCAL_LOGIN=true`, or OIDC / LDAP / FIDO2 / PIV credentials |
| `SPARC_ORG_NAME`, `SPARC_ORG_DESCRIPTION` | Organisation metadata for OSCAL exports |
| `SPARC_HEADER_TEXT`, `SPARC_BANNER_MESSAGE` | Environment banner and consent text, if you want them |

Configuring a block is usually enough to switch it on: setting
`SPARC_OIDC_CLIENT_ID` enables OIDC, `SPARC_SMTP_ADDRESS` enables mail, and
`SPARC_BANNER_MESSAGE` enables the banner. The matching `SPARC_ENABLE_*` flag is
only needed to force something **off**.

### Tier 2 — Infrastructure (your platform decides these)

`DATABASE_URL`, `REDIS_URL`, `AWS_BUCKET`, `AWS_REGION`, secret ARNs. In a
managed deployment these are rendered by Terraform or your orchestrator; they
are not authored by hand.

### Tier 3 — Deploy plumbing (set once, then forget)

`SPARC_RUN_SEEDS`, `SPARC_SEED_MODE`, `SOLID_QUEUE_IN_PUMA`,
`SPARC_SKIP_DEFERRED_DATA_MIGRATIONS`, `PORT`, `RAILS_ENV`. Operational
mechanics rather than product settings.

### Tier 4 — Internal tuning (you will probably never touch these)

`SPARC_PROCESSING_STUCK_MINUTES`, `SPARC_DOCUMENT_REAP_MINUTES`,
`SPARC_ARTIFACT_REAPER_MIN_AGE_HOURS`, `SCRAPE_THROTTLE_SECONDS`, the
`SPARC_RATE_LIMIT_*` family, upload size caps. The shipped defaults are the
supported values; these exist so support can adjust behaviour without a release.
They remain fully supported overrides.

### A note on defaults

**"Not required" is not "unavailable."** A variable whose default already suits
you simply does not need to appear in your configuration. It keeps working as an
override the moment you set it. Setting a variable to the same value as its
default achieves nothing except making your configuration longer — and setting
one to an empty string is worse than leaving it out, because `""` is not "unset"
and will override a real default.

> **Deployment prerequisite:** SPARC expects to run behind a reverse proxy or CDN
> that serves static assets and terminates TLS. It does not serve static files
> itself (`RAILS_SERVE_STATIC_FILES` is not implemented).

---

## System Configuration

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SECRET_KEY_BASE | Rails session/cookie encryption key (generate with `bin/rails secret`) | (auto in dev) | `a1b2c3d4e5f6...` | Yes (prod) |
| FORCE_SSL | Force HTTPS redirect and Strict-Transport-Security header | true (prod) | `true` | No |
| RAILS_MAX_THREADS | Thread pool size for Puma and database connection pool | 5 | `10` | No |
| SPARC_EXTRA_CA_CERTS | Path (file or directory of `.crt`/`.pem`/`.cer`) to custom/private CA certificates the container should trust for **outbound** TLS — LDAPS, OIDC behind a private CA, a corporate TLS-intercepting proxy, or DoD-PKI endpoints. Appended to the system trust store into a combined bundle at startup (public CAs stay trusted); covers all Ruby OpenSSL clients incl. the LDAP default store. See `certs/README.md`. Alternatively bake CAs in at build time via `certs/`. (#774) | (none) | `/rails/certs` | No |
| HTTPS_PROXY / HTTP_PROXY | Egress proxy for SPARC's **outbound** HTTP(S) calls (OIDC discovery/JWKS, federation sync, external-content refreshers). Honored **scheme-strictly** (#775): `HTTPS_PROXY` is used for `https://` requests — all of SPARC's outbound calls — and `HTTP_PROXY` only for `http://`. Set `HTTPS_PROXY` for a standard TLS egress proxy. Lowercase (`https_proxy`) also works. | (none) | `http://egress-proxy.internal:8080` | No |
| NO_PROXY | Comma-separated hosts/domains that bypass the proxy (e.g. internal federation peers on a trusted network). Honored for all outbound calls. Lowercase (`no_proxy`) also works. | (none) | `.internal,10.0.0.0/8,localhost` | No |

---

## Database Configuration

SPARC uses PostgreSQL as the primary database. The preferred way to
configure is via `DATABASE_URL`, but individual variables are supported
for flexibility. `DATABASE_URL` always takes priority when set (Rails
auto-merges it over `database.yml` values).

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| DATABASE_URL | Full PostgreSQL connection URI (preferred method) | (none) | `postgres://user:pass@host:5432/sparc_prod` | Yes (if no individual vars) |
| SPARC_DB_HOST | Database host. **Fallback only** — `DATABASE_URL` is preferred and, since #785 Pass 2, derives all four databases (primary + cache/queue/cable). Set the `SPARC_DB_*` block only when not using `DATABASE_URL`. | localhost | `db.example.com` | No |
| SPARC_DB_PORT | Database port | 5432 | `5433` | No |
| SPARC_DB_NAME | Database name | sparc | `sparc_production` | No |
| SPARC_DB_USER | Database username | (none) | `sparc_app` | No |
| SPARC_DB_PASSWORD | Database password (use secrets manager in prod) | (none) | `super-secure-pass-123` | No |
| SPARC_DB_SSLMODE | TLS mode, applied to **all four** databases (primary + cache/queue/cable). `require` refuses plaintext but does NOT authenticate the server; `verify-full` also verifies the certificate chain and hostname and is the FedRAMP High target. See [DATABASE_TLS.md](DATABASE_TLS.md) | **require** (prod), prefer (dev/test) | `verify-full` | No |
| SPARC_SKIP_DB_TLS_CHECK | Suppress the boot-time database TLS posture check (production only). Not recommended — the check warns and never raises | false | `true` | No |
| SPARC_DB_SSLROOTCERT | CA bundle libpq verifies against. Only consulted by the `verify-*` modes. libpq ignores `SSL_CERT_FILE`, so the database needs its own trust anchor | `/etc/pki/sparc/rds-global-bundle.pem` (baked into the image) | `/rails/certs/my-ca.pem` | No |

---

## Authentication

All authentication methods default to **disabled** (whitelist
approach). Enable one or more to activate the login page at `/login`.

### Local Login

<!-- markdownlint-disable MD013 MD034 -->

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_ENABLE_LOCAL_LOGIN | Enable email/password login | false | `true` | No |
| SPARC_ENABLE_EMAIL_CONFIRMATION | Require email confirmation for new local accounts | false | `true` | No |
| SPARC_SESSION_TIMEOUT_MINUTES | Inactivity timeout in minutes | 60 | `30` | No |
| SPARC_PUBLIC_CATALOGS | Make the Controls layer (control catalogs, baselines, mappings) publicly readable — shown in the header nav and reachable without signing in. Off = gated behind authentication (secure-by-default, #726); enable only when SPARC is fronted by your own network auth (e.g. VPN). | false | `true` | No |
| SPARC_ADMIN_EMAIL | Email for the bootstrapped admin account | admin@sparc.local | `admin@yourorg.com` | No |

<!-- markdownlint-enable MD013 MD034 -->

### Admin Credential Rotation (#402, #403)

For ECS Fargate deployments using AWS Secrets Manager. See **[Admin Credential Rotation](ADMIN_CREDENTIAL_ROTATION.md)** for the full setup, testing, and troubleshooting guide.

<!-- markdownlint-disable MD013 MD034 -->

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_ADMIN_PASSWORD | Plaintext admin password injected by ECS from the `admin-credentials` Secrets Manager secret. `bootstrap_admin` reconciles the DB to match on every container start. Never set this manually in development; it's ECS-managed. | (unset) | _(injected by ECS)_ | When using rotation |
| SPARC_ADMIN_REFRESH_ENABLED | Enables `POST /api/v1/admin/refresh_credentials` for Lambda-driven rotation. Defaults to fail-closed (returns 503). Set to `true` only after the rotation Lambda + service-account token are provisioned per [sparc-iac#197](https://github.com/risk-sentinel/sparc-iac/issues/197). | `false` | `true` | No |
| SPARC_ALLOW_CRED_ROTATION | Outside production, the `sparc:rotate_admin_credentials` rake task refuses to run unless this is `1`. Production has no gate. | (unset) | `1` | No |
| SPARC_PRINT_ROTATED_PASSWORD | Break-glass only — when `1`, the rotate-credentials rake task prints the plaintext password to stdout. Be mindful of log retention. Default behavior (unset) tells the operator to retrieve the password from the AWS Console. | (unset) | `1` | No |

<!-- markdownlint-enable MD013 MD034 -->

### API Authentication Mode

Controls which auth method the REST API accepts. Modes are mutually exclusive.

<!-- markdownlint-disable MD013 MD034 -->

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_API_AUTH | API auth mode: `local`, `oidc`, or `hybrid` | local | `hybrid` | No |
| SPARC_API_OIDC_AUDIENCE | Expected `aud` claim in OIDC JWTs | SPARC_OIDC_CLIENT_ID | `sparc-api` | No (only for oidc/hybrid) |

<!-- markdownlint-enable MD013 MD034 -->

**Mode behaviors:**

| Mode | SPARC Tokens | OIDC JWTs | Pipeline Access | Requires |
| --- | --- | --- | --- | --- |
| `local` (default) | All users | Rejected | SPARC token in CI secret | Nothing extra |
| `oidc` | Rejected | All users | Okta client credentials | `SPARC_OIDC_ISSUER_URL` |
| `hybrid` | Service accounts only | All human users | SPARC token for pipelines | `SPARC_OIDC_ISSUER_URL` |

> **Recommended for production:** `hybrid` — humans authenticate via Okta JWT (MFA enforced by IdP), CI/CD pipelines use SPARC tokens tied to service accounts.

### User Registration

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_ENABLE_USER_REGISTRATION | Allow self-service account creation (often false in prod) | false | `true` | No |

### Login Consent Banner (#190)

Show a mandatory consent/warning banner modal before login options
appear. The banner HTML is loaded from the file at
`SPARC_BANNER_MESSAGE` (relative paths resolve against `Rails.root`)
and sanitized for XSS before rendering in a Bootstrap 5 modal. A
sample file is provided at `docs/banners/sample-consent-banner.html`
(see [`docs/banners/`](banners/) for DoD and demo variants).

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_BANNER_ENABLED | Show mandatory consent banner on login page | false | `true` | No |
| SPARC_BANNER_MESSAGE | File path to banner HTML body (resolved against `Rails.root`) | (none) | `docs/banners/sample-consent-banner.html` | Yes (if enabled) |

### Environment / Rules Header (#682)

Show a configurable header bar on **every screen** describing the deployment
environment and its rules of behavior (e.g. `PRODUCTION — Authorized use only`
or `TEST ENVIRONMENT — Do not enter real data`). Default-off: when
`SPARC_HEADER_TEXT` is empty/unset no header renders. The text is displayed as
escaped plain text, so special characters and full UTF-8 (accents, symbols,
emoji) are supported safely. Maps to NIST **AC-8 (System Use Notification)**.

**Colors are operator-defined and contrast is NOT enforced** — the deployment
owns its color choices, so SPARC does not validate WCAG contrast on the values
you supply. (Values *are* validated against a strict hex/`rgb()` grammar to
prevent injection; a malformed value falls back to the default.) **You are
responsible for ensuring readable contrast.** The built-in defaults are
SPARC-brand and pass WCAG AA: `#ffffff` text on `#1f6fa5` highlight = **5.42:1**.

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_HEADER_TEXT | Short environment / rules description shown on all screens. Empty ⇒ header hidden | (none) | `PRODUCTION — Authorized use only` | No |
| SPARC_HEADER_TEXT_COLOR | Header text color (hex `#rgb`/`#rrggbb` or `rgb()`/`rgba()`); invalid ⇒ default | `#ffffff` | `#0b1f2a` | No |
| SPARC_HEADER_HIGHLIGHT_COLOR | Header highlight/background color (hex or `rgb()`/`rgba()`); invalid ⇒ default | `#1f6fa5` | `#8a6d00` | No |

### GitHub OAuth

<!-- markdownlint-disable MD013 -->

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_GITHUB_CLIENT_ID | GitHub OAuth App Client ID (auto-enables GitHub login when set) | (none) | `Iv1.abc123def456` | No |
| SPARC_GITHUB_CLIENT_SECRET | GitHub OAuth App Client Secret | (none) | `1234567890abcdef` | Yes (if GitHub) |

Create an OAuth App at `https://github.com/organizations/YOUR_ORG/settings/applications`. Set the callback URL to `http://localhost:3000/auth/github/callback`.

<!-- markdownlint-enable MD013 -->

### GitLab OAuth

<!-- markdownlint-disable MD013 -->

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_GITLAB_CLIENT_ID | GitLab Application ID (auto-enables GitLab login when set) | (none) | `abc123...` | No |
| SPARC_GITLAB_CLIENT_SECRET | GitLab Application Secret | (none) | `def456...` | Yes (if GitLab) |
| SPARC_GITLAB_SITE | GitLab instance URL (for self-hosted) | `https://gitlab.com` | `https://gitlab.yourorg.com` | No |

Create an application at `https://gitlab.com/-/user_settings/applications`. Set the callback URL to `http://localhost:3000/auth/gitlab/callback` with `read_user` scope.

<!-- markdownlint-enable MD013 -->

### OIDC / OAuth2 (Generic & Provider-Agnostic)

These variables configure OpenID Connect login delegation
(Okta, Entra ID, Keycloak, Auth0, etc.). See `docs/OKTA_DEV_SETUP.md` for
an Okta-specific configuration guide.

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_ENABLE_OIDC | Enable OIDC-based SSO login | false | `true` | No |
| SPARC_FIDO2_ENABLED | Enable FIDO2/WebAuthn security-key sign-in (passwordless; key + PIN = app-native MFA). Adds "Security Keys" enrollment + a "Sign in with a security key" option. (#779) | false | `true` | No |
| SPARC_FIDO2_RP_NAME | WebAuthn relying-party display name shown by the authenticator. **Derives from `SPARC_APP_NAME`** (#785 Pass 2) — set only to override. | `SPARC_APP_NAME` (default `SPARC`) | `Acme SPARC` | No |
| SPARC_FIDO2_RP_ID | WebAuthn RP ID (domain). Defaults to the host of `SPARC_APP_URL`; set only to scope credentials to a parent domain. Must match the browser origin. | (host of SPARC_APP_URL) | `sparc.example.com` | No |
| SPARC_ENABLE_PIV | Enable PIV / CAC smart-card sign-in (cert + PIN). The mTLS + DoD-PKI validation happens at the proxy/ALB (see sparc-iac); SPARC consumes the forwarded validated cert. **Only enable behind a correctly-configured mTLS gateway** that sets the verify header and strips client-supplied copies. (#779) | false | `true` | No |
| SPARC_PIV_CERT_HEADER | Header carrying the forwarded (PEM, possibly URL-encoded) client cert. | X-SSL-Client-Cert | `X-Amzn-Mtls-Clientcert` | No |
| SPARC_PIV_VERIFY_HEADER | Header carrying the gateway's mTLS verification result. SPARC fails closed unless it equals `SPARC_PIV_VERIFY_SUCCESS`. | X-SSL-Client-Verify | `X-SSL-Client-Verify` | No |
| SPARC_PIV_VERIFY_SUCCESS | The success value SPARC requires in the verify header. | SUCCESS | `SUCCESS` | No |
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
| SPARC_LDAP_CA_FILE | PEM CA file used to verify the directory server certificate for `start_tls`/`simple_tls`. Omit to trust the container/system CA store (add a private CA there via the custom-CA trust mechanism). | (none) | `/etc/sparc/ldap-ca.pem` | No |
| SPARC_LDAP_TLS_VERIFY | Verify the directory server's TLS certificate. **Leave `true`.** Setting `false` encrypts but does **not** authenticate the server — vulnerable to an active man-in-the-middle; a warning is logged on every connection. Only for legacy internal directories that cannot present a trusted cert. | true | `false` | No |

---

## User Lifecycle

Controls automatic account deactivation and password expiration
policies. These settings apply to all users unless noted otherwise.

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_INACTIVITY_DAYS | Days of inactivity before an account is auto-deactivated. **Applies to ALL accounts — human and service (#785 Pass 2.1).** | 30 | `90` | No |
| SPARC_PASSWORD_EXPIRY_DAYS | Number of days before a local-auth user's password expires and must be reset. OAuth/SSO-only users are exempt. | 30 | `90` | No |
| SPARC_PROCESSING_STUCK_MINUTES | Minutes after which a document stuck in pending/processing stops auto-refreshing on its show page (#548). Without this guard, documents whose parsing job never ran trap the browser in a 3-second refresh loop. | 5 | `10` | No |

The `InactivityCheckJob` should be scheduled via cron or your job
scheduler (e.g., `rails runner "InactivityCheckJob.perform_now"`).

---

## Dynamic Roles

Configurable role lists for organizations and authorization boundaries.
Comma-separated lists overriding the hardcoded defaults in
`OrganizationMembership::DEFAULT_ROLES` and
`AuthorizationBoundaryMembership::DEFAULT_ROLES`. Useful when a tenant
needs a custom title set (e.g., agency-specific role names).

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_ORGANIZATION_ROLES | Comma-separated list of role names available to organization members (in addition to the always-present "Org Admin" system role) | Head of Agency, Senior Accountable Official, CIO, CISO, Risk Executive, Chief Acquisition Officer, Senior Agency Official for Privacy, Member | `Director, Officer, Member` | No |
| SPARC_AUTH_BOUNDARY_ROLES | Comma-separated list of role names available to authorization-boundary members | Assessor / 3PAO, Authorizing Official (AO), CISO, ISSO, Team Member, System Owner (SO), View Only | `Assessor, AO, ISSO, Owner, Viewer` | No |
| SPARC_ENVIRONMENTS_LIST | Selectable deployment environments for boundaries, as comma-separated `Name:CODE` pairs. A missing `:CODE` defaults to the name. The stored value is the name slug, so the legacy set (production/development/staging/test) round-trips (#770) | Development (DEV), Test (TEST), Staging (STAG), User Acceptance Testing (UAT), Quality Assurance (QA), Production (PROD) | `Sandbox:SBX, Production:PROD` | No |

> Set these BEFORE inviting members — existing role assignments are not
> automatically migrated to a new role list. Removing a role name that
> users already hold leaves them with the removed-role label until an
> admin reassigns them.

---

## Organization Metadata (OSCAL Exports)

Default values embedded in OSCAL document metadata (SSP, SAR, CDEF,
etc.) when the system generates an export. Each field is optional —
exports omit empty values rather than write blanks.

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_ORG_NAME | Organization name embedded in OSCAL metadata | Default Organization | `ACME Federal Services` | No |
| SPARC_ORG_DESCRIPTION | Organization description embedded in OSCAL metadata | (none) | `Cloud compliance platform for civilian agencies` | No |
| SPARC_ORG_ADDRESS | Organization address embedded in OSCAL metadata | (none) | `1600 Pennsylvania Ave NW, Washington, DC 20500` | No |
| SPARC_ORG_CONTACT_PERSON | Primary contact person embedded in OSCAL metadata | (none) | `Jane Doe` | No |
| SPARC_ORG_CONTACT_EMAIL | Primary contact email embedded in OSCAL metadata | (none) | `compliance@acme.gov` | No |

---

## Deprecations (v1.13.1)

| Variable | Status | Do this instead |
|---|---|---|
| `SPARC_ORG_CONTACT_EMAIL` | **Deprecated alias** — still honoured | Use `SPARC_CONTACT_EMAIL`. SPARC has two email identities: `SPARC_ADMIN_EMAIL` (the administrator account) and `SPARC_CONTACT_EMAIL` (support). When unset, the org contact falls back to the support address |
| `SPARC_AWS_REGION` | Redundant in every known deployment | Use `AWS_REGION`. The accessor already falls back `SPARC_AWS_REGION` → `AWS_REGION` → `us-east-1`, and only a split-region deployment could tell the difference |
| `RAILS_SERVE_STATIC_FILES` | **Not implemented** | Put a reverse proxy or CDN in front of SPARC |
| `HTTP_PORT` | **Not read** | Use `PORT` |

---

## DISA CCI Catalog Retrieval

Controls the source URL and revision set used when SPARC fetches the
DISA CCI (Control Correlation Identifier) list for NIST 800-53 mapping.
Override the URL for air-gapped or mirror environments.

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_DISA_CCI_URL | Source URL for the DISA CCI list ZIP | `https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_CCI_List.zip` | `https://mirror.internal/U_CCI_List.zip` | No |
| SPARC_CCI_REVS | Comma-separated NIST 800-53 revisions to extract from the CCI list | `4,5` | `5` (Rev 5 only) or `4,5,6` (when Rev 6 publishes) | No |

---

## General Application & Logging

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_APP_URL | Base public URL of the application (used in emails, links, redirects) | `http://localhost:3000` | `https://sparc.example.com` | Yes (prod) |
| SPARC_APP_NAME | Human-readable name of the platform | SPARC | `SPARC Compliance Platform` | No |
| SPARC_WELCOME_TEXT | Message displayed on the login page | Welcome to SPARC | `Welcome to ACME Compliance` | No |
| SPARC_CONTACT_EMAIL | Support/admin email shown in UI and login page | (none) | `compliance-team@yourorg.com` | No |
| SPARC_RESOURCES | JSON array of external resource links for Resources page | FedRAMP 20x, NIST OSCAL, MITRE SAF defaults | `'[{"display_text":"Custom","href":"https://example.com"}]'` | No |
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
| SPARC_STORAGE_URL | **Preferred (#785 Pass 2.1).** One variable for object storage; the scheme picks the provider. `s3://bucket` (region from `AWS_REGION`), `s3://bucket?region=us-east-1`, or unset → local disk. Collapses `ACTIVE_STORAGE_SERVICE` + `AWS_BUCKET`. See [OBJECT_STORAGE.md](OBJECT_STORAGE.md). | (unset → local) | `s3://sparc-uploads?region=us-east-1` | No (but see next row) |
| SPARC_ALLOW_LOCAL_STORAGE | Acknowledge running on **local disk in production**. Production hard-fails at boot on local disk (ECS/EKS ephemeral-FS data-loss guard); set `true` only for single-node / mounted-volume deployments that really use durable local storage. | false | `true` | No |
| ACTIVE_STORAGE_SERVICE | **Legacy fallback** — used only when `SPARC_STORAGE_URL` is unset. Active Storage backend (local or amazon). | local | `amazon` | No |
| AWS_ACCESS_KEY_ID | AWS access key for S3 storage | (none) | `AKIA...` | Yes (if amazon) |
| AWS_SECRET_ACCESS_KEY | AWS secret key for S3 storage | (none) | `wJalr...` | Yes (if amazon) |
| AWS_REGION | AWS region for S3 bucket | (none) | `us-east-1` | Yes (if amazon) |
| AWS_BUCKET | **Legacy fallback** for `SPARC_STORAGE_URL`. S3 bucket name for file uploads. | (none) | `sparc-uploads` | Yes (if amazon and no SPARC_STORAGE_URL) |
| SPARC_PERSIST_S3_BLOB | Keep the original upload blob after a successful parse. **As of #680 the blob is RETAINED by default** so a referenced artifact never disappears out from under an exported document (durable back-matter). Set to `false` to restore the old purge-after-parse behavior (#392). Failed parses always retain the blob regardless. | true (retain) | `false` | No |

---

## Upload Limits (#510)

<!-- markdownlint-disable MD013 -->

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_MAX_UPLOAD_MB | Maximum allowed upload size in **megabytes** for every document type (SSP, SAR, SAP, POAM, CDEF, Profile, Evidence). Also caps the uncompressed total of zip-based formats as a zip-bomb defense. SparcConfig converts to bytes internally. Teams needing larger payloads raise this single global cap. | `50` | `100` | No |
| SPARC_MAX_AVATAR_MB | Maximum allowed user-avatar upload size in **megabytes**. Separate from document uploads so avatars never compete with document payload caps. | `2` | `5` | No |

<!-- markdownlint-enable MD013 -->

### Reverse-proxy alignment

Set the reverse-proxy body cap (nginx / ALB / etc.) to `SPARC_MAX_UPLOAD_MB + ~10 MB` headroom so the proxy is the fail-fast outer layer:

```nginx
# nginx — when SPARC_MAX_UPLOAD_MB=50
client_max_body_size 60m;
```

The app-level `AttachmentSizeLimit` validator and the `FileUploadable` zip-bomb check provide the strict upper bound; the proxy cap rejects oversized requests before they reach Puma.

---

## Cookieless User-Data Subdomain (#515)

<!-- markdownlint-disable MD013 -->

User-uploaded blobs (SSP/SAR/CDEF/POAM JSON/XML/YAML, evidence) are served from a separate cookieless hostname. Even if a future code change accidentally sets `disposition: "inline"` on a user-uploaded HTML or SVG file, the browser script lives on the `userdata.*` origin and cannot read the SPARC session cookie (which is host-only on the main app hostname — Rails default, NOT explicitly `Domain=`-scoped).

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_USERDATA_HOST | Override hostname for serving ActiveStorage blobs. When unset, derived as `userdata.<host>` from `SPARC_APP_URL`. Most operators don't need to set this; only relevant for per-tenant subdomain patterns, on-prem split DNS, etc. | (derived) | `userdata.sparc.risk-sentinel.org` | No |

<!-- markdownlint-enable MD013 -->

### How the cookieless protection works

1. User logs in at `https://sparc.risk-sentinel.org/` — session cookie is set **without** a `Domain=` attribute (Rails default), so the browser treats it as **host-only** and never sends it to subdomains.
2. User uploads a file — ActiveStorage stores the blob (S3 or local disk).
3. App generates a download link — URL is `https://userdata.sparc.risk-sentinel.org/rails/active_storage/blobs/<signed-id>/...` (configured via `config.active_storage.url_options` in production).
4. Browser fetches the blob — sends NO session cookie (different exact-match host).
5. Even a malicious HTML/SVG that somehow rendered inline cannot exfiltrate the SPARC session.

### Don't `Domain=`-scope the session cookie

`config/initializers/session_store.rb` documents the constraint explicitly. Setting `domain: "sparc.risk-sentinel.org"` would cause the cookie to be sent to ANY subdomain (per RFC 6265 §5.1.3) — defeating the whole protection. The host-only default is correct; leave it alone.

### sparc-iac coordination

Requires DNS / ALB rule / TLS cert for the `userdata.*` hostname — covered by **sparc-iac issue #269**. SPARC's app-side change ships independently but does nothing useful until the iac side lands.

---

## Rate Limiting (#513)

<!-- markdownlint-disable MD013 -->

Rack::Attack throttle thresholds. Counters live in `Rails.cache` (`solid_cache` in production, in-memory in development, disabled in test). Defaults are conservative — tighten for high-security tenants by setting the env vars below. Throttle hits emit a `[rack-attack] THROTTLED` log line (ingested by CloudWatch in prod) and return HTTP `429` with `Retry-After` + a JSON body that names the offending bucket.

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| ~~SPARC_RATE_LIMITING_ENABLED~~ | **Removed (#785 Pass 2.1)** — rate limiting is now unconditional (best practice). The per-limit `SPARC_RATE_LIMIT_*` tuning knobs remain. | — | — | — |
| SPARC_RATE_LIMIT_UPLOADS_PER_5MIN_PER_IP | Per-IP cap on upload endpoints (document creates + avatar + evidence). Defends against bulk-upload abuse. | `30` | `60` | No |
| SPARC_RATE_LIMIT_UPLOADS_PER_HOUR_PER_USER | Per-authenticated-user cap on upload endpoints. Stops a compromised account from filling storage. | `100` | `500` | No |
| SPARC_RATE_LIMIT_API_WRITES_PER_MINUTE | Per-Bearer-token cap on `/api/v1` write methods (POST/PUT/PATCH/DELETE). Protects mass-import API consumers from runaway scripts. | `300` | `600` | No |
| SPARC_RATE_LIMIT_LOGIN_FAILURES_PER_MIN | Per-IP cap on `POST /login` + `/auth/failure` within 1 minute. Credential-stuffing defense. | `5` | `3` | No |
| SPARC_RATE_LIMIT_SAFELIST_CIDRS | Comma-separated CIDR list. IPs in any listed CIDR bypass ALL throttles. Used for internal health-check IPs, NLB targets, etc. Loopback addresses safelisted by default for dev convenience. | `127.0.0.1,::1` | `127.0.0.1,::1,10.0.0.0/8` | No |

<!-- markdownlint-enable MD013 -->

### Throttle buckets

| Bucket | Discriminator | Window | Default limit |
|---|---|---|---|
| `uploads/5min/ip` | client IP | 5 minutes | 30 |
| `uploads/hour/user` | authenticated user id | 1 hour | 100 |
| `api/writes/min/token` | Bearer token (first 12 chars) | 1 minute | 300 |
| `logins/failures/min/ip` | client IP | 1 minute | 5 |

### 429 response shape

```json
{
  "error": "Too many requests",
  "code": "rate_limit_exceeded",
  "bucket": "uploads/5min/ip",
  "retry_after": 300
}
```

Plus headers: `Retry-After: <seconds>` and `X-RateLimit-Bucket: <bucket-name>`.

---

## Development HTTPS

<!-- markdownlint-disable MD013 -->

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SSL_DEV | Enable HTTPS in development with mkcert certificates | false | `true` | No |
| SSL_PORT | Port for HTTPS binding in development | 3443 | `3443` | No |

<!-- markdownlint-enable MD013 -->

Run `bin/setup-ssl` to generate certificates before enabling.
See `docs/development-https.md` for full setup guide.

---

## Redis & Background Jobs

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| REDIS_URL | Redis connection URL for Sidekiq | `redis://localhost:6379/0` | `redis://redis:6379/0` | Yes |
| SOLID_QUEUE_IN_PUMA | Run Solid Queue in-process with Puma (single-server deploys) | (unset) | `true` | No |
| JOB_CONCURRENCY | Number of Solid Queue worker processes | 1 | `3` | No |

---

## Service Account Lifecycle

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| ~~SPARC_SA_INACTIVITY_DAYS~~ | **Retired (#785 Pass 2.1)** — service accounts now use the same window as human accounts (`SPARC_INACTIVITY_DAYS`, default 30), aligning expiration regardless of owner. Note: the SA window was 90 days; it is now 30. | — | use `SPARC_INACTIVITY_DAYS` | — |

The `ServiceAccountMaintenanceJob` runs daily (3 AM, production) and auto-disables service accounts with all-expired tokens or exceeding the inactivity threshold. Disabled accounts can be re-enabled by an admin.

---

## Docker / Seed Control

| Variable | Description | Default | Example | Required |
|----------|-------------|---------|---------|----------|
| SPARC_RUN_SEEDS | Explicitly run `db:seed` on container start (for non-web containers) | false | `true` | No |
| SPARC_SEED_MODE | Controls which sample data is seeded | full | `traditional`, `20x`, `full` | No |

The web container automatically runs `db:prepare` (which includes seeding) on startup. Use `SPARC_RUN_SEEDS=true` for Sidekiq or one-shot ECS tasks that need seed data without running the Rails server.

Converter mappings (DISA CCI, CIS, SCAP/OVAL) are seeded from `lib/data_mappings/*.json` fixtures.

---

## AWS Secrets Manager (ECS/EC2 Deployments)

Two-secret strategy aligned with [sparc-iac #22](https://github.com/risk-sentinel/sparc-iac/issues/22):

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_AWS_SECRETS_ENABLED | Enable Secrets Manager JSON blob injection at boot | `false` | `true` | No |
| SPARC_APP_CONFIG_SECRET_ARN | ARN of the app-config JSON secret (all non-admin config) | (unset) | `arn:aws:secretsmanager:us-east-1:123:secret:sparc-prod/app-config` | When secrets enabled |
| SPARC_ADMIN_CREDENTIALS_SECRET_ARN | ARN of admin-credentials secret. ECS injects the `password` field as `SPARC_ADMIN_PASSWORD` at task start; the `sparc:rotate_admin_credentials` rake task writes back via `PutSecretValue`. SPARC's task role does NOT have `GetSecretValue` on this secret — ECS does the read on SPARC's behalf, preserving MFA-gated Console retrieval for break-glass. | (unset) | `arn:aws:secretsmanager:us-east-1:123:secret:sparc-prod/admin-credentials` | When using rotation |

### How It Works

When `SPARC_AWS_SECRETS_ENABLED=true`, the `00_aws_secrets.rb` initializer:
1. Reads the JSON blob from `SPARC_APP_CONFIG_SECRET_ARN`
2. Parses each key-value pair and injects into `ENV`
3. **Never overwrites** existing ENV vars (manual ENV takes precedence)
4. Fails fast with a clear error if the ARN is invalid or inaccessible

### Secret JSON Format

```json
{
  "SECRET_KEY_BASE": "a1b2c3...",
  "SPARC_OIDC_CLIENT_SECRET": "okta-secret",
  "SPARC_SMTP_PASSWORD": "ses-password",
  "REDIS_URL": "redis://redis.internal:6379/0"
}
```

---

## AWS IAM Database Authentication

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_AWS_IAM_DB_AUTH | Use IAM auth tokens instead of static DB passwords | `false` | `true` | No |
| SPARC_AWS_REGION | **Deprecated alias for `AWS_REGION`** (#785 Pass 2). Kept working so existing configs don't break; prefer `AWS_REGION`. Only differs from `AWS_REGION` in the theoretical split-region case (SPARC's SDK clients in a different region than the S3 bucket), which nothing needs | `AWS_REGION` or `us-east-1` | — | No — use `AWS_REGION` |

### Prerequisites

- RDS instance with `iam_database_authentication_enabled = true`
- ECS task role with `rds-db:connect` permission
- DB user created with `GRANT rds_iam TO sparc;`

IAM auth tokens are 15-minute auto-rotating credentials — no static DB password needed.

---

## AWS Labs CDEF Fetch (#466)

Runtime ingestion of OSCAL Component Definitions from
[`awslabs/oscal-content-for-aws-services`](https://github.com/awslabs/oscal-content-for-aws-services).
Imported CDEFs land in the `cdef_documents` table with
`import_metadata.source_type = "aws_labs"` and are read-only — users click
"Copy for editing" to amend. Refreshes never touch clones.

License compliance: top-level `NOTICE`, verbatim upstream LICENSE at
`LICENSES/AWS-LABS-OSCAL-CONTENT-LICENSE`, and source registry at
`docs/compliance/THIRD_PARTY_NOTICES.md` (Apache 2.0 inheritance).

| Variable | Description | Default | Example | Required? |
| --- | --- | --- | --- | --- |
| SPARC_AWS_LABS_CDEF_ENABLED | Master switch. Off by default so air-gapped tenants are unaffected. | `false` | `true` | No |
| SPARC_AWS_LABS_CDEF_REPO | Override source repo (e.g. internal fork or mirror) | `awslabs/oscal-content-for-aws-services` | `acme-corp/oscal-content-mirror` | No |
| SPARC_AWS_LABS_CDEF_BRANCH | Pin to a tag or branch for reproducibility | `main` | `v2026.05` | No |
| SPARC_AWS_LABS_OSCAL_VERSIONS | CSV of OSCAL spec versions to ingest. When unset, defaults to whatever versions SPARC's loaded `OscalSchema` rows already cover. | (auto-detect) | `1.1.2,1.0.4` | No |
| SPARC_AWS_LABS_CDEF_REFRESH_INTERVAL_DAYS | How often the recurring job runs. AWS Labs content changes on the order of weeks; weekly default keeps audit logs quiet. Clamped to 1..90. | `7` | `30` | No |
| SPARC_AWS_LABS_GITHUB_TOKEN | Optional PAT (GitHub fine-grained token with `contents:read` is enough). Raises rate limit from 60→5000 req/hr. | (unset) | `github_pat_…` | When refreshing frequently |

### How It Works

1. Solid Queue's `AwsLabsCdefRefreshJob` runs every
   `SPARC_AWS_LABS_CDEF_REFRESH_INTERVAL_DAYS` days at 06:00 UTC (configured
   via ERB in `config/recurring.yml`).
2. The job is a no-op when `SPARC_AWS_LABS_CDEF_ENABLED=false`, so it's
   safe to schedule in every environment.
3. When enabled, the service enumerates `component-definitions/**/*.json`
   via the GitHub Trees API with ETag-conditional fetches — the
   steady-state daily/weekly tick is near-free when nothing has changed.
4. For each new or updated file, the highest `metadata.version` per
   (service directory, oscal-version) is kept; lower versions are
   discarded.
5. Records carry `import_metadata.source_url`, `source_sha`,
   `source_commit_sha`, and `fetched_at` for full audit-trail provenance.

### Manual Trigger

```bash
bin/rails aws_labs:cdefs:import          # respects ETag cache
bin/rails 'aws_labs:cdefs:import[true]'  # force re-fetch ignoring ETag
```

### Disabling

Set `SPARC_AWS_LABS_CDEF_ENABLED=false` (the default). Previously-imported
rows remain in the database; the recurring job becomes a no-op.
