# v1.15.3 customer upgrade plan (#1151)

**Internal.** What the organisation still running v1.15.3 needs in order to reach
v1.16.3 without losing schema, plus the notice to send them.

- **Deployment:** ECS **Fargate**, **Aurora PostgreSQL**, **no ECS Exec**
- **Current release:** v1.15.3
- **Target:** v1.16.3
- **Status:** not yet contacted — nothing protects them until they are

Related: [`wiki/Upgrading.md`](../../wiki/Upgrading.md) (public), issue #1151,
PR #1160.

---

## Why they are at risk

v1.16.1 consolidated 42 schema migrations into one version-stamping file and moved
the originals to `db/migrate_archive/`, which is on no `migrations_paths`. A
database that had already run them is fine; one that had not can no longer reach
them.

Measured from the tags — a **v1.15.3** database cannot reach **21** migrations
that v1.16.3 still expects, **four of which create tables**:

```
cdef_components
cdef_service_aliases
cdef_coverage_runs
dismissed_idp_grants
```

`RepairColumnsArchivedByTheSquash` (v1.16.3) covers `20260908180000` and
`20260912090000` — **neither is in that set**. The v1.16.3 repair does nothing for
this population.

**v1.16.0 is the last release where all 21 are still on the migration path**, so it
is the required intermediate stop. At the v1.15.3 → v1.16.0 hop, **33** migrations
apply normally.

| Path | Result |
|---|---|
| v1.15.3 → **v1.16.0** → v1.16.3 | 33 migrations apply. Correct schema. |
| v1.15.3 → v1.16.3 directly | 21 unreachable, 4 tables never created. `db:migrate` reports nothing pending. |

### Why it will look like it worked

`db:migrate` reports no pending migrations, Rails boots, the ALB health check
passes, and ECS marks the deployment successful. Most pages work — the missing
tables only surface when someone opens CDEF coverage or IdP grant management.
This is the same shape as #1147, where the `cdef_controls` columns went unnoticed
because nobody had opened a CDEF page.

sparc-iac avoided all of this **by accident**: it passed through v1.16.0 on
2026-08-24 as part of a normal cadence. A team that upgrades less often gets no
such protection.

---

## ECS / Aurora specifics that change the procedure

### 1. The migration can be killed mid-flight

If the service migrates on boot, the task has only until
`health_check_grace_period_seconds` expires. Our own default is **300**, and its
description says it was sized from *"v1.8.0's PromoteCdefBackMatterImports
migration timing"* — one slow migration, not 33. If the hop overruns, ECS marks
the task unhealthy, kills it **mid-migration**, and starts another that begins
again.

**Remedy:** migrate with a one-off `run-task` before updating the service. The
service keeps serving the old release throughout. Fallback, if they insist on
migrating through the service: raise the grace period to ~900 first.

### 2. No ECS Exec means every step must be a one-off task

They cannot shell in, and Aurora is not directly reachable. So the pre-flight
check, the migration and the verification all run as `run-task` with a command
override, and output is read from CloudWatch.

`bin/rails db:verify_schema` does not exist before v1.16.3, so the **pre-flight
check must run on their current image** — hence `bin/rails runner` with
`table_exists?` rather than the rake task.

### 3. A one-off task can still have side effects — check `SPARC_RUN_SEEDS`

`bin/docker-entrypoint` gates `db:prepare`, admin bootstrap and seeds behind
`[[ "$*" == *"rails"*"server"* ]]`, so a `db:prepare` / `runner` /
`db:verify_schema` override skips all three. **But line 77 is separate:**

```bash
if [ "${SPARC_RUN_SEEDS:-false}" = "true" ]; then
    bundle exec rails db:seed
fi
```

That runs for **any** command, and a one-off task inherits the service's
environment. If their task definition sets `SPARC_RUN_SEEDS=true`, the
"read-only" check would run seeds. **Confirm it is unset or override it to
`false`** before telling anyone a step is read-only.

Also worth knowing: the entrypoint's PostgreSQL wait is **unconditional**, so
every one-off task blocks until the cluster answers `pg_isready`.

### 4. Aurora gives them a rehearsal

Aurora **fast cloning** is copy-on-write — near-instant and cheap. They can clone
the cluster, run the whole two-step against the clone, verify, then repeat on
production with timings and output already known. Worth recommending, since one
step of this upgrade is irreversible.

**Aurora Backtrack is MySQL-only**, so it is not available to them. Say so before
they go looking for it.

---

## Open items on our side

- [ ] Send the notice (below) — **the only thing protecting them today**
- [ ] Merge PR #1160 so the wiki link resolves (it 404s until then)
- [ ] Decide whether this goes in the next release notes for anyone else below v1.16.0
- [ ] `bin/schema_drift_sql` fix (848df0af) only reaches them in an image **after**
      v1.16.3 — the version they would pull still reports missing tables as clean

---

## The notice

Ready to send. Phrasing is deliberate: it leads with the action, does not assume
they have read anything, and explicitly tells them not to trust a green ECS
deployment.

---

**Subject: Before you upgrade SPARC from v1.15.3 — an extra step is required**

Hello,

You are running **SPARC v1.15.3** on ECS Fargate with Aurora PostgreSQL. Before
you upgrade, there is something you need to know, because the upgrade will
otherwise appear to succeed — including a green ECS deployment — while leaving
your database incomplete.

**Do not upgrade directly to v1.16.3. Go through v1.16.0 first.**

```
v1.15.3  →  v1.16.0  →  v1.16.3
```

Do not stop on v1.16.1 or v1.16.2. v1.16.2 must not be upgraded into; it is a
known-bad release for existing databases.

Every command below runs as a one-off Fargate task. **Nothing here needs ECS
Exec, a bastion, or direct database access.** Output goes to the same CloudWatch
log group your service already uses.

### Why

v1.16.1 consolidated 42 database migrations into a single file and moved the
originals out of the path the upgrade process reads. A database that had already
run them is unaffected. A database on v1.15.3 has **not** run 21 of them and can
no longer reach them — including four that create tables:

```
cdef_components
cdef_service_aliases
cdef_coverage_runs
dismissed_idp_grants
```

The upgrade reports **no pending migrations** and completes normally. Rails
starts, the ALB health check passes, ECS marks the deployment successful, and
most pages work. The missing structure surfaces only when someone opens a feature
that depends on it — component-definition coverage, or IdP grant management.

**Nothing in your infrastructure will flag this.** The ALB health check confirms
the service is responding, not that the schema is correct. Please do not read a
green deployment as confirmation.

**v1.16.0 is the last release where all 21 are still reachable.** Deploying it
applies them normally, with their correct column types, indexes, foreign keys and
data backfills. After that, v1.16.3 upgrades cleanly.

### Step 1 — Confirm your starting point (read-only, ~2 minutes)

Uses the task definition you are **already running**, so nothing new is deployed.
Save this as `check-overrides.json`, replacing `<container>` with your container
name:

```json
{
  "containerOverrides": [{
    "name": "<container>",
    "command": ["bin/rails", "runner",
      "missing = %w[cdef_components cdef_service_aliases cdef_coverage_runs dismissed_idp_grants].reject { |t| ActiveRecord::Base.connection.table_exists?(t) }; puts 'MISSING TABLES: ' + missing.inspect"],
    "environment": [{ "name": "SPARC_RUN_SEEDS", "value": "false" }]
  }]
}
```

Then:

```bash
aws ecs run-task \
  --cluster <cluster> \
  --task-definition <current-v1.15.3-task-def> \
  --launch-type FARGATE \
  --network-configuration <same as your service> \
  --overrides file://check-overrides.json
```

Read the result in CloudWatch. On v1.15.3 you should see **all four** table names
listed as missing. That is expected — they are tables your release does not have
yet — and it confirms the two-step path applies to you.

This is read-only: it creates nothing and changes nothing.

### Step 2 — Back up, and consider rehearsing

**Take a manual Aurora cluster snapshot before you begin.**

```bash
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier <prod-cluster> \
  --db-cluster-snapshot-identifier sparc-pre-v116-upgrade
```

The v1.16.1 consolidation declares itself irreversible — there is no rollback
migration across it. A snapshot you took deliberately is the one you will want.
Note that **Aurora Backtrack is not available for Aurora PostgreSQL** (MySQL
only), so it is not an option here.

**Optional but recommended — rehearse on a clone.** Aurora fast cloning is
copy-on-write, so this is quick and cheap:

```bash
aws rds restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier <prod-cluster> \
  --db-cluster-identifier <prod-cluster>-upgrade-rehearsal \
  --restore-type copy-on-write \
  --use-latest-restorable-time
```

Register a task definition whose database settings point at the clone, run
steps 3–6 against it, then repeat on production with the timings and output
already known. Delete the clone afterwards. Worth the extra hour, given one step
of this upgrade cannot be undone.

### Step 3 — Migrate to v1.16.0 with a one-off task, NOT the service

**This is the part most likely to go wrong on ECS.** If you deploy the service and
let it migrate on boot, the task has only until the ALB health-check grace period
expires to finish. This hop applies **33 migrations** — likely more than that
grace period was sized for. If it overruns, ECS marks the task unhealthy and kills
it **mid-migration**, then starts another that begins again.

Register a task definition at `risksentinel/sparc:v1.16.0` **without** updating
the service, then:

```bash
aws ecs run-task \
  --cluster <cluster> \
  --task-definition <new-v1.16.0-task-def> \
  --launch-type FARGATE \
  --network-configuration <same as your service> \
  --overrides '{"containerOverrides":[{"name":"<container>","command":["bin/rails","db:prepare"]}]}'
```

Wait for the task to exit successfully and read its CloudWatch logs before going
further. The service is untouched and still serving v1.15.3 throughout.

### Step 4 — Deploy v1.16.0 to the service, and let it settle

```bash
aws ecs update-service --cluster <cluster> --service <service> \
  --task-definition <new-v1.16.0-task-def>

aws ecs wait services-stable --cluster <cluster> --services <service>
```

Migrations are already applied, so startup is fast. Background data migrations run
after boot, so give it a few minutes rather than moving on the moment it responds.
Confirm the version reads 1.16.0.

### Step 5 — Repeat for v1.16.3

Same pattern: register the task definition, run `db:prepare` as a one-off task,
then update the service. Far fewer migrations on this hop.

### Step 6 — Verify (this step matters)

```bash
aws ecs run-task \
  --cluster <cluster> \
  --task-definition <v1.16.3-task-def> \
  --launch-type FARGATE \
  --network-configuration <same as your service> \
  --overrides '{"containerOverrides":[{"name":"<container>","command":["bin/rails","db:verify_schema"]}]}'
```

It compares the live database against what the code expects and **exits non-zero**
listing every missing table, column and index. A clean run reports the number of
tables checked.

"No pending migrations" does not mean the schema is correct — that exact claim was
true on deployments that were missing columns. Re-running step 1 should now report
**no** missing tables.

### If you have already upgraded past v1.16.0

Run step 1. If any tables are listed, they are missing and the database needs
attention — please get in touch before making further changes, and tell us which
releases you moved through.

One caveat if you are using the `bin/schema_drift_sql` helper: in v1.16.3 and
earlier it reports missing **columns** only and is blind to missing **tables**, so
it can read as clean in exactly this situation. Use step 1 or `db:verify_schema`,
which has always detected both. The helper is fixed in the next release.

### Questions

Please reach out before upgrading if anything here is unclear, or if your setup
differs from what we have assumed. We would rather answer a question first than
diagnose a database afterwards.

Full upgrade documentation, including the reasoning and verification steps:
<https://github.com/risk-sentinel/sparc/wiki/Upgrading>
