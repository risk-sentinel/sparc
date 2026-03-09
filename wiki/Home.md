# SPARC — Systemized Policy and Regulatory Controls

Welcome to the official SPARC wiki. SPARC is a Rails application for managing NIST 800-53 compliance documentation — System Security Plans (SSPs), Security Assessment Results (SARs), Component Definitions (CDEFs), Security Assessment Plans (SAPs), Plans of Action & Milestones (POA&Ms), and control catalogs. It replaces spreadsheet-based workflows with a web UI and REST API, with full OSCAL export support.

## Quick Links

| Resource | Link |
|----------|------|
| Repository | [Rebel-Raiders/sparc](https://github.com/Rebel-Raiders/sparc) |
| Releases | [All releases](https://github.com/Rebel-Raiders/sparc/releases) |
| Issues | [Open issues](https://github.com/Rebel-Raiders/sparc/issues) |
| Current Version | **v3.4.0** |

## Wiki Sections

### [Role-Based Access Control (RBAC)](RBAC)
29 roles aligned with NIST SP 800-37 Rev. 2 and OSCAL standards, 20 granular permission keys, instance vs. project scoping, and the Instance Admin bypass flag.

### [Screens & UI](Screens)
Complete inventory of every page in the application — Controls Layer, Implementation Layer, Assessment Layer, Project Management, Evidence, Admin, and API endpoints.

### [Core Functions & Features](Core-Functions)
OSCAL import/export/validation, document processing pipeline, SSP wizard, control mapping, audit logging, heatmap analytics, and more.

### [Integrations](Integrations)
Authentication providers (local, GitHub, GitLab, OIDC, LDAP), deployment patterns (Docker, AWS ECS Fargate, EC2, Azure), OSCAL ecosystem, and Active Storage.

### [Glossary](Glossary)
OSCAL and NIST RMF terminology reference.

### [Changelog](Changelog)
Release history from v2.0.0 through v3.4.0.

### [Architecture](Architecture)
Domain model hierarchy, database schema, service layer, and background job architecture.

### [Configuration Reference](Configuration)
All `SPARC_*` environment variables for auth, database, OIDC, LDAP, SMTP, logging, and deployment.

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Framework | Ruby 3.4.4, Rails 8.1.2 |
| Database | PostgreSQL 15 |
| Background Jobs | Sidekiq + Redis |
| Frontend | Hotwire (Turbo + Stimulus), Bootstrap 5.3 |
| Asset Pipeline | Propshaft, importmap (no Node build step) |
| Auth | OmniAuth (GitHub, GitLab, OIDC), net-ldap, bcrypt |
| OSCAL Validation | json_schemer (NIST OSCAL v1.1.2 schemas) |
| File Parsing | Roo (Excel), Nokogiri (XML) |
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

See [Configuration](Configuration) for all environment variables and [Integrations](Integrations) for auth provider setup.

## Contributing to the Wiki

This wiki is version-controlled via its own git repository. To contribute:

```bash
git clone https://github.com/Rebel-Raiders/sparc.wiki.git
cd sparc.wiki
# Edit or add .md files
git add . && git commit -m "Update wiki"
git push origin master
```

All pages use GitHub-flavored Markdown. Please include cross-references to issues, PRs, and commits where relevant.
