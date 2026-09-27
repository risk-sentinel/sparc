# Health Probes

Liveness and readiness endpoints for load balancers and orchestrators. Added in #1151.

| Endpoint | Answers | Touches the database |
| --- | --- | --- |
| `GET /up` | The process is up and routing requests | **No** |
| `GET /up/ready` | The database answers, no migration is pending, and the schema matches `db/schema.rb` | Yes (schema result cached 60 s) |

Neither is under `/api/v1`, and neither appears in the discovery response: they are infrastructure probes, not part of the data API.

## Authentication

**None.** A load balancer holds no credentials. For that reason `/up/ready` returns **counts only** — it never names a table, column or migration. The detail is written to the application log, where an operator can read it.

Both paths are excluded from the HTTP→HTTPS redirect, so a probe over plain HTTP inside the network still gets an answer, and both are silenced in the request log.

## `GET /up` — liveness

```http
GET /up HTTP/1.1
```

```json
{ "status": "ok" }
```

Always `200` while the process is serving. Use it for **liveness** (restart the container if it stops answering). Do not use it to decide whether to send traffic: it succeeds with the database down, by design.

## `GET /up/ready` — readiness

```http
GET /up/ready HTTP/1.1
```

**200 — ready:**

```json
{
  "status": "ok",
  "checks": { "database": "ok", "pending_migrations": 0, "schema_drift": 0 }
}
```

**503 — not ready.** For example, a database missing structure the code expects:

```json
{
  "status": "unavailable",
  "checks": { "database": "ok", "pending_migrations": 0, "schema_drift": 3 }
}
```

or a database that does not answer (the schema is not checked):

```json
{ "status": "unavailable", "checks": { "database": "unavailable" } }
```

| Check | Meaning | Ready when |
| --- | --- | --- |
| `database` | `SELECT 1` succeeds | `"ok"` |
| `pending_migrations` | migrations in the image the database has not run | `0` |
| `schema_drift` | **structural** differences from `db/schema.rb` — a missing extension, table, column, index or foreign key, or a column of the wrong type | `0` |

`schema_drift` counts structural drift only. Definitional differences (a default, nullability, an index's shape) are logged as warnings and do not take an instance out of service; `STRICT=1 bin/rails db:verify_schema` reports them. See [Upgrading](https://github.com/risk-sentinel/sparc/wiki/Upgrading).

Use it for **readiness** — the load balancer's target health check. An instance whose schema stops matching is removed from service rather than serving errors.

## Relationship to the boot gate

A container reconciles and verifies its schema **before it binds its port** (`bin/docker-entrypoint`). A container that cannot is never started, so `/up/ready` is the second line: it catches drift that appears after boot.

## Caching

The schema check reads the catalog for every table, so its result is cached for **60 seconds** per process. The database ping is not cached — losing the database must show on the next probe.
