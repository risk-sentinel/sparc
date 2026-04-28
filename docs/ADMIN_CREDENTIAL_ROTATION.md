# Admin Credential Rotation

How to rotate the SPARC instance admin password — automatically from AWS Secrets Manager (via a scheduled Lambda), manually from inside the running container (rake task), or by restarting the ECS task after an out-of-band password change.

This document is for instance admins, ops engineers, and anyone deploying SPARC on ECS Fargate. For the developer-focused architecture and NIST control mapping, see [`dev/admin_credential_rotation.md`](dev/admin_credential_rotation.md).

---

## TL;DR

| You want to… | Use this path |
|---|---|
| Schedule automatic rotation (recommended) | **Path A — Lambda** |
| Force-rotate right now from inside SPARC | **Path B — rake task** |
| Recover after manually editing SM admin-credentials | **Path C — restart the ECS task** |

All three paths converge on the same source of truth: AWS Secrets Manager `admin-credentials` AWSCURRENT.

---

## Architecture

```
                    AWS Secrets Manager
                  (admin-credentials)        ◀── Lambda writes (Path A — automated)
                          │                  ◀── SPARC writes (Path B — rake task)
                          │
                  ECS task definition
                   secrets injection
                          │
                          ▼
                ENV["SPARC_ADMIN_PASSWORD"]
                          │
                          ▼
                 sparc:bootstrap_admin
                  (runs at task start)
                          │
                          ▼
                  users.password_digest
                       (bcrypt)
```

**Source of truth:** AWS Secrets Manager `admin-credentials` AWSCURRENT.
The DB is a materialized cache that boot reconciliation keeps in sync.

**Trust boundary preserved:** SPARC's ECS task role does **not** have direct read access (`GetSecretValue`) on `admin-credentials`. ECS does the read on SPARC's behalf and hands the plaintext to the container as an env var. Console retrieval of the secret remains MFA-gated for break-glass.

---

## Quick start (new SPARC deployment)

These steps assume a fresh SPARC deployment on ECS Fargate with sparc-iac provisioned per the [#197 contract](https://github.com/Rebel-Raiders/sparc-iac/issues/197).

1. **Convert `admin-credentials` to JSON form** (one-time, only if it's currently plaintext):
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id sparc-{env}/admin-credentials \
     --secret-string '{"password":"<your-existing-plaintext>"}'
   ```
2. **Deploy the SPARC image** that includes this feature.
3. **First task start** — `bootstrap_admin` reads `SPARC_ADMIN_PASSWORD` from env (ECS-injected from SM) and creates/updates the admin user.
4. **Log in** to SPARC with the email from `SPARC_ADMIN_EMAIL` and the password from `admin-credentials`. You'll be prompted to change it; the rotation system tracks the underlying admin password regardless of UI changes.
5. **Enable the API endpoint** for Lambda-driven rotation:
   ```
   SPARC_ADMIN_REFRESH_ENABLED=true
   ```
   Without this, Path A returns 503.
6. **Create the rotation service account** (one-time — see [Path A setup](#path-a-setup) below).

---

## Path A — Lambda-driven (recommended steady-state)

EventBridge schedule invokes a Lambda that generates a new password, writes it to AWS Secrets Manager, calls SPARC's API endpoint to update the running task's DB, then promotes AWSPENDING → AWSCURRENT.

### How it works

```
1. Lambda generates new password
2. Lambda → SM put_secret_value (VersionStage: AWSPENDING)
3. Lambda → SPARC POST /api/v1/admin/refresh_credentials with the plaintext
4. SPARC bcrypts to DB, writes audit row, returns 200
5. Lambda → SM update_secret_version_stage (AWSPENDING → AWSCURRENT)
```

If step 5 fails after step 4 succeeded, SPARC's DB is "ahead" of SM AWSCURRENT until the orphan AWSPENDING is promoted. See [Troubleshooting](#troubleshooting).

### Path A setup

**One-time setup (per environment):**

1. **Create the rotation service account** in SPARC.

   Via Admin UI: Service Accounts → New
   - Email/display name: `rotation-lambda@sparc.local`
   - Owner: any instance admin (for accountability)
   - Role: a role with the `admin.rotate_credentials` permission

   Save the resulting `sparc_sa_<long-hex>` token **once** — it's only displayed at creation. (If you lose it, regenerate from the same admin UI.)

   **Recommended hardening on the token:**

   | Field | Value | Why |
   |---|---|---|
   | `allowed_endpoints` | `["/api/v1/admin/refresh_credentials"]` | Token can only call the rotation endpoint |
   | `allowed_cidrs` | `["<Lambda NAT egress IP>/32"]` | Rejects requests from anywhere else |
   | `expires_at` | 1 year out | Forces annual rotation of the rotation token itself |

2. **Provision the rotation Lambda's SM secret** (sparc-iac side — see [#197](https://github.com/Rebel-Raiders/sparc-iac/issues/197)):
   ```bash
   aws secretsmanager create-secret \
     --name sparc-{env}/rotation-lambda-token \
     --secret-string '<sparc_sa_token>' \
     --kms-key-id <customer-managed-kms-arn>
   ```

3. **Deploy the rotation Lambda** with the IAM policy and code documented in sparc-iac #197. The Lambda needs:
   - `secretsmanager:GetSecretValue` on `rotation-lambda-token`
   - `secretsmanager:Get/Put/UpdateStage/Describe/GetRandomPassword` on `admin-credentials`
   - `execute-api:Invoke` on the SPARC API route

4. **Set `SPARC_ADMIN_REFRESH_ENABLED=true`** on the SPARC ECS task definition.

5. **Schedule the Lambda** via EventBridge — quarterly is a reasonable default:
   ```
   cron(0 6 1 */3 ? *)   # 6am UTC, 1st of every 3rd month
   ```

6. **Wire up CloudWatch alarms** for Lambda failures — manual completion of an aborted rotation is a one-Console-click operation but you need to know about it.

### Triggering Path A manually (for ad-hoc rotation or test)

```bash
aws lambda invoke \
  --function-name sparc-{env}-admin-credential-rotation \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/lambda-out.json && cat /tmp/lambda-out.json
# Expect: {"status":"rotated","version_id":"<uuid>"}
```

---

## Path B — Inside-SPARC rake task (break-glass / manual ops)

Generates a new password locally, writes it to SM via `PutSecretValue` (promoting to AWSCURRENT directly), updates the DB, and writes an audit row. Operator retrieves the new password from the AWS Console.

### When to use

- Lambda unavailable and rotation can't wait
- Forensic incident response — you want one bounded operation, not a multi-step Lambda flow
- Initial seed of `admin-credentials` after a fresh deployment

### How

ECS Exec into the running container:

```bash
aws ecs execute-command --cluster sparc-{env} \
  --task <task-id> --container app --interactive \
  --command "/bin/bash"
```

Inside the container:

```bash
bundle exec rails sparc:rotate_admin_credentials
```

Output:
```
============================================================
  SPARC Admin Credentials Rotated
============================================================
  Version ID: a1b2c3d4-...
  Password:   [retrieve from Secrets Manager via AWS Console]
============================================================
```

**Outside production**, set `SPARC_ALLOW_CRED_ROTATION=1` first to permit the task. **Break-glass scenarios** where the password must be printed to stdout: set `SPARC_PRINT_ROTATED_PASSWORD=1` — be mindful of log retention.

### What it requires (sparc-iac side)

- ECS task role IAM policy includes `secretsmanager:PutSecretValue` + `UpdateSecretVersionStage` on `admin-credentials` (write-only — see [#197](https://github.com/Rebel-Raiders/sparc-iac/issues/197))
- `SPARC_ADMIN_CREDENTIALS_SECRET_ARN` env var set on the task definition

---

## Path C — Out-of-band SM edit + ECS task restart

Useful when:
- An ops engineer has manually edited `admin-credentials` via the AWS Console
- Recovery from a Lambda partial-failure where SM AWSCURRENT was promoted but SPARC's DB never received the new value
- Rebuilding from a snapshot

### How

Just restart the ECS task:

```bash
aws ecs update-service --cluster sparc-{env} \
  --service sparc-{env}-app --force-new-deployment
```

On the new task's startup:
1. ECS reads SM AWSCURRENT, injects as `SPARC_ADMIN_PASSWORD`
2. `bootstrap_admin` runs, sees DB digest doesn't match env, syncs DB
3. Audit row written: `admin_credential_synced_from_env`
4. CloudWatch shows: `[AdminBootstrap] Synced admin password from SPARC_ADMIN_PASSWORD env (rotation detected).`

---

## Initial setup checklist

Use this when standing up SPARC on ECS Fargate for the first time, or when retrofitting an existing deployment to use the rotation system.

### SPARC side

- [ ] Deploy SPARC image that includes the rotation feature
- [ ] Set `SPARC_ADMIN_EMAIL` to your admin's email (defaults to `admin@sparc.local`)
- [ ] Set `SPARC_ADMIN_REFRESH_ENABLED=true` to enable the API endpoint
- [ ] Create the rotation service account with the `admin.rotate_credentials` permission
- [ ] Capture the `sparc_sa_*` token at creation time (only shown once)

### Sparc-iac side (per [#197](https://github.com/Rebel-Raiders/sparc-iac/issues/197))

- [ ] Convert `admin-credentials` SM secret to JSON form (`{"password":"..."}`)
- [ ] Add `SPARC_ADMIN_PASSWORD` to ECS task definition `secrets:` block, sourced from `admin-credentials:password::`
- [ ] Update ECS task role IAM policy: add `PutSecretValue` + `UpdateSecretVersionStage` on `admin-credentials` (do **not** add `GetSecretValue` for it)
- [ ] Create `rotation-lambda-token` SM secret, store the `sparc_sa_*` token, KMS-encrypt with a customer-managed key
- [ ] Deploy the rotation Lambda function with its IAM policy
- [ ] Wire EventBridge schedule (e.g., quarterly)
- [ ] Wire CloudWatch alarm on Lambda failures with SNS-to-ops alerting

### Verification

- [ ] Run [Test Layer 1](#layer-1-curl-from-your-laptop) to confirm SPARC's endpoint works
- [ ] Run [Test Layer 2](#layer-2-lambda-invoked-manually) to confirm the Lambda → SPARC integration
- [ ] Run [Test Layer 3](#layer-3-ecs-restart-after-sm-rotation) to confirm boot reconciliation works
- [ ] Run [Test Layer 4](#layer-4-rake-task) to confirm the rake-task path works

---

## Testing

Four layers, run in order. Each layer adds one piece of the chain so failures isolate cleanly.

### Layer 1: curl from your laptop

Sanity-checks the SPARC endpoint and the service account token. Doesn't involve AWS or the Lambda at all.

```bash
TOKEN="sparc_sa_..."           # the rotation service account token
SPARC_URL="https://staging.sparc.example.gov"
NEW_PW="TestRotation-$(date +%s)"

# Negative — feature disabled (run before setting SPARC_ADMIN_REFRESH_ENABLED)
curl -sS -X POST "$SPARC_URL/api/v1/admin/refresh_credentials" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$NEW_PW\"}"
# Expect: 503 {"error":"Admin credential refresh endpoint is disabled..."}

# Negative — missing token
curl -sS -X POST "$SPARC_URL/api/v1/admin/refresh_credentials" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$NEW_PW\"}"
# Expect: 401

# Negative — missing password
curl -sS -X POST "$SPARC_URL/api/v1/admin/refresh_credentials" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{}'
# Expect: 422 {"error":"password is required"}

# Positive — rotate
curl -sS -X POST "$SPARC_URL/api/v1/admin/refresh_credentials" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$NEW_PW\"}"
# Expect: 200 {"status":"ok","audit_event_id":<int>,"rotated_at":"<iso8601>"}

# Idempotent — same value submitted twice
curl -sS -X POST "$SPARC_URL/api/v1/admin/refresh_credentials" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$NEW_PW\"}"
# Expect: 200 {"status":"unchanged",...}
```

Then log into the SPARC UI with `admin@...` and `$NEW_PW` — should succeed.

This proves SPARC accepts the token, bcrypts the new password, and the running task uses it for auth — without any AWS / Lambda involvement.

### Layer 2: Lambda invoked manually

After sparc-iac #197 deploys:

```bash
aws lambda invoke \
  --function-name sparc-{env}-admin-credential-rotation \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/lambda-out.json && cat /tmp/lambda-out.json
# Expect: {"status":"rotated","version_id":"<uuid>"}
```

Verify on the SPARC side. In CloudWatch Logs, look for:

```
[AdminCredential...] ...
audit_event: {"action":"admin_credential_rotated","metadata":{"source":"api",...}}
```

In the SPARC Rails console:

```ruby
AuditEvent.where(action: "admin_credential_rotated").order(:id).last
# → metadata: { source: "api", actor_token_id: <int>, ... }

User.find_by(email: ENV["SPARC_ADMIN_EMAIL"]).password_changed_at
# → recent
```

In the AWS Console:

- `admin-credentials` secret should show a new AWSCURRENT version with a recent `LastChangedDate`
- The Lambda's CloudWatch Logs should show `Rotated` (or your equivalent message)

Try logging into SPARC with the new password — retrieve from SM Console.

### Layer 3: ECS restart after SM rotation

Tests the case where rotation happens while SPARC is unavailable, or when an operator manually edits the SM secret.

```bash
# 1. Manually rotate via Console / CLI
aws secretsmanager put-secret-value \
  --secret-id sparc-{env}/admin-credentials \
  --secret-string '{"password":"OutOfBand-Rotation-Test"}'

# 2. Force ECS task restart
aws ecs update-service --cluster sparc-{env} \
  --service sparc-{env}-app --force-new-deployment

# 3. Watch the new task's CloudWatch logs for:
#    [AdminBootstrap] Synced admin password from SPARC_ADMIN_PASSWORD env (rotation detected).
#    audit_event: action="admin_credential_synced_from_env"

# 4. Log in to SPARC UI with: admin@... + OutOfBand-Rotation-Test → should succeed
```

This proves rotations performed in SM while SPARC wasn't running propagate into the DB on next start.

### Layer 4: rake task

ECS Exec into the running container, then:

```bash
bundle exec rails sparc:rotate_admin_credentials
```

Expect:
```
============================================================
  SPARC Admin Credentials Rotated
============================================================
  Version ID: <uuid>
  Password:   [retrieve from Secrets Manager via AWS Console]
============================================================
```

In another shell, verify SM was updated:

```bash
aws secretsmanager get-secret-value \
  --secret-id sparc-{env}/admin-credentials \
  --query SecretString --output text
# → JSON {"password":"<new-value>"}
```

Log in to SPARC with the new value.

---

## Configuration reference

| Variable | Default | Set on | Purpose |
|---|---|---|---|
| `SPARC_ADMIN_EMAIL` | `admin@sparc.local` | SPARC ECS env | Email of the admin user the rotation paths target |
| `SPARC_ADMIN_PASSWORD` | _(unset)_ | SPARC ECS secrets | ECS-injected from SM `admin-credentials`. `bootstrap_admin` reconciles DB on container start. |
| `SPARC_ADMIN_CREDENTIALS_SECRET_ARN` | _(unset)_ | SPARC ECS env | ARN of the SM secret. Required for the rake-task `PutSecretValue` write-back. |
| `SPARC_AWS_REGION` | `AWS_REGION` or `us-east-1` | SPARC ECS env | Region for the SM client used by the rake task |
| `SPARC_ADMIN_REFRESH_ENABLED` | `false` | SPARC ECS env | Set `true` to enable `POST /api/v1/admin/refresh_credentials` (otherwise 503 — fail closed) |
| `SPARC_ALLOW_CRED_ROTATION` | _(unset)_ | Operator shell | Set `1` to permit `sparc:rotate_admin_credentials` outside production |
| `SPARC_PRINT_ROTATED_PASSWORD` | _(unset)_ | Operator shell | Set `1` to print rotated password from rake task — break-glass only |

---

## Audit events

Every rotation event produces one or more rows in `audit_events`:

| `action` | When emitted | Notable metadata |
|---|---|---|
| `admin_bootstrap` | First boot creates or initializes the admin user | `source: "ecs_secrets_injection"` or `"generated"` |
| `admin_credential_synced_from_env` | Boot reconciliation detected drift between env and DB (Path C) | `source: "ecs_secrets_injection"` |
| `admin_credential_rotated` | Rake task or API endpoint mutated the password (Path A or B) | `source: "rake"` or `"api"`, `version_id`, `actor_id` / `actor_token_id`, optional `outcome: "unchanged"` |
| `admin_password_reset` | Manual reset via `sparc:reset_admin_password` rake | (none) |

**The plaintext password is never written to any audit row, log line, HTTP response, or notification.**

---

## Troubleshooting

### Decision tree

| Symptom | Most likely cause | Where to look |
|---|---|---|
| Layer-1 curl returns 401 | Bearer token wrong or expired | `ApiToken.find_by(...).expires_at` in SPARC console; regenerate from admin UI |
| Layer-1 curl returns 403 with "lacks admin.rotate_credentials" | Service account's role doesn't have the permission | Admin UI → Roles → check the permission box |
| Any path returns 503 "endpoint is disabled" | `SPARC_ADMIN_REFRESH_ENABLED` not set on the task | Update the task definition env vars |
| Lambda returns 200 but next ECS restart undoes the change | AWSPENDING never got promoted to AWSCURRENT (Lambda crashed mid-flight) | Check Lambda CloudWatch logs for failure after step 5 of the rotation flow; manually promote AWSPENDING via Console |
| `[AdminBootstrap] Synced...` doesn't appear after restart | `SPARC_ADMIN_PASSWORD` env var not set on the task | sparc-iac #197 task-def `secrets:` block not yet deployed |
| Rake task fails with "ECS task role lacks PutSecretValue" | sparc-iac IAM delta not yet deployed | Inspect the task role in IAM Console; add the policy from #197 |
| Rake task fails with "SPARC_ADMIN_CREDENTIALS_SECRET_ARN is not set" | Env var missing on the task definition | Add it to the task definition env block |
| Admin can't log in after rotation | DB and SM AWSCURRENT have drifted | See [Drift recovery](#drift-recovery) below |
| Two rotations within seconds — second one shows old password | Race between Lambda rotation and rake | AWS guarantees one AWSCURRENT — check the Console for which version "won"; restart the ECS task to re-sync |

### Drift recovery

If admin can't log in and you suspect drift between DB and SM AWSCURRENT:

1. **Identify the most recent rotation events.** In the SPARC Rails console:
   ```ruby
   AuditEvent.where(action: %w[admin_credential_rotated admin_credential_synced_from_env])
             .order(created_at: :desc).limit(5)
   ```
   Note the `metadata.source` and `metadata.version_id` of each.

2. **Check SM versions:**
   ```bash
   aws secretsmanager describe-secret \
     --secret-id sparc-{env}/admin-credentials \
     --query 'VersionIdsToStages'
   ```
   You'll see something like:
   ```json
   {
     "v-aaa": ["AWSCURRENT"],
     "v-bbb": ["AWSPREVIOUS"],
     "v-ccc": ["AWSPENDING"]
   }
   ```

3. **Pick the version that should be current.** Usually the most recent rotation, but check the `LastAccessedDate` on each version to confirm.

4. **Promote it:**
   ```bash
   aws secretsmanager update-secret-version-stage \
     --secret-id sparc-{env}/admin-credentials \
     --version-stage AWSCURRENT \
     --move-to-version-id <chosen-version>
   ```

5. **Restart the ECS task** to force boot reconciliation:
   ```bash
   aws ecs update-service --cluster sparc-{env} \
     --service sparc-{env}-app --force-new-deployment
   ```

6. **Confirm** by logging in with the password from the now-current version.

If none of the SM versions match a working password, you've lost the admin credentials — use **Path B** (rake task) inside the running container to generate and persist a fresh one, then retrieve it from SM.

---

## Security model

| Property | How it's enforced |
|---|---|
| Plaintext password never on disk in SPARC | Only `password_digest` (bcrypt) is stored; plaintext exists only in memory during the rotation request |
| Plaintext never logged | `config.filter_parameters` filters `:passw` from Rails logs; audit rows record `version_id` only, never the password |
| API endpoint not exposed without explicit opt-in | `SPARC_ADMIN_REFRESH_ENABLED=false` by default — endpoint returns 503 |
| Only the rotation Lambda can call the endpoint | Service account Bearer token + endpoint scoping (`allowed_endpoints`) + CIDR allowlist (`allowed_cidrs`) — all three layers from #257 |
| Rotation token compromise has bounded blast radius | Token can only invoke the rotation endpoint, only from the Lambda's NAT IP, only for the configured TTL — and rotating the rotation token is a one-line operation |
| SPARC compromise can't read SM admin-credentials directly | SPARC's task role has `PutSecretValue` (write-only), not `GetSecretValue` for that secret; ECS does the read on SPARC's behalf and only at task start |
| MFA-gated break-glass retrieval preserved | `admin-credentials` is still retrieved via AWS Console with whatever IAM/MFA wall your sparc-iac stack puts around Secrets Manager Console access |
| Audit trail of every rotation | `AuditEvent` rows capture actor (user or service-account token id), source (rake/api/ecs_secrets_injection), version_id, and timestamp |
| Idempotent against retries | Submitting the same plaintext twice returns 200/`unchanged` — Lambda or operator can safely retry without re-rotating |

---

## Related documentation

- **[`dev/admin_credential_rotation.md`](dev/admin_credential_rotation.md)** — developer-focused architecture and NIST control mapping
- **[`SPARC_HASH_ROTATION.md`](SPARC_HASH_ROTATION.md)** — sibling runbook for rotating the `SPARC_HASH` master secret that protects encrypted federation peer credentials
- **[`AUTHENTICATION.md`](AUTHENTICATION.md)** — overall SPARC authentication model (local login, OIDC, LDAP)
- **[`API.md`](API.md)** — full SPARC API reference
- **[`ENVIRONMENT_VARIABLES.md`](ENVIRONMENT_VARIABLES.md)** — every SPARC env var
- **[`compliance/nist-sp800-53-rev5-mapping.md`](compliance/nist-sp800-53-rev5-mapping.md)** — NIST 800-53 Rev 5 control mapping (search "Admin Credential Rotation")
- **[Rebel-Raiders/sparc-iac#197](https://github.com/Rebel-Raiders/sparc-iac/issues/197)** — sparc-iac counterpart (task-def secrets injection + IAM delta + rotation Lambda)
- **SPARC issues [#402](https://github.com/Rebel-Raiders/sparc/issues/402) and [#403](https://github.com/Rebel-Raiders/sparc/issues/403)** — the original feature requests

---

## FAQ

**Q: Do I need all three rotation paths to use this feature?**
A: No. Path C (boot reconciliation) is automatic and always works. Path A (Lambda) is the recommended steady-state for any production deployment that wants scheduled rotation. Path B (rake task) is a break-glass tool — useful but not essential. You can deploy with just Path C and add A/B later.

**Q: What happens if I lose the rotation Lambda's service account token?**
A: Regenerate it from the SPARC admin UI (Service Accounts → the rotation account → Regenerate Token), update the value in the `rotation-lambda-token` SM secret, no other action needed. The Lambda fetches the token at invoke time so the next invocation picks up the new value.

**Q: Can I disable rotation entirely?**
A: Yes, in two ways. Either don't deploy the Lambda (Path A is opt-in), or set `SPARC_ADMIN_REFRESH_ENABLED=false` to gate the endpoint at the SPARC level. Path C (boot reconciliation) only fires if `SPARC_ADMIN_PASSWORD` is set and differs from the DB — if you don't inject it from SM, that path is dormant too.

**Q: How often should I rotate?**
A: Quarterly is a reasonable starting point for compliance baselines. The mechanism is cheap enough to run more often if your policy requires it; the only real cost is the audit-log volume and the brief blip while the next admin login forces a password change.

**Q: Does rotating the admin password affect any other accounts?**
A: No. This rotates only the user record identified by `SPARC_ADMIN_EMAIL`. All other users — federated OIDC users, LDAP users, other local accounts, all service accounts — are unaffected.

**Q: What if my SPARC instance has multiple admins?**
A: Only the user matching `SPARC_ADMIN_EMAIL` is rotated. Other admin users are managed normally through the SPARC admin UI. If you need rotation for additional admins, that's a feature request — file an issue.

**Q: Can the Lambda push a password without going through SPARC's API?**
A: Yes — the Lambda could write to SM AWSCURRENT directly and rely on Path C (ECS task restart to pick it up). But that requires a task restart, which causes a brief unavailability. The API path (Path A) propagates the change without restarting.

**Q: What's the relationship between `SPARC_ADMIN_PASSWORD` and `admin-credentials`?**
A: ECS reads `admin-credentials` AWSCURRENT and injects it as `SPARC_ADMIN_PASSWORD` into the SPARC container at task start. SPARC never sees the SM secret directly — only the env var that ECS materialized from it.

**Q: How do I migrate an existing deployment to this rotation system?**
A: Three steps. (1) Convert the existing `admin-credentials` secret to JSON form with one `put-secret-value` call. (2) Land the sparc-iac changes (#197). (3) Deploy the SPARC image that includes this feature. After the next ECS restart, Path C is automatically active. Add Lambda (Path A) when ready.
