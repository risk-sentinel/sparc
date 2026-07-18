<!-- markdownlint-disable MD013 -->
# SPARC `docs/` Index

SPARC (Systematic and Regulatory Compliance) is a Rails 8.1 application for
managing NIST SP 800-53 compliance documentation — SSPs, SARs, SAPs, POA&Ms,
CDEFs, and control catalogs — with a REST API and OSCAL v1.1.2 import/export.

> **📖 Public documentation lives in the [GitHub wiki](https://github.com/risk-sentinel/sparc/wiki).**
> The wiki is the canonical, kept-current home for product usage, configuration,
> architecture, RBAC, screens, integrations, and the changelog. **When you change
> something public-facing, update the wiki** (source under [`wiki/`](../wiki),
> mirrored via `wiki/PUSH_TO_WIKI.sh`).
>
> This page indexes what lives **in the repo** under `docs/`: technical reference
> that ships next to the code, artifacts consumed by CI, and internal dev notes.

---

## Public docs → the wiki

| Topic | Wiki page |
|---|---|
| Getting started | [Getting Started](https://github.com/risk-sentinel/sparc/wiki/Getting-Started) |
| Configuration (env vars) | [Configuration](https://github.com/risk-sentinel/sparc/wiki/Configuration) |
| Architecture (mermaid) | [Architecture](https://github.com/risk-sentinel/sparc/wiki/Architecture) |
| Roles & permissions | [RBAC](https://github.com/risk-sentinel/sparc/wiki/RBAC) · [Data Isolation](https://github.com/risk-sentinel/sparc/wiki/Data-Isolation) |
| Screens / UI | [Screens](https://github.com/risk-sentinel/sparc/wiki/Screens) |
| Features | [Core Functions](https://github.com/risk-sentinel/sparc/wiki/Core-Functions) · [Framework Mapping](https://github.com/risk-sentinel/sparc/wiki/Framework-Mapping) |
| Integrations / auth providers | [Integrations](https://github.com/risk-sentinel/sparc/wiki/Integrations) |
| Release history | [Changelog](https://github.com/risk-sentinel/sparc/wiki/Changelog) · [GitHub Releases](https://github.com/risk-sentinel/sparc/releases) |

---

## In-repo reference

### Deployment & operations

| Doc | Purpose |
|---|---|
| [DOCKER.md](DOCKER.md) | Docker / Docker Compose deployment |
| [ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md) | **Exhaustive** env-var reference (incl. operational/CI vars); the wiki Configuration page is the curated public subset |
| [PRODUCTION_SECURITY.md](PRODUCTION_SECURITY.md) | Production security posture & hardening |
| [troubleshooting.md](troubleshooting.md) | Common problems and fixes |
| [development-https.md](development-https.md) · [puma-dev.md](puma-dev.md) | Local HTTPS (mkcert) & Puma in development |
| [OKTA_DEV_SETUP.md](OKTA_DEV_SETUP.md) | Okta/OIDC local SSO setup |
| [ADMIN_CREDENTIAL_ROTATION.md](ADMIN_CREDENTIAL_ROTATION.md) · [SPARC_HASH_ROTATION.md](SPARC_HASH_ROTATION.md) | Rotating the admin credential and the `SPARC_HASH` master secret |

### Security

| Doc | Purpose |
|---|---|
| [AUTHENTICATION.md](AUTHENTICATION.md) | Auth & authorization model (local, OIDC, SA tokens) |
| [security-scanning.md](security-scanning.md) | Security scanning pipeline (Trivy, Brakeman, Grype, etc.) |
| [security/SCANNER_FINDINGS_AUDIT.md](security/SCANNER_FINDINGS_AUDIT.md) | Audit / disposition of scanner findings |
| [banners/](banners/) | Login consent-banner samples (DoD, demo, sample) |

### Data models & OSCAL field mappings

| Doc | Purpose |
|---|---|
| [oscal-data-mapping.md](oscal-data-mapping.md) | How SPARC's domain model maps to OSCAL |
| [catalog-schema.md](catalog-schema.md) | Control-catalog schema |
| [data_mapping/](data_mapping/) | Per-document OSCAL field maps (SSP/SAR/SAP/POA&M/CDEF/catalogs, metadata & back-matter, baseline→resolved-profile, control mapping) |
| [ssp-columns.md](ssp-columns.md) · [sar-columns.md](sar-columns.md) | Spreadsheet column references (SSP / SAR import) |

### REST API

| Doc | Purpose |
|---|---|
| [api/introduction.md](api/introduction.md) · [api/authentication.md](api/authentication.md) | API overview & bearer-token / session-cookie auth |
| [api/INVENTORY.md](api/INVENTORY.md) | **Index of all endpoints** (links the per-resource docs in `api/endpoints/`) |
| [api/errors.md](api/errors.md) · [api/pagination.md](api/pagination.md) | Error format & pagination conventions |
| [api/README.md](api/README.md) | Postman collection + local/prod environments |
| [API.md](API.md) | Top-level REST API summary |

### Compliance & OSCAL artifacts

| Doc | Purpose |
|---|---|
| [compliance/README.md](compliance/README.md) | Compliance process guide & sparc-iac integration model |
| [compliance/nist-sp800-53-rev5-mapping.md](compliance/nist-sp800-53-rev5-mapping.md) | NIST SP 800-53 Rev 5 HIGH-baseline control mapping |
| [compliance/oscal/cdefs/](compliance/oscal/cdefs/) | OSCAL v1.1.2 component definitions (5 CDEFs) |
| [compliance/hdf-oscal-bridge-demo.md](compliance/hdf-oscal-bridge-demo.md) | HDF ↔ OSCAL translation pipeline demo |
| [compliance/sparc-findings.yml](compliance/sparc-findings.yml) · [threshold.yml](compliance/threshold.yml) | CVE finding dispositions & security-gate thresholds (consumed by CI) |
| [compliance/license-policy.yml](compliance/license-policy.yml) · [license-dispositions.yml](compliance/license-dispositions.yml) · [THIRD_PARTY_NOTICES.md](compliance/THIRD_PARTY_NOTICES.md) | License policy, dispositions, third-party notices |

### Internal development docs

See [`dev/README.md`](dev/README.md) — **internal** process/roadmap/engineering
reference (issue rules, implementation plan, collision-avoidance plan, secrets
inventory, AWS/UBI9/HDF findings, a11y audit, credential rotation). Not public.

### Generated artifacts (not hand-edited)

| Path | Purpose |
|---|---|
| [hdf/](hdf/) | Generated HDF / SBOM scan outputs (gitleaks, SAST, Trivy fs/container) |
| [ci/](ci/) | Pipeline performance metrics (CSV + chart) |

---

*Public documentation is on the [wiki](https://github.com/risk-sentinel/sparc/wiki); keep it in sync as the app changes.*
