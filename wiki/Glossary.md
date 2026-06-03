# Glossary

## OSCAL Terms

| Term | Definition |
|------|------------|
| **OSCAL** | Open Security Controls Assessment Language. A NIST standard for machine-readable security and privacy documentation. |
| **Catalog** | A master list of security controls (e.g., NIST SP 800-53 Rev 5). Contains control families and individual controls. |
| **Baseline** | A predefined starting set of controls for a given impact level (e.g., NIST SP 800-53 **LOW / MODERATE / HIGH**). A Profile typically begins from a baseline and then tailors it. |
| **Profile** | A selection of controls from one or more catalogs (usually starting from a **baseline**), with optional tailoring such as parameter values, additions, and removals. |
| **Resolved Profile** | The fully-expanded catalog produced by applying a Profile's imports and tailoring — the concrete list of controls with resolved parameters that an SSP implements. |
| **SSP (System Security Plan)** | Documents how a system implements its selected security controls. The core artifact required for authorization decisions. |
| **SAP (Security Assessment Plan)** | Defines the scope, schedule, and methodology for assessing whether controls are implemented correctly and operating as intended. |
| **SAR (Security Assessment Results)** | Records the findings, observations, and risks identified during execution of an assessment plan. |
| **POA&M (Plan of Action and Milestones)** | Tracks the remediation of identified weaknesses and deficiencies, including responsible parties, milestones, and target dates. |
| **CDEF (Component Definition)** | Documents the security capabilities and control implementations of a reusable component (software, hardware, or service). |
| **Control Mapping** | A cross-reference between controls in different catalogs or frameworks (e.g., NIST 800-53 to ISO 27001), using set-theory relationships. |
| **Back-Matter** | The OSCAL section holding supporting resources — citations, evidence, attachments, and `rlinks` — referenced by UUID from elsewhere in a document. In SPARC these are promoted to first-class `BackMatterResource` rows (see [Changelog](Changelog) v1.8.0). |
| **Metadata** | The OSCAL header section common to every document — title, version, OSCAL version, roles, parties, and responsible-party assignments. |

## NIST RMF Terms

| Term | Definition |
|------|------------|
| **RMF** | Risk Management Framework (NIST SP 800-37 Rev. 2). A six-step process: Categorize, Select, Implement, Assess, Authorize, Monitor. |
| **ATO (Authorization to Operate)** | A formal decision by an Authorizing Official to accept the risk of operating an information system. |
| **P-ATO (Provisional ATO)** | A FedRAMP provisional authorization issued by the Joint Authorization Board (JAB). |
| **FedRAMP** | Federal Risk and Authorization Management Program. Standardizes security assessment, authorization, and continuous monitoring for cloud services. |

## NIST Publications

| Publication | Title |
|-------------|-------|
| **NIST SP 800-53** | Security and Privacy Controls for Information Systems and Organizations. The primary control catalog used in SPARC. |
| **NIST SP 800-37** | Risk Management Framework for Information Systems and Organizations. Defines the RMF lifecycle. |
| **NIST SP 800-63B** | Digital Identity Guidelines. Defines password and authentication requirements (e.g., 12-character minimum). |
| **NIST IR 8477** | Mapping Relationships Between Security Control Frameworks. Defines set-theory relationships (superset, subset, intersect, equal) for control mappings. |

## NIST 800-53 Control Families

| ID | Family Name |
|----|-------------|
| AC | Access Control |
| AT | Awareness and Training |
| AU | Audit and Accountability |
| CA | Assessment, Authorization, and Monitoring |
| CM | Configuration Management |
| CP | Contingency Planning |
| IA | Identification and Authentication |
| IR | Incident Response |
| MA | Maintenance |
| MP | Media Protection |
| PE | Physical and Environmental Protection |
| PL | Planning |
| PM | Program Management |
| PS | Personnel Security |
| PT | PII Processing and Transparency |
| RA | Risk Assessment |
| SA | System and Services Acquisition |
| SC | System and Communications Protection |
| SI | System and Information Integrity |
| SR | Supply Chain Risk Management |

## SPARC-Specific Terms

| Term | Definition |
|------|------------|
| **Instance Admin** | A boolean flag on the User model granting full system access. Not a role -- it is a superuser designation that bypasses role checks. |
| **Authorization Boundary** | The top-level container in SPARC for organizing compliance artifacts (SSP, SAR, SAP, POA&M, CDEFs, Evidence) around a system's security perimeter, aligned with NIST RMF / FedRAMP terminology. |
| **Instance-Scoped Role** | A role that applies to the entire SPARC instance regardless of authorization boundary context (e.g., Policy Manager). |
| **Authorization-Boundary-Scoped Role** | A role that applies only within a specific authorization boundary (e.g., ISSO). Assigned via the `UserRole` join model with an `authorization_boundary_id`. |
| **Provider Statement** | An inherited control implementation from a parent or leveraged system. Appears as a child row in the SSP control view. |
| **Enrichment** | The process of adding OSCAL metadata (components, users, information types, leveraged authorizations) to a legacy-imported document to bring it into full OSCAL compliance. |
| **Heatmap** | An interactive grid visualization showing control distribution by NIST family and implementation status. Color-coded cells indicate density and status. |
| **DocumentTypeRegistry** | Internal registry mapping document type strings to their parser services, enabling the unified `DocumentConversionJob` to handle all 6 document types. |
| **Conversion Job** | A tracked background job (`ConversionJob` model) that records the status of async document parsing (pending, processing, completed, failed). |
| **Converter** | A mapping engine that translates external framework identifiers — **CCI**, **AWS Config**, **AWS Security Hub**, **STIG** — into NIST 800-53 control IDs. Refreshable on demand from the converter management page. |
| **Authoritative Source** | A trusted upstream library of OSCAL back-matter resources that authorization boundaries can draw from; promoted resources flow through a review/approval **promotion queue** (#372). |
| **Federation Peer** | Another SPARC instance configured to exchange **HMAC-signed OSCAL bundles**, enabling authoritative-source sharing across instances (#372). |
| **Leveraged Authorization** | An inherited authorization from an underlying system (e.g., a cloud platform) whose controls a tenant system can claim as provider-implemented. |
| **Evidence / Attestation** | Records attached to an authorization boundary that substantiate control implementation; can be merged into OSCAL output as back-matter resources. |

## FedRAMP 20x & Integration Terms

| Term | Definition |
|------|------------|
| **KSI (Key Security Indicators)** | FedRAMP 20x machine-checkable security indicators, grouped into **themes**. SPARC ships a read-only KSI catalog and tracks **KSI validations** per authorization boundary, with summary and export. |
| **HDF (Heimdall Data Format)** | MITRE's normalized security-results format (consumed by Heimdall). SPARC bridges **HDF ↔ OSCAL** — emitting OSCAL SAR / POA&M from HDF and round-tripping POA&M amendments back to HDF — via stateless `/api/v1/` endpoints (see [Changelog](Changelog) v1.6.0). |
| **SBOM (Software Bill of Materials)** | A CycloneDX inventory of software components and licenses, generated in CI and scanned by Grype/Trivy for vulnerabilities and license compliance. |
| **SAF CLI** | MITRE's Security Automation Framework CLI, used in CI to normalize scanner output into HDF for compliance evidence. |
