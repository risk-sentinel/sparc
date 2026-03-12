# OSCAL for Managing Foreign Inputs and Integrating Disparate Validation Tools

## Control Mapping in OSCAL for Managing "Foreign" Inputs

**OSCAL** (Open Security Controls Assessment Language) is a
NIST-developed standard for representing security controls,
baselines, implementations, and assessments in machine-readable
formats (**XML**, **JSON**, **YAML**). It enables automation of
compliance processes by allowing structured mappings between
controls from different frameworks or sources.

"Foreign" inputs refer to controls or data from external
standards, tools, or catalogs not native to a primary framework
(e.g., NIST SP 800-53). Examples include DISA STIGs, CIS
Benchmarks, or tool-specific checks from InSpec profiles.

### OSCAL Control Mapping Model

The **OSCAL Control Mapping Model** provides a formal,
machine-readable way to define relationships among controls from
disparate sources (standards, regulations, frameworks like DISA
STIG, CIS Benchmarks, or NIST) **without restating or
duplicating** the original content.

#### Key Features

- **Relationship Types** (using set-theory-inspired semantics):
  - *Equivalent-to*: Controls are identical in meaning.
  - *Equal-to*: Exact syntactic match.
  - *Subset-of*: One control is a narrower version of another.
  - *Superset-of*: One control encompasses another.
  - *Intersects-with*: Partial overlap.
  - *No-relationship*: No meaningful connection.

- **Many-to-Many Mappings**: Supports linking controls from
  multiple OSCAL catalogs or profiles simultaneously, reflecting
  real-world multi-framework compliance (e.g., mapping
  STIG to NIST while incorporating CIS).

- **Analysis Methods**: Mappings can be:
  - Syntactic (exact text match)
  - Semantic (meaning-based)
  - Functional (purpose-based)

- **Purpose for Foreign Inputs**: Abstracts mappings across
  domains (cybersecurity, privacy, supply chain), allowing
  foreign controls (e.g., from DISA or CIS) to be integrated
  into an OSCAL profile or catalog. Example: Import a STIG
  control as a reference in an OSCAL component definition, then
  map it to equivalent NIST controls.

Mappings are defined in an OSCAL mapping document, resolved
during profile processing to create unified baselines. Tools
like `oscal-cli` automate resolution for deterministic,
validation-ready outputs.

## Using DISA STIG (SV or V) in OSCAL Mapping with InSpec Profiles

DISA **Security Technical Implementation Guides (STIGs)** use
IDs like **SV-XXXX** (Severity-Vulnerability) or **V-XXXX**
(Vulnerability ID) for technical checks.

- **Mapping Process**:
  - In OSCAL: Import STIG controls into a catalog as foreign
    elements. Use the mapping model to link STIG IDs to NIST
    SP 800-53 controls (e.g., SV-123456 to AC-2).
  - InSpec Integration: STIG-based InSpec profiles tag controls
    with STIG IDs and CCIs. Run scans
    (`inspec exec ... --reporter json`), convert JSON results
    to OSCAL **Assessment Results (SAR)** format via tools like
    InSpec-to-OSCAL converters.
  - Findings in SAR reference mapped controls, enabling STIG
    checks as evidence for NIST compliance.

- **Workflow Example**:
  1. OSCAL profile imports NIST + maps STIG via CCI XML.
  2. InSpec scans against STIG profiles.
  3. Import results to OSCAL SAR.
  4. Validate with `oscal-cli`.

This supports automated validation in tools like RegScale.

## Mapping CIS-Based Profiles and Checks to NIST Controls in OSCAL

**CIS** (Center for Internet Security) Benchmarks use
hierarchical IDs (e.g., **1.1.1.1** for filesystem
configuration).

- **Mapping Process**:
  - CIS provides official OSCAL serializations (v8/v8.1) in
    their repository for easy import as catalogs.
  - Map CIS checks to NIST via relationships (e.g., 1.1.1.1
    as subset-of CM-6).
  - CIS-aligned InSpec profiles execute checks; map IDs in
    OSCAL profiles.
  - One-to-many links possible (one CIS check to multiple
    NIST controls).

- **Example**: Reference CIS profile in OSCAL component;
  transform InSpec results (e.g., Azure CIS) into SAR findings
  with NIST traceability.

## Integrating DISA CCI in OSCAL for InSpec Profiles

**Control Correlation Identifiers (CCIs)** bridge STIGs to NIST
SP 800-53 (e.g., CCI-000001 to AC-1). Many InSpec profiles
embed CCIs.

- **Fit in OSCAL**:
  - Use DISA CCI XML to generate mappings automatically.
  - Tag STIG/InSpec controls with CCIs to pivot to NIST in
    catalogs/profiles.
  - InSpec results reference CCIs; convert to OSCAL SAR
    (findings/risks link via CCI IDs).
  - Tools like OpenRMF automate CCI to NIST exports to OSCAL.

## Achieving the Goal: Disparate Validation Tools for Component SAR Results

OSCAL's modular architecture integrates results from multiple
tools (InSpec for STIG/CIS, OpenSCAP, custom scripts) into a
unified **SAR**:

- **Component Definition**: Reference foreign implementations
  (e.g., STIG checks as "implemented-requirements").
- **Assessment Layer**: SAR aggregates observations/findings;
  each can embed tool-specific data while linking to unified
  controls via mappings.
- **Automation Benefits**: OSCAL resolvers merge mappings;
  validate combined SAR. Enables "compliance as code" pipelines.
- **Best Practices**:
  - Start with OSCAL catalogs for NIST/CIS/STIG.
  - Use CCI as pivot points.
  - Script tool output conversions.
  - Leverage NIST OSCAL GitHub examples, CIS OSCAL repo,
    Chef InSpec profiles.

This approach reduces manual effort, ensures traceability across
frameworks, and supports automated component-level assessment
reporting.
