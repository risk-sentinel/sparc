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

## 5. Optional — load a realistic authorization to look at

A freshly seeded instance has catalogs and roles but no authorizations, so most
screens are empty. If you are evaluating SPARC, or you want something real to
click through, load the **reference estate**:

```bash
docker compose exec -e SPARC_SEED_REFERENCE=lean web bin/rails db:seed
```

That builds two organizations in a genuine **leveraged authorization**
relationship — a platform provider and a mission system that runs on it — with
the whole chain on each side:

| | Boundary 1 — provider | Boundary 2 — consumer |
|---|---|---|
| Organization | Reference Platform Provider (Org A) | Reference Mission System Owner (Org B) |
| Documents | Profile → SSP → SAP → SAR → 3 POA&Ms | Profile → SSP → SAP → SAR → 3 POA&Ms |
| Evidence | Scanner findings + policy documents | Scanner findings + policy documents |

Boundary 1 declares which controls it **provides** to its customers and which it
hands **back** to them; Boundary 2 inherits implementations for the first set
and is shown an outstanding responsibility for the second. That is the
relationship the [leveraged authorization](Core-Functions#21-leveraged-authorizations)
feature exists to model, and it is hard to understand from an empty screen.

Control satisfaction is derived from the evidence rather than assigned, so the
~5% of controls that are open are open *because* a simulated scanner failed
them — and they flow through to SAR risks and POA&M items you can follow.

```bash
bin/rails db:seed:reference:status   # what is loaded
bin/rails db:seed:reference:purge    # remove it again
```

Two tiers are available: `lean` (40 curated controls spanning all 20 families)
and `full` (real NIST MODERATE and LOW baselines). Loading one replaces the
other. **Neither will load in production** — a reference estate is
indistinguishable from real authorization data once it is in a database.

For the separate, lighter `SPARC_SEED_DEMO` sample records, see
[Configuration](Configuration).

## 6. Where to go next

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
