# Integrations

## Authentication Providers

### Local Email/Password (`SPARC_ENABLE_LOCAL_LOGIN=true`)

- Uses bcrypt with `has_secure_password`
- 12-character minimum password length (NIST SP 800-63B compliant)
- Auto-creates admin account on first `db:seed` with a random password and `must_reset_password` flag
- Session fixation prevention via `reset_session` before storing `user_id`
- Email normalization: downcased and stripped of whitespace
- Related: [PR #73](https://github.com/risk-sentinel/sparc/pull/73) ([Issue #70](https://github.com/risk-sentinel/sparc/issues/70)), [PR #105](https://github.com/risk-sentinel/sparc/pull/105) ([Issue #91](https://github.com/risk-sentinel/sparc/issues/91))

### GitHub OAuth (`SPARC_GITHUB_CLIENT_ID` set)

- Auto-enabled when the GitHub client ID environment variable is present
- OAuth scope: `user:email`
- Creates an `Identity` record with `provider="github"`
- Related: [PR #73](https://github.com/risk-sentinel/sparc/pull/73)

### GitLab OAuth (`SPARC_GITLAB_CLIENT_ID` set)

- Supports self-hosted GitLab instances via `SPARC_GITLAB_SITE`
- Creates an `Identity` record with `provider="gitlab"`

### OIDC / SSO (`SPARC_ENABLE_OIDC=true`)

- OpenID Connect auto-discovery via `.well-known/openid-configuration`
- Compatible with: Okta, Keycloak, Entra ID, Auth0, and other OIDC-compliant providers
- Custom scopes via `SPARC_OIDC_SCOPES` (default: `"openid profile email"`)
- Button text via `SPARC_OIDC_PROVIDER_TITLE` (default: `"SSO"`)
- MFA enforcement via `SPARC_OIDC_FORCE_MFA` (validates ACR/amr claims)
- Related: [Issue #33](https://github.com/risk-sentinel/sparc/issues/33) (Okta), [Issue #35](https://github.com/risk-sentinel/sparc/issues/35) (generic OIDC)

### LDAP (`SPARC_ENABLE_LDAP=true`)

- `LdapAuthService` implements bind-and-search pattern:
  1. Service account bind
  2. User lookup by attribute (default: `uid`)
  3. User bind with supplied password
- Auto-creates a SPARC user from LDAP attributes on first login
- Supports `simple_tls`, `start_tls`, or plain (unencrypted) connections
- Related: [PR #73](https://github.com/risk-sentinel/sparc/pull/73)

### Session Management

| Setting | Default | Description |
|---------|---------|-------------|
| `SPARC_SESSION_TIMEOUT_MINUTES` | 60 | Idle timeout before session expiry |

- Session fixation prevention on every login
- Sign-in tracking: count, last IP address, last timestamp

---

## Deployment Patterns

### Docker Compose (Development)

- **PostgreSQL 15** on port 5433 (offset to avoid conflicts with local Postgres)
- **Redis 7** on port 6380 (offset to avoid conflicts with local Redis)
- **Web service** on port 3000 with auto `db:prepare` + `db:seed`
- **Sidekiq worker** for async document processing
- Volumes: project root (bind mount), `bundle_cache`, `storage_data`

### Docker Compose (Production)

- Stripped-down configuration: no build context, minimal volumes
- Web served via Thrust reverse proxy (maps port 3000 to 80)
- All configuration via environment variables
- Active Storage: local disk or Amazon S3

### Dockerfile

- Multi-stage build: `base` (ruby:3.4.4-slim) -> `build` -> `final`
- Non-root `rails` user (uid 1000) for security
- System dependencies: jemalloc (memory allocator), libvips (image processing), pg-client
- Precompiled assets in the build stage, copied to final image

### AWS ECS Fargate ([Issue #109](https://github.com/risk-sentinel/sparc/issues/109) -- planned)

- Terraform infrastructure as code
- ALB + ECS services for containerized deployment

### AWS EC2 ([Issue #110](https://github.com/risk-sentinel/sparc/issues/110) -- planned)

- Terraform with ALB + Auto Scaling Group

### Azure VM ([Issue #111](https://github.com/risk-sentinel/sparc/issues/111) -- planned)

- Terraform with Application Gateway

---

## OSCAL Ecosystem

### Standards Support

- NIST OSCAL v1.1.2 schema compliance
- 8 OSCAL model types supported: catalog, profile, component-definition, SSP, assessment-plan, assessment-results, POA&M, mapping

### Import Formats

| Format | Source | Notes |
|--------|--------|-------|
| OSCAL JSON | Any OSCAL-compliant tool | Native format |
| SCAP XML | NIST feed v2.0 | Automated vulnerability data |
| XCCDF | DISA STIG | Security Technical Implementation Guides |
| Excel | Manual spreadsheets | Legacy migration path |

### Export Formats

| Format | Validation | Notes |
|--------|------------|-------|
| OSCAL JSON | Validated against official NIST schemas | Primary export |
| JSON | N/A | Simplified internal format |
| Excel | N/A | SAR round-trip support |

### External Dependencies

- Source catalogs from [usnistgov/oscal-content](https://github.com/usnistgov/oscal-content)
- Schema validation via the `json_schemer` gem

---

## Active Storage

- **Development**: local disk storage
- **Production**: Amazon S3 (configured via `ACTIVE_STORAGE_SERVICE=amazon`)
- Used for: document file uploads, evidence files, user avatars

---

## Background Jobs

- **Sidekiq + Redis** for async document processing
- `DocumentConversionJob` handles all 6 document types via `DocumentTypeRegistry`
- Redis URL configurable via `REDIS_URL`

---

## Email / SMTP

Optional SMTP integration for notifications, enabled via `SPARC_ENABLE_SMTP=true`.

| Setting | Default | Description |
|---------|---------|-------------|
| `SPARC_SMTP_ADDRESS` | -- | SMTP server hostname |
| `SPARC_SMTP_PORT` | 587 | SMTP port |
| `SPARC_SMTP_AUTH` | plain | Authentication method (plain/login/cram_md5) |
| `SPARC_SMTP_STARTTLS` | -- | Enable STARTTLS |
| `SPARC_SMTP_FROM_ADDRESS` | -- | Default "From" address |
