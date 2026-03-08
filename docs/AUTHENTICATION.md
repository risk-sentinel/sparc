# Authentication & Authorization

SPARC supports multiple authentication methods, all opt-in via environment variables. When no `SPARC_ENABLE_*` variables are set, all routes remain fully public (backward compatible).

---

## Quick Start — Local Login

The fastest path to enable authentication:

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Enable local login and registration:
   ```
   SPARC_ENABLE_LOCAL_LOGIN=true
   SPARC_ENABLE_USER_REGISTRATION=true
   ```

3. Seed the database (creates admin account + RMF roles):
   ```bash
   bin/rails db:seed
   ```
   The admin credentials are printed to the console. Save them — the password is auto-generated.

4. Start the server and log in at `/login`. The bootstrapped admin must change their password on first login.

### Regenerating Admin Credentials

If you lose the admin password, regenerate it:

```bash
bin/rails sparc:bootstrap_admin
```

This resets the password and prints new credentials.

---

## Admin Bootstrap

When `SPARC_ENABLE_LOCAL_LOGIN=true` and `SPARC_ADMIN_EMAIL` is set (defaults to `admin@sparc.local`), running `rails db:seed` automatically:

1. Creates 9 RMF roles (Policy Manager, Global Viewer, AO, SO/ISO, CISO, ISSO, Project Member, Assessor/3PAO, View Only)
2. Creates an admin user with a random 16-character password
3. Sets `must_reset_password: true` — admin is forced to change password on first login
4. Prints credentials to console output

The admin account has the `admin` flag set (not a role), granting access to the admin UI at `/admin/users`.

---

## Authentication Methods

### Local Email/Password

| Variable | Description | Default |
|----------|-------------|---------|
| `SPARC_ENABLE_LOCAL_LOGIN` | Enable email/password login | `false` |
| `SPARC_ENABLE_USER_REGISTRATION` | Allow self-service account creation | `false` |
| `SPARC_SESSION_TIMEOUT_MINUTES` | Inactivity timeout in minutes | `60` |
| `SPARC_ADMIN_EMAIL` | Email for bootstrapped admin account | `admin@sparc.local` |

Password policy follows NIST 800-63B: 12-character minimum, no complexity rules.

### GitHub OAuth

Set the Client ID to auto-enable the GitHub login button:

| Variable | Description |
|----------|-------------|
| `SPARC_GITHUB_CLIENT_ID` | GitHub OAuth App Client ID |
| `SPARC_GITHUB_CLIENT_SECRET` | GitHub OAuth App Client Secret |

Create an OAuth App at `https://github.com/organizations/YOUR_ORG/settings/applications`.
Set the callback URL to `http://localhost:3000/auth/github/callback`.

### GitLab OAuth

| Variable | Description | Default |
|----------|-------------|---------|
| `SPARC_GITLAB_CLIENT_ID` | GitLab Application ID | (none) |
| `SPARC_GITLAB_CLIENT_SECRET` | GitLab Application Secret | (none) |
| `SPARC_GITLAB_SITE` | GitLab instance URL | `https://gitlab.com` |

Create an application at `https://gitlab.com/-/user_settings/applications`.
Callback URL: `http://localhost:3000/auth/gitlab/callback`. Scope: `read_user`.

### OIDC / SSO (Okta, Keycloak, Entra ID)

| Variable | Description | Default |
|----------|-------------|---------|
| `SPARC_ENABLE_OIDC` | Enable OIDC-based SSO login | `false` |
| `SPARC_OIDC_ISSUER_URL` | OIDC Issuer URL (auto-discovery) | (none) |
| `SPARC_OIDC_CLIENT_ID` | Client ID from your IdP | (none) |
| `SPARC_OIDC_CLIENT_SECRET` | Client Secret from your IdP | (none) |
| `SPARC_OIDC_REDIRECT_URI` | Callback URL (must match IdP config) | auto |
| `SPARC_OIDC_SCOPES` | Space-separated OIDC scopes | `openid profile email` |
| `SPARC_OIDC_PROVIDER_TITLE` | Display name on login button | `SSO` |

See [OKTA_DEV_SETUP.md](OKTA_DEV_SETUP.md) for a step-by-step Okta configuration guide.

### LDAP

| Variable | Description | Default |
|----------|-------------|---------|
| `SPARC_ENABLE_LDAP` | Enable LDAP authentication | `false` |
| `SPARC_LDAP_HOST` | LDAP server hostname | (none) |
| `SPARC_LDAP_PORT` | LDAP server port | `636` |
| `SPARC_LDAP_ENCRYPTION` | Connection encryption (plain, start_tls, simple_tls) | `simple_tls` |
| `SPARC_LDAP_BIND_DN` | Service account bind DN | (none) |
| `SPARC_LDAP_BIND_PASSWORD` | Service account password | (none) |
| `SPARC_LDAP_BASE` | User search base DN | (none) |
| `SPARC_LDAP_ATTRIBUTE` | User lookup attribute | `uid` |

---

## Roles

SPARC seeds 9 RMF roles with two scopes:

**Instance-scoped** (global):
- Policy Manager
- Global Viewer

**Project-scoped** (assigned per project):
- Authorizing Official (AO)
- System Owner / ISO
- CISO
- ISSO
- Project Member
- Assessor / 3PAO
- View Only

Roles are managed via the admin UI at `/admin/users`.

---

## Audit Trail

Every authentication event is logged to the `audit_events` table:

- Login success/failure (with IP, user agent, provider)
- Logout
- Password change
- Role grant/revoke

Access audit events via the Rails console:
```ruby
AuditEvent.where(user: user).order(created_at: :desc)
```

---

## Important Notes

- **dotenv loads at boot** — After changing `.env`, you must restart the Rails server for changes to take effect.
- **OmniAuth requires POST** — All OAuth login buttons use POST forms (via `omniauth-rails_csrf_protection`) to prevent CSRF attacks.
- **Session fixation prevention** — Sessions are reset before storing the authenticated user ID.
- **Email normalization** — All emails are downcased and stripped before storage, preventing case-sensitivity issues across auth providers.
