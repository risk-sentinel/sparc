# #785 — Configuration Reduction Plan

**Status:** plan agreed 2026-07-22. Supersedes the earlier "config manifest + registry"
design, which was **rejected** — it added a second source of truth duplicating the 120
accessors already in `app/models/sparc_config.rb` (the tell: it needed a
"manifest↔accessor parity" spec), and it catalogued variables instead of reducing them.

## The problem

`sparc-iac/AWS/ECS/envs/prod/sparc-task-definition.json` sets **97 `environment` + 10
`secrets`**. Values live in the task definition (sparc-iac); defaults live in Ruby
(`SparcConfig`, in sparc). **Nothing ever compares the two**, so the task definition has
accumulated ~50 entries that either restate a default, are empty no-ops, or are read by
nothing at all.

Measured config surface for context: 146 distinct ENV keys referenced repo-wide, 120
`SparcConfig` accessors, and **exactly one** accessor with no default. Nobody actually
has to set 135 variables — but the task definition makes it look that way.

sparc-iac continues to own and manage its task definition. This plan defines the
requirements it renders from.

## Principle: eliminate the *requirement*, keep the *override*

Where a value is really a tuning knob (upload sizes, API rate limits), we bump the app
default to the production value and delete the line from the task definition. The
variable keeps working as an override — it is simply no longer required. Nothing is
removed from the app's configuration vocabulary.

## Two passes

**Pass 1 — eliminate and just set it.** Delete redundant / empty / dead / no-op entries;
adopt production values as defaults; infer `enable` flags from credential presence; fix
two live defects.

**Pass 2 — consolidate and auto-resolve.** Derive values that are computable from others
(OIDC redirect URI, FIDO2 RP ID, API audience) and collapse the six `SPARC_DB_*` vars
into `DATABASE_URL`.

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
databases** — deleting it and relying on `DATABASE_URL` alone would silently repoint them
at the `ssp_tpr_manager_production_*` fallbacks. Collapsing to one DB variable requires
`database.yml` to parse `DATABASE_URL` in ERB and derive the secondaries. That is Pass 2
and it is a real code change.

**Three dead variables** — zero references anywhere in the repo:
`HTTP_PORT`, `RAILS_SERVE_STATIC_FILES`, and `ACTIVE_STORAGE_SERVICE`. The last is the
notable one: `production.rb:151` hardcodes `config.active_storage.service = :amazon`, so
the operator appears to be selecting a storage backend via a variable nothing reads.

**Two live defects, both caused by setting `""` over a working default:**

1. `SPARC_DISA_CCI_URL=""` overrides the DoD CCI zip URL default — actively breaking that fetch.
2. `SPARC_API_OIDC_AUDIENCE=""` defeats an existing derivation. The read site is already
   `ENV.fetch("SPARC_API_OIDC_AUDIENCE", SparcConfig.oidc_client_id)`; an empty string is
   not `nil`, so the fallback never fires.

## Reconciliation: a drift check, not a manifest

A spec that loads the task-definition JSON, compares each value against the compiled
default, and **fails when an entry is redundant**. That is what stops the file re-growing
to 97, and it works across both repos without a second source of truth.

Open: which repo hosts it. Lean is `sparc` — that is where the defaults change and where
RSpec already runs; it needs a path to (or a checked-in copy of) the task-definition JSON.

---

## Master chart — all 97 `environment[]` entries

| Variable | Value set today | Disposition | Target / new default | Rationale |
|---|---|---|---|---|
| `ACTIVE_STORAGE_SERVICE` | `amazon` | **DELETE** |  | **DEAD** — zero refs; production.rb:151 hardcodes `:amazon` |
| `FORCE_SSL` | `true` | **DELETE** |  | Value identical to app default |
| `HTTP_PORT` | `${rails_port}` | **DELETE** |  | **DEAD** — zero references repo-wide |
| `MALLOC_ARENA_MAX` | `2` | **DELETE** |  | Already baked into Dockerfile:105 |
| `RAILS_SERVE_STATIC_FILES` | `false` | **DELETE** |  | **DEAD** — zero references repo-wide |
| `SOLID_QUEUE_IN_PUMA` | `true` | **DELETE** |  | entrypoint default is `${SOLID_QUEUE_IN_PUMA:-true}` |
| `SPARC_ALLOW_CRED_ROTATION` | `` | **DELETE** |  | Read site tests `== "1"`; set to "" — no-op |
| `SPARC_APP_NAME` | `SPARC` | **DELETE** |  | Value identical to app default |
| `SPARC_ARTIFACT_COPY_PER_VERSION` | `false` | **DELETE** |  | Value identical to app default |
| `SPARC_ARTIFACT_REAPER_PURGE` | `false` | **DELETE** |  | Value identical to app default |
| `SPARC_AUTHORITATIVE_FETCH_ENABLED` | `false` | **DELETE** |  | false == read-site default |
| `SPARC_AWS_IAM_DB_AUTH` | `false` | **DELETE** |  | Value identical to app default |
| `SPARC_AWS_LABS_CDEF_BRANCH` | `main` | **DELETE** |  | Value identical to app default |
| `SPARC_AWS_LABS_CDEF_REFRESH_INTERVAL_DAYS` | `7` | **DELETE** |  | Value identical to app default |
| `SPARC_AWS_LABS_CDEF_REPO` | `awslabs/oscal-content-for-aws-services` | **DELETE** |  | Value identical to app default |
| `SPARC_AWS_LABS_OSCAL_VERSIONS` | `` | **DELETE** |  | Set to "" where default is already nil — no-op |
| `SPARC_AWS_REGION` | `us-east-1` | **DELETE** |  | Triple-redundant: accessor falls back SPARC_AWS_REGION→AWS_REGION→us-east-1, and AWS_REGION is TF-injected. **Does not matter at app layer.** |
| `SPARC_CCI_REVS` | `4,5` | **DELETE** |  | Value identical to app default |
| `SPARC_ENABLE_LDAP` | `false` | **DELETE** |  | LDAP inert in prod (disabled, host/base/bind empty) — whole block is noise |
| `SPARC_ENABLE_USER_REGISTRATION` | `false` | **DELETE** |  | Value identical to app default |
| `SPARC_GITLAB_CLIENT_ID` | `` | **DELETE** |  | Empty; GitLab auto-disabled by presence-inference |
| `SPARC_GITLAB_SITE` | `https://gitlab.com` | **DELETE** |  | Value identical to app default |
| `SPARC_HEADER_HIGHLIGHT_COLOR` | `` | **DELETE** |  | Set to "" where default is already nil — no-op |
| `SPARC_HEADER_TEXT_COLOR` | `` | **DELETE** |  | Set to "" where default is already nil — no-op |
| `SPARC_INACTIVITY_DAYS` | `30` | **DELETE** |  | Value identical to app default |
| `SPARC_LDAP_ATTRIBUTE` | `sAMAccountName` | **DELETE** |  | LDAP inert in prod (disabled, host/base/bind empty) — whole block is noise |
| `SPARC_LDAP_BASE` | `` | **DELETE** |  | LDAP inert in prod (disabled, host/base/bind empty) — whole block is noise |
| `SPARC_LDAP_BIND_DN` | `` | **DELETE** |  | LDAP inert in prod (disabled, host/base/bind empty) — whole block is noise |
| `SPARC_LDAP_ENCRYPTION` | `simple_tls` | **DELETE** |  | LDAP inert in prod (disabled, host/base/bind empty) — whole block is noise |
| `SPARC_LDAP_HOST` | `` | **DELETE** |  | LDAP inert in prod (disabled, host/base/bind empty) — whole block is noise |
| `SPARC_LDAP_PORT` | `636` | **DELETE** |  | LDAP inert in prod (disabled, host/base/bind empty) — whole block is noise |
| `SPARC_LOG_LEVEL` | `info` | **DELETE** |  | Value identical to app default |
| `SPARC_MAX_AVATAR_MB` | `2` | **DELETE** |  | Value identical to app default |
| `SPARC_OIDC_SCOPES` | `openid profile email` | **DELETE** |  | Value identical to app default |
| `SPARC_ORG_ADDRESS` | `` | **DELETE** |  | Set to "" where default is already nil — no-op |
| `SPARC_ORG_CONTACT_PERSON` | `` | **DELETE** |  | Set to "" where default is already nil — no-op |
| `SPARC_PASSWORD_EXPIRY_DAYS` | `30` | **DELETE** |  | Value identical to app default |
| `SPARC_PRINT_ROTATED_PASSWORD` | `` | **DELETE** |  | Read site tests `== "1"`; set to "" — no-op |
| `SPARC_PROCESSING_STUCK_MINUTES` | `5` | **DELETE** |  | Value identical to app default |
| `SPARC_RATE_LIMITING_ENABLED` | `true` | **DELETE** |  | Value identical to app default |
| `SPARC_RESOURCES` | `` | **DELETE** |  | Set to "" where default is already nil — no-op |
| `SPARC_RUN_SEEDS` | `false` | **DELETE** |  | entrypoint default is `${SPARC_RUN_SEEDS:-false}` |
| `SPARC_SA_INACTIVITY_DAYS` | `90` | **DELETE** |  | Value identical to app default |
| `SPARC_SEED_MODE` | `full` | **DELETE** |  | Only read when RUN_SEEDS=true, which is false — dead in prod |
| `SPARC_SESSION_TIMEOUT_MINUTES` | `60` | **DELETE** |  | Value identical to app default |
| `SPARC_SKIP_DEFERRED_DATA_MIGRATIONS` | `false` | **DELETE** |  | false == read-site default |
| `SPARC_SMTP_STARTTLS_AUTO` | `true` | **DELETE** |  | Value identical to app default |
| `SPARC_WELCOME_TEXT` | `Welcome to SPARC` | **DELETE** |  | Value identical to app default |
| `SPARC_API_OIDC_AUDIENCE` | `` | **FIX + DELETE** |  | ⚠️ Read site already derives `ENV.fetch(..., SparcConfig.oidc_client_id)`; `""` is non-nil so it DEFEATS the derivation |
| `SPARC_DISA_CCI_URL` | `` | **FIX + DELETE** |  | ⚠️ `""` overrides a WORKING default (DoD CCI zip URL) with empty — actively breaking the fetch |
| `SPARC_DB_SSLMODE` | `require` | **DEFAULT** | prefer → **require in prod** | Security-correct prod default |
| `SPARC_LOG_TO_STDOUT` | `true` | **DEFAULT** | false → **true in prod** | Correct for any containerised deploy |
| `SPARC_MAX_UPLOAD_MB` | `100` | **DEFAULT** | 50 → **100** | Override retained, no longer required (DONE) |
| `SPARC_RATE_LIMIT_API_WRITES_PER_MINUTE` | `600` | **DEFAULT** | 300 → **600** | Override retained, no longer required |
| `SPARC_RATE_LIMIT_LOGIN_FAILURES_PER_MIN` | `3` | **DEFAULT** | 5 → **3** | Override retained, no longer required |
| `SPARC_RATE_LIMIT_UPLOADS_PER_5MIN_PER_IP` | `60` | **DEFAULT** | 30 → **60** | Override retained, no longer required |
| `SPARC_RATE_LIMIT_UPLOADS_PER_HOUR_PER_USER` | `500` | **DEFAULT** | 100 → **500** | Override retained, no longer required |
| `SPARC_STRUCTURED_LOGGING` | `true` | **DEFAULT** | false → **true in prod** | Correct for any containerised deploy |
| `SPARC_ENABLE_OIDC` | `true` | **INFER** | ← `SPARC_OIDC_CLIENT_ID` present | Matches existing `github_enabled?`/`gitlab_enabled?` pattern; kills 'enabled-but-unconfigured' |
| `SPARC_ENABLE_SMTP` | `true` | **INFER** | ← `SPARC_SMTP_ADDRESS` present | Same pattern |
| `SPARC_OIDC_REDIRECT_URI` | `https://sparc.risk-sentinel.org/auth/oid…` | **DERIVE** | ← `SPARC_APP_URL` + `/auth/oidc/callback` | Our URL, not the IdP's. Override retained |
| `SPARC_ORG_CONTACT_EMAIL` | `support.sparc@risk-sentinel.info` | **CONSOLIDATE** | → `SPARC_CONTACT_EMAIL` (support) | Identical value in prod today. Final state = 2 emails: admin + support |
| `SPARC_DB_HOST` | `${db_host}` | **CONSOLIDATE — Pass 2** | → `DATABASE_URL` | ⚠️ Load-bearing for cache/queue/cable (Rails merges DATABASE_URL into **primary only**). Requires database.yml ERB to parse DATABASE_URL and derive secondaries |
| `SPARC_DB_NAME` | `${db_name}` | **CONSOLIDATE — Pass 2** | → `DATABASE_URL` | ⚠️ Load-bearing for cache/queue/cable (Rails merges DATABASE_URL into **primary only**). Requires database.yml ERB to parse DATABASE_URL and derive secondaries |
| `SPARC_DB_PASSWORD` | `${db_password}` | **CONSOLIDATE — Pass 2** | → `DATABASE_URL` | ⚠️ Load-bearing for cache/queue/cable (Rails merges DATABASE_URL into **primary only**). Requires database.yml ERB to parse DATABASE_URL and derive secondaries |
| `SPARC_DB_PORT` | `${db_port}` | **CONSOLIDATE — Pass 2** | → `DATABASE_URL` | ⚠️ Load-bearing for cache/queue/cable (Rails merges DATABASE_URL into **primary only**). Requires database.yml ERB to parse DATABASE_URL and derive secondaries |
| `SPARC_DB_USER` | `${db_username}` | **CONSOLIDATE — Pass 2** | → `DATABASE_URL` | ⚠️ Load-bearing for cache/queue/cable (Rails merges DATABASE_URL into **primary only**). Requires database.yml ERB to parse DATABASE_URL and derive secondaries |
| `SPARC_ADMIN_REFRESH_ENABLED` | `true` | **DECIDE** | true (default false) | Bump default, or keep explicit? |
| `SPARC_API_AUTH` | `hybrid` | **DECIDE** | hybrid (default local) | Bump default to `hybrid`, or keep explicit as deployment policy? |
| `SPARC_OIDC_FORCE_MFA` | `true` | **DECIDE** | true (default false) | Recommend bumping default to `true` (security-positive) |
| `SPARC_REQUIRE_DOCUMENT_APPROVAL` | `true` | **DECIDE** | true (default false) | Bump default to `true`, or keep explicit as policy? |
| `SPARC_AWS_LABS_CDEF_ENABLED` | `true` | **KEEP** |  | Enables outbound fetch; defaulting on for everyone = behaviour change |
| `SPARC_BANNER_ENABLED` | `true` | **KEEP** |  | Deployment choice |
| `SPARC_BANNER_MESSAGE` | `public/banners/demo-banner.html` | **KEEP** |  | Required when banner enabled |
| `SPARC_ENABLE_LOCAL_LOGIN` | `true` | **KEEP** |  | Policy toggle — cannot be inferred |
| `SPARC_GITHUB_CLIENT_ID` | `Ov23liXGc1MJH1Oork8z` | **KEEP** |  | Credential; already the GitHub on-switch |
| `SPARC_HEADER_TEXT` | `SPARC — Testing / Demonstration Environm…` | **KEEP** |  | Environment banner text |
| `SPARC_OIDC_PROVIDER_TITLE` | `Okta` | **KEEP** |  | Login-button branding |
| `SPARC_ORG_DESCRIPTION` | `SPARC is supported by private developmen…` | **KEEP** |  | OSCAL org metadata |
| `SPARC_ORG_NAME` | `Risk Sentinel` | **KEEP** |  | OSCAL org metadata |
| `SPARC_SMTP_ADDRESS` | `smtp.mail.us-east-1.awsapps.com` | **KEEP** |  | Provider-specific; now also the SMTP on-switch |
| `SPARC_SMTP_AUTH` | `login` | **KEEP** | login (default plain) | Provider-specific |
| `SPARC_SMTP_FROM_ADDRESS` | `noreply@risk-sentinel.info` | **KEEP** |  | Provider-specific |
| `SPARC_SMTP_PORT` | `465` | **KEEP** | 465 (default 587) | Provider-specific |
| `SPARC_SMTP_USERNAME` | `sparc.admin@risk-sentinel.info` | **KEEP** |  | Provider-specific |
| `RAILS_ENV` | `production` | **KEEP — REQUIRED** |  | Framework |
| `SPARC_ADMIN_EMAIL` | `sparc.admin@risk-sentinel.info` | **KEEP — REQUIRED** |  | Canonical **admin** email. Add accessor; kills `admin@sparc.local` literal dup'd in 3 files |
| `SPARC_APP_URL` | `https://sparc.risk-sentinel.org` | **KEEP — REQUIRED** |  | Tier-0. Also the source for derived redirect/RP-ID |
| `SPARC_CONTACT_EMAIL` | `support.sparc@risk-sentinel.info` | **KEEP — REQUIRED** |  | Canonical **support** email (absorbs ORG_CONTACT_EMAIL) |
| `SPARC_OIDC_CLIENT_ID` | `0oa10sfxwbg3ygUxh698` | **KEEP — REQUIRED** |  | Credential; now also the OIDC on-switch |
| `SPARC_OIDC_ISSUER_URL` | `https://integrator-5342723.okta.com/oaut…` | **KEEP — REQUIRED** |  | IdP-specific |
| `AWS_BUCKET` | `${s3_bucket_name}` | **KEEP — TF** |  | Infra-derived |
| `AWS_REGION` | `${aws_region}` | **KEEP — TF** |  | Infra-derived; the one true region var |
| `DATABASE_URL` | `${database_url}` | **KEEP — TF** |  | Infra-derived. Primary DB. Pass 2 makes this the SOLE db var |
| `PORT` | `${rails_port}` | **KEEP — TF** |  | Infra-derived |
| `REDIS_URL` | `${redis_url}` | **KEEP — TF** |  | Infra-derived |
| `SPARC_ADMIN_CREDENTIALS_SECRET_ARN` | `${admin_credentials_secret_arn}` | **KEEP — TF** |  | Infra-derived ARN |

## `secrets[]` — all 10

| Secret | Disposition | Rationale |
|---|---|---|
| `DB_CREDENTIALS` | **REVIEW** | **REVIEW** — overlaps DATABASE_URL/SPARC_DB_PASSWORD; candidate for Pass 2 |
| `SECRET_KEY_BASE` | **KEEP** | **KEEP** — live credential |
| `SPARC_ADMIN_PASSWORD` | **KEEP** | **KEEP** — break-glass; executionRole-injected, taskRole has no access |
| `SPARC_AWS_LABS_GITHUB_TOKEN` | **KEEP** | **KEEP** — live credential |
| `SPARC_GITHUB_CLIENT_SECRET` | **KEEP** | **KEEP** — live credential |
| `SPARC_GITLAB_CLIENT_SECRET` | **DELETE** | **DELETE** — GitLab unconfigured (client_id empty), secret unused |
| `SPARC_HASH` | **KEEP** | **KEEP** — live credential |
| `SPARC_LDAP_BIND_PASSWORD` | **DELETE** | **DELETE** — LDAP inert in prod |
| `SPARC_OIDC_CLIENT_SECRET` | **KEEP** | **KEEP** — live credential |
| `SPARC_SMTP_PASSWORD` | **KEEP** | **KEEP** — live credential |

## Arithmetic

| Stage | Removed | Remaining |
|---|---|---|
| Today | — | **97** |
| Delete redundant / empty / dead / no-op | 50 | 47 |
| Bump defaults (override retained) | 8 | 39 |
| Infer + derive + consolidate | 4 | **35** |
| Pass 2: `SPARC_DB_*` → `DATABASE_URL` | 5 | **30** |

---

## Sequencing (both repos)

Order matters. Defaults must land in `sparc` **before** the task-definition trim in
`sparc-iac`, otherwise deleting a line reverts production to the old default.

1. **sparc** — bump defaults, add inference/derivation, add accessors, fix the two
   defects, add the drift check. (Pure additive; every existing full env still boots.)
2. **sparc-iac** — trim the task definition to the ~35 surviving entries.
3. **sparc** — Pass 2: `database.yml` ERB derives cache/queue/cable from `DATABASE_URL`.
4. **sparc-iac** — drop `SPARC_DB_*`.

The 50 pure deletions in step 2 are order-independent — the value is identical to the
default by definition, so they can ship first and separately if preferred.

## Open decisions

| # | Decision | Recommendation |
|---|---|---|
| 1 | Drift-check home: `sparc` or `sparc-iac`? | `sparc` |
| 2 | `SPARC_API_AUTH` — bump default to `hybrid`, or keep explicit? | Keep explicit (deployment policy) |
| 3 | `SPARC_REQUIRE_DOCUMENT_APPROVAL` — bump default to `true`? | Bump |
| 4 | `SPARC_OIDC_FORCE_MFA` — bump default to `true`? | Bump (security-positive) |
| 5 | `SPARC_ADMIN_REFRESH_ENABLED` — bump default to `true`? | Keep explicit |
| 6 | `.env.example` + `.env.production.example` → one tiered example file? | Yes, but secondary — does not solve reconciliation |
