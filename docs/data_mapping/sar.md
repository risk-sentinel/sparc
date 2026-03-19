<!-- markdownlint-disable MD013 MD031 MD040 MD060 -->

# SAR (Security Assessment Results) -- OSCAL Data Mapping

OSCAL version: **1.1.2** | OSCAL root element: `assessment-results`

Export service: `OscalSarExportService`

---

## Internal Model Hierarchy

```
SarDocument
  |-- has_many SarControl
  |     |-- has_many SarControlField
  |-- has_many SarResult
  |     |-- has_many SarObservation
  |     |     |-- has_many SarFindingObservation (join)
  |     |     |-- has_many SarRiskObservation (join)
  |     |-- has_many SarFinding
  |     |     |-- has_many SarFindingObservation (join)
  |     |     |-- has_many SarFindingRisk (join)
  |     |-- has_many SarRisk
  |     |     |-- has_many SarRiskObservation (join)
  |-- has_many SarLocalComponent
```

---

## Import Sources

| Source | Service | Notes |
|--------|---------|-------|
| Excel (.xlsx) | `SarExcelParserService` | Parses assessment data into SarControl + SarControlField |
| OSCAL JSON | `SarJsonParserService` | Full round-trip; preserves results, observations, findings, risks, components |
| OSCAL XML / YAML | `SarJsonParserService` | XML/YAML converted to JSON hash, then delegated to JSON parser |
| Published Profile | `SarFromProfileService` | Creates SAR shell from profile resolved catalog |
| SSP Document | `SarFromSspService` | Creates SAR from existing SSP, carrying forward control data |
| Wizard | UI-driven | Step-by-step creation via wizard controller |

---

## Export Service Methods

| Method | Behavior |
|--------|----------|
| `export` | Builds OSCAL JSON, validates against NIST schema, raises on failure |
| `export_unvalidated` | Builds OSCAL JSON without schema validation |
| `validation_result` | Builds OSCAL JSON and returns validation result (does not raise) |

---

## Two Export Paths

The SAR export service uses a **unified approach** with two paths:

1. **Enriched path** -- When `SarResult` records exist (OSCAL imports, wizard, or UI-enriched documents), the service uses the full relational model: SarResult with nested SarObservation, SarFinding, and SarRisk records.
2. **Synthesized path** -- When no `SarResult` records exist (typical for Excel imports that have not been enriched), the service synthesizes observations and findings from `SarControl` / `SarControlField` data.

---

## Field Mapping -- Document Level

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SarDocument#uuid` | `assessment-results.uuid` | Yes | Regenerated on content change |
| `SarDocument#name` | `assessment-results.metadata.title` | Yes | |
| `SarDocument#sar_version` | `assessment-results.metadata.version` | Yes | Defaults to `"1.0.0"` |
| `SarDocument#oscal_version` | `assessment-results.metadata.oscal-version` | Yes | Defaults to `"1.1.2"` |
| (generated) | `assessment-results.metadata.last-modified` | Yes | `Time.current.iso8601` at export |
| `SarDocument#metadata_extra` | `assessment-results.metadata.*` | No | Preserved roles, parties, revisions. Merged into metadata |
| (default) | `assessment-results.metadata.roles[]` | No | Default: assessor role |
| (default) | `assessment-results.metadata.parties[]` | No | Default: single organization party "SPARC Export" |

## Field Mapping -- Import AP

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SarDocument#import_ap_href` | `assessment-results.import-ap.href` | Yes | Defaults to `"#"` if blank |

## Field Mapping -- Local Definitions

### Components (SarLocalComponent)

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SarLocalComponent#uuid` | `local-definitions.components[].uuid` | Yes | |
| `SarLocalComponent#component_type` | `local-definitions.components[].type` | Yes | |
| `SarLocalComponent#title` | `local-definitions.components[].title` | Yes | |
| `SarLocalComponent#description` | `local-definitions.components[].description` | Yes | |
| `SarLocalComponent#purpose` | `local-definitions.components[].purpose` | No | |
| `SarLocalComponent#status_state` | `local-definitions.components[].status.state` | No | |
| `SarLocalComponent#status_remarks` | `local-definitions.components[].status.remarks` | No | |
| `SarLocalComponent#responsible_roles_data` | `local-definitions.components[].responsible-roles` | No | JSON array |
| `SarLocalComponent#protocols_data` | `local-definitions.components[].protocols` | No | JSON array |
| `SarLocalComponent#props_data` | `local-definitions.components[].props` | No | JSON array |
| `SarLocalComponent#links_data` | `local-definitions.components[].links` | No | JSON array |
| `SarLocalComponent#remarks` | `local-definitions.components[].remarks` | No | |

Additional local-definitions content (activities, assessment-assets, etc.) is preserved in `SarDocument#local_definitions_extra` and merged at export.

---

## Field Mapping -- Enriched Path (SarResult Records Present)

### Results

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SarResult#uuid` | `results[].uuid` | Yes | |
| `SarResult#title` | `results[].title` | Yes | |
| `SarResult#description` | `results[].description` | Yes | |
| `SarResult#start_time` | `results[].start` | No | ISO 8601 |
| `SarResult#end_time` | `results[].end` | No | ISO 8601 |
| `SarResult#reviewed_controls_data` | `results[].reviewed-controls` | Yes | Default: `{ control-selections: [{ include-all: {} }] }` |
| `SarResult#assessment_log_data` | `results[].assessment-log` | No | Wrapped in `{ entries: [...] }` if array |
| `SarResult#attestations_data` | `results[].attestations` | No | JSON array |
| `SarResult#props_data` | `results[].props` | No | JSON array |
| `SarResult#links_data` | `results[].links` | No | JSON array |
| `SarResult#remarks` | `results[].remarks` | No | |

### Observations (SarObservation)

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SarObservation#uuid` | `results[].observations[].uuid` | Yes | |
| `SarObservation#title` | `results[].observations[].title` | Yes | |
| `SarObservation#description` | `results[].observations[].description` | Yes | |
| `SarObservation#methods_data` | `results[].observations[].methods` | No | JSON array (e.g., ["TEST", "EXAMINE"]) |
| `SarObservation#types_data` | `results[].observations[].types` | No | JSON array |
| `SarObservation#origins_data` | `results[].observations[].origins` | No | JSON array |
| `SarObservation#subjects_data` | `results[].observations[].subjects` | No | JSON array |
| `SarObservation#relevant_evidence_data` | `results[].observations[].relevant-evidence` | No | JSON array |
| `SarObservation#collected` | `results[].observations[].collected` | No | ISO 8601 |
| `SarObservation#expires` | `results[].observations[].expires` | No | ISO 8601 |
| `SarObservation#props_data` | `results[].observations[].props` | No | JSON array |
| `SarObservation#links_data` | `results[].observations[].links` | No | JSON array |
| `SarObservation#remarks` | `results[].observations[].remarks` | No | |

### Findings (SarFinding)

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SarFinding#uuid` | `results[].findings[].uuid` | Yes | |
| `SarFinding#title` | `results[].findings[].title` | Yes | |
| `SarFinding#description` | `results[].findings[].description` | Yes | |
| `SarFinding#target_data` | `results[].findings[].target` | No | JSON object with type, target-id, status |
| `SarFinding#implementation_statement_uuid` | `results[].findings[].implementation-statement-uuid` | No | |
| `SarFinding#origins_data` | `results[].findings[].origins` | No | JSON array |
| (join: SarFindingObservation) | `results[].findings[].related-observations[].observation-uuid` | No | References SarObservation#uuid |
| (join: SarFindingRisk) | `results[].findings[].related-risks[].risk-uuid` | No | References SarRisk#uuid |
| `SarFinding#props_data` | `results[].findings[].props` | No | JSON array |
| `SarFinding#links_data` | `results[].findings[].links` | No | JSON array |
| `SarFinding#remarks` | `results[].findings[].remarks` | No | |

### Risks (SarRisk)

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SarRisk#uuid` | `results[].risks[].uuid` | Yes | |
| `SarRisk#title` | `results[].risks[].title` | Yes | |
| `SarRisk#description` | `results[].risks[].description` | Yes | |
| `SarRisk#statement` | `results[].risks[].statement` | No | |
| `SarRisk#status` | `results[].risks[].status` | No | e.g., "open", "closed" |
| `SarRisk#origins_data` | `results[].risks[].origins` | No | JSON array |
| `SarRisk#threat_ids_data` | `results[].risks[].threat-ids` | No | JSON array |
| `SarRisk#characterizations_data` | `results[].risks[].characterizations` | No | JSON array |
| `SarRisk#mitigating_factors_data` | `results[].risks[].mitigating-factors` | No | JSON array |
| `SarRisk#deadline` | `results[].risks[].deadline` | No | ISO 8601 |
| `SarRisk#remediations_data` | `results[].risks[].remediations` | No | JSON array |
| `SarRisk#risk_log_data` | `results[].risks[].risk-log` | No | JSON object |
| (join: SarRiskObservation) | `results[].risks[].related-observations[].observation-uuid` | No | References SarObservation#uuid |
| `SarRisk#props_data` | `results[].risks[].props` | No | JSON array |
| `SarRisk#links_data` | `results[].risks[].links` | No | JSON array |
| `SarRisk#remarks` | `results[].risks[].remarks` | No | |

---

## Field Mapping -- Synthesized Path (No SarResult Records)

When no `SarResult` records exist, the exporter generates a single result with synthesized observations and findings from `SarControl` data.

### Synthesized Result

| Source | OSCAL JSON Path | Notes |
|--------|----------------|-------|
| (generated) | `results[0].uuid` | Fresh UUID |
| `SarDocument#name` | `results[0].title` | "Assessment Results for {name}" |
| (static) | `results[0].description` | "Synthesized from Excel assessment data." |
| `SarDocument#assessment_start` | `results[0].start` | Falls back to `created_at`, then `Time.current` |
| `SarDocument#assessment_end` | `results[0].end` | Falls back to `Time.current` |
| (static) | `results[0].reviewed-controls` | `{ control-selections: [{ include-all: {} }] }` |

### Synthesized Observations (one per SarControl)

| Source | OSCAL JSON Path | Notes |
|--------|----------------|-------|
| (generated) | `results[0].observations[].uuid` | Fresh UUID |
| `SarControl#control_id` | `results[0].observations[].title` | "Assessment of {control_id}" |
| SarControlField `result` | `results[0].observations[].description` | Includes control_id, result, notes_weakness, recommended_fix |
| SarControlField `notes_weakness` | `results[0].observations[].description` | Appended as "Notes: {value}" |
| SarControlField `recommended_fix` | `results[0].observations[].description` | Appended as "Recommendation: {value}" |
| (static) | `results[0].observations[].methods` | `["TEST"]` |
| `SarDocument#assessment_start` | `results[0].observations[].collected` | Falls back to `created_at` |

### Synthesized Findings (one per SarControl)

| Source | OSCAL JSON Path | Notes |
|--------|----------------|-------|
| (generated) | `results[0].findings[].uuid` | Fresh UUID |
| `SarControl#control_id` | `results[0].findings[].title` | "Finding for {control_id}" |
| SarControlField `result` | `results[0].findings[].description` | "Assessment finding for control {id}: {result}" |
| `SarControl#control_id` | `results[0].findings[].target.target-id` | Normalized control ID |
| (static) | `results[0].findings[].target.type` | `"objective-id"` |
| SarControlField `result` | `results[0].findings[].target.status.state` | Mapped: pass -> "satisfied", fail/not-satisfied -> "not-satisfied" |
| (join) | `results[0].findings[].related-observations[].observation-uuid` | Links to synthesized observation |

---

## Field Mapping -- Back Matter

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SarDocument#build_oscal_back_matter` | `assessment-results.back-matter` | No | Shared concern; includes resources, citations, attachments |

## Control ID Normalization

Same logic as SSP: lowercase, spaces to hyphens, parenthesized enhancements to dot notation (`AC-2 (1)` becomes `ac-2.1`).
