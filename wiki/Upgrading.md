# Upgrading SPARC

How to move a running SPARC deployment from one release to the next without losing schema.

> **Read this before upgrading from any release older than v1.16.0.**
> Upgrading such a database **directly** to v1.16.3 or later silently skips migrations that can no longer be reached — **16 from v1.15.5, 21 from v1.15.3**, including tables that are never created — and `db:migrate` will report that nothing is pending. The upgrade appears to succeed. See [Path B](#path-b--upgrading-from-a-release-older-than-v1160).

These instructions assume the **containerized deployment** (`risksentinel/sparc` on Docker Hub), which is how most teams run SPARC. Every command runs against the published image; nothing requires a repository checkout.

**Which image tag to run.** Every release is published as its full version (`v1.17.9`) and its minor line (`v1.17`), and, from the first release after #1359, its major line (`v1`). Pin a full version (`v1.17.9`, ideally with its digest) in production. `v1` follows the newest 1.x release. `latest` follows the newest release of the supported major line only: a release from any other major line never moves it, so `latest` never jumps you to a new major version.

Moving the database itself to a new PostgreSQL major version, such as Aurora PostgreSQL 14 to 18? See [Upgrading PostgreSQL](#upgrading-postgresql-to-a-new-major-version).

---

## Step 1 — Find the release you are on

The version is shown in the application footer and in **Administration → About**. From a shell:

```bash
docker compose exec web bin/rails runner 'puts SparcConfig::VERSION'
```

---

## Step 2 — Choose your path

| You are on | Path | What to do |
|---|---|---|
| **v1.16.0, v1.16.1, v1.16.2, v1.16.3** | **A** | Upgrade directly to the latest release |
| **v1.15.x or older** | **B** | **Stop at v1.16.0 first**, then go to the latest release |

There is no third case. If you are unsure which release a database was last migrated by, run the [drift check](#step-4--check-for-drift-recommended) — it answers the question without changing anything.

---

## Step 3 — Back up the database

Do this every time, and do not skip it when crossing v1.16.1. The migration squash introduced in that release declares itself irreversible:

```
ActiveRecord::IrreversibleMigration:
  Cannot reverse the consolidated schema migration.
```

Once a database has crossed that point there is no `db:rollback` path back. A backup is the only rollback.

```bash
pg_dump "$DATABASE_URL" -Fc -f sparc-pre-upgrade-$(date +%Y%m%d).dump
```

---

## Step 4 — Check for drift (recommended)

`bin/schema_drift_sql` prints a plain-SQL check of every table and column the application expects. It is dependency-free — no Rails, no gems, no database connection of its own — so it can be generated from a **newer** image and run against an **older** database.

The container entrypoint waits for PostgreSQL before running anything, so bypass it with `--entrypoint`:

```bash
docker run --rm --entrypoint /rails/bin/schema_drift_sql \
  risksentinel/sparc:v1.16.3 > sparc-drift-check.sql

psql "$DATABASE_URL" -f sparc-drift-check.sql
```

**Rows returned are columns the application expects that your database does not have.**

> **Generating this check from a v1.16.3 or earlier image? It cannot report a missing _table_ — only missing columns on tables that already exist.** If an upgrade skipped a migration that creates a table, the check from those images stays silent about it. Run the table check below as well.
>
> Images from v1.17.0 on report both, each row tagged `missing table` or `missing column`. `db:verify_schema` has always detected missing tables and is the authoritative check once you are on v1.16.3 or later.

### Also check for missing tables

```bash
psql "$DATABASE_URL" <<'SQL'
SELECT t.table_name
FROM (VALUES
  ('cdef_components'), ('cdef_service_aliases'),
  ('cdef_coverage_runs'), ('dismissed_idp_grants')
) AS t(table_name)
LEFT JOIN information_schema.tables i
  ON i.table_schema = 'public' AND i.table_name = t.table_name
WHERE i.table_name IS NULL;
SQL
```

Rows returned are tables that should exist and do not. These four are the table-creating migrations a database on **v1.15.x** cannot reach — they are the clearest signal that a direct upgrade was attempted and that [Path B](#path-b--upgrading-from-a-release-older-than-v1160) is required.

Run both checks **before** and **after** the upgrade. Before, they tell you which path you need; after, they prove you arrived.

---

## Path A — Upgrading from v1.16.0 or newer

Pull the new image and restart. The web container's entrypoint runs `db:prepare` on boot, which applies every pending migration.

```bash
docker compose pull web
docker compose up -d web
docker compose logs -f web        # watch migrations apply before moving on
```

Wait for the container to finish booting. Background data migrations run **after** boot via the deferred-migration runner, so let the instance settle before you start using it.

Then [verify](#step-5--verify-you-arrived).

> **Do not stop on v1.16.2.** That release cannot be upgraded into — a database moving from v1.16.0 to v1.16.2 ends with seven missing columns and every boundary page returning `500`. A *fresh install* of v1.16.2 is unaffected. If you are already on v1.16.2, upgrading to v1.16.3 repairs the database automatically.

---

## Path B — Upgrading from a release older than v1.16.0

**You must pass through v1.16.0.** This is not a precaution — a direct jump produces a database that is missing structure the application needs, while reporting a clean migration state.

### Why the intermediate stop is required

v1.16.1 consolidated 42 schema migrations into a single version-stamping migration and moved the original files out of the migration path. A database that had already run them is fine. A database that had **not** run them can no longer reach them: the files are no longer anywhere `db:migrate` looks.

**How many fall into that gap depends on exactly which release you are on** — the older the database, the more it never ran. Measured: **v1.15.5 → 16 migrations** (3 of them creating tables); **v1.15.3 → 21** (4 creating tables, adding `create_cdef_components`).

For a **v1.15.5** database, these 16:

| | |
|---|---|
| `20260812160000` | `create_cdef_service_aliases` — **new table** |
| `20260812160100` | `create_cdef_coverage_runs` — **new table** |
| `20260822160000` | `create_dismissed_idp_grants` — **new table** |
| `20260811150000` | `add_source_to_user_roles` |
| `20260812120000` | `add_collected_by_user_to_evidences` |
| `20260816120000` | `add_component_authoring_fields_to_cdef_documents` |
| `20260816140000` | `drop_excel_default_from_creation_method` |
| `20260818140000` | `add_framework_to_catalogs_and_profiles` |
| `20260818160000` | `add_attester_user_to_attestations` |
| `20260819160000` | `add_links_data_to_catalog_controls` |
| `20260819170000` | `add_validation_modeling_to_components` |
| `20260820180000` | `collapse_duplicate_profile_parameter_fields` |
| `20260821180000` | `reduce_statement_control_ids_on_cdef_controls` |
| `20260821200000` | `add_decider_and_approver_to_finding_dispositions` |
| `20260822120000` | `add_source_to_organization_memberships` |
| `20260823140000` | `add_provided_by_to_back_matter_resources` |

The repair shipped in v1.16.3 covers a different, smaller gap — `20260908180000` and `20260912090000` — and **covers none of these**.

**v1.16.0 is the last release where all 16 are still on the migration path.** Deploying it applies them normally — correct column types, foreign keys, indexes, and the data backfills they carry.

### B1 — Upgrade to v1.16.0 and let it finish

Pin the image tag explicitly:

```bash
docker compose pull web        # with the image pinned to risksentinel/sparc:v1.16.0
docker compose up -d web
docker compose logs -f web
```

**Wait for this to complete fully** before continuing. The instance should boot, serve pages, and finish its deferred data migrations. Confirm the application responds and the version reads `1.16.0`.

### B2 — Upgrade to v1.16.3 or later

Now follow [Path A](#path-a--upgrading-from-v1160-or-newer). Skip v1.16.1 and v1.16.2 — neither adds anything on the way, and v1.16.2 must not be upgraded into.

On this hop the squash becomes a no-op, and the v1.16.3 repair migration restores the seven columns that the v1.16.0 → v1.16.3 step would otherwise leave behind, along with its categorization backfill.

---

## Step 5 — Verify you arrived

**"No pending migrations" is not evidence that the schema is current.** That claim was true, and worthless, on every v1.16.2 deployment that was missing seven columns. Check the schema itself:

```bash
docker compose exec web bin/rails db:verify_schema
```

It compares the live database against the schema the code expects and **exits non-zero** listing every missing table, column and index. A clean run reports the number of tables checked.

Available from v1.16.3 onward. For anything older, use the [SQL drift check](#step-4--check-for-drift-recommended), which works against any database.

From v1.17.0 it also checks each column's **type**, foreign keys and extensions, and with `STRICT=1` each column's nullability and default and each index's shape:

```bash
docker compose exec web env STRICT=1 bin/rails db:verify_schema
```

---

## The boot gate (v1.17.0 and later)

From v1.17.0, **a container checks its own schema before it serves**. After `db:prepare`, and before the web server binds its port, the entrypoint runs:

1. **`db:reconcile_schema`** — creates whatever `db/schema.rb` declares and the database lacks: extensions, tables, columns, indexes, foreign keys. **Additive only**: it never drops, renames or retypes anything. It runs in one transaction, so it either repairs completely or changes nothing, and it **refuses** — changing nothing — when the drift cannot be fixed by adding (a column of the wrong type), when a missing `NOT NULL` column has no default and its table has rows, or when any statement fails (for example a unique index over duplicate data). Every repair or refusal is written to the **audit log** (`schema_reconciled` / `schema_reconciliation_refused`), with the exact SQL.
2. **`db:verify_schema`** — fails on any remaining structural drift.

If either fails, **the container exits before serving**, so your orchestrator keeps the previous version running and the deployment fails, instead of the application serving errors. There is no switch to bypass it.

To see what reconciliation would do without doing it:

```bash
docker compose exec web env DRY_RUN=1 bin/rails db:reconcile_schema
```

**A boot-time repair can hold write locks.** Reconciliation runs in one transaction, so a missing index is built with a plain `CREATE INDEX` (not `CONCURRENTLY`, which cannot run in a transaction) and a missing foreign key validates every existing row. On a large table both block writes to it until the repair finishes — while your previous version is still serving. Tasks booting together also wait for one another: the repair is serialised with a database lock, and a task that waited finds the schema already repaired. If `DRY_RUN=1` (above) shows an index or foreign key on a large table, apply it yourself first — `CREATE INDEX CONCURRENTLY`, or `ADD CONSTRAINT … NOT VALID` then `VALIDATE CONSTRAINT` — and the container will find nothing left to repair.

**If a new version will not start**, read the container log: the report names every difference and why reconciliation refused. Restore the backup from [Step 3](#step-3--back-up-the-database) if you need the previous version back while you resolve it, and open an issue with the report.

Keep your load balancer's health check on **`/up`**, and check **`/up/ready`** after each deploy (and alarm on it): it returns `503` if the database is unreachable, a migration is pending, or the schema drifts after boot — see [Core Functions](Core-Functions#container-deployment).

---

## If verification reports drift

Do not run `db:schema:load` against a populated database — it drops data.

1. **Coming from v1.15.x or older and you skipped v1.16.0?** That is the likely cause. Restore your backup and follow [Path B](#path-b--upgrading-from-a-release-older-than-v1160).
2. **Drift limited to the seven columns** on `authorization_boundaries`, `ssp_information_types` and `cdef_controls`? That is the v1.16.2 gap. Upgrading to v1.16.3 or later repairs it automatically.
3. **Missing tables, not just columns?** The SQL drift check in **v1.16.3 and earlier** images cannot see those — use `db:verify_schema`, or the table check above; later images report them. A database on v1.15.x that upgraded directly is missing four table-creating migrations.
4. **Anything else** — capture the `db:verify_schema` output and open an issue at [risk-sentinel/sparc/issues](https://github.com/risk-sentinel/sparc/issues). Include the release you upgraded from, the release you upgraded to, and the full drift report.

---

## Why upgrades need this

`db:migrate` applies migration files and **never reads `db/schema.rb`**. Only a fresh `db:schema:load` builds a database from the schema file.

That distinction is invisible until a migration is archived. When a release consolidates old migrations into a squash, the squash is correct for a **fresh install** — `db:schema:load` creates every column from `schema.rb`, and the stamp records the history. On an **existing** database the same squash records those versions as applied and performs no DDL at all. Any database that had not already run the archived migrations ends up missing their structure, with a version table that looks perfectly current.

This is why the schema check exists, and why it is the step that actually tells you whether an upgrade worked.

---

## Upgrading PostgreSQL to a new major version

How to move SPARC's database to a new PostgreSQL major version, for example **Aurora PostgreSQL 14 to 18.3** ahead of version 14's end of support. SPARC itself needs no change for this: the same image runs on both.

### What was tested

On 2026-11-06, with SPARC **v1.17.8**:

- A SPARC database created by v1.16.3 on **PostgreSQL 14**, then migrated to v1.17.8. SPARC connected as a **non-superuser** account with an **md5** password.
- Upgraded to **PostgreSQL 18** with `pg_upgrade`, the PostgreSQL tool behind in-place major-version upgrades.
- **No data changed:** every table in all four SPARC databases had the same rows and the same contents before and after the upgrade (120 tables).
- v1.17.8's API and browser test suites pass on the upgraded database, connected over TLS with `SPARC_DB_SSLMODE=verify-full`. With a CA bundle that could not verify the server, SPARC refused to connect.

**Not tested:** Aurora's own upgrade tooling and storage. Rehearse on a copy first (below).

### Before the upgrade

1. **Be on SPARC v1.17.8 or later**, the release tested above. Follow the rest of this page first if you are not.
2. **Rehearse on a copy.** Restore a snapshot to a new cluster, upgrade that, and point a test SPARC at it.
3. **Back up**, as in [Step 3](#step-3--back-up-the-database). On Aurora, take a cluster snapshot.
4. **Stop SPARC** (scale the web service and any workers to zero), so nothing writes during the upgrade.

SPARC uses four databases on the same server: the main one and its `_cache`, `_queue` and `_cable` companions. A server upgrade moves all four together.

### After the upgrade, before starting SPARC

1. **Refresh the query statistics.** An upgrade does not carry all of them over, and until they are rebuilt SPARC's lists and searches can be slow. With PostgreSQL 18's `vacuumdb` (`--missing-stats-only` is new in 18):

   ```bash
   vacuumdb --all --analyze-in-stages --missing-stats-only
   vacuumdb --all --analyze-only
   ```

2. **Check SPARC's extensions, as the master (administrative) user.** In the main database:

   ```sql
   SELECT name, installed_version, default_version
     FROM pg_available_extensions WHERE name IN ('pg_trgm', 'plpgsql');
   ```

   If `pg_trgm`'s `installed_version` is older than its `default_version`, run `ALTER EXTENSION pg_trgm UPDATE;`. Run it as the master user: the upgrade can make the administrative user the extension's owner, and SPARC's own account is then refused (`must be owner of extension pg_trgm`). SPARC never changes the extension itself, so this does not affect the application. In the test, `pg_trgm` was version 1.6 on both 14 and 18, and no update was needed.

3. **Consider resetting SPARC's database password.** PostgreSQL 18 deprecates md5 passwords. An md5 password set on 14 still works on 18; SPARC connected with one in the test. Setting it again on 18, where `scram-sha-256` is the default, stores it the newer way. Update `SPARC_DB_PASSWORD` (or the secret it comes from) to match.

### Start SPARC and check

1. **Keep `SPARC_DB_SSLMODE=verify-full`.** On AWS the image already trusts the RDS CA bundle (see `docs/DATABASE_TLS.md`). At startup the log should report:

   ```
   [SPARC] Database TLS: 4/4 connections encrypted and server-authenticated (sslmode=verify-full, TLSv1.3).
   ```

2. **Verify the schema**, as in [Step 5](#step-5--verify-you-arrived), and check that `/up/ready` returns `200`.

---

## Version notes

| Release | Note |
|---|---|
| **v1.17.1** | No migrations and no configuration changes. Fixes OIDC sign-in, which fails on v1.17.0: a deployment that signs in through Okta or another OIDC provider should move to v1.17.1 rather than stay on v1.17.0. An API client that sends `null` in a parameter update to clear a value must send `""` (or `[]` for a selection) instead: `null` now means "not provided" and leaves the stored value alone. |
| **v1.17.0** | Adds the [boot gate](#the-boot-gate-v1170-and-later), `db:reconcile_schema`, the `/up` and `/up/ready` health probes, and definition-level checks in `db:verify_schema` (`STRICT=1`). `bin/schema_drift_sql` reports missing tables. Rebuilds the FedRAMP 20x KSI catalog from FedRAMP's published rules. FedRAMP has renamed every indicator (`ksi-iam-02` is now `KSI-IAM-ELP`), and the catalog is re-keyed automatically, a few seconds after the first boot. Ten indicators are renamed in place, and their assessments move with them. The other 44 old indicators, and the `AUTH` theme, are **retired, not deleted**: their assessments are kept and shown as history. New assessments go on the current indicators. To preview the change first, run `bin/rails 'ksi:import[true]'`.  Also: OSCAL **1.2.3** becomes the default version SPARC writes (every record validated identically under 1.2.2 and 1.2.3); new nullable columns hold the authorizing official's decision on a risk — three on POA&M risks, one on SAR risks — with no backfill, so existing risks export unchanged. The container image is now built on **Red Hat UBI 10 minimal** (RHEL 10.2) instead of UBI 9. Nothing changes for a deployment: same ports, environment variables, custom-CA mounts and database. The image's PostgreSQL client tools move from 13 to 16, and the image no longer contains a package manager or `rpm`. If you build your own image on top of SPARC's, install packages in your own build stage rather than in the SPARC image. |
| **v1.16.3** | Repairs databases affected by v1.16.2. Adds `db:verify_schema` and `bin/schema_drift_sql`. |
| **v1.16.2** | **Do not upgrade an existing deployment into this release.** Fresh installs are unaffected. Go to v1.16.3. |
| **v1.16.1** | Introduced the migration squash. The last release reachable directly from v1.15.x is **v1.16.0**, not this one. |
| **v1.16.0** | The required intermediate stop for any database older than it. |

---

## See also

* [Changelog](Changelog) — what each release changed
* [Configuration Reference](Configuration) — environment variables, including database settings
* [Getting Started](Getting-Started) — first-time installation
* [FAQ & Troubleshooting](FAQ)
