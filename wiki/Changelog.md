# Changelog

All notable changes to SPARC are documented here. Versions follow semantic versioning. Links reference the [Rebel-Raiders/sparc](https://github.com/Rebel-Raiders/sparc) repository.

---

## v3.4.3 -- HTTPS Enforcement & Security Headers (2026-03-09)

- Enforce HTTPS-only traffic with HSTS preload, subdomains, and 1-year max-age ([Issue #106](https://github.com/Rebel-Raiders/sparc/issues/106))
- Health-check endpoint `/up` excluded from SSL redirect for container probes (ALB, Kubernetes)
- Security headers middleware: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`, `X-Permitted-Cross-Domain-Policies`
- Content Security Policy enabled in report-only mode (Bootstrap CDN allowlisted)
- Centralized version constant in `SparcConfig::VERSION` — no longer hardcoded in layouts
- HTTPS enforcement and security headers test coverage

## v3.4.2 -- Hide Expected Excel Fields from Upload UI (2026-03-09)

- Removed hardcoded "Expected Excel Format" tables from SSP and SAR upload pages ([Issue #129](https://github.com/Rebel-Raiders/sparc/issues/129))
- Replaced with concise import notes referencing data mapping definitions (`lib/data_mappings/`)
- OSCAL files (JSON, XML, YAML) noted as auto-detected with no mapping required

## v3.4.1 -- Full Multi-Format Support (2026-03-09)

- Full OSCAL tri-format support: import and export JSON, YAML, and XML for all six document types ([Issue #120](https://github.com/Rebel-Raiders/sparc/issues/120))
- Six new YAML parser services (SSP, SAR, POAM, Profile, CDEF, SAP) using delegation pattern to avoid logic duplication
- New SAP XML parser service (`SapXmlParserService`) completing XML import coverage for all document types
- OSCAL export format conversion via `OscalExportFormatService` (JSON to YAML/XML)
- OSCAL JSON-to-XML converter (`OscalJsonToXmlConverter`) with Nokogiri XML::Builder and OSCAL namespace
- XSD schema validation for XML exports via `Nokogiri::XML::Schema` with 7 OSCAL XSD schemas
- Format auto-detection service (`OscalFormatDetectionService`) with extension and content sniffing
- Bootstrap 5 split-button dropdown for OSCAL export format selection across all document views
- Upload forms updated to accept `.yaml` and `.yml` extensions
- Fixed pre-existing bug in `CdefJsonParserService#parse_oscal_cdef` (wrong method call for batch insert)

## v3.4.0 -- Robust Audit Logging (2026-03-09)

- Comprehensive audit logging with approximately 80 tracked actions across 16 categories ([PR #121](https://github.com/Rebel-Raiders/sparc/pull/121), [Issue #101](https://github.com/Rebel-Raiders/sparc/issues/101))
- Polymorphic subject tracking (`subject_type`/`subject_id`) for resource-level traceability
- Admin audit log UI at `/admin/audit_logs` with filtering, detail views, and CSV export
- `Auditable` controller concern providing a DRY `audit_log` helper method
- Structured JSON logging to `Rails.logger.info` for integration with CloudWatch/Datadog ([PR #122](https://github.com/Rebel-Raiders/sparc/pull/122))
- Fixed silent audit failures in `ControlMappingsController`
- Authorization failure logging for security monitoring

## v3.3.0 -- Navbar Redesign (2026-03-09)

- Redesigned navbar with OSCAL layer dropdowns organized by function:
  - **Controls** (blue) -- Catalogs, Baselines, Control Mappings
  - **Implementation** (green) -- SSP, CDEF
  - **Assessment** (orange) -- SAP, SAR, POA&M
- User avatar system with upload and remove functionality
- Version badge displayed in the navbar
- [PR #118](https://github.com/Rebel-Raiders/sparc/pull/118) -- Control Mapping Models

## v3.2.1 -- Bug Fix (2026-03-09)

- Fixed user dropdown menu not opening after Turbo navigation ([PR #117](https://github.com/Rebel-Raiders/sparc/pull/117), [Issue #116](https://github.com/Rebel-Raiders/sparc/issues/116))

## v3.2.0 -- RBAC Enforcement & Summary Tiles (2026-03-08)

- Full OSCAL/RMF/FedRAMP role coverage with 29 roles ([PR #115](https://github.com/Rebel-Raiders/sparc/pull/115))
- Restricted catalog and baseline editing to Policy Manager and Instance Admin ([Issue #99](https://github.com/Rebel-Raiders/sparc/issues/99))
- Summary tiles across all main sections for at-a-glance status ([Issue #103](https://github.com/Rebel-Raiders/sparc/issues/103))
- Added SPARC SME and Evidence Integration Engineer roles ([Issue #96](https://github.com/Rebel-Raiders/sparc/issues/96))

## v3.1.1 -- SSP Rebrand (2026-03-08)

- Rebranded "Controls Implementation" to "System Security Plan" throughout the application ([PR #113](https://github.com/Rebel-Raiders/sparc/pull/113), [Issue #97](https://github.com/Rebel-Raiders/sparc/issues/97))

## v3.1.0 -- RBAC Admin Screens (2026-03-08)

- User administration screen with search, suspend, and reactivate capabilities ([Issue #93](https://github.com/Rebel-Raiders/sparc/issues/93))
- Role administration with permission matrix editing ([Issue #94](https://github.com/Rebel-Raiders/sparc/issues/94))
- Project administration with member and role management ([Issue #92](https://github.com/Rebel-Raiders/sparc/issues/92))
- [PR #112](https://github.com/Rebel-Raiders/sparc/pull/112)

## v3.0.0 -- Authentication & RBAC Foundation (2026-03-08)

- Local email/password authentication conforming to NIST SP 800-63B ([Issue #70](https://github.com/Rebel-Raiders/sparc/issues/70))
- OAuth support for GitHub and GitLab ([Issue #34](https://github.com/Rebel-Raiders/sparc/issues/34))
- OIDC support for Okta, Keycloak, and generic providers ([Issue #33](https://github.com/Rebel-Raiders/sparc/issues/33), [Issue #35](https://github.com/Rebel-Raiders/sparc/issues/35))
- LDAP authentication with bind-and-search pattern
- RBAC system with 29 seeded roles and 20 permission keys
- Login page restructure with OSCAL overview ([Issue #90](https://github.com/Rebel-Raiders/sparc/issues/90), [Issue #102](https://github.com/Rebel-Raiders/sparc/issues/102))
- Fixed local login and admin password reset flow ([Issue #91](https://github.com/Rebel-Raiders/sparc/issues/91))
- [PR #73](https://github.com/Rebel-Raiders/sparc/pull/73), [PR #104](https://github.com/Rebel-Raiders/sparc/pull/104), [PR #105](https://github.com/Rebel-Raiders/sparc/pull/105)

## v2.0.1 (2026-03-06)

- Dark mode fixes for consistent theming ([Issue #47](https://github.com/Rebel-Raiders/sparc/issues/47))
- Bug fixes for SSP viewing and inline editing ([Issue #41](https://github.com/Rebel-Raiders/sparc/issues/41), [Issue #42](https://github.com/Rebel-Raiders/sparc/issues/42))

## v2.0.0 -- OSCAL Full Schema (2026-03-06)

### UI & Framework
- Bootstrap 5.3 adoption for modern responsive layout ([Issue #51](https://github.com/Rebel-Raiders/sparc/issues/51))
- Interactive heat maps for control status visualization ([Issue #81](https://github.com/Rebel-Raiders/sparc/issues/81))
- Dashboard aggregate heatmap across all documents ([Issue #83](https://github.com/Rebel-Raiders/sparc/issues/83))

### OSCAL Compliance
- Full OSCAL schema uplift for all artifact types ([Issue #58](https://github.com/Rebel-Raiders/sparc/issues/58))
- OSCAL schema validation against official NIST schemas ([Issue #45](https://github.com/Rebel-Raiders/sparc/issues/45))
- OSCAL metadata management and inheritance ([Issue #52](https://github.com/Rebel-Raiders/sparc/issues/52))
- Vendor-neutral data mapping schema ([Issue #54](https://github.com/Rebel-Raiders/sparc/issues/54))

### Document Types
- SSP wizard, enrichment, and enhanced export ([Issue #30](https://github.com/Rebel-Raiders/sparc/issues/30))
- SAR creation, enrichment, and wizard ([Issue #32](https://github.com/Rebel-Raiders/sparc/issues/32))
- SAP creation ([Issue #28](https://github.com/Rebel-Raiders/sparc/issues/28))
- POA&M import and management ([Issue #27](https://github.com/Rebel-Raiders/sparc/issues/27), [Issue #29](https://github.com/Rebel-Raiders/sparc/issues/29))
- Component Definition (CDEF) support

### Other
- Evidence and attestation collection ([Issue #31](https://github.com/Rebel-Raiders/sparc/issues/31))
- Project orchestration with RMF roles ([Issue #46](https://github.com/Rebel-Raiders/sparc/issues/46))
- Document duplication ([Issue #56](https://github.com/Rebel-Raiders/sparc/issues/56))
- Control catalog and family CRUD ([Issue #48](https://github.com/Rebel-Raiders/sparc/issues/48), [Issue #49](https://github.com/Rebel-Raiders/sparc/issues/49))
