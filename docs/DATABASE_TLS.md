# Database TLS — operator guide

**Applies from v1.13.1.** NIST 800-53 SC-8, SC-8(1), SC-13. Required for FedRAMP High.

## What changed

SPARC now sets a TLS floor for **every** database connection — the primary database and
the three Solid\* databases (`cache`, `queue`, `cable`) — in `config/database.yml`'s
`default:` anchor.

This matters because `DATABASE_URL` is merged by Rails into the **`primary`** database
only. A deployment whose `DATABASE_URL` carried `?sslmode=require` was protecting one of
its four connections; the other three negotiated on libpq's default and could fall back to
plaintext without any error.

| Environment | Default `sslmode` | Effect |
|---|---|---|
| production | `require` | Plaintext is refused |
| development, test | `prefer` | Local Postgres without TLS still connects |

Nothing is required of you for this floor — it applies automatically.

## The three modes

| Mode | Encrypts | Authenticates the server | Use |
|---|---|---|---|
| `prefer` | Opportunistically | No | Local development only |
| `require` | Yes | **No** | Default in production |
| `verify-full` | Yes | Yes — chain **and** hostname | **FedRAMP High target** |

`require` stops an eavesdropper but not an impostor: it will happily complete a TLS
handshake with any server that answers, including one that is not your database. Only the
`verify-*` modes check that the certificate is signed by a CA you trust, and only
`verify-full` additionally checks that the hostname matches. **If you are pursuing FedRAMP
High, `require` is not sufficient — you want `verify-full`.**

## Turning on `verify-full`

### On AWS RDS — no rebuild needed

The AWS RDS global CA bundle is baked into the SPARC image at
`/etc/pki/sparc/rds-global-bundle.pem`, and `SPARC_DB_SSLROOTCERT` already points at it.
Set one variable:

```
SPARC_DB_SSLMODE=verify-full
```

Verify it took effect (see "Verifying" below) before you rely on it.

### On a private CA / non-AWS Postgres — no rebuild needed either

`libpq` verifies against `sslrootcert` and **ignores `SSL_CERT_FILE`**. That means the
runtime CA mechanism used for outbound HTTPS and LDAP (`SPARC_EXTRA_CA_CERTS`, see
[custom CA trust](ENVIRONMENT_VARIABLES.md)) does **not** cover Postgres — the database
needs its own trust anchor.

Mount your CA and point at it:

```
SPARC_DB_SSLROOTCERT=/rails/certs/my-postgres-ca.pem
SPARC_DB_SSLMODE=verify-full
```

> **A rebuild is only required if you want to change the *system* trust store** (the
> anchors used by outbound HTTPS, the AWS SDK and LDAP). For the database connection
> alone, mounting a PEM and setting `SPARC_DB_SSLROOTCERT` is enough.

### If you do need to rebuild (system trust store)

Drop your PEM/CRT files into `certs/` in the source tree and rebuild. They are folded into
the system trust store at build time and trusted by every outbound TLS client:

```
cp corporate-root-ca.pem certs/
docker build -t sparc:custom .
```

## Verifying — do not take it on trust

Ask the **server**, not the client, whether the session is encrypted:

```sql
SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

```bash
bin/rails runner 'puts ActiveRecord::Base.connection.execute(
  "SELECT ssl, version FROM pg_stat_ssl WHERE pid = pg_backend_pid()").to_a.inspect'
```

`ssl` must be `t`. Repeat for each database if you want full coverage — the Solid\*
connections are the ones that were historically unprotected.

To exercise the enforcement itself, including the negative cases:

```bash
bin/test-db-tls
```

This stands up a TLS-enabled and a plaintext-only Postgres and asserts both directions —
that a secured connection is accepted, and that `require`/`verify-full` genuinely **refuse**
rather than silently downgrade (covering missing CA, wrong CA and hostname mismatch).

## Server-side enforcement is a separate control

Everything above is client-side: it governs what SPARC will accept. It does not stop a
*different* client connecting to your database in plaintext. Enforce it at the server too:

- **AWS RDS** — set `rds.force_ssl=1` in the instance parameter group. Tracked for the
  Risk Sentinel reference deployment in `sparc-iac#566`.
- **Self-managed Postgres** — require `hostssl` in `pg_hba.conf`.

An assessor will generally ask for the server-side control, because it is the only one
that does not depend on every client being configured correctly.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `SPARC_DB_SSLMODE` | `require` in production, `prefer` otherwise | `prefer`, `require`, `verify-ca`, `verify-full` |
| `SPARC_DB_SSLROOTCERT` | `/etc/pki/sparc/rds-global-bundle.pem` (set in the image) | Path to the CA bundle libpq verifies against. Only consulted by the `verify-*` modes |

Both apply to all four databases.
