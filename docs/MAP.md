<!-- markdownlint-disable MD013 -->
# SPARC Documentation Map

Central, navigable index of everything under [`docs/`](.). SPARC (Systematic
and Regulatory Compliance) is a Rails 8.1 application for managing NIST SP 800-53
compliance documentation — SSPs, SARs, SAPs, POA&Ms, CDEFs, and control
catalogs — with a REST API and OSCAL v1.1.2 import/export.

> **Maintenance:** when you add or move a file in `docs/`, add or update its row
> here in the same PR. This map is the entry point referenced from the repo
> README and wiki (#606).

---

## Start here — by audience

| You are… | Read in this order |
|---|---|
| **Evaluating SPARC** | [README](../README.md) → [TECH_STACK](TECH_STACK.md) → [API introduction](api/introduction.md) |
| **Deploying / operating** | [DOCKER](DOCKER.md) → [ENVIRONMENT_VARIABLES](ENVIRONMENT_VARIABLES.md) → [PRODUCTION_SECURITY](PRODUCTION_SECURITY.md) → [troubleshooting](troubleshooting.md) → [runbooks/](dev/runbooks/) |
| **Integrating via API** | [api/introduction](api/introduction.md) → [api/authentication](api/authentication.md) → [api/INVENTORY](api/INVENTORY.md) (per-endpoint) → [api/README](api/README.md) (Postman) |
| **Contributing code** | [dev/issue_rules](dev/issue_rules.md) → [dev/Implemenation_plan](dev/Implemenation_plan.md) → [dev/Developer_Collision_Avoidance_Plan](dev/Developer_Collision_Avoidance_Plan.md) → [development-https](development-https.md) |
| **Reviewing security** | [PRODUCTION_SECURITY](PRODUCTION_SECURITY.md) → [AUTHENTICATION](AUTHENTICATION.md) → [security-scanning](security-scanning.md) → [compliance/](compliance/) → [security/SCANNER_FINDINGS_AUDIT](security/SCANNER_FINDINGS_AUDIT.md) |
| **Authoring compliance / OSCAL** | [compliance/README](compliance/README.md) → [compliance/nist-sp800-53-rev5-mapping](compliance/nist-sp800-53-rev5-mapping.md) → [oscal-data-mapping](oscal-data-mapping.md) → [data_mapping/](data_mapping/) |
| **Modeling data / architecture** | [oscal-data-mapping](oscal-data-mapping.md) → [data_mapping/layer_relationships](data_mapping/layer_relationships.md) → the per-document maps in [data_mapping/](data_mapping/) |

---

## 1. Getting started, deployment & operations

| Doc | Purpose |
|---|---|
| [DOCKER.md](DOCKER.md) | Docker / Docker Compose deployment |
| [ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md) | All runtime configuration env vars |
| [development-https.md](development-https.md) | Local HTTPS (mkcert) setup |
| [puma-dev.md](puma-dev.md) | Puma in development |
| [OKTA_DEV_SETUP.md](OKTA_DEV_SETUP.md) | Okta/OIDC local SSO setup |
| [troubleshooting.md](troubleshooting.md) | Common problems and fixes |
| [dev/runbooks/prod-db-verification.md](dev/runbooks/prod-db-verification.md) | Production DB verification (SSM → read-only psql) |
| [ADMIN_CREDENTIAL_ROTATION.md](ADMIN_CREDENTIAL_ROTATION.md) / [dev/admin_credential_rotation.md](dev/admin_credential_rotation.md) | Rotating the admin credential (ops + developer reference) |

## 2. Architecture & technology

| Doc | Purpose |
|---|---|
| [TECH_STACK.md](TECH_STACK.md) | Ruby/Rails/Postgres/Hotwire stack overview |
| [architecture.md](architecture.md) | Component/data-flow diagram + domain ERD (mermaid) |
| [oscal-data-mapping.md](oscal-data-mapping.md) | How SPARC's domain model maps to OSCAL |
| [framework_mapping_plan.md](framework_mapping_plan.md) | STIG / CIS / CCI / SCAP → OSCAL framework mapping plan |
| [catalog-schema.md](catalog-schema.md) | Control-catalog schema |

## 3. Authentication, authorization & security

| Doc | Purpose |
|---|---|
| [AUTHENTICATION.md](AUTHENTICATION.md) | Auth & authorization model (local, OIDC, SA tokens) |
| [PRODUCTION_SECURITY.md](PRODUCTION_SECURITY.md) | Production security posture & hardening |
| [SPARC_HASH_ROTATION.md](SPARC_HASH_ROTATION.md) | Rotating the `SPARC_HASH` master secret |
| [security-scanning.md](security-scanning.md) | Security scanning pipeline (Trivy, Brakeman, Grype, etc.) |
| [security/SCANNER_FINDINGS_AUDIT.md](security/SCANNER_FINDINGS_AUDIT.md) | Audit / disposition of scanner findings |
| [banners/](banners/) | Login consent-banner samples (DoD, demo, sample) |

## 4. REST API

| Doc | Purpose |
|---|---|
| [api/introduction.md](api/introduction.md) | API overview & getting started |
| [api/authentication.md](api/authentication.md) | Bearer-token auth & the session cookie bridge |
| [api/INVENTORY.md](api/INVENTORY.md) | **Index of all endpoints** (links the 18 per-resource docs in `api/endpoints/`) |
| [api/errors.md](api/errors.md) · [api/pagination.md](api/pagination.md) | Error format & pagination conventions |
| [api/README.md](api/README.md) | Postman collection + local/prod environments |
| [api/SPARC-API-Review-and-Automated-Testing-Procedure.md](api/SPARC-API-Review-and-Automated-Testing-Procedure.md) | API review & automated-test procedure |
| [API.md](API.md) | Top-level REST API summary |

## 5. OSCAL data models & field mappings

The [`data_mapping/`](data_mapping/) folder documents how each document type maps to OSCAL:

| Doc | Purpose |
|---|---|
| [data_mapping/layer_relationships.md](data_mapping/layer_relationships.md) | How the OSCAL layers relate (catalog → profile → SSP → SAP → SAR → POA&M) |
| [data_mapping/ssp.md](data_mapping/ssp.md) · [sar.md](data_mapping/sar.md) · [sap.md](data_mapping/sap.md) · [poam.md](data_mapping/poam.md) · [cdef.md](data_mapping/cdef.md) · [catalogs.md](data_mapping/catalogs.md) | Per-document OSCAL field maps |
| [data_mapping/metadata_section.md](data_mapping/metadata_section.md) · [backmatter_section.md](data_mapping/backmatter_section.md) | Shared metadata & back-matter standards |
| [data_mapping/baseline_resolved_profile.md](data_mapping/baseline_resolved_profile.md) · [contro_mapping.md](data_mapping/contro_mapping.md) | Baseline→resolved-profile relationship; foreign-input control mapping |
| [ssp-columns.md](ssp-columns.md) · [sar-columns.md](sar-columns.md) | Spreadsheet column references (SSP / SAR import) |

## 6. User roles & permissions

| Doc | Purpose |
|---|---|
| [groups_users/groups_users.md](groups_users/groups_users.md) | SPARC roles & user relationships |
| [groups_users/mindmap.md](groups_users/mindmap.md) | Organizational structure mind map |

## 7. Compliance & OSCAL artifacts

| Doc | Purpose |
|---|---|
| [compliance/README.md](compliance/README.md) | Compliance process guide & sparc-iac integration model |
| [compliance/nist-sp800-53-rev5-mapping.md](compliance/nist-sp800-53-rev5-mapping.md) | NIST SP 800-53 Rev 5 HIGH-baseline control mapping (+ Section 508 / WCAG row) |
| [compliance/oscal/cdefs/](compliance/oscal/cdefs/) | OSCAL v1.1.2 component definitions (5 CDEFs) |
| [compliance/hdf-oscal-bridge-demo.md](compliance/hdf-oscal-bridge-demo.md) | HDF ↔ OSCAL translation pipeline demo |
| [compliance/sparc-findings.yml](compliance/sparc-findings.yml) · [threshold.yml](compliance/threshold.yml) | CVE finding dispositions & security-gate thresholds |
| [compliance/license-policy.yml](compliance/license-policy.yml) · [license-dispositions.yml](compliance/license-dispositions.yml) · [THIRD_PARTY_NOTICES.md](compliance/THIRD_PARTY_NOTICES.md) | License policy, dispositions, third-party notices |

## 8. Developer process & planning

| Doc | Purpose |
|---|---|
| [dev/issue_rules.md](dev/issue_rules.md) | **Mandatory** issue-process workflow, guardrails, compliance-artifact requirements |
| [dev/Implemenation_plan.md](dev/Implemenation_plan.md) | Phased roadmap & issue tracking |
| [dev/Developer_Collision_Avoidance_Plan.md](dev/Developer_Collision_Avoidance_Plan.md) | Domain ownership, hot files, migration coordination |
| [dev/release_notes.md](dev/release_notes.md) | Historical stacked release notes (current notes live on GitHub Releases) |
| [dev/secrets_variables.md](dev/secrets_variables.md) | GitHub Actions secrets & variables inventory |
| [dev/a11y_worm_refactor_plan.md](dev/a11y_worm_refactor_plan.md) · [a11y_audit.md](dev/a11y_audit.md) | Accessibility WORM color refactor plan & live WCAG audit (v1.8.6) |
| [dev/aws_labs_cdef_coverage.md](dev/aws_labs_cdef_coverage.md) · [aws_security_hub_nist_mapping.md](dev/aws_security_hub_nist_mapping.md) | AWS Labs CDEF coverage; AWS Security Hub → NIST mapping |

## 9. CI, scanning & generated artifacts

| Path | Purpose |
|---|---|
| [hdf/](hdf/) | Generated HDF / SBOM scan outputs (gitleaks, SAST, Trivy fs/container) — build artifacts, not hand-edited |
| [ci/](ci/) | Pipeline performance metrics (CSV + chart) |
| [regression_testing/regression_plan.md](regression_testing/regression_plan.md) | Regression test plan |

## 10. Media & marketing

| Path | Purpose |
|---|---|
| [images/](images/) | Screenshots, logos, intro videos |
| [SPARC_Video_Script.md](SPARC_Video_Script.md) | Intro-video script |

---

## Coverage of the #606 focus areas

| Area | Primary docs |
|---|---|
| **Technology stack** | [TECH_STACK](TECH_STACK.md), [DOCKER](DOCKER.md), [ENVIRONMENT_VARIABLES](ENVIRONMENT_VARIABLES.md) |
| **User roles & permissions** | [groups_users/](groups_users/), [AUTHENTICATION](AUTHENTICATION.md) |
| **Data architecture** | [oscal-data-mapping](oscal-data-mapping.md), [data_mapping/](data_mapping/), [catalog-schema](catalog-schema.md) |
| **Security model** | [PRODUCTION_SECURITY](PRODUCTION_SECURITY.md), [AUTHENTICATION](AUTHENTICATION.md), [security-scanning](security-scanning.md), [compliance/](compliance/), [SPARC_HASH_ROTATION](SPARC_HASH_ROTATION.md) |
| **API / integration** | [api/](api/) (28 docs; index at [api/INVENTORY](api/INVENTORY.md)) |
| **Methodology / compliance** | [compliance/](compliance/), [framework_mapping_plan](framework_mapping_plan.md) |

---

## Gap analysis (resolved under #606)

The documentation gaps observed while building this map have been addressed as
part of the #606 wiki + docs refresh:

1. ✅ **Top-level architecture diagram** — added [`architecture.md`](architecture.md)
   (mermaid component/data-flow diagram).
2. ✅ **Consolidated data-model / ERD** — domain ERD added in
   [`architecture.md`](architecture.md).
3. ✅ **Glossary** — NIST/OSCAL/SPARC terms (SSP, SAR, SAP, POA&M, CDEF, KSI,
   baseline, profile, back-matter, federation) are defined in the wiki
   [Glossary](https://github.com/risk-sentinel/sparc/wiki/Glossary).
4. ✅ **Getting-started quick-start** — the wiki
   [Getting Started](https://github.com/risk-sentinel/sparc/wiki/Getting-Started)
   page provides a "first 15 minutes" walkthrough.
5. ✅ **Wiki ↔ docs/ sync** — the wiki sidebar links this map as its `docs/`
   entry point, and the wiki is mirrored from the repo `wiki/` directory.

---

*Generated for #606. Keep rows in sync as `docs/` changes.*
