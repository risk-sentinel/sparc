# Admin Credential Rotation Runbook (Developer Reference)

How the SPARC instance admin password stays in sync between AWS Secrets
Manager, the running ECS task, and the database — and how to rotate it.

> **Looking for setup, testing, and troubleshooting?** See the user-facing
> guide at [`docs/ADMIN_CREDENTIAL_ROTATION.md`](../ADMIN_CREDENTIAL_ROTATION.md).
> This document is the developer-focused architecture reference (NIST control
> mapping, code locations, rationale).

## Architecture

```
                    AWS Secrets Manager
                  (admin-credentials)        ◀── Lambda writes (rotation Lambda)
                          │                  ◀── SPARC writes (rake task path)
                          │
                  ECS task definition
                   secrets injection
                          │
                          ▼
                ENV["SPARC_ADMIN_PASSWORD"]   (SPARC's task role does NOT
                          │                    have GetSecretValue on this
                          │                    secret — ECS does the read
                          ▼                    on SPARC's behalf)
                 sparc:bootstrap_admin
                          │
                          ▼
                  users.password_digest
                       (bcrypt)
```

**Source of truth:** AWS Secrets Manager `admin-credentials` AWSCURRENT.
The DB is a materialized cache that boot reconciliation keeps in sync.

## Three rotation paths

### Path 1 — Lambda-driven (the steady-state automation)

1. EventBridge schedule fires the rotation Lambda (e.g., quarterly).
2. Lambda generates a new password (`secretsmanager:GetRandomPassword`).
3. Lambda writes it to SM with `VersionStages: ["AWSPENDING"]`.
4. Lambda fetches the SPARC service-account Bearer token from a separate
   SM secret only it can read.
5. Lambda `POST /api/v1/admin/refresh_credentials` with
   `{ "password": "<new plaintext>" }` and the Bearer token.
6. SPARC bcrypts the plaintext into `users.password_digest`, sets
   `must_reset_password: true`, writes an `AuditEvent`, returns 200.
7. Lambda promotes AWSPENDING → AWSCURRENT in SM.
8. On any subsequent ECS task restart, ECS injects the new SM AWSCURRENT
   value as `SPARC_ADMIN_PASSWORD`, and `bootstrap_admin` confirms the
   DB already matches (no-op).

If step 5 fails (4xx/5xx), Lambda leaves the AWSPENDING in place and
does **not** promote — rotation aborts cleanly.

If step 7 fails after step 5 succeeded, the DB is "ahead" of SM
AWSCURRENT until an operator promotes the orphaned AWSPENDING. The next
ECS task restart would reset DB to AWSCURRENT (old value) — see
"Failure recovery" below.

### Path 2 — Inside-SPARC rake task (break-glass / manual ops)

```bash
# Inside the running SPARC container (e.g., ECS Exec)
SPARC_ALLOW_CRED_ROTATION=1 bin/rails sparc:rotate_admin_credentials
```

The task generates a new password locally, writes to SM via
`PutSecretValue` (promoting to AWSCURRENT directly), updates the DB, and
writes an `AuditEvent`. Operator retrieves the new password from the AWS
Console for distribution to the admin.

`SPARC_ALLOW_CRED_ROTATION=1` is required outside production. For
break-glass scenarios where the password must be printed to stdout
(rare), set `SPARC_PRINT_ROTATED_PASSWORD=1` — be mindful of log
retention policies.

### Path 3 — First boot (initial bootstrap)

If `SPARC_ADMIN_PASSWORD` is set in env (sparc-iac provisioned it),
`bootstrap_admin` uses that value to set the initial admin password.
Otherwise it generates a random 20-char password and prints it to
stdout for the operator to capture.

## Failure recovery

### Symptom: admin can't log in after a rotation

1. Check the most recent `AuditEvent` rows for action
   `admin_credential_rotated` and `admin_credential_synced_from_env`.
   The metadata captures `source` and `actor_token_id` / `actor_id`.
2. Compare DB state with SM:
   - In the AWS Console, retrieve the AWSCURRENT version of
     `admin-credentials` and try logging in.
   - If that works → DB is in sync; the operator was given a stale
     password.
   - If it doesn't work → DB and SM AWSCURRENT have drifted.
3. To force re-sync: restart the ECS task. `bootstrap_admin` will
   re-bcrypt from `SPARC_ADMIN_PASSWORD` env (which ECS pulls from SM
   AWSCURRENT). The DB will then match SM AWSCURRENT.
4. If that still doesn't work, the SM secret may itself have an
   orphaned AWSPENDING that should be the real current value. Inspect
   versions with `aws secretsmanager describe-secret --secret-id
   <admin-credentials-arn>` and promote the correct version with
   `aws secretsmanager update-secret-version-stage`.

### Symptom: rotation Lambda crashed mid-flight

The rotation Lambda's idempotency guarantees:
- If it crashes before step 5 (the SPARC POST), no SPARC state changed
  → rerun is safe.
- If it crashes after step 5 returned 200 but before step 7 (promotion)
  → DB has the new password but SM AWSCURRENT still points to the old
  one. Rerun the Lambda; it will detect the orphaned AWSPENDING and
  promote it (or generate a fresh password if the orphan check fails).

### Symptom: PutSecretValue fails from the rake task

The rake task fails before mutating DB (per `AdminCredentialRotationService#call`
ordering), so retry is safe. Common causes:
- SPARC's task role lacks `PutSecretValue` on admin-credentials → check
  sparc-iac IAM (Rebel-Raiders/sparc-iac#197).
- `SPARC_ADMIN_CREDENTIALS_SECRET_ARN` env var is unset → ECS task
  definition needs this configured.

## Audit events

Every rotation event produces one or more rows in `audit_events`:

| `action` | When emitted | Notable metadata |
|---|---|---|
| `admin_bootstrap` | First boot creates or initializes the admin user | `source: "ecs_secrets_injection"` or `"generated"` |
| `admin_credential_synced_from_env` | Boot reconciliation detected drift between env and DB | `source: "ecs_secrets_injection"` |
| `admin_credential_rotated` | Rake task or API endpoint mutated the password | `source: "rake"` or `"api"`, `version_id`, `actor_id` / `actor_token_id`, optional `outcome: "unchanged"` |
| `admin_password_reset` | Manual reset via `sparc:reset_admin_password` rake | (none) |

The plaintext password is **never** written to any audit row, log line,
HTTP response, or notification.

## Configuration reference

| Variable | Default | Purpose |
|---|---|---|
| `SPARC_ADMIN_EMAIL` | `admin@sparc.local` | Email of the admin user the rotation paths target |
| `SPARC_ADMIN_PASSWORD` | _(unset)_ | ECS-injected from SM admin-credentials. Read by `bootstrap_admin` to reconcile DB on container start. |
| `SPARC_ADMIN_CREDENTIALS_SECRET_ARN` | _(unset)_ | ARN of the SM secret. Used by the rake task for the PutSecretValue write-back. |
| `SPARC_AWS_REGION` | `AWS_REGION` or `us-east-1` | Region for SM client construction |
| `SPARC_ADMIN_REFRESH_ENABLED` | `false` | Gate for `POST /api/v1/admin/refresh_credentials` — must be `true` to enable Lambda-driven rotation |
| `SPARC_ALLOW_CRED_ROTATION` | _(unset)_ | Outside production, set to `1` to permit `sparc:rotate_admin_credentials` |
| `SPARC_PRINT_ROTATED_PASSWORD` | _(unset)_ | Set to `1` to print the rotated password from the rake task — break-glass only |

## Sparc-iac coordination

The sparc-iac counterpart for full Lambda-driven rotation is tracked in
**Rebel-Raiders/sparc-iac#197**:

1. Task-definition `secrets:` block injects `SPARC_ADMIN_PASSWORD` from
   `admin-credentials:password::`
2. SPARC ECS task role IAM policy gains
   `secretsmanager:PutSecretValue` + `UpdateSecretVersionStage`
   (write-only)
3. New SM secret for the rotation Lambda's SPARC service-account token
4. Lambda function with the contract documented in #403's design comment

The SPARC side (this repo) ships first — backward-compatible: if env
isn't yet injecting `SPARC_ADMIN_PASSWORD`, `bootstrap_admin` falls
back to generated-on-first-boot behavior.
