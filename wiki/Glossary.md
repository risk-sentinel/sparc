# Glossary

## OSCAL Terms

| Term | Definition |
|------|------------|
| **OSCAL** | Open Security Controls Assessment Language. A NIST standard for machine-readable security and privacy documentation. |
| **Catalog** | A master list of security controls (e.g., NIST SP 800-53 Rev 5). Contains control families and individual controls. |
| **Profile** | A baseline selection of controls from one or more catalogs, with optional tailoring such as parameter values, additions, and removals. |
| **SSP (System Security Plan)** | Documents how a system implements its selected security controls. The core artifact required for authorization decisions. |
| **SAP (Security Assessment Plan)** | Defines the scope, schedule, and methodology for assessing whether controls are implemented correctly and operating as intended. |
| **SAR (Security Assessment Results)** | Records the findings, observations, and risks identified during execution of an assessment plan. |
| **POA&M (Plan of Action and Milestones)** | Tracks the remediation of identified weaknesses and deficiencies, including responsible parties, milestones, and target dates. |
| **CDEF (Component Definition)** | Documents the security capabilities and control implementations of a reusable component (software, hardware, or service). |
| **Control Mapping** | A cross-reference between controls in different catalogs or frameworks (e.g., NIST 800-53 to ISO 27001), using set-theory relationships. |

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
| **Instance-Scoped Role** | A role that applies to the entire SPARC instance regardless of project context (e.g., Policy Manager). |
| **Project-Scoped Role** | A role that applies only within a specific project (e.g., ISSO). Assigned via the `UserRole` join model with a `project_id`. |
| **Provider Statement** | An inherited control implementation from a parent or leveraged system. Appears as a child row in the SSP control view. |
| **Enrichment** | The process of adding OSCAL metadata (components, users, information types, leveraged authorizations) to a legacy-imported document to bring it into full OSCAL compliance. |
| **Heatmap** | An interactive grid visualization showing control distribution by NIST family and implementation status. Color-coded cells indicate density and status. |
| **DocumentTypeRegistry** | Internal registry mapping document type strings to their parser services, enabling the unified `DocumentConversionJob` to handle all 6 document types. |
| **Conversion Job** | A tracked background job (`ConversionJob` model) that records the status of async document parsing (pending, processing, completed, failed). |
