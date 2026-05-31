# Runbook — Production DB Verification (post-deploy)

**Purpose:** Read-only verification of the production PostgreSQL database after a
deployment, run from an EC2 instance in the production Auto Scaling Group.
First used to validate the **v1.8.5** deployment (#593 — CSP OAuth login fix +
DB-enforced case-insensitive email uniqueness).

**Scope:** Read-only `SELECT`s only. Never run writes/migrations from this
session. The schema migration that enforces email uniqueness runs synchronously
at container boot (`db:prepare`) and fails fast on any case-variant collision,
so a healthy serving instance already implies the migration succeeded — these
queries are confirmatory.

---

## 1. Access — SSM into the ASG instance (NOT ECS Exec)

> **ECS Exec is explicitly denied in production.** Do not use
> `aws ecs execute-command`. The EC2 instances in the ASG hold the database
> credentials and network/security-group path to RDS; access them via SSM
> Session Manager.

```bash
ASG=<asg-name>            # from sparc-iac

# In-service instance IDs in the ASG:
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
  --output text

# Open an audited session (no inbound SSH):
aws ssm start-session --target <instance-id>
```

Client check on the box:

```bash
psql -V        # e.g. psql (PostgreSQL) 16.14 — a 16.x client against the PG15 RDS is fine
```

---

## 2. Connection

The instance environment carries the DB connection string:

```bash
DATABASE_URL = postgres://sparc_admin:***@<rds-endpoint>:5432/sparc
```

Connectivity sanity check:

```bash
psql "$DATABASE_URL" -c "SELECT current_database(), current_user, version();"
```

### Troubleshooting notes (encountered during v1.8.5 verification)

- **Bash hangs at a `>` prompt.** That's the shell waiting for an unterminated
  here-doc — not a failed connection. Close it (type the terminator line, e.g.
  `SQL`, or press `Ctrl-C`). **Prefer `psql -c "<query>"`** (one query per
  invocation) over here-docs for immediate, unambiguous feedback.
- **Verify the var is actually populated** (redacts credentials):
  ```bash
  [ -n "$DATABASE_URL" ] && printf '%s\n' "$DATABASE_URL" | sed -E 's#://[^@]*@#://***@#' \
    || echo "DATABASE_URL is EMPTY in this shell"
  ```
  If empty in the login shell, the credentials live where sparc-iac provisions
  them (an `EnvironmentFile`, SSM Parameter Store, Secrets Manager, or RDS IAM
  auth). If a value appears wrapped in curly “smart quotes”, that's an upstream
  copy-paste artifact — strip with `sed 's/[“”]//g'` or paste a clean URL by
  hand.

---

## 3. Validation queries

Run each as its own `psql "$DATABASE_URL" -c "<query>"`.

| # | Check | Query | Expected | Result (v1.8.5) |
|---|-------|-------|----------|-----------------|
| 1 | No case-variant duplicate emails | `SELECT lower(email) AS email_ci, count(*) FROM users GROUP BY 1 HAVING count(*) > 1;` | **0 rows** | ✅ `(0 rows)` |
| 2 | No non-lowercased emails | `SELECT count(*) AS non_lowercase FROM users WHERE email <> lower(email);` | `0` | ✅ `0` |
| 3 | Case-insensitive unique index present | `SELECT indexname FROM pg_indexes WHERE tablename='users' AND indexname='index_users_on_lower_email';` | one row: `index_users_on_lower_email` | ✅ `index_users_on_lower_email` (post-deploy) |
| 4 | Email-uniqueness migration applied | `SELECT version FROM schema_migrations WHERE version='20260529000000';` | `20260529000000` | ✅ `20260529000000` (post-deploy) |
| 5 | Users by status (sanity) | `SELECT status, count(*) FROM users GROUP BY status;` | sane counts; no unexpected spike in `suspended`/`deactivated` | ✅ `active=9`, `deactivated=12` (all 12 API-test cleanup, `inactive_reason="Deactivated via API by <admin-email>"`) |
| 6 | Originally-affected user healthy | `SELECT id, email, status, deleted_at FROM users WHERE lower(email)=lower('<redacted-user-email>');` | `status=active`, `deleted_at` empty | ✅ id 6, `active`, `deleted_at` empty |

> Note on #6: the original GitHub-OAuth login failure was a **client-side CSP
> (`form-action`) issue fixed in the app** (#593), not a corrupted user record —
> this query just confirms the account isn't independently inactive.

---

## 4. Sign-off

- **Dates:** 2026-05-29 (DB hygiene checks, pre-deploy) → 2026-05-30 (post-deploy confirmation)
- **Release verified:** v1.8.5
- **Operator:** @clem-field
- **Outcome:** ✅ **All clear.** No case-variant duplicate emails, all emails
  lowercased, affected user healthy. Queries 3 & 4 (index + migration) were
  correctly **absent before the v1.8.5 rollout** and **present after** — a clean
  illustration that "image built ≠ deployed": the schema migration only lands
  once a v1.8.5 container boots on the ASG. The 12 `deactivated` users are API
  test-cleanup, not a regression.

**"All clear" criteria:** #1 = 0 rows · #2 = 0 · #3 returns the index · #4 returns
the migration version · #5 sane · #6 user `active`.
