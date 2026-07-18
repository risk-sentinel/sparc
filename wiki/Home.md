# SPARC — Systematic and Regulatory Compliance

Welcome to the official SPARC wiki. SPARC is a Rails 8.1 application for managing NIST SP 800-53 compliance documentation — System Security Plans (SSPs), Security Assessment Results (SARs), Security Assessment Plans (SAPs), Plans of Action & Milestones (POA&Ms), Component Definitions (CDEFs), and control catalogs. It replaces spreadsheet-based workflows with a web UI and REST API, with full OSCAL v1.1.2 import/export support.

## Quick Links

| Resource | Link |
|----------|------|
| Repository | [risk-sentinel/sparc](https://github.com/risk-sentinel/sparc) |
| Releases | [All releases](https://github.com/risk-sentinel/sparc/releases) |
| Issues | [Open issues](https://github.com/risk-sentinel/sparc/issues) |
| Documentation index | [`docs/MAP.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/MAP.md) — full `docs/` inventory |
| Current Version | **v1.12.1** |

> **Versioning note:** SPARC's public release line is **v1.x** (current: v1.12.1).
> Older `v2.x`–`v3.x` entries in the [Changelog](Changelog) are the project's
> pre-reset numbering, retained for historical traceability.

## Wiki Sections

### [Getting Started](Getting-Started)
First-15-minutes setup — Docker quick start, seeding the NIST catalogs, first login, and where to go next.

### [Role-Based Access Control (RBAC)](RBAC)
29 roles aligned with NIST SP 800-37 Rev. 2 and OSCAL standards, granular permission keys, instance vs. authorization-boundary scoping, and the Instance Admin bypass flag.

### [Data Isolation](Data-Isolation)
How SPARC organizes and isolates data — Organization → Authorization Boundary → OSCAL artifacts — and the boundary-scoped access model (NIST AC-3).

### [Screens & UI](Screens)
Complete inventory of every page in the application — Controls Layer, Implementation Layer, Assessment Layer, Authorization Boundary Management, Evidence, Federation, and Admin.

### [Core Functions & Features](Core-Functions)
OSCAL import/export/validation, the document processing pipeline, SSP/SAR wizards, control mapping, converters (CCI / AWS), KSI validations, the HDF ↔ OSCAL bridge, authoritative-source federation, and audit logging.

### [Framework Mapping](Framework-Mapping)
How SPARC maps external frameworks — DISA STIG, CIS Benchmarks, CCI, SCAP/OVAL — to NIST SP 800-53 via OSCAL, and the roadmap for expanding coverage.

### [Architecture](Architecture)
Domain model hierarchy, database schema, the service layer, and background-job architecture.

### [Integrations](Integrations)
Authentication providers (local, GitHub, GitLab, OIDC, LDAP), deployment patterns (Docker, AWS), the OSCAL ecosystem, and Active Storage.

### [API Reference](API-Reference)
REST API overview and a pointer to the full per-endpoint docs and Postman collection under [`docs/api/`](https://github.com/risk-sentinel/sparc/tree/main/docs/api).

### [Configuration Reference](Configuration)
All `SPARC_*` environment variables for auth, database, OIDC, LDAP, SMTP, logging, and deployment.

### [Glossary](Glossary)
OSCAL and NIST RMF terminology reference.

### [FAQ & Troubleshooting](FAQ)
Common questions and fixes for setup, auth, OSCAL validation, and deployment.

### [Contributing](Contributing)
How to propose changes — the mandatory issue process, branching, and compliance-artifact requirements.

### [Changelog](Changelog)
Full release history — the current v1.x line plus the legacy v2.x–v3.x entries.

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Framework | Ruby 3.4.4, Rails 8.1.3 |
| Database | PostgreSQL 15 |
| Background Jobs | Solid Queue (default) · Sidekiq + Redis (optional) |
| Frontend | Hotwire (Turbo + Stimulus), Bootstrap 5.3 |
| Asset Pipeline | Propshaft, importmap (no Node build step) |
| Auth | OmniAuth (GitHub, GitLab, OIDC), net-ldap, bcrypt |
| OSCAL Validation | json_schemer (NIST OSCAL v1.1.2 schemas, baked into the container) |
| File Parsing | Nokogiri (XML) |
| Containerization | Docker, Docker Compose |

## Getting Started

```bash
# Docker (recommended)
docker compose up --build
docker compose exec web bin/rails db:seed

# Local development
bundle install
bin/rails db:create db:migrate db:seed
bin/rails server
```

See [Getting Started](Getting-Started) for a guided walkthrough, [Configuration](Configuration) for all environment variables, and [Integrations](Integrations) for auth provider setup.

## Contributing to the Wiki

This wiki is mirrored from the `wiki/` directory in the main repository and
published via `wiki/PUSH_TO_WIKI.sh`. **Edit the source under `wiki/` in
[risk-sentinel/sparc](https://github.com/risk-sentinel/sparc/tree/main/wiki)
through the normal issue/PR process** — direct edits to the wiki git repo are
overwritten on the next sync.

All pages use GitHub-flavored Markdown. Please include cross-references to
issues, PRs, and commits where relevant. See [Contributing](Contributing) for
the full process.
