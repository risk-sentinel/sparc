# Regression testing

The goal of regression testing is to validate that all functions are working
from end-to-end. These tests should be automated to the fullest extent possible
and performed prior to each release.

Testing files are kept in: [Sample Files](../../spec/fixtures/files/)

**Note:** The application manages OSCAL layers (Catalog → Profile/Baseline →
CDEF/SSP → SAP → SAR → POA&M) with additional enrichment capabilities. Regression
tests should verify format compatibility, data preservation across imports/exports,
round-tripping, and end-to-end traceability.

## Catalogs

Catalogs are the base for all files and will feed nearly all downstream functions.
The primary value of catalogs being to upload from existing frameworks that can
be tailored into a fully resolved profile that addresses the systems baseline controls.
A user could build a Catalog from scratch if they desired; however, this is not
part of the regression testing at this time.

- Upload
  - NIST (legacy)
    - XML
    - JSON
  - OSCAL
    - XML
    - YAML
    - JSON
- Export
  - NIST (legacy)
    - XML
    - JSON
  - OSCAL
    - XML
    - YAML
    - JSON

## Baseline / Profile

- Upload OSCAL
  - XML
  - YAML
  - JSON
- Import from Catalog
  - OSCAL
    - Rev 4
      - XML
      - JSON
      - YAML
    - Rev 5
      - XML
      - JSON
      - YAML
  - Legacy
    - Rev 4
      - XML
      - JSON
    - Rev 5
      - XML
      - JSON
- Update Parameters
- Update Priority
- Publish
  - OSCAL
    - Rev 4
      - XML
      - JSON
      - YAML
    - Rev 5
      - XML
      - JSON
      - YAML
  - Legacy
    - Rev 4
      - XML
      - JSON
    - Rev 5
      - XML
      - JSON
- Upload Fully resolved OSCAL
  - Rev 4
    - Low
    - Moderate
    - High
  - Rev 5
    - Low
    - Moderate
    - High

## System Security Plan

The System Security Plan (SSP) is the core implementation-layer document in OSCAL.
It describes how an information system implements the selected security controls
from a baseline/profile, including system characteristics, architecture, components,
responsibilities, parameters, and detailed control implementation statements. The
SSP enables traceability from control requirements to actual system-specific security
measures and supports authorization and continuous monitoring processes.

- Upload OSCAL
  - XML
  - YAML
  - JSON
- Import from Baseline / Profile
  - OSCAL
    - Rev 4
      - XML
      - JSON
      - YAML
    - Rev 5
      - XML
      - JSON
      - YAML
- Edit through Completion
  - Control implementation statements
  - Responsible roles and parties
  - Parameters and values
  - System-specific details and enrichment
- Export / Publish
  - OSCAL
    - Rev 4
      - XML
      - JSON
      - YAML
    - Rev 5
      - XML
      - JSON
      - YAML

## Component Definition (CDEF)

The Component Definition (CDEF) model allows vendors, developers, or system owners
to document reusable security capabilities of individual components (software,
hardware, services, configurations, etc.) and how they satisfy specific controls.
It acts like a "shipping container" for security implementation details, enabling
modular reuse across systems, semi-automated SSP generation, and clearer mapping
of controls to real-world system elements.

- Upload OSCAL
  - XML
  - YAML
  - JSON
- Upload Additional Formats
  - InSpec Profiles
    - JSON
  - XCCDF
    - From SCAP
    - From DISA
- Import from Catalog / Baseline / SSP
  - OSCAL Rev 4 and Rev 5 formats
- Edit
  - Component definitions and inventories
  - Control mappings and implemented-by relationships
  - Properties, metadata, and enrichment layers
- Export
  - OSCAL Rev 4 and Rev 5
    - XML
    - JSON
    - YAML

## Security Assessment Plan (SAP)

The Security Assessment Plan (SAP) defines the methodology, scope, schedule,
resources, and detailed procedures for assessing whether the security controls
described in the SSP (and supported by CDEFs/components) are implemented correctly
and operating as intended. It references the SSP and baseline for context, specifies
assessment actions (test, interview, examine), and ensures consistent, repeatable
evaluations.

- Import from
  - SSP
  - CDEF
  - Catalog
  - Baseline/Profile
  - System context
- Upload OSCAL compliant SAP
  - XML
  - YAML
  - JSON
- Edit
  - Assessment objectives, methods, and scope
  - Test cases and resources
- Export
  - OSCAL
    - XML
    - YAML
    - JSON

## Security Assessment Results (SAR)

The Security Assessment Results (SAR) model captures the outcomes of executing the
SAP, including findings, observations, evidence collected, risk characterizations,
deviations, and overall assessment status for each control or objective. It provides
a traceable record of what was actually assessed versus planned, supporting authorization
decisions and feeding into remediation tracking.

- Generate / Import from SAP
- Upload OSCAL SAR or raw assessment results
- Record findings
  - Link evidence
  - Risk determinations
- Edit / Update observations and results
- Export OSCAL SAR
  - XML, JSON, YAML

## Plan of Action & Milestones (POA&M)

The Plan of Action and Milestones (POA&M) tracks identified weaknesses, risks, or
non-compliances discovered during assessment (typically from the SAR). It outlines
remediation steps, responsible parties, milestones, due dates, resources, and status
updates, serving as a living corrective action plan to reduce risk over time until
controls are fully satisfied.

- Generate from SAR findings
- Upload OSCAL POA&M
- Edit
  - Milestones, due dates, and status
  - Assigned resources and owners
  - Remediation details
- Export OSCAL POA&M
  - XML, JSON, YAML

## Evidence

Evidence in OSCAL is managed primarily through the **back-matter** section (and
linked resources) across documents like SSP, CDEF, SAP, SAR, and POA&M. It allows
attachment, referencing, and embedding of supporting artifacts (scans, logs, screenshots,
documents, tool outputs, etc.) to substantiate control implementations, assessment
findings, or remediation claims, ensuring auditability, traceability, and non-repudiation.

- Upload evidence files
  - Supported formats: PDF, DOCX, images (PNG/JPG), logs, JSON results (InSpec),
  XML (XCCDF/SCAP), etc.
- Link and associate evidence to
  - Specific controls (SSP/CDEF)
  - Assessment steps/results (SAP/SAR)
  - Components
- Manage evidence library and versioning
- Verify referencing in OSCAL back-matter and links upon export
