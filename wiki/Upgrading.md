# Upgrading SPARC

How to move a running SPARC deployment from one release to the next without losing schema.

> **Read this before upgrading from any release older than v1.16.0.**
> Upgrading such a database **directly** to v1.16.3 or later silently skips migrations that can no longer be reached — **16 from v1.15.5, 21 from v1.15.3**, including tables that are never created — and `db:migrate` will report that nothing is pending. The upgrade appears to succeed. See [Path B](#path-b--upgrading-from-a-release-older-than-v1160).

These instructions assume the **containerized deployment** (`risksentinel/sparc` on Docker Hub), which is how most teams run SPARC. Every command runs against the published image; nothing requires a repository checkout.

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

`bin/schema_drift_sql` prints a plain-SQL check of every column the application expects. It is dependency-free — no Rails, no gems, no database connection of its own — so it can be generated from a **newer** image and run against an **older** database.

The container entrypoint waits for PostgreSQL before running anything, so bypass it with `--entrypoint`:

```bash
docker run --rm --entrypoint /rails/bin/schema_drift_sql \
  risksentinel/sparc:v1.16.3 > sparc-drift-check.sql

psql "$DATABASE_URL" -f sparc-drift-check.sql
```

**Rows returned are columns the application expects that your database does not have.**

> **Generating this check from a v1.16.3 or earlier image? It cannot report a missing _table_ — only missing columns on tables that already exist.** If an upgrade skipped a migration that creates a table, the check from those images stays silent about it. Run the table check below as well.
>
> Images after v1.16.3 report both, each row tagged `missing table` or `missing column`. `db:verify_schema` has always detected missing tables and is the authoritative check once you are on v1.16.3 or later.

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

---

## If verification reports drift

Do not run `db:schema:load` against a populated database — it drops data.

1. **Coming from v1.15.x or older and you skipped v1.16.0?** That is the likely cause. Restore your backup and follow [Path B](#path-b--upgrading-from-a-release-older-than-v1160).
2. **Drift limited to the seven columns** on `authorization_boundaries`, `ssp_information_types` and `cdef_controls`? That is the v1.16.2 gap. Upgrading to v1.16.3 or later repairs it automatically.
3. **Missing tables, not just columns?** The SQL drift check cannot see those — use `db:verify_schema`, or the table check above. A database on v1.15.x that upgraded directly is missing four table-creating migrations.
4. **Anything else** — capture the `db:verify_schema` output and open an issue at [risk-sentinel/sparc/issues](https://github.com/risk-sentinel/sparc/issues). Include the release you upgraded from, the release you upgraded to, and the full drift report.

---

## Why upgrades need this

`db:migrate` applies migration files and **never reads `db/schema.rb`**. Only a fresh `db:schema:load` builds a database from the schema file.

That distinction is invisible until a migration is archived. When a release consolidates old migrations into a squash, the squash is correct for a **fresh install** — `db:schema:load` creates every column from `schema.rb`, and the stamp records the history. On an **existing** database the same squash records those versions as applied and performs no DDL at all. Any database that had not already run the archived migrations ends up missing their structure, with a version table that looks perfectly current.

This is why the schema check exists, and why it is the step that actually tells you whether an upgrade worked.

---

## Version notes

| Release | Note |
|---|---|
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
