# Framework Mapping Plan: STIG, CIS, CCI, SCAP → OSCAL

Target: 80%+ automated coverage for mapping DISA STIGs, CIS Benchmarks,
CCI references, and SCAP/OVAL content to NIST SP 800-53 via OSCAL.

---

## Architecture Overview

```text
                          ┌──────────────────────────────┐
                          │      XCCDF/SCAP File         │
                          │  (STIG, CIS, or generic)     │
                          └──────────────┬───────────────┘
                                         │
                    ┌────────────────────▼────────────────────┐
                    │     CdefXccdfParserService (existing)    │
                    │  - detect_cdef_type → disa_stig/cis/scap │
                    │  - parse Rules → CdefControl records     │
                    │  - extract cci_references (STIG)         │
                    │  - extract group_id (CIS)                │
                    └────────────────────┬────────────────────┘
                                         │
                    ┌────────────────────▼────────────────────┐
                    │  FrameworkMappingGeneratorService (new)  │
                    │  - reads lib/data_mappings/<type>.json   │
                    │  - resolves each control → NIST IDs      │
                    │  - creates ControlMapping + entries       │
                    └────────────────────┬────────────────────┘
                                         │
            ┌────────────────────────────▼────────────────────────┐
            │                                                      │
   ┌────────▼────────┐   ┌──────────▼──────────┐   ┌─────────▼──────────┐
   │  lib/data_maps/  │   │  ControlMapping      │   │  OSCAL Export       │
   │  cci_to_nist.json│   │  + entries (DB)       │   │  (both existing)    │
   │  cis_to_nist.json│   │                      │   │  - Mapping JSON     │
   │  scap_to_nist    │   │  SV-257777 → AC-2    │   │  - Component Def    │
   └──────────────────┘   │  SV-257777 → AC-6    │   └─────────────────────┘
                          │  1.1.1 → CM-6        │
                          │  1.1.1 → CM-7        │
                          └──────────────────────┘
```

---

## The Core Pattern: One Source ID → Multiple NIST Controls

Each `ControlMappingEntry` is one source→target pair. A single SV-XXXXX
or CIS section with 3 related NIST controls becomes 3 entry rows — all
with the same `source_control_id` but different `target_control_id` values.

### DISA STIG Flow (CCI Pivot)

```text
SV-257777 → CCI-000015 → ac-2
SV-257777 → CCI-000225 → ac-6
SV-257777 → CCI-000764 → ia-2
```

The **CCI (Control Correlation Identifier)** is the pivot. DISA publishes
a CCI XML file (~7,500 entries) that maps each CCI to a NIST control.
STIGs embed CCI references in each rule's `<ident>` element.

### CIS Benchmark Flow (Direct Mapping)

```text
1.1.1 (Ensure mounting of cramfs disabled) → cm-6, cm-7
5.2.1 (Ensure permissions on sshd_config)  → ac-3, ac-6
```

CIS publishes official NIST mappings. Each benchmark section maps to
one or more NIST controls via a static lookup table.

### SCAP/OVAL Flow (Multi-Tier Resolution)

```text
1. Check system URI → NIST (e.g., OVAL defs → cm-6)
2. OVAL family detection → NIST (e.g., "patch" → si-2)
3. Keyword matching (fallback) → NIST (e.g., "password" → ia-5)
```

---

## Files Created

| File | Purpose |
|------|---------|
| `app/services/framework_mapping_generator_service.rb` | Unified converter service |
| `lib/data_mappings/cci_to_nist.json` | CCI→NIST lookup (50 starter, rake for full ~7,500) |
| `lib/data_mappings/cis_to_nist.json` | CIS Benchmark→NIST lookup (40 entries) |
| `lib/data_mappings/scap_oval_to_nist.json` | SCAP/OVAL→NIST (families + keywords) |
| `lib/tasks/import_cci.rake` | Rake task: DISA CCI XML → cci_to_nist.json |
| `spec/services/framework_mapping_generator_service_spec.rb` | Specs |

## Existing Infrastructure (No Changes Needed)

| File | Role |
|------|------|
| `app/services/cdef_xccdf_parser_service.rb` | XCCDF parser (STIG+CIS+SCAP auto-detection) |
| `app/models/control_mapping.rb` | Mapping collection model |
| `app/models/control_mapping_entry.rb` | Individual source→target entry |
| `app/services/oscal_mapping_export_service.rb` | OSCAL v1.2.1 mapping-collection JSON export |
| `app/services/oscal_component_definition_export_service.rb` | OSCAL component-definition export |
| `app/models/cdef_document.rb` | CDEF document (cdef_type: disa_stig/cis/scap/custom) |
| `app/models/cdef_control.rb` | Parsed control with cci_references, group_id, rule_id |
| `spec/fixtures/files/controls/oscal_mapping_schema.json` | OSCAL mapping JSON schema |

---

## Service API

```ruby
# After importing a STIG/CIS/SCAP XCCDF file:
doc = CdefDocument.find(123)
nist_catalog = ControlCatalog.find_by(name: "NIST SP 800-53 Rev 5")
service = FrameworkMappingGeneratorService.new(doc, nist_catalog)

# Dry-run preview (no DB writes)
service.preview
# => { "SV-257777" => ["ac-2", "ac-6", "ia-2"], "SV-258001" => ["cm-6"] }

# Coverage stats
service.coverage_stats
# => { total: 200, mapped: 170, unmapped: 30, coverage_pct: 85.0 }

# Generate and persist mapping
mapping = service.generate!
# => ControlMapping with auto-populated entries

# Export to OSCAL
OscalMappingExportService.new(mapping).export
# => OSCAL v1.2.1 mapping-collection JSON string
```

---

## Coverage Targets

| Framework | Source ID | Pivot | Auto-Coverage | Notes |
|-----------|-----------|-------|--------------|-------|
| **DISA STIG** | SV-XXXXX | CCI-XXXXX → NIST | **~95%** | CCI XML is comprehensive |
| **CIS Benchmarks** | 1.1.1 etc | CIS→NIST table | **~85%** | CIS publishes official mappings |
| **CCI Direct** | CCI-XXXXX | self → NIST | **~98%** | CCI *is* the mapping |
| **SCAP/OVAL** | OVAL def | family + keywords | **~70%** | Family-level, not rule-level |
| **Combined** | | | **~87%** | Above 80% target |

---

## Getting Full CCI Data

The starter `cci_to_nist.json` has 50 entries. To populate all ~7,500:

1. Download `U_CCI_List.zip` from:
   `https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_CCI_List.zip`
2. Unzip and place `U_CCI_List.xml` in the `tmp/` directory
3. Run: `rake mapping:import_cci`
4. Verify: `lib/data_mappings/cci_to_nist.json` now has ~7,500 entries

---

## Expanding CIS Coverage

CIS publishes official OSCAL catalogs at their GitHub repository. To
expand the `cis_to_nist.json` mapping table:

1. Download CIS Controls v8.1 OSCAL catalog from CIS
2. Extract section→NIST mappings from the OSCAL profile `imports`
3. Add entries to `lib/data_mappings/cis_to_nist.json`

Platform-specific benchmarks (Ubuntu, RHEL, Windows, etc.) follow the
same CIS section numbering, so one mapping table covers multiple
benchmarks.

---

## Database Schema (Existing)

### control_mappings

```
uuid, name, description, mapping_version, oscal_version, status,
method_type, matching_rationale, source_catalog_id, target_catalog_id,
metadata_extra (jsonb), timestamps
```

### control_mapping_entries

```
uuid, control_mapping_id, source_control_id, source_type,
target_control_id, target_type, relationship, matching_rationale,
remarks, row_order, timestamps
Unique index: (mapping_id, source_control_id, target_control_id)
```

### Relationship types (NIST IR 8477)

- `equal` — exact syntactic match
- `equivalent` — identical in meaning
- `subset` — source is narrower than target
- `superset` — source encompasses target
- `intersects` — partial overlap

---

## Future Enhancements

- **Bulk CIS import rake task** — similar to `import_cci` but for CIS
  OSCAL catalog JSON
- **SCAP DataStream support** — parse `<ds:data-stream-collection>` to
  extract OVAL + XCCDF together
- **Reverse mapping** — NIST → STIG/CIS for gap analysis
- **Mapping confidence scores** — weight entries by how they were
  resolved (CCI = high, keyword = low)
- **UI integration** — "Auto-map" button on CdefDocument show page that
  calls the generator and displays coverage stats
- **InSpec profile import** — parse InSpec JSON profiles and extract
  STIG/CCI tags for mapping
