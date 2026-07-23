# #785 — Configuration Reduction Plan

> **STATUS — Pass 1 shipped (v1.13.1, PR #789 merged). Pass 2 IN PROGRESS on branch
> `785-config-pass2`.** The authoritative state is the **"Pass 2 — record"** section at the
> very end; earlier sections are kept for reasoning, not status.
>
> Suite: **3023 examples, 0 failures, 10 pending**. Rubocop clean.
> Outstanding elsewhere: **sparc-iac#566** (server-side `rds.force_ssl=1`) and the
> task-definition trim itself. Follow-ups: **#788** (YAML linter), **#790** (PIV parser).

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

**One capability gap — `ACTIVE_STORAGE_SERVICE` was not wired.** ✅ *Fixed in v1.13.1.*
Nothing in the repo read it; `production.rb` hardcoded
`config.active_storage.service = :amazon`, so setting the variable silently did nothing.

The variable names a service from `config/storage.yml` (`local`/`test` → Disk, `amazon` →
S3) and selects where **every uploaded blob** goes: SSP/SAR/CDEF/SAP/POAM/Profile document
files, `Evidence` files, `ArtifactVersion` content (#680), and user avatars.

The right response was to **make the variable functional**, not to drop it. On ECS the
container filesystem is ephemeral, so production must stay on `amazon` — but a non-AWS or
air-gapped install needs `:local` and previously had no way to ask for it.

`HTTP_PORT` and `RAILS_SERVE_STATIC_FILES` are likewise unread. `HTTP_PORT` is a leftover
(`PORT` is the real one). `RAILS_SERVE_STATIC_FILES` is a standard Rails knob we simply do
not implement — wiring it up is a small, reasonable addition if we ever front the app
without a CDN.

## Reconciliation: a drift check, not a manifest

A spec that loads the task-definition JSON, compares each value against the compiled
default, and **flags entries that merely restate a default**. That is what stops the file
re-growing to 97, and it works across both repos without a second source of truth. It
reports redundancy; it never asserts that a variable should not exist.

**Resolved:** it lives in `sparc` (`spec/config/task_definition_drift_spec.rb`), reading the
sibling checkout, and runs as an on-demand audit rather than a default-suite spec. See
"Pass 1 — complete" below.

---

## Master chart — all 97 `environment[]` entries

*“Not required” means the task definition need not set it. Every such variable **remains fully supported** and documented — only the obligation to set it goes away.*

| Variable | Set today | Task-def action | App-side | Code change | Note |
|---|---|---|---|---|---|
| `RAILS_ENV` | `production` | **Required** | Framework | none | Framework |
| `SPARC_ADMIN_EMAIL` | `sparc.admin@risk-sentinel.info` | **Required** | Supported — override retained | accessor added ✅ **done** | Canonical **admin** email; kills `admin@sparc.local` literal dup'd in 3 files |
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
| `SPARC_API_OIDC_AUDIENCE` | `` | **Fix defect** | Supported — override retained | blank treated as unset ✅ **done** | ⚠️ Read site already derives from `oidc_client_id`; `""` is non-nil so the fallback never fires |
| `SPARC_DISA_CCI_URL` | `` | **Fix defect** | Supported — override retained | blank treated as unset ✅ **done** | ⚠️ `""` overrides the working DoD CCI URL default — fetch is broken today |
| `ACTIVE_STORAGE_SERVICE` | `amazon` | Keep — deployment-specific | **Gained function** | `production.rb` now reads it ✅ **done** | Selects the Active Storage backend for every uploaded blob (documents, evidence, artifact versions, avatars). Was hardcoded `:amazon`, so on-prem/air-gap could not select `:local`. ECS filesystems are ephemeral, so prod must stay `amazon` |
| `RAILS_SERVE_STATIC_FILES` | `false` | Not required | Not a SPARC var | dropped; proxy requirement documented ✅ **done** | SPARC requires a reverse proxy / CDN for static assets — document that rather than implement the knob |
| `SPARC_ADMIN_REFRESH_ENABLED` | `true` | Not required (bump default) | Supported — override retained | `false` → `true` ✅ done, accessor added | Endpoint already gated by admin token + `admin.rotate_credentials`; the flag was a third lock |
| `SPARC_API_AUTH` | `hybrid` | **Required** | Supported | **none — stays explicit** | ⚠️ Cannot be defaulted or inferred. `hybrid` raises at boot without an issuer; inferring from issuer presence changed API auth semantics and **failed 338 specs**. See "Inference safety rule" |
| `SPARC_OIDC_FORCE_MFA` | `true` | Not required (bump default) | Supported — override retained | `false` → `true` ✅ done | Only consulted on the OIDC path, so inert when OIDC is off |
| `SPARC_REQUIRE_DOCUMENT_APPROVAL` | `true` | Not required (bump default) | Supported — override retained | `false` → `true` ✅ **done** | ⚠️ Behaviour change on upgrade: documents that used to publish freely now need approval. 18 specs encoded the old default |
| `SPARC_DB_SSLMODE` | `require` | Not required (bump default) | **Gained function** | prod → `require`, wired into `database.yml` ✅ **done** | Now applies to **all four** databases. Was inert (no `sslmode` key existed). See DB TLS section |
| `SPARC_LOG_TO_STDOUT` | `true` | Not required (bump default) | **Gained function** | prod → `true`, honoured in every env ✅ **done** | Was inert — proven by setting it to `false` and still getting stdout. Now read in `application.rb` |
| `SPARC_MAX_UPLOAD_MB` | `100` | Not required (bump default) | Supported — stays in `.env.example` + docs | `50` → `100` ✅ done | Tuning knob — override retained |
| `SPARC_RATE_LIMIT_API_WRITES_PER_MINUTE` | `600` | Keep — deployment-specific | Supported | **none — not approved** | Left at the shipped default of 300; prod continues to set it |
| `SPARC_RATE_LIMIT_LOGIN_FAILURES_PER_MIN` | `3` | Not required (bump default) | Supported — override retained | `5` → `3` ✅ **done** | Tightening |
| `SPARC_RATE_LIMIT_UPLOADS_PER_5MIN_PER_IP` | `60` | Not required (bump default) | Supported — override retained | `30` → `60` ✅ **done** | Override retained |
| `SPARC_RATE_LIMIT_UPLOADS_PER_HOUR_PER_USER` | `500` | Not required (bump default) | Supported — override retained | `100` → **`250`** ✅ done | 250 chosen over the prod value of 500 |
| `SPARC_STRUCTURED_LOGGING` | `true` | Not required (bump default) | **Gained function** | prod → `true`, JSON formatter implemented ✅ **done** | Was a documented promise with no implementation. `lib/logging/sparc_json_formatter.rb` |
| `SPARC_ENABLE_OIDC` | `true` | Not required (inferred) | Supported — override retained | infer from `SPARC_OIDC_CLIENT_ID` ✅ **done** | Explicit `false` still forces off |
| `SPARC_ENABLE_SMTP` | `true` | Not required (inferred) | Supported — override retained | infer from `SPARC_SMTP_ADDRESS` ✅ **done** | Inference duplicated inline in `production.rb` (boot, pre-autoload) — keep in step |
| `SPARC_OIDC_REDIRECT_URI` | `https://sparc.risk-sentinel.org/au…` | Not required (derived) | Supported — override retained | derived from `SPARC_APP_URL` ✅ **done** | Our URL, not the IdP's. Override retained |
| `SPARC_ORG_CONTACT_EMAIL` | `support.sparc@risk-sentinel.info` | Retire — consolidated | → `SPARC_CONTACT_EMAIL` | deprecating alias ✅ **done** | Identical value in prod today. Final state = 2 emails: admin + support |
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
| `SPARC_AUTHORITATIVE_FETCH_ENABLED` | `false` | Not required | Supported — override retained | accessor added, service routed ✅ **done** | Value equals the shipped default. Was reading raw `ENV` — **found by the drift check** |
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
| `RAILS_SERVE_STATIC_FILES` → drop, document proxy | ✅ applied — documented in `ENVIRONMENT_VARIABLES.md` and `.env.example` |
| `SPARC_API_AUTH` → default hybrid | ❌ **not safe** — see Inference safety rule |
| `SPARC_AWS_REGION` — what is it for? | ⚠️ **No demonstrated value.** See below — candidate for deprecation, not retention |

Suite at that point: 2985 examples, 0 failures. **Final state for v1.13.1: 3009 examples, 0 failures, 10 pending.**

## Remaining open

| # | Decision | Outcome |
|---|---|---|
| 1 | Drift-check home: `sparc` or `sparc-iac`? | ✅ **Resolved** — `sparc`, as an on-demand audit |
| 2 | Wire up or drop the three INERT vars | ✅ **Resolved** — all three wired |
| 3 | Verify SMTP port 465 + STARTTLS before deriving TLS mode | ⏳ **Still open** — needs confirmation that mail delivers in prod |
| 4 | Adopt the four-tier documentation split? | ✅ **Resolved** — applied to both docs |
| 5 | Hard-fail the drift check in CI once the task definition is trimmed? | ⏳ **Still open** |

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

---

# Record of work — #785

Branch `785-config-reduction`. Chronological; every entry states what was approved,
what was done, and how it was verified. Nothing lands here without explicit approval.

## Applied and verified

| # | Change | Approved | Verification |
|---|---|---|---|
| 1 | `SPARC_MAX_UPLOAD_MB` default `50` → `100` | ✅ explicit | suite green; 1 spec updated |
| 2 | `SPARC_RATE_LIMIT_UPLOADS_PER_HOUR_PER_USER` `100` → `250` | ✅ explicit | suite green |
| 3 | `SPARC_OIDC_FORCE_MFA` default `false` → `true` | ✅ explicit | suite green; inert when OIDC off |
| 4 | `SPARC_ADMIN_REFRESH_ENABLED` default `false` → `true`, new accessor, controller routed off raw `ENV` | ✅ explicit | suite green; 2 specs rewritten for the new contract |
| 5 | `SPARC_BANNER_ENABLED` inferred from `SPARC_BANNER_MESSAGE` | ✅ explicit | suite green |
| 6 | `SPARC_REQUIRE_DOCUMENT_APPROVAL` default `false` → `true` | ✅ explicit | **18 specs failed**, all from this flip; 3 spec files updated to pin the gate off where they test publish mechanics, not the gate |
| 7 | `SPARC_RATE_LIMIT_LOGIN_FAILURES_PER_MIN` `5` → `3` | ✅ explicit | suite green |
| 8 | `SPARC_RATE_LIMIT_UPLOADS_PER_5MIN_PER_IP` `30` → `60` | ✅ explicit | suite green |
| 9 | `SPARC_ENABLE_OIDC` inferred from `SPARC_OIDC_CLIENT_ID` | ✅ explicit | suite green |
| 10 | `SPARC_ENABLE_SMTP` inferred from `SPARC_SMTP_ADDRESS`, inference duplicated inline in `production.rb` | ✅ explicit | suite green |
| 11 | `SPARC_DB_SSLMODE` prod default → `require` | ✅ explicit | applied — **inert, see below** |
| 12 | `SPARC_LOG_TO_STDOUT` prod default → `true` | ✅ explicit | applied — **inert, see below** |
| 13 | `SPARC_STRUCTURED_LOGGING` prod default → `true` | ✅ explicit | applied — **inert, see below** |

Suite at that point: 2985 examples, 0 failures. **Final v1.13.1 state: 3009 examples, 0 failures, 10 pending; rubocop clean across 739 files.**

## Rejected or reverted

| Change | Why |
|---|---|
| `SPARC_API_AUTH` → `hybrid` | **Refused on evidence.** A flat default raises at boot without an OIDC issuer; inferring from issuer presence changed *who may authenticate* and failed **338 specs**. Reasoning recorded in the accessor so it is not retried |
| `SPARC_RATE_LIMIT_API_WRITES_PER_MINUTE` `300` → `600` | Applied from an unapproved draft, then reverted |
| `SPARC_RATE_LIMIT_LOGIN_FAILURES_PER_MIN` (first attempt) | Applied unapproved, reverted, later approved and re-applied |
| `SPARC_RATE_LIMIT_UPLOADS_PER_5MIN_PER_IP` (first attempt) | Same |
| Config manifest + registry design | Rejected: second source of truth duplicating 120 existing accessors |

## Findings that changed the plan

| Finding | Impact |
|---|---|
| `DATABASE_URL` is merged for `primary` **only** (activerecord 8.1.3) | `SPARC_DB_*` is load-bearing for cache/queue/cable; one-DB-var needs `database.yml` ERB work (Pass 2) |
| `SPARC_DISA_CCI_URL=""` overrides a working default | Live defect — DoD CCI fetch broken in prod. ✅ **Fixed** |
| `SPARC_API_OIDC_AUDIENCE=""` defeats its own fallback | Live defect. ✅ **Fixed** |
| `ACTIVE_STORAGE_SERVICE` unread; `production.rb` hardcoded `:amazon` | Capability gap — wired up, not dropped. ✅ **Fixed** |
| `HTTP_PORT`, `RAILS_SERVE_STATIC_FILES` unread | Drop; proxy requirement documented. ✅ **Done** |
| `SPARC_AWS_REGION` justification withdrawn | No demonstrated value; deprecate in Pass 2 as a silent alias |
| **`DB_SSLMODE`, `LOG_TO_STDOUT`, `STRUCTURED_LOGGING` had zero consumers** | Defaults were bumped but changed no behaviour. ✅ **All three now wired** — see the v1.13.1 section |
| SMTP port `465` set alongside `STARTTLS_AUTO=true`, no `tls:` key | Flagged, unverified — confirm mail delivers before acting |

## Three variables that were inert — all now wired

At the time their defaults were bumped, none of these three was read by anything, so the
bump changed no behaviour. **All three were subsequently wired up in v1.13.1** and are now
load-bearing:

| Variable | Was inert because | Now |
|---|---|---|
| `SPARC_DB_SSLMODE` | `config/database.yml` had no `sslmode` key at all | ✅ Set in the `default:` anchor, so **all four** databases inherit it. Production floors at `require` |
| `SPARC_LOG_TO_STDOUT` | `production.rb` set the logger to STDOUT unconditionally | ✅ Read in `application.rb`, honoured in every environment. Proven: `false` no longer logs to stdout |
| `SPARC_STRUCTURED_LOGGING` | No structured formatter existed anywhere | ✅ `lib/logging/sparc_json_formatter.rb` implements it |

`SPARC_DB_SSLMODE` was the one with a security dimension. It is resolved on the app side;
server-side enforcement (`rds.force_ssl=1`) is **sparc-iac#566** and still outstanding.

## Status at that point (superseded)

The section above was written mid-flight. See **"Pass 1 — complete"** at the end of this
document for the final state — every Pass 1 item listed there as outstanding has since
shipped.

---

# v1.13.1 — logging + DB TLS work (items 2, 3, 4)

Scope agreed 2026-07-22. Shipped on `785-config-reduction` as part of **v1.13.1**.

## Item 2 — `SPARC_LOG_TO_STDOUT`: proven, then fixed

Measured against the running UBI9 **production** image:

| Proof | Result |
|---|---|
| Container emits to stdout | ✅ Puma boot, SolidQueue, ActiveJob all visible via `docker logs` |
| Request logs are traced | ✅ `[7ba21cc6-…] Started GET "/" … Completed 302 in 27ms` |
| **Was the flag honoured?** | ❌ **No.** `SPARC_LOG_TO_STDOUT=false` still logged to stdout |

Containers were getting what they need in production, but only by accident of an
unconditional `config.logger = …STDOUT` line in `production.rb`. Two consequences: the
variable was a lie, and **any non-production container wrote to a file inside the image**,
invisible to `docker logs` and CloudWatch.

Fixed by moving log destination and format into `config/application.rb`, so it applies to
every environment. Verified after the fix: `true` → line appears, `false` → line does not.

## Item 3 — `SPARC_STRUCTURED_LOGGING`: the promise is now real

Documented since the first version of `ENVIRONMENT_VARIABLES.md` as *"Output logs in JSON
format (CloudWatch, ELK, Splunk friendly)"*, and never implemented — no formatter existed
and nothing read the variable.

`lib/logging/sparc_json_formatter.rb` implements it. The key property is that
`request_id` is emitted as a **field**, not a text prefix, which is what makes a request
traceable by query rather than by grep:

```json
{"ts":"2026-07-23T00:26:16.427Z","level":"WARN","msg":"hello-json","request_id":"req-abc123"}
```

NIST AU-3 (content of audit records). Distinct from the `AuditEvent` model, which remains
the system of record for security-relevant user actions; this is operational logging.

10 specs pin the contract, including that the formatter **never raises** — a logger that
throws takes the process with it, so serialisation failure degrades to a valid record.

## Item 4 — Database TLS: all four layers

| Layer | State |
|---|---|
| 1. `rds.force_ssl=1` parameter group | **Filed as sparc-iac#566** — no server-side enforcement exists today |
| 2. `sslmode` floor for all four databases | ✅ Shipped |
| 3. RDS CA bundle baked into the image | ✅ Shipped |
| 4. Both-directions proof | ✅ Shipped |

**The finding that justified the work:** `DATABASE_URL` carries `?sslmode=require`, but
Rails merges it into `primary` **only**. Cache, queue and cable negotiated on libpq's
default. Measured in the running production image: `pg_stat_ssl` reported **`ssl=false`**.

Layer 2 puts `sslmode` in `database.yml`'s `default:` anchor so every database inherits it.

Layer 3 bakes the AWS RDS global bundle (108 certs) to
`/etc/pki/sparc/rds-global-bundle.pem`. **libpq ignores `SSL_CERT_FILE`**, so the v1.12.3
runtime CA mechanism — which covers Net::HTTP, the AWS SDK and LDAP — does not reach
Postgres. On RDS, `verify-full` is now a one-variable change.

Layer 4 (`bin/test-db-tls`, `spec/security/database_tls_spec.rb`) proves both directions
with real handshakes against live TLS and plaintext-only servers — 11 examples:

```
accepts:  verify-full + correct CA + matching host  -> TLS 1.3
          sslmode=require                           -> TLS 1.3
refuses:  require against a plaintext-only server
          verify-full with no CA / wrong CA / hostname mismatch
control:  prefer downgrades, proving the harness detects a downgrade
```

### Guidance for customers

`docs/DATABASE_TLS.md`. The headline for operators: **`require` is not sufficient for
FedRAMP High** — it encrypts but does not authenticate the server, so it will complete a
handshake with any host that answers. `verify-full` is the target.

One correction to an earlier assumption, stated plainly in the guide so operators do not
rebuild unnecessarily: **a rebuild is NOT required to use a private CA for the database.**
libpq reads `sslrootcert` from a path, so mounting a PEM and setting
`SPARC_DB_SSLROOTCERT` is enough. Rebuilding via `certs/` is only needed to change the
*system* trust store used by outbound HTTPS and LDAP.

### On the "APP→APP no SSL, APP→non-APP explicit SSL" model

Reasonable in principle, but SPARC has almost no APP→APP surface — every dependency is a
network service reached across the VPC:

| Hop | Transport today |
|---|---|
| App → Postgres (RDS) | Was the **only** unencrypted hop; now floored at `require` |
| App → Redis (ElastiCache) | Already TLS — `transit_encryption_enabled = true` |
| App → S3 | HTTPS |
| App → OIDC / LDAP / SMTP / GitHub | TLS, hardened in v1.12.3 |

RDS is a separate managed service, not an in-boundary process, so the carve-out would not
apply to it anyway — and the infra **already** encrypts the Redis hop. The database was the
outlier, not the rule. Recommendation: keep a single policy of explicit TLS everywhere.

## Verification

- Suite at that point: 3006 examples, 0 failures, 7 pending. **Final v1.13.1 state: 3009 / 0 / 10.**
- `bin/test-db-tls` — 11 examples, 0 failures.
- Rubocop clean.
- `VERSION` bumped to **1.13.1** in the same PR, per convention.

---

## Pass 1 — complete (v1.13.1)

| Item | Outcome |
|---|---|
| `SPARC_DISA_CCI_URL=""` defect | ✅ Fixed — blank treated as unset. The DoD CCI fetch was broken in prod |
| `SPARC_API_OIDC_AUDIENCE=""` defect | ✅ Fixed — fallback to `oidc_client_id` now fires |
| `ACTIVE_STORAGE_SERVICE` unwired | ✅ Wired. `production.rb` hardcoded `:amazon`; on-prem/air-gap can now select `:local` |
| `SPARC_ADMIN_EMAIL` accessor | ✅ Added — `admin@sparc.local` literal removed from 4 call sites |
| `SPARC_ORG_CONTACT_EMAIL` | ✅ Consolidated into `SPARC_CONTACT_EMAIL`, deprecating alias retained |
| `SPARC_OIDC_REDIRECT_URI` | ✅ Derived from `SPARC_APP_URL` |
| `SPARC_AUTHORITATIVE_FETCH_ENABLED` | ✅ Accessor added, service routed — **found by the drift check** |
| Drift check | ✅ `spec/config/task_definition_drift_spec.rb` |
| Four-tier docs | ✅ `ENVIRONMENT_VARIABLES.md` + `.env.example` |

**One variable name retired programme-wide** (`SPARC_ORG_CONTACT_EMAIL`), and it still
works as an alias. Nothing lost capability; two things *gained* it
(`ACTIVE_STORAGE_SERVICE`, `SPARC_STRUCTURED_LOGGING`).

### The drift check

Reads the real task definition, compares against the real compiled defaults by calling
the accessors with the variable unset. No second source of truth — a default changed in
code is picked up automatically. Reports three things: entries restating a default,
entries set to `""` over a real default, and variables nothing reads any more.

It is an **on-demand audit**, not a default-suite spec:

```bash
SPARC_DRIFT_CHECK=1 bundle exec rspec spec/config
```

It reports work pending in a *sibling* repo (trimming the task definition), so failing
our suite over sparc-iac's backlog would be reporting someone else's to-do list as our
breakage. Wiring it into CI is a follow-up once the trim lands.

**Current audit: 15 redundant entries** — including `SPARC_MAX_UPLOAD_MB=100`,
`SPARC_RATE_LIMIT_UPLOADS_PER_5MIN_PER_IP=60` and
`SPARC_RATE_LIMIT_LOGIN_FAILURES_PER_MIN=3`, which became redundant *because of the
default bumps made in this release*. The check earning its keep on day one.

It also found `SPARC_AUTHORITATIVE_FETCH_ENABLED` reading raw `ENV` with no accessor —
a gap that inspection had missed.

### Remaining (Pass 2, not started)

Collapse `SPARC_DB_*` → `DATABASE_URL` (needs `database.yml` ERB to derive
cache/queue/cable — see the verified finding above), derive `SPARC_FIDO2_RP_ID` /
`RP_NAME`, deprecate `SPARC_AWS_REGION`, and the sparc-iac task-definition trim
(sparc-iac#566 covers layer 1 of the TLS work; the trim itself is separate).

---

# Pass 2 — record

Branch `785-config-pass2`, off main after PR #789 merged (v1.13.1). Same discipline as
Pass 1: nothing lands without verification, and the highest-risk change is proven against a
live container, not just a test harness.

## `SPARC_DB_*` → `DATABASE_URL` (the load-bearing change)

`database.yml` now derives **all four** databases from `DATABASE_URL`, with `SPARC_DB_*`
kept as a fully supported fallback. This is the change that could have bricked production —
Rails merges `DATABASE_URL` into `primary` only, so the cache/queue/cable secondaries had
to be derived explicitly or they would silently repoint at `localhost` with no password.

| Decision | Why |
|---|---|
| Parse with Rails' own `ActiveRecord::…::ConnectionUrlResolver` | Guarantees the secondaries decode **identically** to how Rails resolves `primary` — same percent-decoding of passwords. Hand-rolled URI parsing would risk the secondaries authenticating with a wrong password on any special-char password. Proven with a `%40`→`@` case |
| All logic in `lib/db_url/config.rb`, `database.yml` uses inline `<%= DbUrl.* %>` only | A first draft used a multi-line `<% %>` block and **broke raw-YAML parseability** — the exact regression class #788 exists for, caught by the Pass 1 spec. Helper required from `application.rb` (the logging-formatter pattern) so `DbUrl` exists when `database.yml` renders |
| `SPARC_DB_*` stays a fallback, not removed | "Not required" ≠ "deleted." Existing deployments that set `SPARC_DB_*` keep working unchanged |

**Proof — live UBI9 container, `DATABASE_URL` only, no `SPARC_DB_*`** (`docker-compose.dburl.yaml`):

```
primary  host=db db=ssp_tpr_manager_production        user=postgres
cache    host=db db=ssp_tpr_manager_production_cache  user=postgres
queue    host=db db=ssp_tpr_manager_production_queue  user=postgres
cable    host=db db=ssp_tpr_manager_production_cable  user=postgres
```

All four created and connected from one URL; **`tests/api` 363 passed** in this mode, which
exercises the secondaries for real (SolidQueue→queue, SolidCache→cache). The `SPARC_DB_*`
fallback path (base compose) still boots — backward-compat confirmed.

`spec/lib/db_url_config_spec.rb` (13 examples) pins: URL derivation, special-char password
decode, secondary suffixes, DATABASE_URL-wins-over-`SPARC_DB_*`, the `SPARC_DB_*` fallback,
the legacy `SSP_TPR_MANAGER_DATABASE_PASSWORD` alias, malformed-URL resilience, and
raw-YAML parseability of all four databases.

## FIDO2 RP derivation

- `SPARC_FIDO2_RP_NAME` now defaults to `SPARC_APP_NAME` (was a hardcoded `"SPARC"`), so a
  branded instance gets a matching security-key prompt for free. Explicit override retained.
- `SPARC_FIDO2_RP_ID` needed **no change** — the WebAuthn gem already derives it from the
  origin host, so it was already not-required. Documented in `webauthn.rb`.

## `SPARC_AWS_REGION` deprecation

Now a **silent alias** for `AWS_REGION` (`SPARC_AWS_REGION` → `AWS_REGION` → `us-east-1`,
each `.presence`-guarded). The one app-layer stray read (`admin_credential_rotation_service`)
is routed through `SparcConfig.aws_region`; the two pre-autoload initializers
(`00_aws_secrets`, `aws_db_auth`) keep inline `ENV` reads (they cannot call `SparcConfig`).
To be removed from the documented vocabulary in the docs update.

## Still open in Pass 2

- Docs: mark `SPARC_AWS_REGION` deprecated in `ENVIRONMENT_VARIABLES.md`; note that
  `SPARC_FIDO2_RP_NAME`/`_RP_ID` are derived.
- `DB_CREDENTIALS` secret in the task def overlaps `DATABASE_URL` — a **sparc-iac** concern
  (secrets delivery), out of app scope; flag for the trim.
- SMTP port-465-vs-STARTTLS (carried from Pass 1) — still needs prod delivery confirmation.
