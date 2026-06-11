# NIST SP 800-53 Rev 5 HIGH Baseline Control Mapping

**System:** SPARC (Systematic Policy and Regulatory Compliance)
**Baseline:** NIST SP 800-53 Revision 5 -- HIGH Impact
**Last Reviewed:** 2026-03-21
**Version:** 1.0
**Maintainer:** SPARC Security Team

---

## How to Use This Document

This document maps NIST SP 800-53 Rev 5 HIGH baseline controls to their
implementation within the SPARC ecosystem. Each control is assigned a
**Responsibility** indicating which component owns the implementation and a
**Status** reflecting the current state.

**Responsibility values:**

| Label | Meaning |
|---|---|
| Application (SPARC) | Implemented in SPARC application code |
| Infrastructure (sparc-iac) | Terraform / IaC in the sparc-iac repository |
| CSP Inherited | Cloud service provider responsibility (AWS/Azure) |
| Organizational Policy | Requires organization-level policy documents |
| Hybrid | Shared across two or more of the above |

**Status values:**

| Status | Meaning |
|---|---|
| Implemented | Control is fully satisfied |
| Partial | Some requirements met; gaps documented |
| Planned | Implementation scheduled but not yet complete |
| N/A | Not applicable to this system type |
| CSP Inherited | Fully inherited from CSP |

**⚠ Conditional coverage:** Some controls have implementation status that
varies by deployment configuration. These are marked with **⚠ CONDITIONAL**
in the Implementation Summary column. The most significant variable is the
authentication mode — see [`docs/dev/issue_rules.md`](../dev/issue_rules.md)
for the full auth mode coverage matrix. Key takeaway: **OIDC with
`SPARC_OIDC_FORCE_MFA=true` is required for full IA-2/MFA coverage.**

---

## Table of Contents

- [Integration with sparc-iac](#integration-with-sparc-iac)
- [Automated Evidence Collection](#automated-evidence-collection)
- [AC -- Access Control](#ac----access-control)
- [AT -- Awareness and Training](#at----awareness-and-training)
- [AU -- Audit and Accountability](#au----audit-and-accountability)
- [CA -- Assessment, Authorization, and Monitoring](#ca----assessment-authorization-and-monitoring)
- [CM -- Configuration Management](#cm----configuration-management)
- [CP -- Contingency Planning](#cp----contingency-planning)
- [IA -- Identification and Authentication](#ia----identification-and-authentication)
- [IR -- Incident Response](#ir----incident-response)
- [MA -- Maintenance](#ma----maintenance)
- [MP -- Media Protection](#mp----media-protection)
- [PE -- Physical and Environmental Protection](#pe----physical-and-environmental-protection)
- [PL -- Planning](#pl----planning)
- [PM -- Program Management](#pm----program-management)
- [PS -- Personnel Security](#ps----personnel-security)
- [PT -- Personally Identifiable Information Processing and Transparency](#pt----personally-identifiable-information-processing-and-transparency)
- [RA -- Risk Assessment](#ra----risk-assessment)
- [SA -- System and Services Acquisition](#sa----system-and-services-acquisition)
- [SC -- System and Communications Protection](#sc----system-and-communications-protection)
- [SI -- System and Information Integrity](#si----system-and-information-integrity)
- [SR -- Supply Chain Risk Management](#sr----supply-chain-risk-management)
- [Summary Statistics](#summary-statistics)

---

## Integration with sparc-iac

SPARC uses a **two-repository model** to separate application logic from
infrastructure provisioning:

| Repository | Scope | Examples |
|---|---|---|
| **sparc** (this repo) | Application-level controls: authentication, authorization, audit logging, session management, input validation, OSCAL export/validation | Rails controllers, models, services |
| **sparc-iac** | Infrastructure controls: network segmentation, encryption at rest, backup/restore, container hardening, WAF, load balancing, DNS, TLS termination | Terraform modules, ~41 CDEFs |

When a control is labeled **Infrastructure (sparc-iac)**, the implementation
details and evidence artifacts live in the sparc-iac repository. When labeled
**Hybrid**, both repositories contribute to satisfying the control.

---

## Automated Evidence Collection

The SPARC CI/CD security pipeline (`.github/workflows/security.yml`) runs
9 parallel scan jobs on every PR, push to main, and weekly schedule. Results
are normalized to MITRE SAF Heimdall Data Format (HDF) with OSCAL metadata
injection for direct import into compliance dashboards.

| Pipeline Job | Tool | Control Families Supported | Output Formats |
|---|---|---|---|
| Secrets Scan | Gitleaks | IA, SC | SARIF, HDF |
| SAST (Rails) | Brakeman | SA, SI, SC | SARIF, HDF |
| SAST (Semantic) | CodeQL | SA, SI, SC | SARIF, HDF |
| SAST (Optional) | Semgrep | SA, SI | SARIF, HDF |
| Dependency Audit | bundler-audit | RA, SI, SR | JSON, HDF |
| JS Dependency Audit | importmap audit | RA, SI, SR | stdout |
| Filesystem Scan | Trivy FS | CM, SI, SR | SARIF, CycloneDX, HDF |
| Container Scan | Trivy Image | CM, SI, SR | SARIF, ASFF, CycloneDX, HDF |
| SBOM Generation | CycloneDX Ruby | CM, SR, SA | CycloneDX JSON |

**Additional automated evidence:**

- **OSCAL Schema Validation:** `OscalSchemaValidationService` validates all
  OSCAL exports against official NIST JSON schemas before download.
- **CCI-to-NIST Mapping:** `CciNistResolvable` concern resolves DISA STIG
  CCI references to NIST SP 800-53 control identifiers.
- **Severity Threshold Evaluation:** Pipeline fails on configurable severity
  thresholds (critical/high/medium/low).
- **90-day artifact retention** for all SARIF, HDF, SBOM, and ASFF outputs.

---

## AC -- Access Control

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| AC-1 | Policy and Procedures | H | Organizational Policy | Organization defines access control policy and procedures | Org policy docs | Planned |
| AC-2 | Account Management | H | Application (SPARC) | User model with active/suspended/deactivated statuses; admin bootstrap; role assignment; organization membership. Service account lifecycle management: create, disable, enable, transfer ownership, and soft-delete — admin-only with owner accountability. ServiceAccountMaintenanceJob runs daily via Solid Queue to auto-disable service accounts with all-expired tokens (reason: token_expired) or exceeding configurable inactivity threshold via `SPARC_SA_INACTIVITY_DAYS` (default 90 days, reason: inactivity). ServiceAccountNotificationJob sends proactive email warnings to service account owners and admins at 14 and 7 days before token expiry, on token expiration, and before inactivity auto-disable threshold. Notifications are gated on `SparcConfig.enable_smtp?` and delivered via ServiceAccountMailer | `app/models/user.rb`, `app/controllers/admin/service_accounts_controller.rb`, `app/jobs/service_account_maintenance_job.rb`, `app/jobs/service_account_notification_job.rb`, `app/mailers/service_account_mailer.rb` | Implemented |
| AC-2(1) | Automated System Account Management | H | Application (SPARC) | `inactive_past_threshold` scope identifies dormant accounts; `user_auto_deactivated` audit event | `app/models/user.rb`, `SPARC_INACTIVITY_DAYS` | Implemented |
| AC-2(2) | Automated Temporary and Emergency Account Removal | H | Application (SPARC) | Inactive user detection scope with configurable threshold (default 30 days) | `app/models/user.rb`, `SPARC_INACTIVITY_DAYS` | Implemented |
| AC-2(3) | Disable Accounts | H | Application (SPARC) | `deactivate!` and `reactivate!` methods; `SPARC_INACTIVITY_DAYS` configurable threshold | `app/models/user.rb` | Implemented |
| AC-2(4) | Automated Audit Actions | H | Application (SPARC) | All account lifecycle events logged: user_suspended, user_reactivated, user_deactivated, user_auto_deactivated | `app/models/audit_event.rb` | Implemented |
| AC-2(5) | Inactivity Logout | H | Application (SPARC) | Session timeout check against `SPARC_SESSION_TIMEOUT_MINUTES` (default 60) | `app/controllers/concerns/authentication.rb` | Implemented |
| AC-2(13) | Disable Accounts for High-Risk Individuals | H | Application (SPARC) | Admin can suspend/deactivate any account; status transitions audited | `app/models/user.rb` | Implemented |
| AC-3 | Access Enforcement | H | Application (SPARC) | RBAC with 29 roles, 57 granular permissions via JSONB; boundary-scoped authorization. API enforces boundary-scoped RBAC on all document CRUD endpoints (SSP, SAR, SAP, POA&M) via `DocumentBaseController`. Phase 2 API adds 4 controllers (catalogs, profiles, CDEFs, control mappings) that enforce Bearer token auth; catalogs and mappings require admin role for write operations. `BaselineParametersController` enforces Bearer auth on parameter CRUD endpoints. `KsiCatalogController` (read-only) and `KsiValidationsController` (CRUD) enforce Bearer token auth on all KSI endpoints. Discovery endpoint (`GET /api/v1/available`) enforces authorization scoping — callers only see endpoints/methods they are permitted to use. Service account tokens enforce endpoint-scoped access via `allowed_endpoints` JSONB attribute and CIDR-based IP restrictions | `app/controllers/concerns/authorization.rb`, `app/controllers/api/v1/document_base_controller.rb`, `app/controllers/api/v1/control_catalogs_controller.rb`, `app/controllers/api/v1/profile_documents_controller.rb`, `app/controllers/api/v1/cdef_documents_controller.rb`, `app/controllers/api/v1/control_mappings_controller.rb`, `app/controllers/api/v1/baseline_parameters_controller.rb`, `app/controllers/api/v1/ksi_catalog_controller.rb`, `app/controllers/api/v1/ksi_validations_controller.rb`, `app/controllers/api/v1/discovery_controller.rb`, `app/models/api_token.rb`, `app/controllers/admin/service_accounts_controller.rb` | Implemented |
| AC-3(8) | Revocation of Access Authorizations | H | Application (SPARC) | Role revocation via `role_revoke` audit event; immediate effect on next request | `app/controllers/concerns/authorization.rb` | Implemented |
| AC-4 | Information Flow Enforcement | H | Hybrid | Authorization boundaries scope data access; network-level controls in sparc-iac | `app/controllers/concerns/authorization.rb`, sparc-iac | Implemented |
| AC-5 | Separation of Duties | H | Application (SPARC) | 29 distinct roles across 10 instance-level and 19 boundary-scoped roles; granular permission keys prevent privilege concentration | `app/models/user.rb`, `app/models/role.rb` | Implemented |
| AC-6 | Least Privilege | H | Application (SPARC) | Default deny; `authorize_permission!` checks granular permission keys; admin bypass is explicit boolean, not a role. API non-admin users see only documents within their assigned authorization boundaries. Phase 2 API enforces admin-only gates for catalog and control-mapping writes; profile and CDEF endpoints require authenticated user (any role). Discovery endpoint (`GET /api/v1/available`) omits write methods for read-only callers and hides admin-only endpoints (users, catalog writes, mapping writes) from non-admins. Service accounts cannot be assigned admin role; endpoint-scoped access (`allowed_endpoints`) and CIDR restrictions enforce least privilege on service account tokens | `app/controllers/concerns/authorization.rb`, `app/controllers/api/v1/document_base_controller.rb`, `app/controllers/api/v1/control_catalogs_controller.rb`, `app/controllers/api/v1/control_mappings_controller.rb`, `app/controllers/api/v1/discovery_controller.rb`, `app/controllers/admin/service_accounts_controller.rb`, `app/models/api_token.rb` | Implemented |
| AC-6(1) | Authorize Access to Security Functions | H | Application (SPARC) | `authorize_admin!` gate restricts security functions to Instance Admin | `app/controllers/concerns/authorization.rb` | Implemented |
| AC-6(2) | Non-Privileged Access for Non-Security Functions | H | Application (SPARC) | Non-admin users receive minimal permissions; boundary-scoped roles restrict access to assigned boundaries only | `app/models/user.rb` | Implemented |
| AC-6(5) | Privileged Accounts | H | Application (SPARC) | Instance Admin is a distinct boolean, not a general role; tracked via `admin_bootstrap` audit event | `app/models/user.rb` | Implemented |
| AC-6(9) | Log Use of Privileged Functions | H | Application (SPARC) | Authorization failures logged with user, path, method; admin actions audited across all 16 categories | `app/controllers/concerns/authorization.rb`, `app/models/audit_event.rb` | Implemented |
| AC-6(10) | Prohibit Non-Privileged Users from Executing Privileged Functions | H | Application (SPARC) | `authorize_admin!`, `authorize_role!`, `authorize_permission!` gates enforce separation | `app/controllers/concerns/authorization.rb` | Implemented |
| AC-7 | Unsuccessful Logon Attempts | H | Hybrid | `login_failure` audit events tracked with IP and user agent; lockout policy at infrastructure/WAF level | `app/models/audit_event.rb`, sparc-iac WAF | Partial |
| AC-8 | System Use Notification | H | Application (SPARC) | Configurable consent/warning banner modal before login; HTML loaded from file, sanitized for XSS | `SPARC_BANNER_ENABLED`, `SPARC_BANNER_MESSAGE` | Implemented |
| AC-10 | Concurrent Session Control | H | Infrastructure (sparc-iac) | Session management at load balancer / infrastructure layer | sparc-iac | Planned |
| AC-11 | Device Lock | H | Hybrid | Session timeout after configurable inactivity period; client-side lock deferred to endpoint management | `app/controllers/concerns/authentication.rb`, `SPARC_SESSION_TIMEOUT_MINUTES` | Partial |
| AC-11(1) | Pattern-Hiding Displays | H | Application (SPARC) | Session expiry redirects to login page, clearing all session data | `app/controllers/concerns/authentication.rb` | Implemented |
| AC-12 | Session Termination | H | Application (SPARC) | `end_session` calls `reset_session` to clear all data; explicit logout; timeout-based termination | `app/controllers/concerns/authentication.rb` | Implemented |
| AC-12(1) | User-Initiated Logouts | H | Application (SPARC) | Logout action available in UI; triggers `reset_session` and `logout` audit event | `app/controllers/concerns/authentication.rb` | Implemented |
| AC-14 | Permitted Actions Without Identification or Authentication | H | Application (SPARC) | Only `/up` health check and login page accessible without authentication when auth is enabled | `app/controllers/concerns/authentication.rb` | Implemented |
| AC-17 | Remote Access | H | Hybrid | HTTPS-only access with HSTS; VPN/network controls in sparc-iac | `config/environments/production.rb`, sparc-iac | Implemented |
| AC-17(1) | Monitoring and Control | H | Hybrid | All remote access events logged in audit trail; network monitoring in sparc-iac | `app/models/audit_event.rb`, sparc-iac | Implemented |
| AC-17(2) | Protection of Confidentiality and Integrity Using Encryption | H | Hybrid | TLS enforced via `force_ssl` with HSTS (1 year, subdomains, preload); TLS termination in sparc-iac | `config/environments/production.rb` | Implemented |
| AC-17(4) | Privileged Commands and Access | H | Application (SPARC) | All admin actions audited; privileged API endpoints require bearer token with admin role | `app/controllers/concerns/api_authentication.rb`, `app/controllers/concerns/authorization.rb` | Implemented |
| AC-20 | Use of External Systems | H | Organizational Policy | Organization defines policies for external system connections | Org policy docs | Planned |
| AC-21 | Information Sharing | H | Application (SPARC) | Authorization boundaries scope document access; role-based sharing within boundaries | `app/controllers/concerns/authorization.rb` | Implemented |

---

## AT -- Awareness and Training

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| AT-1 | Policy and Procedures | H | Organizational Policy | Organization defines security awareness and training policy | Org policy docs | Planned |
| AT-2 | Literacy Training and Awareness | H | Organizational Policy | Security awareness training program managed by organization | Org policy docs | Planned |
| AT-2(2) | Insider Threat | H | Organizational Policy | Insider threat awareness training | Org policy docs | Planned |
| AT-2(3) | Social Engineering and Mining | H | Organizational Policy | Social engineering awareness training | Org policy docs | Planned |
| AT-3 | Role-Based Training | H | Organizational Policy | Role-based security training for privileged users and system administrators | Org policy docs | Planned |
| AT-4 | Training Records | H | Organizational Policy | Organization maintains training records | Org policy docs | Planned |

---

## AU -- Audit and Accountability

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| AU-1 | Policy and Procedures | H | Organizational Policy | Organization defines audit and accountability policy | Org policy docs | Planned |
| AU-2 | Event Logging | H | Application (SPARC) | 139 audit event types across 16 categories covering authentication, authorization, user management, document lifecycle, evidence, and more. API CRUD operations on SSP, SAR, SAP, POA&M documents generate audit events for all mutations. Phase 2 API controllers (catalogs, profiles, CDEFs, control mappings) log all mutations via `audit_log()` helper with action name, user, subject, and metadata. Service account lifecycle events: service_account_created, service_account_disabled, service_account_enabled, service_account_token_regenerated, service_account_deleted, service_account_updated. Automated `service_account_auto_disabled` audit event generated by ServiceAccountMaintenanceJob for each service account auto-disabled due to expired tokens or inactivity, with metadata including reason, email, and last_used_at. **Bulk-apply Converter pattern (#499)** — `cdef_bulk_apply_converter_previewed` and `cdef_bulk_apply_converter_applied` events emitted for the preview-then-confirm flow that applies a Converter's output to a CDEF clone; the applied event records added control ids, source converter, and Rev 4↔5 translation when used. | `app/models/audit_event.rb`, `app/controllers/api/v1/base_controller.rb`, `app/controllers/admin/service_accounts_controller.rb`, `app/jobs/service_account_maintenance_job.rb`, `app/services/cdef_bulk_apply_service.rb` | Implemented |
| AU-3 | Content of Audit Records | H | Application (SPARC) | Each audit event records: user, action, provider, IP address, user agent, structured metadata (JSONB), subject type/ID, timestamp. Phase 2 API audit records include action name, authenticated user, subject (catalog/profile/CDEF/mapping), and request metadata. Service account audit records include: owner, token_prefix (sparc_sa_), allowed_endpoints, CIDR allowlist, and originating IP | `app/models/audit_event.rb`, `app/controllers/api/v1/base_controller.rb`, `app/controllers/admin/service_accounts_controller.rb` | Implemented |
| AU-3(1) | Additional Audit Information | H | Application (SPARC) | JSONB metadata column stores arbitrary context per event (path, method, reason, role name, document IDs) | `app/models/audit_event.rb` | Implemented |
| AU-4 | Audit Log Storage Capacity | H | Hybrid | PostgreSQL-backed audit_events table; storage scaling managed by sparc-iac (RDS/EBS) | `app/models/audit_event.rb`, sparc-iac | Implemented |
| AU-5 | Response to Audit Logging Process Failures | H | Hybrid | `AuditEvent.log` rescues failures and emits Rails.logger.error; infrastructure alerting in sparc-iac | `app/models/audit_event.rb` | Implemented |
| AU-5(1) | Storage Capacity Warning | H | Infrastructure (sparc-iac) | Database storage monitoring and alerting via CloudWatch/infrastructure monitoring | sparc-iac | Planned |
| AU-6 | Audit Record Review, Analysis, and Reporting | H | Hybrid | Admin UI provides audit event filtering by category, user, date range, and search; external SIEM integration via structured JSON logs | `app/models/audit_event.rb` | Implemented |
| AU-6(1) | Automated Process Integration | H | Application (SPARC) | Structured JSON emitted to STDOUT for container log aggregation (CloudWatch, Datadog, Splunk) | `app/models/audit_event.rb` | Implemented |
| AU-6(3) | Correlate Audit Record Repositories | H | Application (SPARC) | Tagged logging with request_id enables cross-service correlation; subject_type/subject_id link events to resources | `config/environments/production.rb`, `app/models/audit_event.rb` | Implemented |
| AU-7 | Audit Record Reduction and Report Generation | H | Application (SPARC) | Scopes: `recent`, `for_user`, `logins`, `for_subject`, `by_subject_type`, `by_category`, `in_date_range`, `search` | `app/models/audit_event.rb` | Implemented |
| AU-7(1) | Automatic Processing | H | Application (SPARC) | Structured JSON logs enable automated processing by log aggregation tools | `app/models/audit_event.rb` | Implemented |
| AU-8 | Time Stamps | H | Hybrid | Rails `Time.current` with database-level timestamps; NTP synchronization at infrastructure level | `app/models/audit_event.rb`, sparc-iac | Implemented |
| AU-9 | Protection of Audit Information | H | Hybrid | Audit events are append-only (no updated_at column, no update methods); database access controls in sparc-iac | `app/models/audit_event.rb`, sparc-iac | Implemented |
| AU-9(2) | Store on Separate Physical Systems or Components | H | Infrastructure (sparc-iac) | Log aggregation to external systems (CloudWatch Logs, S3) | sparc-iac | Planned |
| AU-9(4) | Access by Subset of Privileged Users | H | Application (SPARC) | Audit event viewing restricted to admin users via `authorize_admin!` | `app/controllers/concerns/authorization.rb` | Implemented |
| AU-10 | Non-Repudiation | H | Application (SPARC) | Audit events link actions to authenticated user_id, IP address, and user agent; immutable records | `app/models/audit_event.rb` | Implemented |
| AU-11 | Audit Record Retention | H | Hybrid | Application retains all audit records in PostgreSQL; archival/retention policies in sparc-iac | `app/models/audit_event.rb`, sparc-iac | Partial |
| AU-12 | Audit Record Generation | H | Application (SPARC) | `AuditEvent.log` factory called throughout controllers and models; `audit_log` helper in API base controller generates records for all document CRUD mutations. Phase 2 API extends `audit_log()` coverage to catalog, profile, CDEF, and control-mapping controllers for create/update/destroy actions. Baseline parameter updates are audit-logged via `audit_log()` in `BaselineParametersController`. KSI validation mutations (create, update, delete) are audit-logged via `audit_log()` in `KsiValidationsController` | `app/models/audit_event.rb`, `app/controllers/api/v1/base_controller.rb`, `app/controllers/api/v1/baseline_parameters_controller.rb`, `app/controllers/api/v1/ksi_validations_controller.rb` | Implemented |
| AU-12(1) | System-Wide and Time-Correlated Audit Trail | H | Application (SPARC) | All events use `created_at` with database clock; request_id tagging enables correlation | `app/models/audit_event.rb`, `config/environments/production.rb` | Implemented |
| AU-12(3) | Changes by Authorized Individuals | H | Application (SPARC) | Audit configuration changes require admin role; event types defined in immutable constant array | `app/models/audit_event.rb` | Implemented |

---

## CA -- Assessment, Authorization, and Monitoring

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| CA-1 | Policy and Procedures | H | Organizational Policy | Organization defines assessment and authorization policy | Org policy docs | Planned |
| CA-2 | Control Assessments | H | Hybrid | SPARC manages SAR documents for assessment results; automated security scanning provides continuous evidence. KsiValidation model tracks assessment results per KSI per authorization boundary. **Attestation records (#440)** capture reviewer sign-off (control owner / system owner / ISSO / CISO / assessor / AO) on Evidence artefacts with cadence tracking (daily / weekly / monthly / quarterly / annually / ad_hoc) and a tamper-evident SHA-256 signature_hash for non-repudiation; `Api::V1::AttestationsController#export` emits records in the canonical CMS / SAF CLI attestation JSON schema for downstream OSCAL / Heimdall consumption | `app/models/sar_document.rb`, `.github/workflows/security.yml`, `app/models/ksi_validation.rb`, `app/models/attestation.rb`, `app/services/cms_attestation_export_service.rb`, `app/controllers/api/v1/attestations_controller.rb` | Implemented |
| CA-2(1) | Independent Assessors | H | Organizational Policy | Organization arranges independent assessors | Org policy docs | Planned |
| CA-2(2) | Specialized Assessments | H | Hybrid | 9 automated security scan tools provide specialized vulnerability, SAST, SCA, and container assessments | `.github/workflows/security.yml` | Implemented |
| CA-3 | Information Exchange | H | Organizational Policy | Organization defines system interconnection agreements | Org policy docs | Planned |
| CA-5 | Plan of Action and Milestones | H | Application (SPARC) | SPARC manages POA&M documents with item tracking, status, and milestone dates | `app/models/poam_document.rb` | Implemented |
| CA-6 | Authorization | H | Organizational Policy | Authorizing official grants ATO; SPARC manages the SSP package | Org policy docs | Partial |
| CA-7 | Continuous Monitoring | H | Hybrid | Weekly scheduled security scans; HDF normalization enables dashboard integration; audit event stream. KSI validations support scheduled re-validation with next_validation_due tracking and auto-expiration. **Threshold-based security gate (#244)** evaluates every PR against `threshold.yml` after applying disposition amendments from `sparc-findings.yml` (waivers, false positives, POA&Ms). Severity-based review cadence (HIGH 30d, MEDIUM 60d, LOW 120d) enforced by `bin/sparc_findings_to_hdf_amendments.rb` validator — stale dispositions block merge. **Attestation cadence (#440)** captures application-level periodic-review frequency on Evidence-bound attestations (`frequency` field: daily / weekly / monthly / quarterly / annually / ad_hoc) for downstream FedRAMP package generation join. **HDF ↔ OSCAL translation bridge (#449)** exposes tenants' compliance pipelines to the same translation engine SPARC uses internally — `POST /api/v1/oscal/sar_from_hdf` / `oscal/poam_from_hdf` accept tenant scan output and emit OSCAL SAR / POAM (with optional Evidence-record back-matter linkage when `authorization_boundary_id` is supplied); `POST /api/v1/hdf/amendments_from_oscal_poam` reverses the flow for `hdf amend apply` consumers | `.github/workflows/security.yml` (security_gate job), `app/models/audit_event.rb`, `app/models/ksi_validation.rb`, `app/models/attestation.rb`, `app/services/ksi_export_service.rb`, `app/services/cms_attestation_export_service.rb`, `app/services/hdf_runner.rb`, `app/services/hdf_oscal_translation_service.rb`, `app/controllers/api/v1/translations_controller.rb`, `bin/sparc_findings_to_hdf_amendments.rb`, `bin/install-hdf.sh`, `docs/compliance/threshold.yml`, `docs/compliance/sparc-findings.yml` | Implemented |
| CA-7(1) | Independent Assessment | H | Organizational Policy | Organization schedules independent continuous monitoring assessments | Org policy docs | Planned |
| CA-7(4) | Risk Monitoring | H | Hybrid | Security pipeline evaluates severity thresholds via SAF CLI threshold gating against amended HDFs (#244); dependency audit detects new CVEs; Brakeman/CodeQL/Trivy/Gitleaks all enforce strict severity bands in `threshold.yml` | `.github/workflows/security.yml` (security_gate), `docs/compliance/threshold.yml` | Implemented |
| CA-8 | Penetration Testing | H | Organizational Policy | Organization conducts penetration testing per policy | Org policy docs | Planned |
| CA-9 | Internal System Connections | H | Hybrid | Application boundary scoping; network segmentation in sparc-iac | `app/controllers/concerns/authorization.rb`, sparc-iac | Partial |

---

## CM -- Configuration Management

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| CM-1 | Policy and Procedures | H | Organizational Policy | Organization defines configuration management policy | Org policy docs | Planned |
| CM-2 | Baseline Configuration | H | Hybrid | Application baseline: Gemfile.lock, Dockerfile, docker-compose.yml; infrastructure baseline in sparc-iac Terraform state | `Gemfile.lock`, `Dockerfile`, sparc-iac | Implemented |
| CM-2(2) | Automation Support for Accuracy and Currency | H | Hybrid | Dependabot / bundler-audit for dependency updates; Trivy scans for container baseline drift | `.github/workflows/security.yml` | Implemented |
| CM-2(3) | Retention of Previous Configurations | H | Hybrid | Git version history retains all previous configurations; Terraform state versioning in sparc-iac | Git history, sparc-iac | Implemented |
| CM-3 | Configuration Change Control | H | Hybrid | Pull request workflow with required reviews; CI security gates; Terraform plan/apply in sparc-iac. **CDEF bulk-apply preview-then-confirm (#499)** — operator-initiated, two-step (preview → token → confirm) workflow gated on `converters.write` RBAC. The HMAC-signed (15 min TTL) token snapshots the exact changeset previewed; confirm replays via `CdefMutationService` so the post-apply OSCAL is schema-validated pre-commit. Re-applying the same converter is a no-op (idempotency). Rev 4 ↔ Rev 5 normalization via `ControlIdNormalizer` documented in back-matter citations on the resulting CDEF. | `.github/workflows/`, sparc-iac, `app/services/cdef_bulk_apply_service.rb`, `app/services/control_id_normalizer.rb` | Implemented |
| CM-3(1) | Automated Documentation, Notification, and Prohibition of Changes | H | Hybrid | GitHub Actions enforce security checks on all PRs; SARIF uploaded to Code Scanning | `.github/workflows/security.yml` | Implemented |
| CM-3(2) | Testing, Validation, and Documentation of Changes | H | Hybrid | RSpec test suite; security scan pipeline; OSCAL schema validation for exports | `spec/`, `.github/workflows/security.yml` | Implemented |
| CM-4 | Impact Analyses | H | Hybrid | PR-based review process; automated security analysis on every change | `.github/workflows/security.yml` | Implemented |
| CM-5 | Access Restrictions for Change | H | Hybrid | GitHub branch protection; admin-only deployment; IAM in sparc-iac | GitHub settings, sparc-iac | Implemented |
| CM-5(1) | Automated Access Enforcement and Audit Records | H | Application (SPARC) | Document change events audited (created/updated/deleted/exported for all doc types) | `app/models/audit_event.rb` | Implemented |
| CM-6 | Configuration Settings | H | Hybrid | `SparcConfig` centralizes all SPARC_* env var settings with secure defaults; infrastructure config in sparc-iac. `SPARC_API_OIDC_AUDIENCE` for JWT audience validation. `SPARC_API_AUTH` env var selects mutually exclusive API auth mode (`local`, `oidc`, `hybrid`); boot-time validation in `config/initializers/api_auth.rb` ensures correct configuration at startup (e.g., OIDC settings present when mode requires them). `BaselineParameterService` enables API-driven baseline parameter customization for profile documents. `SPARC_AWS_SECRETS_ENABLED` and `SPARC_APP_CONFIG_SECRET_ARN` control AWS Secrets Manager integration for injecting secrets from a KMS-encrypted JSON blob into ENV at boot. `SPARC_AWS_IAM_DB_AUTH` enables IAM database authentication with auto-rotating 15-minute tokens. Container image baseline documented in `sparc-findings.yml` -- hardened Dockerfile (non-root, multi-stage, minimal runtime deps) | `app/models/sparc_config.rb`, `app/services/baseline_parameter_service.rb`, `app/controllers/api/v1/baseline_parameters_controller.rb`, `config/initializers/api_auth.rb`, `config/initializers/00_aws_secrets.rb`, `config/initializers/aws_db_auth.rb`, `Dockerfile`, `docs/compliance/sparc-findings.yml` | Implemented |
| CM-6(1) | Automated Management, Application, and Verification | H | Hybrid | Environment variable driven configuration; Terraform manages infrastructure settings | `app/models/sparc_config.rb`, sparc-iac | Implemented |
| CM-7 | Least Functionality | H | Hybrid | Auth features default disabled (whitelist approach); minimal container image; sparc-iac restricts network ports | `app/models/sparc_config.rb`, `Dockerfile` | Implemented |
| CM-7(1) | Periodic Review | H | Hybrid | Weekly security scans detect unnecessary components; dependency audits flag unused gems | `.github/workflows/security.yml` | Implemented |
| CM-7(2) | Prevent Program Execution | H | Infrastructure (sparc-iac) | Container runtime restrictions; network policies | sparc-iac | Planned |
| CM-8 | System Component Inventory | H | Hybrid | CycloneDX SBOM generation for Ruby dependencies; Trivy CycloneDX for container components. **AWS-sourced CDEF provenance (#466)** — every runtime-imported CDEF row carries `source_url`, `source_sha`, `source_commit_sha`, and `fetched_at` so the in-app catalog is auditable back to the upstream blob. | `.github/workflows/security.yml` (sbom_generation job), `app/services/aws_labs_cdef_import_service.rb` | Implemented |
| CM-8(1) | Updates During Installation and Removal | H | Hybrid | SBOM regenerated on every CI run; reflects current component state | `.github/workflows/security.yml` | Implemented |
| CM-8(3) | Automated Unauthorized Component Detection | H | Hybrid | Trivy filesystem and container scans detect unauthorized or vulnerable components | `.github/workflows/security.yml` | Implemented |
| CM-9 | Configuration Management Plan | H | Organizational Policy | Organization defines CM plan; SPARC supports with automated tooling | Org policy docs | Partial |
| CM-10 | Software Usage Restrictions | H | Hybrid | License compliance via SBOM; importmap pins JS dependencies to known versions | `config/importmap.rb`, `.github/workflows/security.yml` | Partial |
| CM-11 | User-Installed Software | H | Infrastructure (sparc-iac) | Container immutability prevents user-installed software; read-only filesystem in production | sparc-iac, `Dockerfile` | Planned |

---

## CP -- Contingency Planning

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| CP-1 | Policy and Procedures | H | Organizational Policy | Organization defines contingency planning policy | Org policy docs | Planned |
| CP-2 | Contingency Plan | H | Organizational Policy | Organization develops and maintains contingency plan; SPARC SSP documents support planning | Org policy docs | Planned |
| CP-2(1) | Coordinate with Related Plans | H | Organizational Policy | Contingency plan coordination with related plans | Org policy docs | Planned |
| CP-2(3) | Resume Mission and Business Functions | H | Organizational Policy | Mission/business function resumption procedures | Org policy docs | Planned |
| CP-2(5) | Continue Mission and Business Functions | H | Organizational Policy | Continuity of operations planning | Org policy docs | Planned |
| CP-2(8) | Identify Critical Assets | H | Hybrid | SPARC manages system security plans identifying critical assets; infrastructure asset inventory in sparc-iac | `app/models/ssp_document.rb`, sparc-iac | Partial |
| CP-3 | Contingency Training | H | Organizational Policy | Organization conducts contingency training | Org policy docs | Planned |
| CP-4 | Contingency Plan Testing | H | Organizational Policy | Organization tests contingency plan | Org policy docs | Planned |
| CP-4(1) | Coordinate with Related Plans | H | Organizational Policy | Coordinated contingency plan testing | Org policy docs | Planned |
| CP-6 | Alternate Storage Site | H | Infrastructure (sparc-iac) | Cross-region S3 replication; RDS multi-AZ | sparc-iac | Planned |
| CP-6(1) | Separation from Primary Site | H | CSP Inherited | AWS regions provide geographic separation | CSP (AWS) | CSP Inherited |
| CP-6(3) | Accessibility | H | Infrastructure (sparc-iac) | Alternate storage site accessibility planning | sparc-iac | Planned |
| CP-7 | Alternate Processing Site | H | Infrastructure (sparc-iac) | Multi-AZ deployment; failover configuration | sparc-iac | Planned |
| CP-7(1) | Separation from Primary Site | H | CSP Inherited | AWS availability zones and regions | CSP (AWS) | CSP Inherited |
| CP-7(2) | Accessibility | H | Infrastructure (sparc-iac) | Alternate processing site accessibility | sparc-iac | Planned |
| CP-7(3) | Priority of Service | H | Infrastructure (sparc-iac) | Service priority agreements with CSP | sparc-iac | Planned |
| CP-8 | Telecommunications Services | H | CSP Inherited | Network redundancy provided by CSP | CSP (AWS) | CSP Inherited |
| CP-8(1) | Priority of Service Provisions | H | CSP Inherited | Telecommunications priority of service | CSP (AWS) | CSP Inherited |
| CP-8(2) | Single Points of Failure | H | Infrastructure (sparc-iac) | Multi-AZ eliminates single points of failure | sparc-iac | Planned |
| CP-9 | System Backup | H | Infrastructure (sparc-iac) | RDS automated backups; S3 versioning; EBS snapshots | sparc-iac | Planned |
| CP-9(1) | Testing for Reliability and Integrity | H | Infrastructure (sparc-iac) | Backup restoration testing | sparc-iac | Planned |
| CP-9(2) | Test Restoration Using Sampling | H | Infrastructure (sparc-iac) | Sample restoration testing procedures | sparc-iac | Planned |
| CP-9(5) | Transfer to Alternate Storage Site | H | Infrastructure (sparc-iac) | Cross-region backup replication | sparc-iac | Planned |
| CP-10 | System Recovery and Reconstitution | H | Infrastructure (sparc-iac) | Container orchestration enables rapid recovery; database restore procedures | sparc-iac | Planned |
| CP-10(2) | Transaction Recovery | H | Hybrid | PostgreSQL WAL ensures transaction-level recovery; SolidQueue persists jobs to database | `config/environments/production.rb`, sparc-iac | Partial |
| CP-10(4) | Restore Within Time Period | H | Infrastructure (sparc-iac) | RTO/RPO targets defined in infrastructure runbooks | sparc-iac | Planned |

---

## IA -- Identification and Authentication

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| IA-1 | Policy and Procedures | H | Organizational Policy | Organization defines I&A policy | Org policy docs | Planned |
| IA-2 | Identification and Authentication (Organizational Users) | H | Application (SPARC) | Multi-provider authentication: local (bcrypt), OIDC, LDAP, GitHub OAuth, GitLab OAuth. API auth modes are mutually exclusive via `SPARC_API_AUTH` env var (`local`, `oidc`, `hybrid`). In hybrid mode, OIDC JWT is enforced for human users and SPARC Bearer tokens are restricted to service accounts only (`service_account` flag on User). SessionsController blocks service account web login. **⚠ CONDITIONAL:** Full coverage (incl. MFA) requires `SPARC_ENABLE_OIDC=true` + `SPARC_OIDC_FORCE_MFA=true`. Local-only login = single-factor only | `app/models/sparc_config.rb`, `app/controllers/concerns/authentication.rb`, `app/controllers/concerns/api_authentication.rb`, `config/initializers/api_auth.rb` | Implemented |
| IA-2(1) | Multi-Factor Authentication to Privileged Accounts | H | Hybrid | **⚠ CONDITIONAL:** Requires OIDC with `SPARC_OIDC_FORCE_MFA=true` — MFA enforced by IdP. **Not met** with local-only login. LDAP depends on directory config | `app/models/sparc_config.rb` (`SPARC_OIDC_FORCE_MFA`) | Implemented |
| IA-2(2) | Multi-Factor Authentication to Non-Privileged Accounts | H | Hybrid | **⚠ CONDITIONAL:** Requires OIDC with `SPARC_OIDC_FORCE_MFA=true`. **Not met** with local-only login. LDAP depends on directory config | `SPARC_OIDC_FORCE_MFA`, IdP configuration | Partial |
| IA-2(6) | Access to Accounts -- Separate Device | H | Hybrid | MFA device separation managed by identity provider | IdP configuration | Partial |
| IA-2(8) | Access to Accounts -- Replay Resistant | H | Application (SPARC) | Session fixation prevention via `reset_session` before storing user_id; OAuth state/nonce verification | `app/controllers/concerns/authentication.rb` | Implemented |
| IA-2(12) | Acceptance of PIV Credentials | H | Hybrid | OIDC integration supports PIV/CAC when configured at identity provider | `SPARC_OIDC_*` configuration | Partial |
| IA-3 | Device Identification and Authentication | H | Infrastructure (sparc-iac) | Network-level device authentication; TLS mutual auth | sparc-iac | Planned |
| IA-4 | Identifier Management | H | Application (SPARC) | UUID immutability enforced (`enforce_uuid_immutability` callback); email uniqueness enforced at the **database** layer via a functional `UNIQUE` index on `LOWER(email)` (#593) plus app-level `normalize_email` downcasing and `case_sensitive: false` validation — case-variant duplicates are rejected even under races or callback-bypassing writes. Service accounts use UUID identifiers and `sparc_sa_` token prefix for clear identification | `app/models/user.rb`, `app/models/api_token.rb`, `db/migrate/20260529000000_enforce_case_insensitive_unique_email.rb` | Implemented |
| IA-4(4) | Identify User Status | H | Application (SPARC) | User status field (active/suspended/deactivated); only active users can authenticate; `deleted_at` timestamp | `app/models/user.rb` | Implemented |
| IA-5 | Authenticator Management | H | Application (SPARC) | bcrypt password hashing via `has_secure_password`; minimum 12 characters (NIST 800-63B); password expiry; forced reset. API tokens use SHA-256 digest; OIDC JWT tokens validated via RS256 signature verification. Hybrid mode (`SPARC_API_AUTH=hybrid`) uses RS256 JWT for human users and SHA-256 token digest for service accounts. Boot-time initializer (`config/initializers/api_auth.rb`) validates auth configuration at startup, ensuring correct OIDC settings for oidc/hybrid modes. JWKS caching uses Rails.cache for multi-process safety. Service account tokens: SHA-256 digest storage, `sparc_sa_` prefix, mandatory expiry, owner accountability, regeneration support. When `SPARC_AWS_IAM_DB_AUTH=true`, database authentication uses auto-rotating 15-minute IAM auth tokens instead of static passwords, eliminating long-lived database credentials. Gitleaks CI scanning with custom rules in `.gitleaks.toml` detects accidentally committed `sparc_` and `sparc_sa_` API tokens, preventing leaked authenticators from reaching the repository | `app/models/user.rb`, `app/models/api_token.rb`, `app/controllers/concerns/api_authentication.rb`, `app/controllers/admin/service_accounts_controller.rb`, `config/initializers/api_auth.rb`, `config/initializers/aws_db_auth.rb`, `.gitleaks.toml` | Implemented |
| IA-5(1) | Password-Based Authentication | H | Application (SPARC) | Minimum 12 chars; bcrypt hashing; password expiry configurable via `SPARC_PASSWORD_EXPIRY_DAYS` (default 30); `must_reset_password` flag; `password_changed_at` tracking | `app/models/user.rb`, `app/models/sparc_config.rb` | Implemented |
| IA-5(2) | Public Key-Based Authentication | H | Hybrid | API bearer tokens use SHA-256 digest storage; OIDC/OAuth use public key verification | `app/controllers/concerns/api_authentication.rb` | Implemented |
| IA-5(6) | Protection of Authenticators | H | Application (SPARC) | Passwords stored as bcrypt digests; API tokens stored as SHA-256 digests; OAuth credentials excluded from stored auth_data | `app/models/user.rb`, `app/controllers/omniauth_callbacks_controller.rb` | Implemented |
| IA-6 | Authentication Feedback | H | Application (SPARC) | Generic error messages on login failure; no indication of valid/invalid usernames | `app/controllers/concerns/authentication.rb` | Implemented |
| IA-7 | Cryptographic Module Authentication | H | Hybrid | Ruby OpenSSL for bcrypt and SHA-256; TLS at infrastructure layer | Ruby OpenSSL, sparc-iac | Implemented |
| IA-8 | Identification and Authentication (Non-Organizational Users) | H | Application (SPARC) | **⚠ CONDITIONAL:** Requires OIDC or OAuth enabled for federation (Okta, Entra, GitHub, GitLab). **Not met** with local-only login (no external IdP). OmniAuth callbacks map federated identities to local accounts. API supports Okta JWT federation for non-organizational API access | `app/controllers/omniauth_callbacks_controller.rb`, `app/models/sparc_config.rb`, `app/controllers/concerns/api_authentication.rb` | Implemented |
| IA-8(1) | Acceptance of PIV Credentials from Other Agencies | H | Hybrid | OIDC federation supports cross-agency PIV when configured | `SPARC_OIDC_*` configuration | Partial |
| IA-8(2) | Acceptance of External Authenticators | H | Application (SPARC) | GitHub, GitLab, and generic OIDC external authenticators supported | `app/controllers/omniauth_callbacks_controller.rb` | Implemented |
| IA-8(4) | Use of Defined Profiles | H | Hybrid | OIDC scopes configurable; standard `openid profile email` defaults | `SPARC_OIDC_SCOPES` | Implemented |
| IA-11 | Re-Authentication | H | Application (SPARC) | Session timeout forces re-authentication; password expiry forces credential refresh; `check_password_reset` before_action | `app/controllers/concerns/authentication.rb` | Implemented |
| IA-12 | Identity Proofing | H | Hybrid | **⚠ CONDITIONAL:** With OIDC enabled, identity proofing delegated to IdP (Okta, Entra). **Not met** with local-only login (self-registration). Organization defines proofing procedures | `app/controllers/omniauth_callbacks_controller.rb`, Org policy docs | Partial |

---

## IR -- Incident Response

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| IR-1 | Policy and Procedures | H | Organizational Policy | Organization defines incident response policy | Org policy docs | Planned |
| IR-2 | Incident Response Training | H | Organizational Policy | Organization provides IR training | Org policy docs | Planned |
| IR-3 | Incident Response Testing | H | Organizational Policy | Organization tests IR plan | Org policy docs | Planned |
| IR-3(2) | Coordination with Related Plans | H | Organizational Policy | Coordinated IR plan testing | Org policy docs | Planned |
| IR-4 | Incident Handling | H | Hybrid | Audit trail provides forensic evidence; structured JSON logs enable SIEM integration; security scan alerts | `app/models/audit_event.rb`, `.github/workflows/security.yml` | Partial |
| IR-4(1) | Automated Incident Handling Processes | H | Hybrid | Automated security scanning detects incidents; structured logs feed SIEM alerting | `.github/workflows/security.yml`, `app/models/audit_event.rb` | Partial |
| IR-5 | Incident Monitoring | H | Application (SPARC) | 139 audit event types provide comprehensive incident monitoring; login_failure tracking; authorization_failure tracking | `app/models/audit_event.rb` | Implemented |
| IR-5(1) | Automated Tracking, Data Collection, and Analysis | H | Application (SPARC) | Structured JSON audit events with automated export to log aggregation systems | `app/models/audit_event.rb` | Implemented |
| IR-6 | Incident Reporting | H | Organizational Policy | Organization defines incident reporting procedures | Org policy docs | Planned |
| IR-7 | Incident Response Assistance | H | Organizational Policy | Organization provides IR assistance resources | Org policy docs | Planned |
| IR-8 | Incident Response Plan | H | Organizational Policy | Organization maintains IR plan | Org policy docs | Planned |
| IR-9 | Information Spillage Response | H | Hybrid | Gitleaks detects secrets in code; audit trail tracks document access | `.github/workflows/security.yml`, `app/models/audit_event.rb` | Partial |

---

## MA -- Maintenance

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| MA-1 | Policy and Procedures | H | Organizational Policy | Organization defines maintenance policy | Org policy docs | Planned |
| MA-2 | Controlled Maintenance | H | Infrastructure (sparc-iac) | Container-based deployment; maintenance via CI/CD pipeline | sparc-iac, `.github/workflows/` | Partial |
| MA-2(2) | Automated Maintenance Activities | H | Hybrid | Automated dependency updates; scheduled security scans (weekly); CI/CD deployment pipeline | `.github/workflows/security.yml` | Implemented |
| MA-3 | Maintenance Tools | H | Infrastructure (sparc-iac) | Approved tools defined in CI pipeline; container image controls | sparc-iac | Planned |
| MA-4 | Nonlocal Maintenance | H | Hybrid | All maintenance via SSH/HTTPS with audit logging; no direct database access in production | sparc-iac, `app/models/audit_event.rb` | Partial |
| MA-5 | Maintenance Personnel | H | Organizational Policy | Organization manages maintenance personnel access | Org policy docs | Planned |
| MA-6 | Timely Maintenance | H | Hybrid | Automated vulnerability alerting; dependency update notifications | `.github/workflows/security.yml` | Partial |

---

## MP -- Media Protection

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| MP-1 | Policy and Procedures | H | Organizational Policy | Organization defines media protection policy | Org policy docs | Planned |
| MP-2 | Media Access | H | Hybrid | Application: role-based document access; Infrastructure: S3 bucket policies, EBS encryption | `app/controllers/concerns/authorization.rb`, sparc-iac | Implemented |
| MP-3 | Media Marking | H | Organizational Policy | Organization defines media marking procedures | Org policy docs | Planned |
| MP-4 | Media Storage | H | Infrastructure (sparc-iac) | S3 server-side encryption; EBS encryption at rest; RDS encryption | sparc-iac | Planned |
| MP-5 | Media Transport | H | Hybrid | TLS encryption for all data in transit; HTTPS-only document downloads | `config/environments/production.rb`, sparc-iac | Implemented |
| MP-6 | Media Sanitization | H | CSP Inherited | CSP handles physical media sanitization and disposal | CSP (AWS) | CSP Inherited |
| MP-7 | Media Use | H | Infrastructure (sparc-iac) | Container immutability; no removable media in cloud environment | sparc-iac | CSP Inherited |

---

## PE -- Physical and Environmental Protection

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| PE-1 | Policy and Procedures | H | CSP Inherited | CSP maintains physical security policies for data centers | CSP (AWS) | CSP Inherited |
| PE-2 | Physical Access Authorizations | H | CSP Inherited | CSP controls data center access | CSP (AWS) | CSP Inherited |
| PE-3 | Physical Access Control | H | CSP Inherited | CSP data center physical access controls | CSP (AWS) | CSP Inherited |
| PE-3(1) | System Access | H | CSP Inherited | Physical access to system components | CSP (AWS) | CSP Inherited |
| PE-4 | Access Control for Transmission | H | CSP Inherited | CSP controls physical access to transmission media | CSP (AWS) | CSP Inherited |
| PE-5 | Access Control for Output Devices | H | CSP Inherited | CSP controls physical output devices | CSP (AWS) | CSP Inherited |
| PE-6 | Monitoring Physical Access | H | CSP Inherited | CSP monitors physical access to data centers | CSP (AWS) | CSP Inherited |
| PE-6(1) | Intrusion Alarms and Surveillance Equipment | H | CSP Inherited | CSP intrusion detection systems | CSP (AWS) | CSP Inherited |
| PE-6(4) | Monitoring Physical Access to Systems | H | CSP Inherited | CSP physical access monitoring | CSP (AWS) | CSP Inherited |
| PE-8 | Visitor Access Records | H | CSP Inherited | CSP maintains visitor records | CSP (AWS) | CSP Inherited |
| PE-9 | Power Equipment and Cabling | H | CSP Inherited | CSP protects power infrastructure | CSP (AWS) | CSP Inherited |
| PE-10 | Emergency Shutoff | H | CSP Inherited | CSP emergency power shutoff capability | CSP (AWS) | CSP Inherited |
| PE-11 | Emergency Power | H | CSP Inherited | CSP provides emergency power (UPS, generators) | CSP (AWS) | CSP Inherited |
| PE-11(1) | Alternate Power Supply -- Long-Term | H | CSP Inherited | CSP long-term alternate power | CSP (AWS) | CSP Inherited |
| PE-12 | Emergency Lighting | H | CSP Inherited | CSP emergency lighting | CSP (AWS) | CSP Inherited |
| PE-13 | Fire Protection | H | CSP Inherited | CSP fire suppression systems | CSP (AWS) | CSP Inherited |
| PE-13(1) | Detection Systems -- Automatic Activation and Notification | H | CSP Inherited | CSP automatic fire detection | CSP (AWS) | CSP Inherited |
| PE-13(2) | Suppression Systems -- Automatic Activation and Notification | H | CSP Inherited | CSP automatic fire suppression | CSP (AWS) | CSP Inherited |
| PE-14 | Environmental Controls | H | CSP Inherited | CSP temperature and humidity controls | CSP (AWS) | CSP Inherited |
| PE-15 | Water Damage Protection | H | CSP Inherited | CSP water damage protection | CSP (AWS) | CSP Inherited |
| PE-16 | Delivery and Removal | H | CSP Inherited | CSP controls equipment delivery and removal | CSP (AWS) | CSP Inherited |
| PE-17 | Alternate Work Site | H | Organizational Policy | Organization defines alternate work site security | Org policy docs | Planned |
| PE-18 | Location of System Components | H | CSP Inherited | CSP positions equipment to minimize risk | CSP (AWS) | CSP Inherited |

---

## PL -- Planning

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| PL-1 | Policy and Procedures | H | Organizational Policy | Organization defines planning policy | Org policy docs | Planned |
| PL-2 | System Security and Privacy Plans | H | Application (SPARC) | SPARC manages SSP documents with full control-level detail; OSCAL SSP export for machine-readable plans | `app/models/ssp_document.rb`, `app/services/oscal_ssp_export_service.rb` | Implemented |
| PL-2(3) | Plan and Coordinate with Other Organizational Entities | H | Organizational Policy | Cross-organizational SSP coordination | Org policy docs | Planned |
| PL-4 | Rules of Behavior | H | Application (SPARC) | Configurable consent/warning banner displayed before login; customizable HTML message | `SPARC_BANNER_ENABLED`, `SPARC_BANNER_MESSAGE` | Implemented |
| PL-4(1) | Social Media and External Site/Application Usage Restrictions | H | Organizational Policy | Organization defines social media usage policy | Org policy docs | Planned |
| PL-8 | Security and Privacy Architectures | H | Hybrid | SPARC architecture documented; authorization boundary model; sparc-iac infrastructure architecture | Architecture docs, sparc-iac | Partial |
| PL-10 | Baseline Selection | H | Application (SPARC) | SPARC imports and manages NIST SP 800-53 Rev 4 and Rev 5 control catalogs with baseline tagging (LOW/MODERATE/HIGH) | `app/models/control_catalog.rb`, `app/services/catalog_import_service.rb` | Implemented |
| PL-11 | Baseline Tailoring | H | Application (SPARC) | Profile documents enable baseline tailoring with control selection, parameter adjustment, and priority setting | `app/models/profile_document.rb` | Implemented |

---

## PM -- Program Management

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| PM-1 | Information Security Program Plan | H | Organizational Policy | Organization maintains information security program plan | Org policy docs | Planned |
| PM-2 | Information Security Program Leadership Role | H | Organizational Policy | Organization designates CISO / security program leader | Org policy docs | Planned |
| PM-3 | Information Security and Privacy Resources | H | Organizational Policy | Organization allocates security resources | Org policy docs | Planned |
| PM-4 | Plan of Action and Milestones Process | H | Application (SPARC) | SPARC manages POA&M documents with item-level tracking, milestones, and status | `app/models/poam_document.rb` | Implemented |
| PM-5 | System Inventory | H | Application (SPARC) | Authorization boundaries serve as system inventory; each boundary contains associated documents (SSP, SAR, CDEF, POA&M) | `app/models/authorization_boundary.rb` | Implemented |
| PM-6 | Measures of Performance | H | Hybrid | Security scan metrics; audit event analytics; control implementation status tracking | `.github/workflows/security.yml`, `app/models/audit_event.rb` | Partial |
| PM-9 | Risk Management Strategy | H | Organizational Policy | Organization defines risk management strategy | Org policy docs | Planned |
| PM-10 | Authorization Process | H | Hybrid | SPARC manages ATO package documents (SSP, SAR, POA&M); authorization process defined by organization | SSP/SAR/POA&M document models | Partial |
| PM-11 | Mission and Business Process Definition | H | Organizational Policy | Organization defines mission and business processes | Org policy docs | Planned |
| PM-14 | Testing, Training, and Monitoring | H | Hybrid | Automated security testing via CI pipeline; audit monitoring; organizational training programs | `.github/workflows/security.yml` | Partial |
| PM-15 | Security and Privacy Groups and Associations | H | Organizational Policy | Organization participates in security communities | Org policy docs | Planned |
| PM-16 | Threat Awareness Program | H | Organizational Policy | Organization maintains threat awareness program | Org policy docs | Planned |

---

## PS -- Personnel Security

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| PS-1 | Policy and Procedures | H | Organizational Policy | Organization defines personnel security policy | Org policy docs | Planned |
| PS-2 | Position Risk Designation | H | Organizational Policy | Organization designates position risk levels | Org policy docs | Planned |
| PS-3 | Personnel Screening | H | Organizational Policy | Organization screens personnel before granting access | Org policy docs | Planned |
| PS-4 | Personnel Termination | H | Hybrid | SPARC supports account deactivation with reason tracking; `deactivate!` with timestamp; organization removes access | `app/models/user.rb` | Implemented |
| PS-4(2) | Automated Actions | H | Application (SPARC) | Automated inactivity-based deactivation via `inactive_past_threshold` scope; `user_auto_deactivated` audit event | `app/models/user.rb`, `SPARC_INACTIVITY_DAYS` | Implemented |
| PS-5 | Personnel Transfer | H | Hybrid | Role reassignment via admin UI; boundary membership changes audited; organization manages transfer procedures | `app/models/user_role.rb`, `app/models/audit_event.rb` | Implemented |
| PS-6 | Access Agreements | H | Application (SPARC) | Consent banner presents rules of behavior/access agreement before login | `SPARC_BANNER_ENABLED`, `SPARC_BANNER_MESSAGE` | Implemented |
| PS-7 | External Personnel Security | H | Organizational Policy | Organization manages external personnel security | Org policy docs | Planned |
| PS-8 | Personnel Sanctions | H | Hybrid | Account suspension capability; `user_suspended` audit event; organizational sanctions policy | `app/models/user.rb`, `app/models/audit_event.rb` | Partial |

---

## PT -- Personally Identifiable Information Processing and Transparency

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| PT-1 | Policy and Procedures | H | Organizational Policy | Organization defines PII processing and transparency policy | Org policy docs | Planned |
| PT-2 | Authority to Process Personally Identifiable Information | H | Organizational Policy | Organization establishes authority for PII processing | Org policy docs | Planned |
| PT-3 | Personally Identifiable Information Processing Purposes | H | Organizational Policy | Organization defines PII processing purposes | Org policy docs | Planned |
| PT-4 | Consent | H | Hybrid | Consent banner supports use notification; organizational consent policies | `SPARC_BANNER_ENABLED`, Org policy docs | Partial |
| PT-5 | Privacy Notice | H | Organizational Policy | Organization provides privacy notices | Org policy docs | Planned |
| PT-6 | System of Records Notice | H | Organizational Policy | Organization publishes SORN as required | Org policy docs | Planned |
| PT-7 | Specific Categories of Personally Identifiable Information | H | Hybrid | SPARC stores minimal PII (email, name, IP); access controlled by RBAC | `app/models/user.rb` | Partial |

---

## RA -- Risk Assessment

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| RA-1 | Policy and Procedures | H | Organizational Policy | Organization defines risk assessment policy | Org policy docs | Planned |
| RA-2 | Security Categorization | H | Hybrid | SPARC manages system categorization in SSP documents; FIPS 199 categorization | `app/models/ssp_document.rb` | Implemented |
| RA-3 | Risk Assessment | H | Hybrid | Automated vulnerability scanning provides risk data; SAR documents capture assessment results. **Per-finding risk acceptance (#244)** — each entry in `docs/compliance/sparc-findings.yml` is a documented risk decision with disposition (false_positive / accepted-waiver / deferred-poam / remediated), mitigating control rationale, NIST control reference, reviewer identity, and forced re-review (`next_review_date`). CRITICAL findings cannot be `accepted` per policy (waivers banned); only `false_positive` (with documented why-it-doesn't-apply), `deferred` (POA&M), or `remediated` are allowed. Converted to HDF Amendments format and applied via `hdf-cli amend` for unified evidence flow. **Tenant risk-assessment translation (#449)** — `POST /api/v1/oscal/poam_from_hdf` lets tenant pipelines convert their own scanner output into OSCAL POA&M for regulator-facing risk-acceptance packages | `app/models/sar_document.rb`, `.github/workflows/security.yml`, `app/services/hdf_oscal_translation_service.rb`, `docs/compliance/sparc-findings.yml`, `bin/sparc_findings_to_hdf_amendments.rb` | Implemented |
| RA-3(1) | Supply Chain Risk Assessment | H | Hybrid | SBOM generation; dependency vulnerability scanning; SBOM-driven SCA via Grype (#461); supply chain analysis. **External content supply chain (#466)** — runtime ingestion of OSCAL Component Definitions from `awslabs/oscal-content-for-aws-services` is opt-in via `SPARC_AWS_LABS_CDEF_ENABLED`; every imported row records `source_url`, `source_sha` (GitHub blob SHA), `source_commit_sha`, and `fetched_at` in `import_metadata` for provenance. AWS-sourced rows are read-only; users clone to amend, preserving the upstream content untouched. | `.github/workflows/security.yml` (sbom_generation, dependency_audit, grype_sbom_scan), `app/services/aws_labs_cdef_import_service.rb`, `docs/compliance/THIRD_PARTY_NOTICES.md` | Implemented |
| RA-5 | Vulnerability Monitoring and Scanning | H | Hybrid | 10 automated security scanners: Gitleaks, Brakeman, CodeQL, Semgrep, bundler-audit, importmap audit, Trivy FS, Trivy Container, CycloneDX SBOM, **Grype SBOM-driven SCA (#461)** — consumes CycloneDX SBOMs from sbom_generation + Trivy and runs vulnerability matching against Anchore's vuln DB. SARIF surfaced in Code Scanning; JSON normalized to HDF via SAF CLI `anchoregrype2hdf`. Container vulnerability baseline tracked in `docs/compliance/sparc-findings.yml` with 76 CVE dispositions, 30-day review cycle, and deployment-agnostic mitigating controls | `.github/workflows/security.yml`, `docs/compliance/sparc-findings.yml` | Implemented |
| RA-5(2) | Update Vulnerabilities to Be Scanned | H | Hybrid | bundler-audit updates advisory database before each scan; Trivy uses latest vulnerability database; Grype vuln DB cached weekly (#461) | `.github/workflows/security.yml` | Implemented |
| RA-5(4) | Discoverable Information | H | Hybrid | Gitleaks scans for exposed secrets; Trivy detects misconfigurations | `.github/workflows/security.yml` | Implemented |
| RA-5(5) | Privileged Access | H | Hybrid | Security scans run with read-only repository access; CodeQL uses minimal permissions | `.github/workflows/security.yml` (permissions block) | Implemented |
| RA-7 | Risk Response | H | Hybrid | POA&M documents track risk responses; severity threshold evaluation in pipeline | `app/models/poam_document.rb`, `.github/workflows/security.yml` | Implemented |
| RA-9 | Criticality Analysis | H | Organizational Policy | Organization performs criticality analysis | Org policy docs | Planned |

---

## SA -- System and Services Acquisition

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| SA-1 | Policy and Procedures | H | Organizational Policy | Organization defines SA policy | Org policy docs | Planned |
| SA-2 | Allocation of Resources | H | Organizational Policy | Organization allocates security resources | Org policy docs | Planned |
| SA-3 | System Development Life Cycle | H | Hybrid | PR-based development with security gates; automated testing; security scanning in CI | `.github/workflows/`, `spec/` | Implemented |
| SA-4 | Acquisition Process | H | Organizational Policy | Organization defines acquisition security requirements | Org policy docs | Planned |
| SA-4(1) | Functional Properties of Controls | H | Application (SPARC) | SPARC documents control functional properties in SSP/CDEF; OSCAL export provides machine-readable descriptions | `app/services/oscal_ssp_export_service.rb` | Implemented |
| SA-4(2) | Design and Implementation Information for Controls | H | Application (SPARC) | Component Definition documents capture implementation details; OSCAL component-definition export | `app/services/oscal_component_definition_export_service.rb` | Implemented |
| SA-4(9) | Functions, Ports, Protocols, and Services | H | Hybrid | Application: documented API endpoints; Infrastructure: network port restrictions in sparc-iac | API docs, sparc-iac | Partial |
| SA-4(10) | Use of Approved PIV Products | H | Hybrid | OIDC integration supports PIV-enabled identity providers | `SPARC_OIDC_*` configuration | Partial |
| SA-5 | System Documentation | H | Application (SPARC) | Comprehensive documentation: API docs, environment variable reference, architecture docs, OSCAL data mapping | `docs/` directory | Implemented |
| SA-8 | Security and Privacy Engineering Principles | H | Application (SPARC) | Defense in depth: layered auth, RBAC, audit trail, input validation, secure defaults, least privilege | Architecture design | Implemented |
| SA-9 | External System Services | H | Hybrid | OIDC/LDAP/OAuth integrations use TLS; API tokens use SHA-256 digest storage; external service access audited | `app/services/ldap_auth_service.rb` | Implemented |
| SA-9(2) | Identification of Functions, Ports, Protocols, and Services | H | Hybrid | LDAP port 636 (simple_tls) or start_tls; OIDC standard endpoints; documented in env var reference | `app/models/sparc_config.rb` | Implemented |
| SA-10 | Developer Configuration Management | H | Hybrid | Git version control; PR reviews; branch protection; CI/CD pipeline enforcement | `.github/workflows/`, Git history | Implemented |
| SA-11 | Developer Testing and Evaluation | H | Hybrid | RSpec test suite (~2076 examples); Brakeman SAST; CodeQL semantic analysis; security scan pipeline. **Code coverage threshold (#367)** — SimpleCov enforces minimum 70% line coverage on every CI run (current baseline 71.17%); ratchet policy prevents regression. Configured in `spec/spec_helper.rb` | `spec/`, `spec/spec_helper.rb`, `.github/workflows/security.yml`, `.github/workflows/ci.yml` | Implemented |
| SA-11(1) | Static Code Analysis | H | Application (SPARC) | Brakeman (Rails-specific SAST), CodeQL (semantic analysis), Semgrep (optional pattern-based SAST). SCA augmented by Grype SBOM-driven scanning (#461) — see RA-5 | `.github/workflows/security.yml` | Implemented |
| SA-15 | Development Process, Standards, and Tools | H | Hybrid | rubocop-rails-omakase linting; RSpec testing framework; documented development workflow. **Third-party content management (#466)** — `docs/compliance/THIRD_PARTY_NOTICES.md` enumerates external content sources (AWS Labs CDEFs), governs ingestion behavior, and documents the read-only + clone-to-amend policy that keeps upstream Apache 2.0 content untouched. **License policy as code (#472)** — `docs/compliance/license-policy.yml` defines allowlist/warn_list/blocklist as machine-readable policy; `docs/compliance/license-dispositions.yml` records per-component dispositions following the `sparc-findings.yml` pattern. CI publishes a consolidated `license-inventory.{json,md}` artifact on every Security Scanning run. | `.rubocop.yml`, `spec/`, `docs/compliance/THIRD_PARTY_NOTICES.md`, `NOTICE`, `docs/compliance/license-policy.yml`, `docs/compliance/license-dispositions.yml`, `scripts/ci/build_license_inventory.rb` | Implemented |
| SA-17 | Developer Security and Privacy Architecture and Design | H | Application (SPARC) | Three-level document model; concern-based auth/authz separation; env-var-driven config; append-only audit | Architecture design | Implemented |
| SA-22 | Unsupported System Components | H | Hybrid | **License-driven supply chain risk (#472)** — `scripts/ci/build_license_inventory.rb` flags components on the policy warn_list/blocklist (including license-relicense scenarios that often indicate upstream sustainability risk) and components with no recoverable license metadata. Action-item list in `license-inventory.md` lets operators triage unsupported / mis-licensed dependencies before they ship. | `scripts/ci/build_license_inventory.rb`, `docs/compliance/license-policy.yml`, `docs/compliance/license-dispositions.yml` | Implemented |

---

## SC -- System and Communications Protection

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| SC-1 | Policy and Procedures | H | Organizational Policy | Organization defines SC policy | Org policy docs | Planned |
| SC-2 | Separation of User and System Management Functionality | H | Application (SPARC) | Admin functions separated behind `authorize_admin!` gate; separate admin UI sections | `app/controllers/concerns/authorization.rb` | Implemented |
| SC-3 | Security Function Isolation | H | Hybrid | Authentication, authorization, and audit concerns isolated in separate modules; container isolation in sparc-iac | `app/controllers/concerns/authentication.rb`, `app/controllers/concerns/authorization.rb` | Implemented |
| SC-4 | Information in Shared System Resources | H | Application (SPARC) | `reset_session` clears all session data on login/logout; no shared state between users | `app/controllers/concerns/authentication.rb` | Implemented |
| SC-5 | Denial-of-Service Protection | H | Infrastructure (sparc-iac) | WAF, rate limiting, auto-scaling at infrastructure layer | sparc-iac | Planned |
| SC-7 | Boundary Protection | H | Hybrid | Application: authorization boundaries scope access; Infrastructure: VPC, security groups, NACLs | `app/controllers/concerns/authorization.rb`, sparc-iac | Implemented |
| SC-7(3) | Access Points | H | Infrastructure (sparc-iac) | Limited access points via ALB; no direct database access | sparc-iac | Planned |
| SC-7(4) | External Telecommunications Services | H | Infrastructure (sparc-iac) | CSP-managed network infrastructure | sparc-iac | Planned |
| SC-7(5) | Deny by Default -- Allow by Exception | H | Hybrid | Application: auth defaults disabled (whitelist approach); Infrastructure: security group deny-by-default | `app/models/sparc_config.rb`, sparc-iac | Implemented |
| SC-7(7) | Split Tunneling -- Networking Devices | H | Infrastructure (sparc-iac) | VPC routing configuration | sparc-iac | Planned |
| SC-7(8) | Route Traffic to Authenticated Proxy Servers | H | Infrastructure (sparc-iac) | ALB/reverse proxy for all inbound traffic | sparc-iac | Planned |
| SC-7(18) | Fail Secure | H | Application (SPARC) | Authentication gate defaults to redirect to login; authorization gate raises NotAuthorizedError on failure | `app/controllers/concerns/authentication.rb`, `app/controllers/concerns/authorization.rb` | Implemented |
| SC-7(21) | Isolation of System Components | H | Infrastructure (sparc-iac) | Container isolation; network segmentation; separate database subnet | sparc-iac | Planned |
| SC-8 | Transmission Confidentiality and Integrity | H | Hybrid | `force_ssl` with HSTS (1 year, subdomains, preload); LDAP uses simple_tls or start_tls | `config/environments/production.rb`, `app/services/ldap_auth_service.rb` | Implemented |
| SC-8(1) | Cryptographic Protection | H | Hybrid | TLS encryption for all HTTP, LDAP, and OIDC communications; HSTS preload | `config/environments/production.rb`, `FORCE_SSL` | Implemented |
| SC-10 | Network Disconnect | H | Application (SPARC) | Session timeout disconnects after configurable inactivity; `reset_session` clears state | `app/controllers/concerns/authentication.rb`, `SPARC_SESSION_TIMEOUT_MINUTES` | Implemented |
| SC-12 | Cryptographic Key Establishment and Management | H | Hybrid | bcrypt cost factor for passwords; SHA-256 for API tokens; TLS certificate management in sparc-iac. When `SPARC_AWS_SECRETS_ENABLED=true`, SECRET_KEY_BASE is managed via AWS Secrets Manager with KMS encryption. When `SPARC_AWS_IAM_DB_AUTH=true`, IAM database authentication uses IAM-signed tokens instead of static passwords for PostgreSQL connections | `app/models/user.rb`, `config/initializers/00_aws_secrets.rb`, `config/initializers/aws_db_auth.rb`, sparc-iac | Implemented |
| SC-13 | Cryptographic Protection | H | Hybrid | bcrypt password hashing; SHA-256 API token digests; RS256 JWT signature verification for OIDC API auth; TLS 1.2+ enforced at infrastructure | Ruby OpenSSL, `app/controllers/concerns/api_authentication.rb`, sparc-iac | Implemented |
| SC-15 | Collaborative Computing Devices and Applications | H | N/A | Not applicable -- SPARC is a web application, not a collaborative computing device | N/A | N/A |
| SC-17 | Public Key Infrastructure Certificates | H | Infrastructure (sparc-iac) | TLS certificate provisioning via ACM or similar | sparc-iac | Planned |
| SC-18 | Mobile Code | H | Application (SPARC) | No user-uploaded executable code; Stimulus controllers are server-managed; importmap pins JS to known versions. Enforced Content-Security-Policy restricts script execution to nonce'd/self sources and constrains `form-action`; the login page narrowly relaxes `form-action` to the enabled SSO IdP origins only, so OAuth POST-redirects succeed in Chromium while every other page keeps strict `form-action 'self'` (#593) | `config/importmap.rb`, `config/initializers/content_security_policy.rb`, `app/controllers/sessions_controller.rb` | Implemented |
| SC-20 | Secure Name/Address Resolution Service (Authoritative Source) | H | Infrastructure (sparc-iac) | DNS configuration and DNSSEC in sparc-iac | sparc-iac | Planned |
| SC-21 | Secure Name/Address Resolution Service (Recursive or Caching Resolver) | H | Infrastructure (sparc-iac) | DNS resolver configuration | sparc-iac | Planned |
| SC-22 | Architecture and Provisioning for Name/Address Resolution Service | H | Infrastructure (sparc-iac) | Redundant DNS architecture | sparc-iac | Planned |
| SC-23 | Session Authenticity | H | Application (SPARC) | Rails encrypted session cookies; session fixation prevention via `reset_session`; CSRF protection via authenticity tokens | `app/controllers/concerns/authentication.rb`, Rails defaults | Implemented |
| SC-28 | Protection of Information at Rest | H | Hybrid | RDS encryption; S3 server-side encryption; EBS encryption. Application secrets (SECRET_KEY_BASE, database credentials) are KMS-encrypted in AWS Secrets Manager and injected at boot time — never stored on disk. Feature-gated by `SPARC_AWS_SECRETS_ENABLED` | `config/initializers/00_aws_secrets.rb`, sparc-iac | Partial |
| SC-28(1) | Cryptographic Protection | H | Infrastructure (sparc-iac) | AES-256 encryption at rest via AWS KMS | sparc-iac | Planned |

---

## SI -- System and Information Integrity

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| SI-1 | Policy and Procedures | H | Organizational Policy | Organization defines SI policy | Org policy docs | Planned |
| SI-2 | Flaw Remediation | H | Hybrid | bundler-audit and Trivy detect known vulnerabilities; dependency updates via Gemfile; container rebuilds. Findings dispositioned in `sparc-findings.yml` with rationale, NIST control mapping, and **severity-based review cadence** (#244): HIGH 30d, MEDIUM 60d, LOW 120d, INFO 60d, CRITICAL 30d (POA&M only — no waivers). Disposition validation enforced by `bin/sparc_findings_to_hdf_amendments.rb`; freshness check fails CI on stale `next_review_date`. **`false_positive` exempt from the review cadence (#620)** — a false positive is a determination that the finding is not real (vulnerable code unreachable / scanner sees a present-but-not-loaded file), so it carries no risk on a remediation clock; the window/overdue checks apply only to risk-bearing `accepted`/`deferred` dispositions. Threshold-based merge gate (#244) blocks PRs that introduce new findings exceeding `threshold.yml` after dispositions are applied. **CVE-baseline refresh (#620)** — openssl bumped to the patched bookworm-security build; Ruby default-gem CVEs (net-imap, erb, zlib) remediated by Gemfile pins (resolv-style override) so Bundler loads the patched versions while the present-but-shadowed default gems are dispositioned `false_positive`; oauth2 bumped 2.0.18→2.0.22; thruster Go-1.26.2 stdlib CVEs accepted with reverse-proxy compensating controls (no upstream build on Go≥1.26.3). **Tenant amendment generation (#449)** — `POST /api/v1/hdf/amendments_from_oscal_poam` lets tenant pipelines convert OSCAL POA&M tracker output into HDF Amendments JSON for `hdf amend apply` consumption, validated by `hdf amend verify` before serving | `.github/workflows/security.yml`, `Gemfile`, `app/services/hdf_oscal_translation_service.rb`, `docs/compliance/sparc-findings.yml`, `docs/compliance/threshold.yml`, `bin/sparc_findings_to_hdf_amendments.rb` | Implemented |
| SI-2(2) | Automated Flaw Remediation Status | H | Hybrid | Security pipeline reports flaw status; SARIF uploaded to GitHub Code Scanning for tracking | `.github/workflows/security.yml` | Implemented |
| SI-2(5) | Automatic Software and Firmware Updates | H | Hybrid | CI/CD pipeline deploys updated containers; bundler-audit alerts on outdated gems | `.github/workflows/security.yml`, CI/CD | Partial |
| SI-3 | Malicious Code Protection | H | Hybrid | Brakeman detects injection vulnerabilities; CodeQL identifies malicious patterns; Trivy scans for malware in container images | `.github/workflows/security.yml` | Implemented |
| SI-4 | System Monitoring | H | Hybrid | 139 audit event types; structured JSON logging to STDOUT; security scan pipeline; infrastructure monitoring in sparc-iac | `app/models/audit_event.rb`, `.github/workflows/security.yml` | Implemented |
| SI-4(1) | System-Wide Intrusion Detection System | H | Infrastructure (sparc-iac) | Network-level IDS/IPS; WAF rules | sparc-iac | Planned |
| SI-4(2) | Automated Tools and Mechanisms for Real-Time Analysis | H | Hybrid | Structured JSON logs enable real-time SIEM analysis; audit event categories support automated alerting | `app/models/audit_event.rb` | Implemented |
| SI-4(4) | Inbound and Outbound Communications Traffic | H | Infrastructure (sparc-iac) | Network traffic monitoring; VPC flow logs | sparc-iac | Planned |
| SI-4(5) | System-Generated Alerts | H | Hybrid | Security pipeline severity threshold triggers workflow failure; audit events support alerting integration | `.github/workflows/security.yml`, `app/models/audit_event.rb` | Implemented |
| SI-4(12) | Automated Organization-Generated Alerts | H | Hybrid | Structured JSON audit events enable automated alert generation in external systems | `app/models/audit_event.rb` | Implemented |
| SI-5 | Security Alerts, Advisories, and Directives | H | Hybrid | bundler-audit and Trivy consume CVE advisories; GitHub Dependabot alerts | `.github/workflows/security.yml` | Implemented |
| SI-6 | Security and Privacy Function Verification | H | Application (SPARC) | RSpec test suite verifies security functions; OSCAL schema validation ensures export correctness | `spec/`, `app/services/oscal_schema_validation_service.rb` | Implemented |
| SI-7 | Software, Firmware, and Information Integrity | H | Hybrid | Gemfile.lock pins dependency versions; container image digests; Gitleaks detects tampering; SBOM provides integrity baseline | `Gemfile.lock`, `.github/workflows/security.yml` | Implemented |
| SI-7(1) | Integrity Checks | H | Hybrid | bundler-audit verifies gem integrity; Trivy verifies container component integrity; CycloneDX SBOM comparison | `.github/workflows/security.yml` | Implemented |
| SI-7(7) | Integration of Detection and Response | H | Hybrid | Security scan results feed into HDF normalization; severity thresholds trigger pipeline failures | `.github/workflows/security.yml` | Implemented |
| SI-8 | Spam Protection | H | Infrastructure (sparc-iac) | Email spam filtering at infrastructure/service level | sparc-iac | N/A |
| SI-10 | Information Input Validation | H | Application (SPARC) | Rails strong parameters; model validations (email format, password length, status inclusion); XSS sanitization for banner HTML; avatar upload validates content type allowlist (PNG/JPG/GIF/WebP) and 2 MB size limit at client-side (Stimulus) and server-side (controller + model); Cropper.js constrains output to 256x256 | `app/models/user.rb`, `app/controllers/profiles_controller.rb`, `app/javascript/controllers/avatar_crop_controller.js`, Rails defaults | Implemented |
| SI-11 | Error Handling | H | Application (SPARC) | Production disables full error reports; generic error messages for auth failures; `rescue_from` for authorization errors | `config/environments/production.rb`, `app/controllers/concerns/authorization.rb` | Implemented |
| SI-12 | Information Management and Retention | H | Hybrid | Audit events retained in PostgreSQL; 90-day artifact retention for security scan results; organizational retention policies | `app/models/audit_event.rb`, `.github/workflows/security.yml` | Partial |
| SI-16 | Memory Protection | H | Infrastructure (sparc-iac) | OS-level memory protections; container runtime security | sparc-iac | Planned |

---

## Section 508 / Accessibility (WCAG 2.1 AA)

Section 508 of the Rehabilitation Act requires federal ICT to conform to
**WCAG 2.1 Level AA**. SPARC's application UI is checked automatically against
that bar by axe-core, integrated into both layers of the UI test net (#572).

| Standard | Scope | Automated Control | Code / Config Location | Status |
|---|---|---|---|---|
| WCAG 2.1 A + AA (Section 508) | SPARC web UI | axe-core accessibility checks -- Layer 1 (RSpec system specs, real Chrome, per-PR) + Layer 2 (Playwright post-deploy, Chromium + Firefox). Baseline + ratchet: new violations fail the build; tracked debt is recorded and burned down. | `spec/system/accessibility_spec.rb`, `spec/support/axe_helper.rb`, `tests/ui-smoke/test_accessibility.py`, `tests/ui-smoke/a11y_baseline.json` | Implemented¹ |

**Conformance status (v1.8.6, #599 / #602):** the captured baseline was burned
down to zero. A local real-Chromium axe sweep across the 20 core pages reports
**0 color-contrast, select-name, label, and meta-refresh violations in both
light and dark themes.** The remediation introduced a WORM color architecture --
semantic helper keys + single-source `.sparc-status`/`.sparc-heading` components
in `sparc-theme.css` own all contrast, so views carry no badge/heading color
hex and future palette changes stay AA by construction. The login consent-banner
items (#602 -- amber heading contrast, `.btn-outline-secondary`,
`#consentBannerBody` keyboard focus) are resolved.

> ¹ Local-verification status. The committed `a11y_baseline.json` still reflects
> the pre-v1.8.6 production capture; the authoritative prod re-capture (and
> baseline shrink) happens post-deploy, after which the Layer 2 ratchet enforces
> the cleared state. Net-new regressions are blocked per-PR by Layer 1 today.

> Note: Section 508 / WCAG is a distinct legal standard, not a NIST SP 800-53
> control -- it is documented here for authorization-package completeness, not
> as an 800-53 control mapping.

## SR -- Supply Chain Risk Management

| Control ID | Title | Baseline | Responsibility | Implementation Summary | Code / Config Location | Status |
|---|---|---|---|---|---|---|
| SR-1 | Policy and Procedures | H | Organizational Policy | Organization defines supply chain risk management policy | Org policy docs | Planned |
| SR-2 | Supply Chain Risk Management Plan | H | Organizational Policy | Organization develops SCRM plan | Org policy docs | Planned |
| SR-2(1) | Establish SCRM Team | H | Organizational Policy | Organization establishes SCRM team | Org policy docs | Planned |
| SR-3 | Supply Chain Controls and Processes | H | Hybrid | CycloneDX SBOM generation; dependency auditing; container scanning; SBOM-driven vulnerability scanning via Grype (#461) — published SBOMs are scan-verified before release, not just generated; known-good version pinning. **External CDEF content supply chain (#466)** — runtime ingestion uses GitHub blob SHA for integrity verification, ETag-conditional fetches for cache integrity, and full attribution per `docs/compliance/THIRD_PARTY_NOTICES.md` (Apache 2.0 inheritance). **License inventory and policy (#472)** — the three CycloneDX SBOMs are consolidated by `scripts/ci/build_license_inventory.rb` into a `license-inventory.{json,md}` artifact that records every component's resolved license + policy disposition + dispositions trail. Trivy's `license` scanner is enabled on both fs and container scans for full coverage. | `.github/workflows/security.yml`, `Gemfile.lock`, `app/services/aws_labs_cdef_source_client.rb`, `NOTICE`, `LICENSES/AWS-LABS-OSCAL-CONTENT-LICENSE`, `scripts/ci/build_license_inventory.rb`, `docs/compliance/license-policy.yml`, `docs/compliance/license-dispositions.yml` | Implemented |
| SR-5 | Acquisition Strategies, Tools, and Methods | H | Organizational Policy | Organization defines acquisition strategies | Org policy docs | Planned |
| SR-6 | Supplier Assessments and Reviews | H | Organizational Policy | Organization assesses suppliers | Org policy docs | Planned |
| SR-8 | Notification Agreements | H | Organizational Policy | Organization establishes notification agreements with suppliers | Org policy docs | Planned |
| SR-10 | Inspection of Systems or Components | H | Hybrid | Trivy container and filesystem scanning inspects components for vulnerabilities and misconfigurations | `.github/workflows/security.yml` | Implemented |
| SR-11 | Component Authenticity | H | Hybrid | Gemfile.lock with specific version pins; container image provenance; SBOM tracks component origins; Grype SBOM scan (#461) verifies component vulnerabilities against Anchore vuln DB | `Gemfile.lock`, `.github/workflows/security.yml` | Implemented |
| SR-11(1) | Anti-Counterfeit Training | H | Organizational Policy | Organization provides anti-counterfeit training | Org policy docs | Planned |
| SR-11(2) | Configuration Control for Component Service and Repair | H | Hybrid | Immutable container images; version-controlled dependencies; CI rebuilds from source | `Dockerfile`, `Gemfile.lock` | Implemented |
| SR-12 | Component Disposal | H | CSP Inherited | CSP handles physical component disposal | CSP (AWS) | CSP Inherited |

---

## Admin Credential Rotation (#402, #403)

The admin credential rotation workflow propagates rotations performed in AWS Secrets Manager into the running SPARC task and provides two SPARC-initiated paths (rake + API) to push rotations back to SM.

| Control | Contribution | CDEF | Code Location |
|---|---|---|---|
| AC-2 | Account lifecycle: rotation events emit AuditEvent rows (`admin_credential_synced_from_env`, `admin_credential_rotated`, `admin_password_reset`) tagged with source/actor/version_id | authentication, audit | `app/services/admin_credential_rotation_service.rb`, `lib/tasks/admin.rake`, `app/models/audit_event.rb` |
| AC-3 | API endpoint gated by new `admin.rotate_credentials` permission key (Role::PERMISSION_KEYS) plus existing service-account endpoint scoping (#257) | authentication | `app/controllers/api/v1/admin/credentials_controller.rb`, `app/models/role.rb` |
| AC-17 | Lambda's service-account token can be CIDR-allowlisted to its egress NAT IPs via existing #257 capability — restricts rotation invocations to a known network origin | authentication | `app/models/api_token.rb#cidr_allowed?` |
| AU-2 | Three new audit actions registered in `AuditEvent::ACTIONS` (User Management category): `admin_password_reset` (closes a latent silent-failure bug from existing rake), `admin_credential_synced_from_env`, `admin_credential_rotated` | audit | `app/models/audit_event.rb` |
| AU-3 | Rotation audit rows capture: source (rake/api), actor user/token id, secret version_id (when SM was touched), outcome (rotated/unchanged); never the password material | audit | `app/services/admin_credential_rotation_service.rb`, `app/controllers/api/v1/admin/credentials_controller.rb` |
| IA-4 | Admin user identifier (email) preserved across rotations; only the authenticator material changes | authentication | `lib/tasks/admin.rake` |
| IA-5 | Three coordinated rotation paths: (1) bootstrap reconciliation from `SPARC_ADMIN_PASSWORD` env on container start, (2) `sparc:rotate_admin_credentials` rake (DB + SM PutSecretValue), (3) `POST /api/v1/admin/refresh_credentials` (Lambda → SPARC → DB; Lambda owns SM AWSCURRENT promotion) | authentication | `lib/tasks/admin.rake`, `app/services/admin_credential_rotation_service.rb`, `app/controllers/api/v1/admin/credentials_controller.rb` |
| SC-13 | Bcrypt at rest for the password digest; TLS in transit for the API path; SPARC's task role holds `PutSecretValue` write-only access on admin-credentials — not `GetSecretValue`, preserving MFA-gated break-glass retrieval | authentication, session-mgmt | `app/services/admin_credential_rotation_service.rb`, sparc-iac IAM policy (#197) |
| SI-10 | Password-length validation (min 8 chars), presence check, idempotency check (`admin.authenticate(plaintext)` before mutating); failures return structured 4xx without partial DB mutation | authentication | `app/services/admin_credential_rotation_service.rb`, `app/controllers/api/v1/admin/credentials_controller.rb` |

**Configuration dependencies:**
- ECS task definition injects `SPARC_ADMIN_PASSWORD` from the `admin-credentials` SM secret (sparc-iac change — see risk-sentinel/sparc-iac#197)
- SPARC ECS task role has `secretsmanager:PutSecretValue` + `UpdateSecretVersionStage` on `admin-credentials` (write-only — sparc-iac IAM delta)
- `SPARC_ADMIN_REFRESH_ENABLED=true` to enable the API endpoint (off by default — fail closed)
- A SPARC service account holds the `admin.rotate_credentials` permission and its `sparc_sa_*` token is provisioned to the rotation Lambda via a separate SM secret

---

## Authoritative Sources & Federation (#372)

The authoritative back-matter workflow added in #372 contributes to the following Rev 5 controls beyond what is captured in the per-family tables above. Detailed control-by-control narratives live in the OSCAL CDEF JSON files cross-referenced below.

| Control | Contribution | CDEF | Code Location |
|---|---|---|---|
| AC-3 | Approver-authority predicate gates promotion approve/reject (admin OR `policy_manager` OR `ao`/`agency_ao`/`so_iso` scoped to the resource boundary) | authentication | `app/services/back_matter_resource_promotion_service.rb#can_approve?` |
| AC-4 | Federation peer trust model: signed bundles + peer allow-list, no implicit cross-instance trust | session-mgmt | `app/services/authoritative_source_federation_service.rb`, `app/models/federation_peer.rb` |
| AC-6 | New permission keys `back_matter.{promote,approve_promotion,archive,bulk_import,federate}` with role-tier defaults; least-privileged surface for each new endpoint | authentication | `app/models/role.rb` (PERMISSION_KEYS), `app/controllers/api/v1/back_matter_resources_controller.rb` (before_actions) |
| AC-20 | FederationPeer model registers external SPARC instances under explicit admin control; secrets exchanged out of band | session-mgmt | `app/models/federation_peer.rb` |
| AU-2 | Per-resource `BackMatterResourceChange` rows on every promotion, archive, restore, and federation event; shared `batch_uuid` groups related rows | audit | `app/models/back_matter_resource_change.rb`, `app/services/back_matter_resource_promotion_service.rb` |
| AU-3 | Change rows capture changed_by_user, change_type, field, from_value, to_value, batch_uuid, changed_at; federation rows additionally capture federated_from_instance and federated_bundle_uuid | audit | `app/models/back_matter_resource_change.rb`, `app/services/authoritative_source_federation_service.rb` |
| AU-10 | HMAC-SHA256 signature over canonical-JSON bundle payload provides non-repudiation tying each bundle to a specific peer's signing secret | session-mgmt | `app/services/federation_bundle_signing_service.rb` |
| IA-5 | Federation peer service tokens and signing secrets stored encrypted at rest using AES-GCM via `ActiveSupport::MessageEncryptor`, keyed via `SparcKeyDerivation` from SPARC_HASH | session-mgmt | `app/models/federation_peer.rb`, `app/lib/sparc_key_derivation.rb` |
| SC-7 | `AuthoritativeSourceFetchService` rejects non-HTTPS hrefs and is gated by `SPARC_AUTHORITATIVE_FETCH_ENABLED` (off by default); air-gapped deployments disable outbound URL fetching entirely | session-mgmt | `app/services/authoritative_source_fetch_service.rb` |
| SC-8 | Federation bundles signed with HMAC-SHA256 — application-layer integrity that survives TLS termination at intermediate proxies | session-mgmt | `app/services/federation_bundle_signing_service.rb` |
| SC-12 | New per-instance master secret `SPARC_HASH` introduced; `SparcKeyDerivation` derives purpose-specific keys via HKDF (`ActiveSupport::KeyGenerator` with SHA-256). SPARC_HASH provisioning tracked by sparc-iac issue #195. | session-mgmt | `app/lib/sparc_key_derivation.rb`, `.env.production.example` |
| SC-13 | HMAC-SHA256 (FIPS 198-1) for bundle signing; AES-GCM authenticated encryption (via `ActiveSupport::MessageEncryptor`) for stored peer credentials | session-mgmt | `app/services/federation_bundle_signing_service.rb`, `app/models/federation_peer.rb` |
| SI-10 | `AuthoritativeSourceFetchService` enforces 25 MB body cap, 30s read timeout, content-type-derived filename validation; `BackMatterBulkImportService` validates each row independently with per-row error reporting; signed bundle verification rejects unknown algorithms and tampered payloads | session-mgmt, audit | `app/services/authoritative_source_fetch_service.rb`, `app/services/back_matter_bulk_import_service.rb`, `app/services/federation_bundle_signing_service.rb` |

**Configuration dependencies:**
- `SPARC_HASH` ≥32 bytes (provisioned by sparc-iac into AWS Secrets Manager — issue risk-sentinel/sparc-iac#195). Falls back to Rails `secret_key_base` in dev/test with a logged warning in production.
- `SPARC_AUTHORITATIVE_FETCH_ENABLED=true` to allow URL auto-fetch on resource creation. Off by default.

---

## Summary Statistics

### By Responsibility

| Responsibility | Count | Percentage |
|---|---|---|
| Application (SPARC) | 96 | 39% |
| Infrastructure (sparc-iac) | 47 | 19% |
| CSP Inherited | 28 | 11% |
| Organizational Policy | 58 | 24% |
| Hybrid | 16 | 7% |
| N/A | 2 | 1% |
| **Total** | **247** | **100%** |

### By Status

| Status | Count | Percentage |
|---|---|---|
| Implemented | 133 | 54% |
| Partial | 22 | 9% |
| Planned | 59 | 24% |
| CSP Inherited | 28 | 11% |
| N/A | 5 | 2% |
| **Total** | **247** | **100%** |

### By Family

| Family | Controls Listed | Implemented | Partial | Planned | CSP Inherited | N/A |
|---|---|---|---|---|---|---|
| AC | 28 | 22 | 3 | 3 | 0 | 0 |
| AT | 6 | 0 | 0 | 6 | 0 | 0 |
| AU | 17 | 14 | 1 | 2 | 0 | 0 |
| CA | 11 | 5 | 2 | 4 | 0 | 0 |
| CM | 16 | 11 | 2 | 3 | 0 | 0 |
| CP | 22 | 0 | 2 | 17 | 3 | 0 |
| IA | 18 | 12 | 4 | 2 | 0 | 0 |
| IR | 12 | 2 | 4 | 6 | 0 | 0 |
| MA | 6 | 1 | 3 | 2 | 0 | 0 |
| MP | 7 | 2 | 0 | 2 | 2 | 1 |
| PE | 22 | 0 | 0 | 1 | 21 | 0 |
| PL | 8 | 4 | 1 | 3 | 0 | 0 |
| PM | 12 | 3 | 3 | 6 | 0 | 0 |
| PS | 8 | 4 | 1 | 3 | 0 | 0 |
| PT | 7 | 0 | 2 | 5 | 0 | 0 |
| RA | 10 | 7 | 0 | 2 | 0 | 1 |
| SA | 15 | 11 | 2 | 2 | 0 | 0 |
| SC | 26 | 12 | 0 | 12 | 0 | 2 |
| SI | 18 | 13 | 2 | 2 | 0 | 1 |
| SR | 11 | 4 | 0 | 5 | 1 | 1 |
| **Total** | **247** | **133** | **22** | **59** | **28** | **5** |
