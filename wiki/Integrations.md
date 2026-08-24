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

#### Asking the IdP for more than the default scopes

`SPARC_OIDC_SCOPES` defaults to `"openid profile email"` — enough to sign a
person in and know who they are, and nothing more. Anything else you want in the
token has to be requested here **and** released by the IdP; the two halves are
configured in different places and both are required, which is the usual reason
a claim "isn't arriving".

```bash
SPARC_OIDC_SCOPES="openid profile email groups"
```

**Setting the scope alone is not enough.** A scope is a request; the IdP decides
what it actually puts in the token. In Okta, for example, group membership is
not released by default — an administrator adds a claim on the application
(**Applications → your app → Sign On → OpenID Connect ID Token**) or on the
authorization server (**Security → API → Authorization Servers → Claims**),
choosing a value type of *Groups* and a filter.

**Use a filter.** Without one the IdP sends every group the person belongs to,
which on a real directory is hundreds of unrelated names. A regex filter such as
`^sparc:` keeps the token to the groups that concern SPARC. The same reasoning
applies to any provider: release the narrowest claim that answers the question.

**Verifying what actually arrived.** Sign in and check the identity record for
the user under **Administration → Users → *the user***; SPARC stores the
provider response on `Identity#auth_data`. That is the authoritative answer to
"did the claim arrive", and it is faster than reading an IdP log.

Order of operations, so a mistake is cheap:

1. Confirm plain sign-in works **before** adding scopes. If it breaks after,
   you know which change did it.
2. Add the claim at the IdP, with a filter.
3. Add the scope to `SPARC_OIDC_SCOPES` and restart.
4. Sign in and confirm the claim arrived.

> **Adding a scope the IdP does not recognise can break sign-in outright** —
> some providers reject the whole authorization request rather than ignoring the
> unknown scope. Change this in a test environment first. This is also why SPARC
> does not add scopes to the default on your behalf when new features need them:
> your login page is not a safe place for us to make assumptions.

#### Group-based entitlements: letting the IdP decide who holds which role

SPARC can read role grants from a claim, so membership is managed where your
people already are. Roles keep their meaning in SPARC — the IdP never learns
what a role can *do*, only who holds it and where.

**Off by default.** Set `SPARC_OIDC_SYNC_MODE` to enable it.

##### The grant format

A grant is a group name:

```
sparc:instance:{role}
sparc:org:{org_slug}:{role}
sparc:boundary:{org_slug}:{boundary_slug}:{role}
```

> **Use the SLUG, not the display name.** This is the single most common
> mistake. A boundary named `Café & Co — Prod` has the slug `cafe-co-prod`:
> SPARC lowercases, strips accents and punctuation, and joins words with
> hyphens. The slug is what appears in the boundary's own URL
> (`/authorization_boundaries/cafe-co-prod`), so read it there if in doubt.
> Grants are matched case-insensitively, but the slug itself must be exact.

##### The modes

| Mode | What a login does |
| --- | --- |
| `off` *(default)* | Nothing. Roles are managed entirely in SPARC |
| `bootstrap` | **Adds** grants. Never removes anything |
| `authoritative` | Adds grants, and removes ones the claim no longer carries |

Adopt in that order. `off` → `bootstrap` → `authoritative` is a ladder;
`off` → `authoritative` is a cliff.

##### What SPARC will not do

- **It never creates an organization, boundary or role.** A grant naming
  something that does not exist is recorded and surfaced, never provisioned —
  otherwise your directory could define your estate. The user still signs in,
  holding whatever access *did* resolve.
- **It never removes a role an administrator granted.** Revocation is limited to
  memberships the sync itself created, so an in-app grant survives any claim,
  any misconfiguration, and any empty group.
- **It never grants instance admin.** Instance Admin is not a role, so no claim
  can confer it — which is what keeps a break-glass recovery path open no matter
  what your directory says.
- **A MISSING claim is an error, not "revoke everything."** If the claim name is
  wrong or the scope was not released, SPARC changes nothing and records why.
  Only an *empty* claim means "this person has no grants."

##### Instance-wide roles

Off unless you name them explicitly:

```bash
SPARC_OIDC_INSTANCE_ROLES="global_viewer,policy_manager"
```

An allowlist per role, not a switch — opting in to `global_viewer` does not
confer `head_of_agency`.

##### When a grant names something that does not exist

Look under **Administration → IdP Grants**. Administrators also get a daily
digest by email when SMTP is configured.

**Nothing there needs clearing.** Create the missing organization or boundary and
the grant resolves by itself at that user's next sign-in.

##### Configuration reference

| Variable | Default | Purpose |
| --- | --- | --- |
| `SPARC_OIDC_SYNC_MODE` | `off` | `off` / `bootstrap` / `authoritative` |
| `SPARC_OIDC_GRANTS_CLAIM` | `groups` | Which claim carries grants |
| `SPARC_OIDC_GRANTS_PREFIX` | `sparc:` | Only values with this prefix are read |
| `SPARC_OIDC_INSTANCE_ROLES` | *(empty)* | Instance roles the IdP may grant |
| `SPARC_USER_INACTIVITY_DAYS` | `0` | Deactivate accounts idle this long. **This is offboarding** — a disabled IdP account cannot sign in |

##### Offboarding

SPARC is not told when your IdP disables someone. It does not need to be: a
disabled account cannot authenticate, so `SPARC_USER_INACTIVITY_DAYS` covers a
leaver, a revoked IdP account and a dormant local login with one rule. Removing
someone from a group takes effect at their next sign-in, and
`SPARC_SESSION_MAX_HOURS` bounds how long their current session can outlive that.

Tracked as [#860](https://github.com/risk-sentinel/sparc/issues/860).

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

### AWS (Production) — managed by `sparc-iac`

Production deployment is **not** defined in this repository. It lives in the
separate **[`sparc-iac`](https://github.com/risk-sentinel/sparc-iac)** repo,
which provisions the AWS infrastructure as Terraform and deploys the
container image published by this repo's CI:

- **AWS ECS** behind an Application Load Balancer, running the signed SPARC container image.
- Database credentials and the `SPARC_HASH` master secret sourced from **AWS Secrets Manager** (`SPARC_AWS_SECRETS_ENABLED`), with optional **IAM database authentication** (`SPARC_AWS_IAM_DB_AUTH`).
- Active Storage backed by **Amazon S3** (`ACTIVE_STORAGE_SERVICE=amazon`).
- The application consumes the compliance evidence bundle (`sparc-compliance-latest`) published by this repo's `security.yml` workflow.

> The SPARC application image is built and signed by the **`container-build-sign`**
> repo; `sparc-iac` consumes that signed image. See the
> [repo layout](#repository-layout) note below.

### Repository layout

| Repo | Responsibility |
|------|----------------|
| `sparc` | The Rails application (this repo) |
| `sparc-iac` | AWS deployment infrastructure (Terraform, ECS) |
| `container-build-sign` | Base image build + image signing |
| `sparc-validate` | External validation harness |

---

## OSCAL Ecosystem

### Standards Support

- NIST OSCAL schema compliance — **1.2.2** as of v1.16.0
- 8 OSCAL model types supported: catalog, profile, component-definition, SSP, assessment-plan, assessment-results, POA&M, mapping

### Import Formats

| Format | Source | Notes |
|--------|--------|-------|
| OSCAL JSON | Any OSCAL-compliant tool | Native format |
| SCAP XML | NIST feed v2.0 | Automated vulnerability data |
| XCCDF | DISA STIG | Security Technical Implementation Guides |

### Export Formats

| Format | Validation | Notes |
|--------|------------|-------|
| OSCAL JSON | Validated against official NIST schemas | Primary export |
| JSON | N/A | Simplified internal format |

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
