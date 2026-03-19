<!-- markdownlint-disable MD013 MD031 MD040 MD060 -->

# OSCAL Data Mapping Guide

## 1. Overview

SPARC transforms security compliance data through a three-stage pipeline:

```
Import (file upload)          Internal Model             Export (download)
─────────────────────     ─────────────────────     ─────────────────────
Excel / JSON / XML /  →   Document → Controls   →   OSCAL JSON validated
YAML / XCCDF              → ControlFields            against NIST schemas
```

**Import**: Files are uploaded through the UI or API. `DocumentTypeRegistry` maps the file extension to the correct parser service, which normalises the source data into SPARC's three-level model (Document, Controls, ControlFields).

**Internal Model**: All document types share the same structural pattern. Controls belong to a document; fields belong to a control. Editable fields can be updated through inline editing in the UI or via the REST API.

**Export**: Export services read the internal model and produce OSCAL v1.1.2 JSON. The output is validated against the official NIST JSON Schema before download. An unvalidated export option is also available.

## 2. Document Type Reference Table

| Document Type | Internal Model | Control Model | Field Model | Parser Services | Export Service | OSCAL Root Element | Schema File |
|---|---|---|---|---|---|---|---|
| SSP | `SspDocument` | `SspControl` | `SspControlField` | `SspExcelParserService`, `SspJsonParserService`, `SspXmlParserService`, `SspYamlParserService` | `OscalSspExportService` | `system-security-plan` | `oscal_ssp_schema.json` |
| SAR | `SarDocument` | `SarControl` | `SarControlField` | `SarExcelParserService`, `SarJsonParserService`, `SarXmlParserService`, `SarYamlParserService` | `OscalSarExportService` | `assessment-results` | `oscal_assessment-results_schema.json` |
| SAP | `SapDocument` | `SapControl` | `SapControlField` | `SapJsonParserService`, `SapXmlParserService`, `SapYamlParserService` | `OscalAssessmentPlanExportService` | `assessment-plan` | `oscal_assessment-plan_schema.json` |
| POA&M | `PoamDocument` | `PoamItem` | _(none)_ | `PoamJsonParserService`, `PoamXmlParserService`, `PoamYamlParserService` | `OscalPoamExportService` | `plan-of-action-and-milestones` | `oscal_poam_schema.json` |
| CDEF | `CdefDocument` | `CdefControl` | `CdefControlField` | `CdefJsonParserService`, `CdefYamlParserService`, `CdefXccdfParserService` | `OscalComponentDefinitionExportService` | `component-definition` | `oscal_component_schema.json` |
| Profile | `ProfileDocument` | `ProfileControl` | `ProfileControlField` | `ProfileJsonParserService`, `ProfileXmlParserService`, `ProfileYamlParserService` | `OscalProfileExportService` | `profile` | `oscal_profile_schema.json` |
| Catalog | `ControlCatalog` | `ControlFamily` / `CatalogControl` | _(hierarchy)_ | `CatalogImportService` | `OscalCatalogExportService` | `catalog` | `oscal_catalog_schema.json` |

Parser routing is defined in `app/models/document_type_registry.rb`. The registry maps file extensions to format keys, then format keys to parser classes.

## 3. Per-Document Mapping Guides

Detailed field-level mapping documentation for each document type:

- [`docs/data_mapping/layer_relationships.md`](data_mapping/layer_relationships.md) -- OSCAL layer relationships and document flow
- [`docs/data_mapping/metadata_section.md`](data_mapping/metadata_section.md) -- Common OSCAL metadata section mapping
- [`docs/data_mapping/backmatter_section.md`](data_mapping/backmatter_section.md) -- Back-matter and resource references
- [`docs/data_mapping/contro_mapping.md`](data_mapping/contro_mapping.md) -- Control-level mapping details
- [`docs/data_mapping/baseline_resolved_profile.md`](data_mapping/baseline_resolved_profile.md) -- Profile resolution and baselines
- [`docs/data_mapping/catalogs.md`](data_mapping/catalogs.md) -- Catalog structure and import

Additional column references for Excel-based imports:

- [`docs/ssp-columns.md`](ssp-columns.md) -- SSP Excel column definitions
- [`docs/sar-columns.md`](sar-columns.md) -- SAR Excel column definitions

## 4. Three-Level Model Architecture

Every document type (except POA&M and Catalog) follows the same three-level structure:

```
Document (metadata, title, version, source_data_json)
  └── Control (control_id, title, status, sort_order)
        └── ControlField (field_name, value, editable)
```

| Level | SSP | SAR | SAP | CDEF | Profile |
|---|---|---|---|---|---|
| Document | `SspDocument` | `SarDocument` | `SapDocument` | `CdefDocument` | `ProfileDocument` |
| Control | `SspControl` | `SarControl` | `SapControl` | `CdefControl` | `ProfileControl` |
| Field | `SspControlField` | `SarControlField` | `SapControlField` | `CdefControlField` | `ProfileControlField` |

**POA&M** uses `PoamDocument` -> `PoamItem` (no separate field model; items store all data directly).

**Catalog** uses `ControlCatalog` -> `ControlFamily` -> `CatalogControl` (a parallel hierarchy for reference data).

### Key Relationships

- Controls belong to exactly one document via a foreign key (e.g., `ssp_document_id`).
- ControlFields belong to exactly one control and store individual data points (implementation narrative, status, parameters, etc.).
- The `editable` flag on ControlFields controls which values users can modify through the UI.

## 5. Data Mapping Configuration Files

Data mapping JSON files in `lib/data_mappings/` define how source columns map to the internal model. They are used by Excel parser services and the `DataMappingSchema` class.

### Available Mapping Files

| File | Purpose |
|---|---|
| `ssp_excel.json` | SSP Excel column-to-model mapping |
| `sar_excel.json` | SAR Excel column-to-model mapping |
| `cci_to_nist.json` | CCI identifier to NIST control ID crosswalk |
| `cis_to_nist.json` | CIS benchmark to NIST control ID crosswalk |
| `scap_oval_to_nist.json` | SCAP/OVAL to NIST control ID crosswalk |

### Schema Format

Each Excel mapping file follows this structure:

```json
{
  "format": "ssp_excel",
  "version": "1.0",
  "description": "Mapping schema for SSP Excel import/export",
  "document_type": "SspDocument",
  "control_type": "SspControl",
  "field_type": "SspControlField",
  "fields": [
    {
      "key": "control_id",
      "source_header": "paragraph/reqid",
      "storage": "control_attribute",
      "data_type": "string",
      "required": true,
      "editable": false,
      "description": "NIST control identifier (e.g. AC-1, AC-2)"
    }
  ]
}
```

### Field Properties

| Property | Required | Description |
|---|---|---|
| `key` | Yes | Internal field identifier |
| `source_header` | Yes | Column header in the source Excel file (case-insensitive match) |
| `storage` | Yes | Where the value is stored: `control_attribute` (on the control model), `control_field` (as a ControlField record), or `subject` |
| `data_type` | No | Data type hint (`string`, `text`, `date`, etc.) |
| `required` | No | Whether the field must be present in the source |
| `editable` | No | Whether users can modify the value in the UI |
| `oscal_mapping` | No | How this field maps to an OSCAL element on export |
| `validation` | No | Validation rules (e.g., `allowed_values`) |

### Loading Mappings in Code

```ruby
schema = DataMappingSchema.load(:ssp_excel)
schema.column_map        # Header-to-attribute mapping for parsers
schema.editable_fields   # List of user-editable field keys
schema.oscal_mappings    # Field-to-OSCAL-element mapping for exports
```

## 6. OSCAL Schema Validation

`OscalSchemaValidationService` validates exported OSCAL documents against official NIST schemas (v1.1.2).

### Schema Locations

| Format | Directory | Example File |
|---|---|---|
| JSON Schema | `lib/oscal_schemas/` | `oscal_ssp_schema.json` |
| XSD (XML) | `lib/oscal_xsd_schemas/` | `oscal_ssp_schema.xsd` |

### Supported Model Types

The service accepts these symbolic keys: `:ssp`, `:assessment_plan`, `:assessment_results`, `:poam`, `:component_definition`, `:profile`, `:catalog`, `:mapping`.

### Validation API

```ruby
# Validate a Ruby hash (parsed JSON)
result = OscalSchemaValidationService.validate(:ssp, data_hash)
result.valid?          # => true / false
result.errors          # => [] or array of error strings
result.schema_version  # => "1.1.2"

# Validate and raise on failure (used in export pipelines)
OscalSchemaValidationService.validate!(:ssp, data_hash)

# Validate raw XML against XSD
result = OscalSchemaValidationService.validate_xml(:ssp, xml_string)
```

### How Validation Is Triggered

1. **On export**: Export services call `validate!` after building the OSCAL hash. If validation fails, the user sees errors in a modal and can choose to download the unvalidated version.
2. **On import**: JSON/XML/YAML parsers do not validate against OSCAL schemas on import; they extract data into the internal model regardless of schema compliance.
3. **Schema preprocessing**: NIST schemas use fragment `$id` anchors that are incompatible with the `json_schemer` gem. The service rewrites these to standard JSON Pointer format (`#/definitions/X`) at load time.

## 7. Developer Guide: Adding New Field Mappings

### Adding a Field to Excel Import

1. **Update the mapping file** (`lib/data_mappings/ssp_excel.json` or `sar_excel.json`):
   ```json
   {
     "key": "new_field_name",
     "source_header": "Excel Column Header",
     "storage": "control_field",
     "data_type": "string",
     "editable": true,
     "description": "What this field represents"
   }
   ```

2. **If `storage` is `control_attribute`**, add a database column to the control model via migration. If `storage` is `control_field`, no migration is needed -- values are stored as `ControlField` records.

3. **Update the parser service** if the field needs special handling (e.g., date parsing, value normalisation). The `DataMappingSchema#column_map` is consumed by the parser to route values automatically.

4. **Add tests** in the corresponding parser spec (`spec/services/ssp_excel_parser_service_spec.rb`).

### Adding a Field to OSCAL Export

1. **Add an `oscal_mapping` entry** to the field definition in the data mapping JSON:
   ```json
   {
     "key": "new_field_name",
     "oscal_mapping": {
       "target": "prop",
       "name": "new-field-name",
       "ns": "https://your-namespace"
     }
   }
   ```

2. **Update the export service** (e.g., `OscalSspExportService`) to read the field value and place it in the correct location in the OSCAL output hash.

3. **Run validation** to confirm the exported document still passes schema validation:
   ```ruby
   OscalSchemaValidationService.validate!(:ssp, exported_hash)
   ```

4. **Add export tests** in the corresponding export service spec.

### Adding a New Document Type

1. Create the three-level model (Document, Control, ControlField) with migrations.
2. Register the type in `DocumentTypeRegistry` with parser map and allowed extensions.
3. Create parser services for each supported format.
4. Create an export service and add the schema entry to `OscalSchemaValidationService::SCHEMA_MAP`.
5. Add routes, controllers, and views following existing patterns.

## 8. Common Validation Errors

| Error | Cause | Fix |
|---|---|---|
| `Missing required root key 'system-security-plan'` | Exported hash is missing the OSCAL root wrapper | Ensure the export service wraps output in `{ "system-security-plan" => { ... } }` |
| `(root): missing required properties: uuid, metadata` | Required OSCAL fields not populated | Check that the export service generates `uuid` (via `SecureRandom.uuid`) and a valid `metadata` block |
| `does not match pattern` on UUID fields | UUID not in RFC 4122 format | Use `SecureRandom.uuid` which produces lowercase hex with hyphens |
| `value not in allowed list` on status fields | Implementation status value not in OSCAL enum | Use standard values: `implemented`, `partially-implemented`, `planned`, `alternative-implementation`, `not-applicable` |
| `XSD schema file not found` | Missing XSD file in `lib/oscal_xsd_schemas/` | Download the schema from the NIST OSCAL releases page |
| `Schema validation error: ...` | Catch-all for unexpected validation failures | Check the full error message; often caused by malformed nested structures or missing required arrays |
