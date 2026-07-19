# SPARC — Systematic Policy and Regulatory Compliance

<p align="center">
  <img src="docs/images/sparc_logo_clear.png" alt="SPARC Logo" width="624">
</p>

**SPARC** is an open-source compliance documentation platform that transforms how
organizations manage NIST 800-53 security controls. It replaces fragmented
spreadsheets and siloed documents with a **coordinated, web-based, real-time**
**source of truth** — empowering security teams, assessors, system owners, and
program managers to document, assess, and prove compliance across the full RMF lifecycle.

> **Documentation:** See the **[SPARC Wiki](https://github.com/risk-sentinel/sparc/wiki)**
>for comprehensive documentation covering RBAC, screens, core functions, integrations,
>architecture, and configuration.

<p align="center">
  <img src="docs/images/sparc_home.jpg" alt="Home Page" width="75%">
</p>

---

<p align="center">
  <a href="https://sonarcloud.io/summary/new_code?id=risk-sentinel_sparc">
    <img src="https://sonarcloud.io/images/project_badges/sonarcloud-light.svg" alt="SonarQube Cloud">
  </a>
</p>

---

## Key Features

- **Full RMF Artifact Lifecycle** — Manage Catalogs, Profiles, Component Definitions
(CDEFs), SSPs, SAPs, SARs, and POA&Ms in one platform
- **SSP Creation Wizard** — Build System Security Plans from scratch by selecting
baselines and assembling components
- **Multi-Format Import** — Import from OSCAL JSON, OSCAL XML,
DISA STIGs (XCCDF), and InSpec profiles
- **OSCAL Export** — Export validated OSCAL v1.1.2 JSON for SSPs, CDEFs, Profiles,
SARs, and POA&Ms
- **HDF ↔ OSCAL Translation** — Convert scanner findings (HDF) to OSCAL SAR via the
MITRE hdf-libs bridge, with optional evidence back-matter enrichment
- **Document Review & Approval** — Optional review queue and approval workflow for
trust-store documents, gated by `SPARC_REQUIRE_DOCUMENT_APPROVAL`
- **Authoritative Sources & Federation** — Subscribe to HMAC-signed authoritative
content bundles published by federation peers
- **Interactive Heat Maps** — Visual compliance dashboards showing control status
by NIST family
- **Inline Field Editing** — Edit implementation details directly in the browser
- **Authentication & SSO** — Local login, GitHub/GitLab OAuth, OIDC (Okta/Keycloak/
Entra ID), and LDAP
- **Role-Based Access** — 29 NIST RMF roles with instance and authorization-boundary
scoping, boundary-scoped document access (AC-3), and an admin UI
- **Background Processing** — Async job processing for large files via Solid Queue
(database-backed; Sidekiq + Redis optional)
- **RESTful API** — Programmatic access at `/api/v1/`

---

Follow the [Quick Start Guide](docs/quick_start.md) to begin local use, testing,
and development of the application.

---

## Configuration

SPARC is configured via environment variables with sensible defaults. No configuration
is required for local development.

- **Full reference:** [docs/ENVIRONMENT_VARIABLES.md](docs/ENVIRONMENT_VARIABLES.md)
- **Production hardening guide:** [docs/PRODUCTION_SECURITY.md](docs/PRODUCTION_SECURITY.md) —
operator-facing checklist of every security-relevant env var, deployment-layer requirement,
and hardening verification steps
- **Quick start templates:** `.env.example` (development), `.env.production.example`
(production)

The centralized `SparcConfig` module (`app/models/sparc_config.rb`) reads all
variables with defaults.

---

## Documentation

📖 **Public documentation lives in the [SPARC Wiki](https://github.com/risk-sentinel/sparc/wiki)** —
the canonical, kept-current home for product docs:

| | | |
|---|---|---|
| [Getting Started](https://github.com/risk-sentinel/sparc/wiki/Getting-Started) | [Configuration](https://github.com/risk-sentinel/sparc/wiki/Configuration) | [Architecture](https://github.com/risk-sentinel/sparc/wiki/Architecture) |
| [RBAC](https://github.com/risk-sentinel/sparc/wiki/RBAC) | [Data Isolation](https://github.com/risk-sentinel/sparc/wiki/Data-Isolation) | [Screens](https://github.com/risk-sentinel/sparc/wiki/Screens) |
| [Core Functions](https://github.com/risk-sentinel/sparc/wiki/Core-Functions) | [Framework Mapping](https://github.com/risk-sentinel/sparc/wiki/Framework-Mapping) | [Integrations](https://github.com/risk-sentinel/sparc/wiki/Integrations) |

📦 **Release notes:** [GitHub Releases](https://github.com/risk-sentinel/sparc/releases)
(the wiki [Changelog](https://github.com/risk-sentinel/sparc/wiki/Changelog) is
a concise index).

### In-repo reference

Technical reference that ships next to the code — indexed in [**docs/MAP.md**](docs/MAP.md):

| Topic | Link |
| ------- | ------ |
| Environment variables (exhaustive) | [docs/ENVIRONMENT_VARIABLES.md](docs/ENVIRONMENT_VARIABLES.md) |
| REST API (per-endpoint + Postman) | [docs/API.md](docs/API.md) · [docs/api/](docs/api/) |
| OSCAL field mappings & schemas | [docs/oscal-data-mapping.md](docs/oscal-data-mapping.md) · [docs/data_mapping/](docs/data_mapping/) |
| Production security & hardening | [docs/PRODUCTION_SECURITY.md](docs/PRODUCTION_SECURITY.md) · [docs/AUTHENTICATION.md](docs/AUTHENTICATION.md) |
| Compliance artifacts | [docs/compliance/README.md](docs/compliance/README.md) · [NIST 800-53 mapping](docs/compliance/nist-sp800-53-rev5-mapping.md) · [OSCAL CDEFs](docs/compliance/oscal/cdefs/) |
| Contributing (internal dev docs) | [docs/dev/issue_rules.md](docs/dev/issue_rules.md) · [docs/dev/README.md](docs/dev/README.md) |

---

## RMF Artifact Lifecycle

The UI follows the OSCAL / RMF artifact dependency chain:

| Order | Artifact | Purpose | Status |
| ------- | ---------- | --------- | -------- |
| 1 | **Catalog** | Raw control definitions (e.g., NIST SP 800-53) | Implemented |
| 2 | **Profile** | Tailored baseline / selection set | Implemented |
| 3 | **Component Definition (CDEF)** | Reusable control implementations | Implemented |
| 4 | **System Security Plan (SSP)** | How the system implements the baseline | Implemented |
| 5 | **Assessment Plan (SAP)** | How the assessment will be performed | Implemented |
| 6 | **Assessment Results (SAR)** | Findings & evidence from assessment | Implemented |
| 7 | **POA&M** | Remediation tracking for weaknesses | Implemented |

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Ensure all checks pass:

    ```bash
    bundle exec rubocop && bundle exec brakeman && bundle exec rspec
    ```

4. Commit your changes and open a Pull Request against `main`

| Branch Prefix | Purpose |
| --------------- | --------- |
| `feature/` | New functionality |
| `fix/` | Bug fixes |
| `refactor/` | Code restructuring |
| `docs/` | Documentation |

---

## Acknowledgments

- **[NIST](https://www.nist.gov/)** — SP 800-53 control catalog framework
- [OSCAL](https://pages.nist.gov/OSCAL/) standard
- **[MITRE](https://www.mitre.org/)** — [SAF](https://saf.mitre.org/) and [Heimdall](https://github.com/mitre/heimdall2)
- **[Chef/Progress InSpec](https://www.inspec.io/)** — Compliance-as-code framework
- **[DISA](https://www.disa.mil/)** — STIGs in XCCDF format
- **[CIS](https://www.cisecurity.org/)** — Security benchmarks

### Contributors

- **[@clem-field](https://github.com/clem-field)** — Creator, lead developer, and
maintainer

---

## License

SPARC is released under the [Apache License, Version 2.0](LICENSE).
Copyright 2026 Risk Sentinel.

Third-party content sources and per-component license dispositions
are tracked in [`docs/compliance/THIRD_PARTY_NOTICES.md`](docs/compliance/THIRD_PARTY_NOTICES.md)
and [`docs/compliance/license-dispositions.yml`](docs/compliance/license-dispositions.yml).
Canonical text for every license referenced by SPARC's SBOM lives under
[`LICENSES/`](LICENSES/).
