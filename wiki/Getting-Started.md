# Getting Started

This page gets you from a clone to a running SPARC instance with the NIST
catalogs seeded, in about fifteen minutes.

## Prerequisites

- **Docker + Docker Compose** (recommended path), or
- **Ruby 3.4.4**, **PostgreSQL 15**, and (optionally) **Redis** for local development.

## 1. Run with Docker (recommended)

```bash
git clone https://github.com/risk-sentinel/sparc.git
cd sparc
docker compose up --build
```

The web service comes up on **http://localhost:3000**. Compose uses offset host
ports to avoid clashing with local services — **PostgreSQL on 5433** and
**Redis on 6380** (see [Configuration](Configuration#docker-compose-defaults)).

## 2. Seed the NIST catalogs

```bash
docker compose exec web bin/rails db:seed
```

This loads the NIST SP 800-53 **Rev 4 + Rev 5** control catalogs, the 29 RBAC
roles, the FedRAMP 20x KSI catalog, and the framework converters.

## 3. Local development (without Docker)

```bash
bundle install
bin/rails db:create db:migrate db:seed
bin/rails server
```

The development database is `ssp_tpr_manager_development`; the test database is
`ssp_tpr_manager_test`.

## 4. First login

All authentication modes default to **disabled** (whitelist approach). For a
local instance, enable email/password login:

```bash
SPARC_ENABLE_LOCAL_LOGIN=true
```

Then bootstrap an admin (Instance Admin) account:

```bash
docker compose exec web bin/rails sparc:bootstrap_admin
```

For SSO, see [Integrations](Integrations) and
[docs/OKTA_DEV_SETUP.md](https://github.com/risk-sentinel/sparc/blob/main/docs/OKTA_DEV_SETUP.md).
For local HTTPS, see
[docs/development-https.md](https://github.com/risk-sentinel/sparc/blob/main/docs/development-https.md).

## 5. Where to go next

| Goal | Start here |
|------|-----------|
| Understand the UI | [Screens & UI](Screens) |
| Understand the features | [Core Functions & Features](Core-Functions) |
| Configure auth / env vars | [Configuration](Configuration) |
| Integrate via the API | [API Reference](API-Reference) |
| Understand roles & permissions | [RBAC](RBAC) |
| Learn the architecture | [Architecture](Architecture) |
| Look up a term | [Glossary](Glossary) |

## Common first-run issues

See [FAQ & Troubleshooting](FAQ) and
[docs/troubleshooting.md](https://github.com/risk-sentinel/sparc/blob/main/docs/troubleshooting.md).
