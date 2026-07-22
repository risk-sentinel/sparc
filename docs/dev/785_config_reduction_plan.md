# #785 — Configuration Reduction Plan

**Status:** plan agreed 2026-07-22. Supersedes the earlier "config manifest + registry"
design, which was **rejected** — it added a second source of truth duplicating the 120
accessors already in `app/models/sparc_config.rb` (the tell: it needed a
"manifest↔accessor parity" spec), and it catalogued variables instead of reducing them.

## The governing distinction

**"Not required" ≠ "deleted."**

This plan reduces what an operator is *obliged to set*. It does **not** reduce what SPARC
*supports*. A variable whose production value already equals its shipped default does not
need a line in the task definition — but it remains a fully supported, documented
override. A capability that this particular deployment does not use (LDAP, GitLab) stays
shipped, supported, and documented; it simply is not configured here.

Across the entire programme **exactly one variable name is retired**
(`SPARC_ORG_CONTACT_EMAIL`, folded into `SPARC_CONTACT_EMAIL`, and even that keeps a
deprecating alias). Nothing else loses capability.

`.env.example` and `docs/ENVIRONMENT_VARIABLES.md` remain the complete vocabulary and
must continue to document every variable, required or not. The task definition carries
only what is genuinely deployment-specific.

## The problem

`sparc-iac/AWS/ECS/envs/prod/sparc-task-definition.json` sets **97 `environment` + 10
`secrets`**. Values live in the task definition (sparc-iac); defaults live in Ruby
(`SparcConfig`, in sparc). **Nothing ever compares the two**, so the task definition has
accumulated ~46 entries that restate a default or configure a feature that is switched off.

Measured config surface for context: 146 distinct ENV keys referenced repo-wide, 120
`SparcConfig` accessors, and **exactly one** accessor with no default. Nobody actually
has to set 135 variables — the task definition just makes it look that way.

sparc-iac continues to own and manage its task definition. This plan defines the
requirements it renders from.

## Two passes

**Pass 1 — eliminate the requirement.** Drop lines whose value equals the default or whose
feature is off; adopt production values as defaults where the knob is pure tuning; infer
`enable` flags from credential presence; fix two live defects; wire up one variable that
is documented but not actually read.

**Pass 2 — consolidate and auto-resolve.** Derive values computable from others (OIDC
redirect URI, FIDO2 RP ID, API audience) and collapse the six `SPARC_DB_*` vars into
`DATABASE_URL`.

## Verified findings

**`DATABASE_URL` precedence (Rails 8.1.3).** `database.yml` never references
`DATABASE_URL`; Rails merges it automatically, but only for `primary`:

```ruby
# activerecord-8.1.3/lib/active_record/database_configurations.rb:304
def environment_value_for(name)
  url   = ENV["#{name.upcase}_DATABASE_URL"]
  url ||= ENV["DATABASE_URL"] if name == "primary"   # primary ONLY
  url
end
```

`cache`, `queue`, and `cable` all inherit `*primary_production`, which derives their names
from `SPARC_DB_NAME`. **`SPARC_DB_*` is therefore load-bearing for the three secondary
databases** — dropping it and relying on `DATABASE_URL` alone would silently repoint them
at the `ssp_tpr_manager_production_*` fallbacks. Collapsing to one DB variable requires
`database.yml` to parse `DATABASE_URL` in ERB and derive the secondaries. That is Pass 2
and it is a real code change.

**Two live defects, both from setting `""` over a working default.** An empty string is
not `nil`, so `ENV.fetch(key, fallback)` returns `""` and the fallback never fires:

1. `SPARC_DISA_CCI_URL=""` overrides the DoD CCI zip URL default — that fetch is broken today.
2. `SPARC_API_OIDC_AUDIENCE=""` defeats an existing derivation. The read site is already
   `ENV.fetch("SPARC_API_OIDC_AUDIENCE", SparcConfig.oidc_client_id)`.

Fix by treating empty as unset at these read sites, not by removing the variables.

**One capability gap — `ACTIVE_STORAGE_SERVICE` is not wired.** Nothing in the repo reads
it; `production.rb:151` hardcodes `config.active_storage.service = :amazon`. The right
response is to **make the variable functional**, not to drop it: non-AWS and air-gapped
installs need `:local`. Setting it today silently does nothing.

`HTTP_PORT` and `RAILS_SERVE_STATIC_FILES` are likewise unread. `HTTP_PORT` is a leftover
(`PORT` is the real one). `RAILS_SERVE_STATIC_FILES` is a standard Rails knob we simply do
not implement — wiring it up is a small, reasonable addition if we ever front the app
without a CDN.

## Reconciliation: a drift check, not a manifest

A spec that loads the task-definition JSON, compares each value against the compiled
default, and **flags entries that merely restate a default**. That is what stops the file
re-growing to 97, and it works across both repos without a second source of truth. It
reports redundancy; it never asserts that a variable should not exist.

Open: which repo hosts it. Lean is `sparc` — that is where the defaults change and where
RSpec already runs; it needs a path to (or a checked-in copy of) the task-definition JSON.

---

## Master chart — all 97 `environment[]` entries

*“Not required” means the task definition need not set it. Every such variable **remains fully supported** and documented — only the obligation to set it goes away.*

| Variable | Set today | Task-def action | App-side | Code change | Note |
|---|---|---|---|---|---|
| `RAILS_ENV` | `production` | **Required** | Framework | none | Framework |
| `SPARC_ADMIN_EMAIL` | `sparc.admin@risk-sentinel.info` | **Required** | Supported — stays in `.env.example` + docs | add accessor | Canonical **admin** email; kills `admin@sparc.local` literal dup'd in 3 files |
| `SPARC_APP_URL` | `https://sparc.risk-sentinel.org` | **Required** | Supported — stays in `.env.example` + docs | none | Tier-0; also the source for derived redirect URI + FIDO2 RP ID |
| `SPARC_CONTACT_EMAIL` | `support.sparc@risk-sentinel.info` | **Required** | Supported — stays in `.env.example` + docs | none | Canonical **support** email (absorbs `ORG_CONTACT_EMAIL`) |
| `SPARC_OIDC_CLIENT_ID` | `0oa10sfxwbg3ygUxh698` | **Required** | Supported — stays in `.env.example` + docs | none | Credential; becomes the OIDC on-switch |
| `SPARC_OIDC_ISSUER_URL` | `https://integrator-5342723.okta.co…` | **Required** | Supported — stays in `.env.example` + docs | none | IdP-specific |
| `SPARC_AWS_LABS_CDEF_ENABLED` | `true` | Keep — deployment-specific | Supported — stays in `.env.example` + docs | none | Genuine per-deployment value |
| `SPARC_BANNER_ENABLED` | `true` | Not required (inferred) | Supported — override retained | infer from `SPARC_BANNER_MESSAGE` ✅ done | A banner with no message renders nothing; presence of the message IS the switch. Explicit `false` still forces off |
| `SPARC_BANNER_MESSAGE` | `public/banners/demo-banner.html` | Keep — deployment-specific | Supported | now also the banner on-switch | Per-deployment consent text |
| `SPARC_ENABLE_LOCAL_LOGIN` | `true` | Keep — deployment-specific | Supported — stays in `.env.example` + docs | none | Genuine per-deployment value |
| `SPARC_GITHUB_CLIENT_ID` | `Ov23liXGc1MJH1Oork8z` | Keep — deployment-specific | Supported — stays in `.env.example` + docs | none | Genuine per-deployment value |
| `SPARC_HEADER_TEXT` | `SPARC — Testing / Demonstration En…` | Keep — deployment-specific | Supported — stays in `.env.example` + docs | none | Genuine per-deployment value |
| `SPARC_OIDC_PROVIDER_TITLE` | `Okta` | Keep — deployment-specific | Supported — stays in `.env.example` + docs | none | Genuine per-deployment value |
| `SPARC_ORG_DESCRIPTION` | `SPARC is supported by private deve…` | Keep — deployment-specific | Supported — stays in `.env.example` + docs | none | Genuine per-deployment value |
| `SPARC_ORG_NAME` | `Risk Sentinel` | Keep — deployment-specific | Supported — stays in `.env.example` + docs | none | Genuine per-deployment value |
| `SPARC_SMTP_ADDRESS` | `smtp.mail.us-east-1.awsapps.com` | Keep — deployment-specific | Supported — stays in `.env.example` + docs | none | Genuine per-deployment value |
| `SPARC_SMTP_AUTH` | `login` | Keep — deployment-specific | Supported — stays in `.env.example` + docs | none | Genuine per-deployment value |
| `SPARC_SMTP_FROM_ADDRESS` | `noreply@risk-sentinel.info` | Keep — deployment-specific | Supported — stays in `.env.example` + docs | none | Genuine per-deployment value |
| `SPARC_SMTP_PORT` | `465` | Keep — deployment-specific | Supported — stays in `.env.example` + docs | none | Genuine per-deployment value |
| `SPARC_SMTP_USERNAME` | `sparc.admin@risk-sentinel.info` | Keep — deployment-specific | Supported — stays in `.env.example` + docs | none | Genuine per-deployment value |
| `AWS_BUCKET` | `${s3_bucket_name}` | TF-injected | Supported — stays in `.env.example` + docs | none | Infra-derived by Terraform |
| `AWS_REGION` | `${aws_region}` | TF-injected | Supported — stays in `.env.example` + docs | none | Infra-derived by Terraform |
| `DATABASE_URL` | `${database_url}` | TF-injected | Supported — stays in `.env.example` + docs | none | Infra-derived by Terraform |
| `PORT` | `${rails_port}` | TF-injected | Supported — stays in `.env.example` + docs | none | Infra-derived by Terraform |
| `REDIS_URL` | `${redis_url}` | TF-injected | Supported — stays in `.env.example` + docs | none | Infra-derived by Terraform |
| `SPARC_ADMIN_CREDENTIALS_SECRET_ARN` | `${admin_credentials_secret_arn}` | TF-injected | Supported — stays in `.env.example` + docs | none | Infra-derived by Terraform |
| `SPARC_API_OIDC_AUDIENCE` | `` | **Fix defect** | Supported — stays in `.env.example` + docs | guard: treat `""` as unset | ⚠️ Read site already derives from `oidc_client_id`; `""` is non-nil so the fallback never fires |
| `SPARC_DISA_CCI_URL` | `` | **Fix defect** | Supported — stays in `.env.example` + docs | guard: treat `""` as unset | ⚠️ `""` overrides the working DoD CCI URL default — fetch is broken today |
| `ACTIVE_STORAGE_SERVICE` | `amazon` | **Wire up** | Supported — stays in `.env.example` + docs | make `production.rb` read it | ⚠️ `production.rb:151` hardcodes `:amazon`. Non-AWS/on-prem installs need `:local` — **wire it, don't drop it** |
| `RAILS_SERVE_STATIC_FILES` | `false` | Not required | Not a SPARC var | **drop; document proxy requirement** ✅ decided | SPARC requires a reverse proxy / CDN for static assets — document that rather than implement the knob |
| `SPARC_ADMIN_REFRESH_ENABLED` | `true` | Not required (bump default) | Supported — override retained | `false` → `true` ✅ done, accessor added | Endpoint already gated by admin token + `admin.rotate_credentials`; the flag was a third lock |
| `SPARC_API_AUTH` | `hybrid` | **Required** | Supported | **none — stays explicit** | ⚠️ Cannot be defaulted or inferred. `hybrid` raises at boot without an issuer; inferring from issuer presence changed API auth semantics and **failed 338 specs**. See "Inference safety rule" |
| `SPARC_OIDC_FORCE_MFA` | `true` | Not required (bump default) | Supported — override retained | `false` → `true` ✅ done | Only consulted on the OIDC path, so inert when OIDC is off |
| `SPARC_REQUIRE_DOCUMENT_APPROVAL` | `true` | Decide | Supported — stays in `.env.example` + docs | bump default to `true`? | Recommend bump |
| `SPARC_DB_SSLMODE` | `require` | Not required (bump default) | Supported — stays in `.env.example` + docs | prod default → `require` | Security-correct prod default |
| `SPARC_LOG_TO_STDOUT` | `true` | Not required (bump default) | Supported — stays in `.env.example` + docs | prod default → `true` | Correct for any container deploy |
| `SPARC_MAX_UPLOAD_MB` | `100` | Not required (bump default) | Supported — stays in `.env.example` + docs | `50` → `100` ✅ done | Tuning knob — override retained |
| `SPARC_RATE_LIMIT_API_WRITES_PER_MINUTE` | `600` | Not required (bump default) | Supported — stays in `.env.example` + docs | `300` → `600` | Override retained |
| `SPARC_RATE_LIMIT_LOGIN_FAILURES_PER_MIN` | `3` | Not required (bump default) | Supported — stays in `.env.example` + docs | `5` → `3` | Override retained |
| `SPARC_RATE_LIMIT_UPLOADS_PER_5MIN_PER_IP` | `60` | Not required (bump default) | Supported — stays in `.env.example` + docs | `30` → `60` | Override retained |
| `SPARC_RATE_LIMIT_UPLOADS_PER_HOUR_PER_USER` | `500` | Not required (bump default) | Supported — override retained | `100` → **`250`** ✅ done | 250 chosen over the prod value of 500 |
| `SPARC_STRUCTURED_LOGGING` | `true` | Not required (bump default) | Supported — stays in `.env.example` + docs | prod default → `true` | Correct for any container deploy |
| `SPARC_ENABLE_OIDC` | `true` | Not required (inferred) | Supported — stays in `.env.example` + docs | infer from `SPARC_OIDC_CLIENT_ID` | Explicit `false` still forces off. Mirrors `github_enabled?` |
| `SPARC_ENABLE_SMTP` | `true` | Not required (inferred) | Supported — stays in `.env.example` + docs | infer from `SPARC_SMTP_ADDRESS` | Explicit `false` still forces off |
| `SPARC_OIDC_REDIRECT_URI` | `https://sparc.risk-sentinel.org/au…` | Not required (derived) | Supported — stays in `.env.example` + docs | derive from `SPARC_APP_URL` + `/auth/oidc/callback` | Our URL, not the IdP's. Override retained |
| `SPARC_ORG_CONTACT_EMAIL` | `support.sparc@risk-sentinel.info` | Retire — consolidated | → `SPARC_CONTACT_EMAIL` | alias w/ deprecation warning | Identical value in prod today. Final state = 2 emails: admin + support |
| `SPARC_DB_HOST` | `${db_host}` | Pass 2 — consolidate | Supported — stays in `.env.example` + docs | `database.yml` ERB derives cache/queue/cable from `DATABASE_URL` | ⚠️ **Load-bearing**: Rails merges `DATABASE_URL` into **primary only**; secondaries derive names from `SPARC_DB_NAME` |
| `SPARC_DB_NAME` | `${db_name}` | Pass 2 — consolidate | Supported — stays in `.env.example` + docs | `database.yml` ERB derives cache/queue/cable from `DATABASE_URL` | ⚠️ **Load-bearing**: Rails merges `DATABASE_URL` into **primary only**; secondaries derive names from `SPARC_DB_NAME` |
| `SPARC_DB_PASSWORD` | `${db_password}` | Pass 2 — consolidate | Supported — stays in `.env.example` + docs | `database.yml` ERB derives cache/queue/cable from `DATABASE_URL` | ⚠️ **Load-bearing**: Rails merges `DATABASE_URL` into **primary only**; secondaries derive names from `SPARC_DB_NAME` |
| `SPARC_DB_PORT` | `${db_port}` | Pass 2 — consolidate | Supported — stays in `.env.example` + docs | `database.yml` ERB derives cache/queue/cable from `DATABASE_URL` | ⚠️ **Load-bearing**: Rails merges `DATABASE_URL` into **primary only**; secondaries derive names from `SPARC_DB_NAME` |
| `SPARC_DB_USER` | `${db_username}` | Pass 2 — consolidate | Supported — stays in `.env.example` + docs | `database.yml` ERB derives cache/queue/cable from `DATABASE_URL` | ⚠️ **Load-bearing**: Rails merges `DATABASE_URL` into **primary only**; secondaries derive names from `SPARC_DB_NAME` |
| `SPARC_ENABLE_LDAP` | `false` | Not required (feature off) | Supported — stays in `.env.example` + docs | none | **LDAP stays fully supported.** Not enabled here, so the block need not be carried in this task def |
| `SPARC_LDAP_ATTRIBUTE` | `sAMAccountName` | Not required (feature off) | Supported — stays in `.env.example` + docs | none | **LDAP stays fully supported.** Not enabled here, so the block need not be carried in this task def |
| `SPARC_LDAP_BASE` | `` | Not required (feature off) | Supported — stays in `.env.example` + docs | none | **LDAP stays fully supported.** Not enabled here, so the block need not be carried in this task def |
| `SPARC_LDAP_BIND_DN` | `` | Not required (feature off) | Supported — stays in `.env.example` + docs | none | **LDAP stays fully supported.** Not enabled here, so the block need not be carried in this task def |
| `SPARC_LDAP_ENCRYPTION` | `simple_tls` | Not required (feature off) | Supported — stays in `.env.example` + docs | none | **LDAP stays fully supported.** Not enabled here, so the block need not be carried in this task def |
| `SPARC_LDAP_HOST` | `` | Not required (feature off) | Supported — stays in `.env.example` + docs | none | **LDAP stays fully supported.** Not enabled here, so the block need not be carried in this task def |
| `SPARC_LDAP_PORT` | `636` | Not required (feature off) | Supported — stays in `.env.example` + docs | none | **LDAP stays fully supported.** Not enabled here, so the block need not be carried in this task def |
| `FORCE_SSL` | `true` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `HTTP_PORT` | `${rails_port}` | Not required | Not a SPARC var | none | Nothing reads it; `PORT` is the real one. Leftover |
| `MALLOC_ARENA_MAX` | `2` | Not required | Image-level | none | Already set in `Dockerfile:105` |
| `SOLID_QUEUE_IN_PUMA` | `true` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_ALLOW_CRED_ROTATION` | `` | Not required | Supported — stays in `.env.example` + docs | none | Break-glass rake gate; read site tests `== "1"`, `""` is a no-op |
| `SPARC_APP_NAME` | `SPARC` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_ARTIFACT_COPY_PER_VERSION` | `false` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_ARTIFACT_REAPER_PURGE` | `false` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_AUTHORITATIVE_FETCH_ENABLED` | `false` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_AWS_IAM_DB_AUTH` | `false` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_AWS_LABS_CDEF_BRANCH` | `main` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_AWS_LABS_CDEF_REFRESH_INTERVAL_DAYS` | `7` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_AWS_LABS_CDEF_REPO` | `awslabs/oscal-content-for-aws-serv…` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_AWS_LABS_OSCAL_VERSIONS` | `` | Not required | Supported — stays in `.env.example` + docs | none | Optional; `""` is a no-op |
| `SPARC_AWS_REGION` | `us-east-1` | Not required | **Deprecate (Pass 2)** | keep as silent alias for `AWS_REGION` | ⚠️ No demonstrated value. Every read site is the identical chain `SPARC_AWS_REGION`→`AWS_REGION`→`us-east-1`. The only scenario it enables (SDK clients in a different region than the S3 bucket) is theoretical — no real deployment needs it |
| `SPARC_CCI_REVS` | `4,5` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_ENABLE_USER_REGISTRATION` | `false` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_GITLAB_CLIENT_ID` | `` | Not required | Supported — stays in `.env.example` + docs | none | Optional; `""` is a no-op |
| `SPARC_GITLAB_SITE` | `https://gitlab.com` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_HEADER_HIGHLIGHT_COLOR` | `` | Not required | Supported — stays in `.env.example` + docs | none | Optional; `""` is a no-op |
| `SPARC_HEADER_TEXT_COLOR` | `` | Not required | Supported — stays in `.env.example` + docs | none | Optional; `""` is a no-op |
| `SPARC_INACTIVITY_DAYS` | `30` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_LOG_LEVEL` | `info` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_MAX_AVATAR_MB` | `2` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_OIDC_SCOPES` | `openid profile email` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_ORG_ADDRESS` | `` | Not required | Supported — stays in `.env.example` + docs | none | Optional; `""` is a no-op |
| `SPARC_ORG_CONTACT_PERSON` | `` | Not required | Supported — stays in `.env.example` + docs | none | Optional; `""` is a no-op |
| `SPARC_PASSWORD_EXPIRY_DAYS` | `30` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_PRINT_ROTATED_PASSWORD` | `` | Not required | Supported — stays in `.env.example` + docs | none | Break-glass rake gate; read site tests `== "1"`, `""` is a no-op |
| `SPARC_PROCESSING_STUCK_MINUTES` | `5` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_RATE_LIMITING_ENABLED` | `true` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_RESOURCES` | `` | Not required | Supported — stays in `.env.example` + docs | none | Optional; `""` is a no-op |
| `SPARC_RUN_SEEDS` | `false` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_SA_INACTIVITY_DAYS` | `90` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_SEED_MODE` | `full` | Not required | Supported — stays in `.env.example` + docs | none | Only read when `SPARC_RUN_SEEDS=true` |
| `SPARC_SESSION_TIMEOUT_MINUTES` | `60` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_SKIP_DEFERRED_DATA_MIGRATIONS` | `false` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_SMTP_STARTTLS_AUTO` | `true` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |
| `SPARC_WELCOME_TEXT` | `Welcome to SPARC` | Not required | Supported — stays in `.env.example` + docs | none | Value equals the shipped default |

## `secrets[]` — all 10

| Secret | Task-def action | Note |
|---|---|---|
| `DB_CREDENTIALS` | Review | Overlaps `DATABASE_URL`/`SPARC_DB_PASSWORD` — resolve in Pass 2 |
| `SECRET_KEY_BASE` | **Required** | Live credential |
| `SPARC_ADMIN_PASSWORD` | **Required** | Break-glass; executionRole-injected, taskRole has no access |
| `SPARC_AWS_LABS_GITHUB_TOKEN` | **Required** | Live credential |
| `SPARC_GITHUB_CLIENT_SECRET` | **Required** | Live credential |
| `SPARC_GITLAB_CLIENT_SECRET` | Not required (feature off) | GitLab unconfigured; secret unused. Capability retained |
| `SPARC_HASH` | **Required** | Live credential; ≥32 chars |
| `SPARC_LDAP_BIND_PASSWORD` | Not required (feature off) | **LDAP stays supported** — no bind password needed while LDAP is off here |
| `SPARC_OIDC_CLIENT_SECRET` | **Required** | Live credential |
| `SPARC_SMTP_PASSWORD` | **Required** | Live credential |

## Arithmetic — lines the task definition must carry

| Stage | Lines dropped | Remaining | Vars removed from SPARC |
|---|---|---|---|
| Today | — | **97** | — |
| Default already correct / feature off | 46 | 51 | 0 |
| Bump defaults (override retained) | 8 | 43 | 0 |
| Infer / derive / consolidate | 4 | 39 | 1 (`SPARC_ORG_CONTACT_EMAIL`, aliased) |
| Fix the two `""` defects | 2 | **37** | 0 |
| Pass 2: `SPARC_DB_*` → `DATABASE_URL` | 5 | **32** | 0 |

**Net: 97 → ~32 task-def lines, with exactly ONE variable name retired across the whole programme** (and that one keeps a deprecating alias). Nothing else loses capability.

---

## Inference safety rule (learned the hard way)

Inference is the main lever for taking configuration off the customer's plate, but it is
only safe in one direction.

> **Infer only when the inference can turn a feature ON that the operator has already
> configured. Never infer something that changes the semantics of a feature that is
> already working.**

| Inference | Verdict | Why |
|---|---|---|
| Banner on ⟸ banner message present | ✅ Safe | Message present means they want it shown. Nothing else changes |
| OIDC on ⟸ client ID present | ✅ Safe | Adds a login method they configured |
| SMTP on ⟸ SMTP address present | ✅ Safe | Adds mail delivery they configured |
| GitHub/GitLab on ⟸ client ID present | ✅ Safe | Already shipped, already proven |
| **API auth mode ⟸ OIDC issuer present** | ❌ **Unsafe** | Changes *who can authenticate*. A deployment with OIDC configured that still issues SPARC tokens to humans gets 401s on upgrade. **Measured: 338 spec failures** |

`SPARC_API_AUTH` therefore stays explicit and required. This is the one requested default
bump that could not be delivered; the reason is behavioural, not effort.

In every safe case the explicit variable still wins, so an operator who wants a banner
configured-but-hidden, or OIDC credentials present but login disabled, sets the flag to
`false` and gets exactly that.

## Customer perception: four audiences, not one list

The deeper problem is that all ~146 variables are presented as though a single person must
consider them. They actually belong to four different audiences, and only the first is
"configuration" in any sense the customer would recognise:

| Tier | Who decides | Examples | Presentation |
|---|---|---|---|
| **1. Product configuration** | The customer | `SPARC_APP_URL`, admin/support email, org metadata, auth block, banner text, retention policy | Front and centre. This is the real list, and it is roughly **10–12 entries** |
| **2. Infrastructure** | Terraform / the platform | `DATABASE_URL`, `REDIS_URL`, `AWS_BUCKET`, secret ARNs | Never shown as customer config — it is rendered, not authored |
| **3. Deploy plumbing** | The operator, once | `SPARC_RUN_SEEDS`, `SPARC_SEED_MODE`, `SOLID_QUEUE_IN_PUMA`, `SPARC_SKIP_DEFERRED_DATA_MIGRATIONS`, `PORT` | A separate "operations" section, not mixed with product settings |
| **4. Internal tuning** | Nobody, normally | `SPARC_PROCESSING_STUCK_MINUTES`, `SPARC_DOCUMENT_REAP_MINUTES`, `SPARC_ARTIFACT_REAPER_MIN_AGE_HOURS`, `SCRAPE_THROTTLE_SECONDS` | Documented as support-escalation knobs, below the fold. Still fully overridable |

Restructuring `docs/ENVIRONMENT_VARIABLES.md` and `.env.example` along these four tiers
costs nothing at runtime and changes the perceived size of the system far more than any
individual deletion. **The customer's list goes from "135 variables" to "about a dozen,
plus knobs you will never touch."**

## Candidate: derive SMTP TLS mode from the port

`SPARC_SMTP_STARTTLS_AUTO` is a good example of a knob the customer should not have to
reason about — the correct value is determined by the port:

| Port | Correct mode |
|---|---|
| 465 | Implicit TLS (SMTPS) — STARTTLS off |
| 587 | STARTTLS |
| 25 | Usually none |

⚠️ **Needs verification before acting.** Production currently sets port `465` *and*
`SPARC_SMTP_STARTTLS_AUTO=true`, and `smtp_settings` has no `tls:`/`ssl:` key at all
(`production.rb:119–128`). That combination is contradictory on paper. Confirm whether
mail is actually delivering in production before treating this as a bug — if it is
working, the finding is only that the knob is redundant, not that it is broken.

---

## Sequencing (both repos)

Defaults must land in `sparc` **before** the task-definition trim in `sparc-iac`, otherwise
dropping a line reverts production to the old default.

1. **sparc** — bump defaults, add inference/derivation, add accessors, fix the two `""`
   defects, wire up `ACTIVE_STORAGE_SERVICE`, add the drift check. Purely additive.
2. **sparc-iac** — trim the task definition to the surviving entries.
3. **sparc** — Pass 2: `database.yml` ERB derives cache/queue/cable from `DATABASE_URL`.
4. **sparc-iac** — drop `SPARC_DB_*`.

## Documentation obligation

Because "not required" is not "deleted":

- Every variable stays in `docs/ENVIRONMENT_VARIABLES.md`, marked **required** vs
  **optional (default: X)**, and grouped by the four audience tiers above.
- `.env.example` becomes one tiered file: required block at the top, optional blocks below,
  each entry commented out with its default shown inline.
- Document that **SPARC requires a reverse proxy or CDN for static assets** — this replaces
  implementing `RAILS_SERVE_STATIC_FILES`.
- Continue to omit `SPARC_ENABLE_XLSX_UPLOADS` (obscure-by-default).

## Status of decisions

| Decision | Outcome |
|---|---|
| `SPARC_MAX_UPLOAD_MB` → 100 | ✅ applied |
| `SPARC_RATE_LIMIT_UPLOADS_PER_HOUR_PER_USER` → 250 | ✅ applied |
| Other three rate limits → prod values | ↩︎ **reverted — not approved.** `API_WRITES_PER_MINUTE`, `LOGIN_FAILURES_PER_MIN`, `UPLOADS_PER_5MIN_PER_IP` are back at their shipped defaults |
| `SPARC_OIDC_FORCE_MFA` → default true | ✅ applied |
| `SPARC_ADMIN_REFRESH_ENABLED` → default true | ✅ applied (+ accessor, controller routed) |
| `SPARC_BANNER_ENABLED` ⟸ `SPARC_BANNER_MESSAGE` | ✅ applied |
| `RAILS_SERVE_STATIC_FILES` → drop, document proxy | ✅ decided, doc pending |
| `SPARC_API_AUTH` → default hybrid | ❌ **not safe** — see Inference safety rule |
| `SPARC_AWS_REGION` — what is it for? | ⚠️ **No demonstrated value.** See below — candidate for deprecation, not retention |

Full suite green after these changes: **2985 examples, 0 failures**; rubocop clean.

## Remaining open

| # | Decision | Recommendation |
|---|---|---|
| 1 | Drift-check home: `sparc` or `sparc-iac`? | `sparc` |
| 2 | `SPARC_REQUIRE_DOCUMENT_APPROVAL` — bump default to `true`? | Bump |
| 3 | Verify SMTP port 465 + STARTTLS before deriving TLS mode | Verify first |
| 4 | Adopt the four-tier documentation split? | Yes — biggest perception win |

---

## `SPARC_AWS_REGION` — reassessed, and it does not earn its place

An earlier draft justified this variable as enabling "split-region" deployments. That
justification does not hold up:

- All four read sites use the **identical** chain `SPARC_AWS_REGION` → `AWS_REGION` →
  `us-east-1` (`sparc_config.rb:468`, `admin_credential_rotation_service.rb:122`,
  `00_aws_secrets.rb:38`, `aws_db_auth.rb:25`).
- The only behaviour it can produce that `AWS_REGION` alone cannot is running the Secrets
  Manager / RDS-IAM / rotation SDK clients in a *different* region from the S3 bucket.
- No real deployment needs that, and none is planned.

**Recommendation: deprecate in Pass 2.** Keep it as a silent alias for `AWS_REGION` so
existing configurations do not break, remove it from the documented vocabulary, and route
the three duplicated fallback chains through a single accessor.

### Note on S3 and regions

S3 **bucket names** are globally unique, but buckets are regional resources and the SDK
still needs a region to resolve an endpoint — `Aws::S3::Client.new` without one raises
`Aws::Errors::MissingRegionError`. `config/storage.yml:11` is `region: <%= ENV['AWS_REGION'] %>`.

So `AWS_REGION` is genuinely load-bearing for Active Storage and must stay (it is
Terraform-injected in any case). It is `SPARC_AWS_REGION`, the SPARC-specific override,
that has no demonstrated purpose.
