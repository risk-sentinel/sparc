<!-- markdownlint-disable MD013 MD031 MD040 MD060 -->

# SAP (Security Assessment Plan) -- OSCAL Data Mapping

OSCAL version: **1.1.2** | OSCAL root element: `assessment-plan`

Export service: `OscalAssessmentPlanExportService`

---

## Internal Model Hierarchy

```
SapDocument
  |-- has_many SapControl
  |     |-- has_many SapControlField
  |-- belongs_to SspDocument (optional, linked SSP)
```

---

## Import Sources

| Source | Service | Notes |
|--------|---------|-------|
| OSCAL JSON | `SapJsonParserService` | Full round-trip; preserves metadata, local definitions, terms |
| OSCAL XML / YAML | `SapJsonParserService` | XML/YAML converted to JSON hash, then delegated to JSON parser |
| Wizard | `SapGeneratorService` | Generates SAP from linked SSP; populates controls with assessment methods |

---

## Export Service Methods

| Method | Behavior |
|--------|----------|
| `export` | Builds OSCAL JSON, validates against NIST schema, raises on failure |
| `export_unvalidated` | Builds OSCAL JSON without schema validation |
| `validation_result` | Builds OSCAL JSON and returns validation result (does not raise) |

---

## Field Mapping -- Document Level

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SapDocument#uuid` | `assessment-plan.uuid` | Yes | Regenerated on content change |
| `SapDocument#name` | `assessment-plan.metadata.title` | Yes | |
| `SapDocument#sap_version` | `assessment-plan.metadata.version` | Yes | Defaults to `"1.0.0"` |
| `SapDocument#oscal_version` | `assessment-plan.metadata.oscal-version` | Yes | Defaults to `"1.1.2"` |
| (generated) | `assessment-plan.metadata.last-modified` | Yes | `Time.current.iso8601` at export |
| `SapDocument#metadata_extra` | `assessment-plan.metadata.*` | No | Preserved roles, parties, revisions. Merged into metadata |
| `SapDocument#assessment_type` | `assessment-plan.metadata.props[name=assessment-type]` | No | ns: `https://sparc.local/ns`; appended if not already in metadata_extra |

### Default Metadata (when no metadata_extra)

| OSCAL JSON Path | Default Value |
|----------------|---------------|
| `metadata.roles[]` | assessor, assessment-lead, system-owner, csp-operations + dynamic assessor roles from SapControl#assessor_name |
| `metadata.parties[]` | Organization "Assessment Organization (SPARC Export)" + person entries for each distinct assessor_name |

## Field Mapping -- Import SSP

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SapDocument#ssp_document` | `assessment-plan.import-ssp.href` | Yes | `"#ssp-{id}"` if linked, `"#"` if none |

## Field Mapping -- Local Definitions (Activities)

Activities are generated from distinct `SapControl#assessment_method` values. One activity per method.

| Source | OSCAL JSON Path | Notes |
|--------|----------------|-------|
| (generated) | `local-definitions.activities[].uuid` | Fresh UUID |
| `SapControl#assessment_method` | `local-definitions.activities[].title` | "{Method} Assessment Activities" (titleized) |
| `SapControl#assessment_method` | `local-definitions.activities[].description` | "Assessment activities using the {method} method." |
| `SapControl#assessment_method` | `local-definitions.activities[].props[name=method]` | Uppercased method name |

### Activity Steps (per control within that method)

| Source | OSCAL JSON Path | Notes |
|--------|----------------|-------|
| (generated) | `local-definitions.activities[].steps[].uuid` | Fresh UUID |
| `SapControl#control_id` | `local-definitions.activities[].steps[].title` | "Assess {control_id}" |
| `SapControl#objective` | `local-definitions.activities[].steps[].description` | Falls back to "Assess {control_id} using {method} method." |
| `SapControl#test_case` | `local-definitions.activities[].steps[].remarks` | Only if present |

### Activity Related Controls

| Source | OSCAL JSON Path | Notes |
|--------|----------------|-------|
| `SapControl#control_id` | `...activities[].related-controls.control-selections[].include-controls[].control-id` | Normalized control IDs for all controls using this method |

Only included if at least one SapControl has a non-blank assessment_method.

## Field Mapping -- Terms and Conditions

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SapDocument#assessment_start` | `terms-and-conditions.parts[name=assessment-schedule].prose` | No | "Start: {date}" |
| `SapDocument#assessment_end` | `terms-and-conditions.parts[name=assessment-schedule].prose` | No | Appended as " \| End: {date}" |
| `SapDocument#description` | `terms-and-conditions.parts[name=assessment-scope].prose` | No | Assessment scope description |

Only included if at least one field (assessment_start, assessment_end, or description) is present.

## Field Mapping -- Reviewed Controls

| Source | OSCAL JSON Path | Notes |
|--------|----------------|-------|
| `SapControl#control_id` | `reviewed-controls.control-selections[].include-controls[].control-id` | Normalized; all controls listed |
| `SapControl#objective` | `reviewed-controls.control-selections[].include-controls[].statement-ids[]` | `"{control-id}_obj"` -- only if objective is present |

## Field Mapping -- Assessment Subjects

| OSCAL JSON Path | Value | Notes |
|----------------|-------|-------|
| `assessment-subjects[].type` | `"component"` | Static |
| `assessment-subjects[].description` | `"System components included in this assessment."` | Static |
| `assessment-subjects[].include-all` | `{}` | Includes all components |

## Field Mapping -- Assessment Assets

| OSCAL JSON Path | Value | Notes |
|----------------|-------|-------|
| `assessment-assets.assessment-platforms[].uuid` | (generated) | Fresh UUID |
| `assessment-assets.assessment-platforms[].title` | `"Assessment Platform"` | Static |
| `assessment-assets.assessment-platforms[].props[name=type]` | `"manual"` | ns: `https://sparc.local/ns` |

## Field Mapping -- Back Matter

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SapDocument#build_oscal_back_matter` | `assessment-plan.back-matter` | No | Shared concern; includes resources, citations, attachments |

---

## Assessment Method Mapping

SAP controls carry an `assessment_method` field that maps to OSCAL assessment activities. The three standard NIST methods are:

| Method Value | OSCAL Method Prop | Description |
|-------------|-------------------|-------------|
| `examine` | `EXAMINE` | Review of documentation, policies, procedures |
| `interview` | `INTERVIEW` | Discussions with personnel responsible for implementation |
| `test` | `TEST` | Hands-on testing of technical controls and mechanisms |

Methods are stored on `SapControl#assessment_method` and grouped into local-definition activities at export time. Each activity contains steps (one per control using that method) with optional objectives and test cases.

## Control ID Normalization

Same logic as SSP/SAR: lowercase, spaces to hyphens, parenthesized enhancements to dot notation (`AC-2 (1)` becomes `ac-2.1`).
