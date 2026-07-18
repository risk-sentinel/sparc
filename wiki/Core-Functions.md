# Core Functions & Features

This page documents every major subsystem and feature in SPARC, the Systematic and Regulatory Compliance platform for NIST 800-53 compliance management.

---

## Table of Contents

1. [Document Processing Pipeline](#1-document-processing-pipeline)
2. [OSCAL Export & Validation](#2-oscal-export--validation)
3. [SSP Wizard](#3-ssp-wizard)
4. [SSP Enrichment](#4-ssp-enrichment)
5. [Control Mapping](#5-control-mapping)
6. [Evidence & Attestation Management](#6-evidence--attestation-management)
7. [Authorization Boundary Management](#7-authorization-boundary-management)
8. [Audit Logging](#8-audit-logging)
9. [Heatmap Analytics](#9-heatmap-analytics)
10. [Document Duplication & Copy](#10-document-duplication--copy)
11. [SAP Generation](#11-sap-generation)
12. [JSON Export](#12-json-export)
13. [REST API](#13-rest-api)
14. [Dark Mode & Theming](#14-dark-mode--theming)
15. [HTTPS Enforcement & Security Headers](#15-https-enforcement--security-headers)
16. [Converters (CCI / AWS / STIG → NIST)](#16-converters-cci--aws--stig--nist)
17. [AWS Labs CDEF Ingestion](#17-aws-labs-cdef-ingestion)
18. [HDF ↔ OSCAL Translation Bridge](#18-hdf--oscal-translation-bridge)
19. [FedRAMP 20x KSI Catalog & Validations](#19-fedramp-20x-ksi-catalog--validations)
20. [Authoritative Sources & Federation](#20-authoritative-sources--federation)
21. [Leveraged Authorizations](#21-leveraged-authorizations)
22. [Organizations & Service Accounts](#22-organizations--service-accounts)
23. [Document Review & Approval Workflow](#23-document-review--approval-workflow)

---

## 1. Document Processing Pipeline

All document uploads follow a unified flow driven by the `FileUploadable` controller concern and the `DocumentTypeRegistry` model. This architecture ensures consistent behavior across all six document types.

### Supported Document Types

| Type Key | Document Class     | Control Class     | Field Class            | Allowed Extensions                           |
|----------|--------------------|-------------------|------------------------|----------------------------------------------|
| `ssp`    | `SspDocument`      | `SspControl`      | `SspControlField`      | `.json`, `.xml`, `.yaml`, `.yml`             |
| `sar`    | `SarDocument`      | `SarControl`      | `SarControlField`      | `.json`, `.xml`, `.yaml`, `.yml`             |
| `cdef`   | `CdefDocument`     | `CdefControl`     | `CdefControlField`     | `.xml`, `.json`, `.yaml`, `.yml`             |
| `profile`| `ProfileDocument`  | `ProfileControl`  | `ProfileControlField`  | `.json`, `.xml`, `.yaml`, `.yml`             |
| `sap`    | `SapDocument`      | `SapControl`      | `SapControlField`      | `.json`, `.xml`, `.yaml`, `.yml`             |
| `poam`   | `PoamDocument`     | `PoamItem`        | (none)                 | `.json`, `.xml`, `.yaml`, `.yml`             |

### DocumentTypeRegistry

The `DocumentTypeRegistry` (located at `app/models/document_type_registry.rb`) is a centralized registry that maps each type key to its associated classes, file extensions, parser services, and user-facing messages. Each entry is a `Data.define` struct:

```ruby
Entry = Data.define(
  :document_class,
  :control_class,
  :field_class,
  :document_fk,
  :allowed_extensions,
  :parser_map,
  :file_prefix,
  :success_message
)
```

Usage:

```ruby
entry = DocumentTypeRegistry.for(:sar)
entry.document_class  # => SarDocument
entry.parser_map      # => { "json" => SarJsonParserService, "xml" => SarXmlParserService, ... }
```

### Upload Flow

The `FileUploadable` concern (`app/controllers/concerns/file_uploadable.rb`) implements a five-step pipeline that every document controller shares:

1. **Validate file presence** -- returns an error flash if no file is attached.
2. **Detect file type** -- maps the file extension against `registry.allowed_extensions` to determine the parser format (e.g., `.json` maps to `"json"`).
3. **Write to persistent path** -- the file is written to `tmp/` with a safe prefix and random hex suffix. File path components come exclusively from frozen constants (`SAFE_PREFIXES`, `SAFE_EXTENSIONS`), satisfying Brakeman taint analysis.
4. **Create document record** -- a new document is created with `status: "pending"`, the uploaded file is attached via Active Storage, and `DocumentConversionJob` is enqueued.
5. **Error handling** -- on failure, the temporary file is cleaned up and the user sees the error.

```ruby
# In any document controller:
def create
  handle_file_upload(:ssp, param_key: :ssp_document)
end
```

### Async Processing

Large files are processed asynchronously via Sidekiq:

- `DocumentConversionJob` receives the type key, document ID, and file path.
- The job instantiates the appropriate parser service from the registry.
- Document status transitions: `pending` -> `processing` -> `completed` (or `failed`).
- The `ConversionJob` model tracks job state for monitoring.

### Status Polling

Each document type exposes a `status` endpoint that returns JSON, enabling the frontend to poll for completion:

```
GET /:document_type/:id/status
# => { "status": "completed" }
```

### Parser Services

Each parser service handles a specific input format and populates the three-level model hierarchy (Document -> Controls -> Fields).

#### CdefJsonParserService and CdefXccdfParserService

**Files:** `app/services/cdef_json_parser_service.rb`, `app/services/cdef_xccdf_parser_service.rb`

- `CdefJsonParserService` -- parses OSCAL Component Definition JSON.
- `CdefXccdfParserService` -- parses DISA STIG XCCDF XML format, extracting rules, check content, and fix text.

#### ProfileJsonParserService and ProfileXmlParserService

**Files:** `app/services/profile_json_parser_service.rb`, `app/services/profile_xml_parser_service.rb`

Parse OSCAL Profile baselines from JSON and XML formats.

#### CatalogImportService

**File:** `app/services/catalog_import_service.rb`

Imports NIST 800-53 control catalogs from two formats:

- **OSCAL JSON** -- standard NIST OSCAL catalog schema from `oscal-content`.
- **NIST XML** -- SP 800-53 SCAP feed schema v2.0.

Key behaviors:

- **Zero-padding:** Single-digit control numbers are padded (`AC-1` becomes `AC-01`, `AC-10` stays unchanged).
- **Sub-parts as siblings:** Statement parts are stored as sibling `CatalogControl` records with hierarchical IDs: `AC-01`, `AC-01a`, `AC-01a.1`, `AC-01a.1.(a)`.
- **Format auto-detection:** Inspects file extension and content structure to determine OSCAL JSON vs. NIST XML.
- **Upsert semantics:** Uses `find_or_initialize_by` for catalogs, families, and controls, so re-importing updates existing records rather than creating duplicates.
- Extracts guidance data including statements, supplemental guidance, related controls, and references.
- Supports all 20 NIST 800-53 control families via a `FAMILY_NAME_TO_CODE` lookup table.

#### SapJsonParserService, SapXmlParserService, and SapYamlParserService

**Files:** `app/services/sap_json_parser_service.rb`, `app/services/sap_xml_parser_service.rb`, `app/services/sap_yaml_parser_service.rb`

Parse OSCAL Assessment Plan documents from JSON, XML, and YAML. The XML parser uses Nokogiri to extract metadata, activities, reviewed controls, and assessment subjects, then delegates via a temporary JSON file. The YAML parser loads via `YAML.safe_load` and delegates via temporary JSON file.

#### PoamJsonParserService, PoamXmlParserService, and PoamYamlParserService

**Files:** `app/services/poam_json_parser_service.rb`, `app/services/poam_xml_parser_service.rb`, `app/services/poam_yaml_parser_service.rb`

Parse Plan of Action & Milestones documents from JSON, XML, and YAML. The POA&M model uses `PoamItem` rather than a generic control class, reflecting the distinct structure of POA&M findings. The YAML parser delegates to `PoamJsonParserService#parse_from_hash`.

#### YAML Parser Services

**Files:** `app/services/ssp_yaml_parser_service.rb`, `app/services/sar_yaml_parser_service.rb`, `app/services/poam_yaml_parser_service.rb`, `app/services/profile_yaml_parser_service.rb`, `app/services/cdef_yaml_parser_service.rb`, `app/services/sap_yaml_parser_service.rb`

All six document types support YAML import. YAML parsers use two delegation patterns to avoid duplicating parsing logic:

- **Pattern A** (SSP, SAR, POAM) -- the JSON parser exposes a `parse_from_hash(data)` method; the YAML parser calls `YAML.safe_load` and passes the resulting hash directly.
- **Pattern B** (Profile, CDEF, SAP) -- the JSON parser has no `parse_from_hash`; the YAML parser writes the parsed data to a temporary JSON file and delegates to the JSON parser's `parse` method.

Both patterns use `YAML.safe_load` with `permitted_classes: [Date, Time]` for safe deserialization.

#### OscalFormatDetectionService

**File:** `app/services/oscal_format_detection_service.rb`

Detects the format of an OSCAL file by extension first (`.json`, `.yaml`, `.yml`, `.xml`), falling back to content sniffing (first non-whitespace character: `{` or `[` for JSON, `<` for XML, otherwise YAML). Returns a `Result` struct with `format` and `detected_by` fields.

### BatchInsertable Concern

**File:** `app/services/concerns/batch_insertable.rb`

Provides high-throughput bulk insertion shared across parser services. Uses the `activerecord-import` gem to batch insert records within a single database transaction:

- **Control batch size:** 5,000 records per batch
- **Field batch size:** 10,000 records per batch

```ruby
batch_insert_records(
  control_class: SarControl,
  field_class:   SarControlField,
  document_fk:   :sar_document_id,
  control_attrs: control_attrs,     # Array of attribute hashes
  field_entries: field_entries       # Array of [control_index, field_name, field_value]
)
```

Control IDs are returned via `returning: :id` so field records can be linked to their parent controls by index.

### Data Mapping Schema

**Directory:** `lib/data_mappings/`
**Files:** `ssp_excel.json`, `sar_excel.json`
**Service:** `app/services/data_mapping_schema.rb`

Data mapping files are vendor-neutral, declarative JSON definitions that describe how source columns (tabular headers) map to internal model attributes and fields. Each mapping entry includes:

- `source_header` -- the normalized column header from the source file.
- `key` -- the internal attribute or field name.
- `storage` -- one of `control_attribute` (stored on the model), `control_field` (stored in the field table), or `subject` (split on `"|"` into asset/environment).
- `editable` -- whether the field is editable in the UI.
- `validation` -- optional rules (e.g., `allowed_values`).
- `oscal_mapping` -- how the field maps to OSCAL export targets.

```ruby
schema = DataMappingSchema.load(:ssp_excel)
schema.column_map          # => { "paragraph/reqid" => { key: :control_id, control_attr: true } }
schema.editable_fields     # => ["status", "implementation_statement", ...]
schema.oscal_mappings      # => { "status" => { "target" => "prop", ... } }
```

---

## 2. OSCAL Export & Validation

SPARC provides full OSCAL v1.1.2 export in three formats (JSON, YAML, XML) for all document types, with schema validation against the official NIST JSON schemas and XSD schemas.

### Export Services

Each document type has a dedicated OSCAL export service:

| Service                                 | Document Type          | OSCAL Root Key                    |
|-----------------------------------------|------------------------|-----------------------------------|
| `OscalSspExportService`                 | SSP                    | `system-security-plan`            |
| `OscalComponentDefinitionExportService` | Component Definition   | `component-definition`            |
| `OscalSarExportService`                 | Assessment Results     | `assessment-results`              |
| `OscalProfileExportService`             | Profile                | `profile`                         |
| `OscalCatalogExportService`             | Catalog                | `catalog`                         |
| `OscalPoamExportService`                | POA&M                  | `plan-of-action-and-milestones`   |
| `OscalAssessmentPlanExportService`      | Assessment Plan        | `assessment-plan`                 |
| `OscalMappingExportService`             | Control Mapping        | `mapping-collection`              |

#### OscalSspExportService

**File:** `app/services/oscal_ssp_export_service.rb`

Builds a complete OSCAL v1.1.2 System Security Plan JSON document. The top-level structure includes:

- **metadata** -- title, version, oscal-version, last-modified, roles, parties, revisions.
- **import-profile** -- reference to the baseline profile.
- **system-characteristics** -- system IDs, name, description, security sensitivity level, security impact levels, system status, authorization boundary, network architecture, data flow.
- **system-implementation** -- users, components (including `this-system`), leveraged authorizations, inventory items.
- **control-implementation** -- implemented requirements with by-components, statements (private/public/inherited), and props (status, control type, origination, responsible entities).
- **back-matter** -- preserved resources from import metadata.

The service works uniformly: enriched relational data is used when available (regardless of whether the SSP was created via wizard or file import), falling back to placeholder values only when no data exists.

```ruby
service = OscalSspExportService.new(ssp_document)
json_string = service.export              # validates, raises on failure
json_string = service.export_unvalidated  # skips validation
result      = service.validation_result   # inspect errors without raising
```

#### OscalComponentDefinitionExportService

Supports NIST, CIS, and DISA source mappings for component definitions.

#### OscalSarExportService

Exports assessment results with synthesized observations and findings.

### Multi-Format Export

**File:** `app/services/oscal_export_format_service.rb`

All OSCAL export services produce JSON natively. The `OscalExportFormatService` wraps these exports to provide YAML and XML output:

- `OscalExportFormatService.to_yaml(json_string)` -- parses the JSON and converts to YAML via `.to_yaml`.
- `OscalExportFormatService.to_xml(json_string, model_type)` -- delegates to `OscalJsonToXmlConverter`.

**File:** `app/services/oscal_json_to_xml_converter.rb`

Converts OSCAL JSON to XML using `Nokogiri::XML::Builder` with the OSCAL namespace (`http://csrc.nist.gov/ns/oscal/1.0`). Uses an explicit `ATTRIBUTE_KEYS` set (uuid, id, href, type, name, value, etc.) to distinguish XML attributes from child elements per OSCAL convention. Handles plural-to-singular element unwrapping (e.g., `controls` -> `control`) and recursive hash-to-XML conversion.

Each document controller provides `download_yaml` and `download_xml` actions that call the appropriate export service and format converter. The UI presents a Bootstrap 5 split-button dropdown allowing the user to select the export format (OSCAL JSON validated, JSON, YAML, XML).

### Schema Validation

**File:** `app/services/oscal_schema_validation_service.rb`

Validates OSCAL JSON against the official NIST v1.1.2 JSON schemas using the `json_schemer` gem (Draft 2020-12 support), and validates OSCAL XML against XSD schemas using `Nokogiri::XML::Schema`. Supports all eight OSCAL model types:

```ruby
SCHEMA_MAP = {
  component_definition: { file: "oscal_component_schema.json",            root_key: "component-definition" },
  ssp:                  { file: "oscal_ssp_schema.json",                  root_key: "system-security-plan" },
  assessment_plan:      { file: "oscal_assessment-plan_schema.json",      root_key: "assessment-plan" },
  assessment_results:   { file: "oscal_assessment-results_schema.json",   root_key: "assessment-results" },
  poam:                 { file: "oscal_poam_schema.json",                 root_key: "plan-of-action-and-milestones" },
  profile:              { file: "oscal_profile_schema.json",              root_key: "profile" },
  catalog:              { file: "oscal_catalog_schema.json",              root_key: "catalog" },
  mapping:              { file: "oscal_mapping_schema.json",              root_key: "mapping-collection" }
}
```

The validation service performs:

1. **Structural pre-check** -- verifies the expected root key is present.
2. **Full schema validation** -- runs `json_schemer` against the NIST schema.
3. **Error formatting** -- produces human-readable messages (caps at 50 errors) with data pointer paths, missing required properties, enum violations, type mismatches, and pattern failures.

Schema files are cached after first load. An internal `preprocess_schema` step rewrites NIST anchor-style `$ref` values to standard JSON Pointer format (`#/definitions/X`) so `json_schemer` can resolve them locally without network access.

#### XSD Validation

**Directory:** `lib/oscal_xsd_schemas/`

XML exports are validated against NIST OSCAL v1.1.2 XSD schemas using `Nokogiri::XML::Schema`. Seven XSD schema files are stored locally:

| Schema File | OSCAL Model |
|---|---|
| `oscal_ssp_schema.xsd` | System Security Plan |
| `oscal_assessment-results_schema.xsd` | Security Assessment Results |
| `oscal_assessment-plan_schema.xsd` | Security Assessment Plan |
| `oscal_poam_schema.xsd` | Plan of Action & Milestones |
| `oscal_profile_schema.xsd` | Profile |
| `oscal_catalog_schema.xsd` | Catalog |
| `oscal_component_schema.xsd` | Component Definition |

```ruby
result = OscalSchemaValidationService.validate_xml(:ssp, xml_string)
result.valid?   # => true/false
result.errors   # => array of error messages
```

### Download Options

Five download modes are available in the UI for every document type:

- **Validated** (`download_oscal_validated`) -- validates against the NIST schema; fails with an error if invalid.
- **Unvalidated** (`download_oscal_unvalidated`) -- always downloads, skipping validation.
- **Auto** (`download_oscal`) -- attempts validated export first; on failure, redirects to the unvalidated endpoint.
- **YAML** (`download_yaml`) -- exports as OSCAL YAML.
- **XML** (`download_xml`) -- exports as OSCAL XML with XSD validation.

### OSCAL Metadata Inheritance

**File:** `app/services/oscal_metadata_inheritance_service.rb`

Preserves and merges OSCAL metadata (roles, parties, revisions, oscal-version) along the artifact chain:

```
ControlCatalog -> ProfileDocument -> SspDocument -> SapDocument -> SarDocument
                                     SspDocument -> PoamDocument
```

Uses OSCAL resolution rules: child overrides parent for scalar fields; array fields (roles, parties) are merged with child entries taking precedence.

```ruby
OscalMetadataInheritanceService.new(ssp_document).resolve!
```

### Related Issues/PRs

- PR #53 -- OSCAL schema validation and SSP export (#45)
- PR #67 -- Full schema uplift for CDEF, Catalogs, Profiles, SAR (#58)
- PR #64 -- OSCAL metadata management & inheritance (#52)
- PR #60 -- SSP creation wizard, OSCAL import, enrichment
- Issue #120 -- Full multi-format support (JSON, YAML, XML import and export for all document types)

---

## 3. SSP Wizard

**File:** `app/services/ssp_wizard_service.rb`

The SSP Wizard allows users to create a System Security Plan from scratch rather than importing from a file. The entire process runs in a single database transaction.

### Wizard Inputs

- **Profile (baseline)** -- a `ProfileDocument` that serves as the control source.
- **Component Definitions (CDEFs)** -- optionally attach one or more `CdefDocument` records.
- **System metadata:**
  - System name and description
  - System status (default: `"operational"`)
  - Security sensitivity level
  - Security objectives (Confidentiality, Integrity, Availability)
  - Authorization boundary description

### Creation Process

1. **Create SspDocument** with `creation_method: "wizard"` and `status: "processing"`.
2. **Create "this-system" component** -- the OSCAL-required default component representing the system itself.
3. **Create default information type** -- placeholder for system information.
4. **Create default user** -- "General User" with the `system-owner` role.
5. **Import CDEF components** (if selected) -- creates `SspDocumentCdefDocument` join records and corresponding `SspComponent` entries.
6. **Populate controls from profile** -- iterates through the profile's controls, creating `SspControl` records with default fields (status defaults to "Deferred") and a `this-system` by-component entry.
7. **Auto-fill from CDEFs** (if selected) -- matches CDEF controls to SSP controls by NIST ID, populates `implementation_statement` from the CDEF's `implementation_narrative`, upgrades status from "Deferred" to "Implemented" when narrative is present, and creates by-component entries.
8. **Mark complete** -- sets `status: "completed"`.

Control IDs are normalized for matching: lowercased, whitespace replaced with hyphens, parentheses converted to dots, and multiple dots collapsed.

### Related

- PR #60, Issue #30

---

## 4. SSP Enrichment

SSP Enrichment allows users to uplift legacy file-imported SSPs with full OSCAL metadata that cannot be expressed in the original tabular format.

### Enrichable Metadata

The SSP enrichment UI (`enrich` / `update_enrich` actions in `SspDocumentsController`) supports adding and editing:

- **System-level fields:** system name, description, system ID, system status, date authorized, security sensitivity level, security objectives (C/I/A), authorization boundary description, network architecture description, data flow description.
- **Components:** type, title, description, status state, status remarks, purpose, responsible roles, protocols, props, links, remarks.
- **Users:** UUID, title, description, short name, role IDs, authorized privileges, props, links, remarks.
- **Information types:** title, description, categorizations, confidentiality/integrity/availability impact (base, selected, adjustment justification).
- **Leveraged authorizations:** title, party UUID, date authorized.

### Sync Helpers

The controller includes sync helpers that handle create/update/delete of nested OSCAL entities. Each entity section (components, users, information types) can be managed independently, with changes applied via the `update_enrich` action.

The `OscalSspExportService` works uniformly -- it uses enriched relational data when available regardless of whether the SSP was created via wizard or file import. File-imported SSPs that have been enriched via the UI get proper exports with the enriched data, while un-enriched SSPs continue to export valid OSCAL with sensible defaults.

---

## 5. Control Mapping

**Models:** `app/models/control_mapping.rb`, `app/models/control_mapping_entry.rb`

Control Mapping provides cross-walk functionality between two control catalogs, such as NIST SP 800-53 Rev 4 to Rev 5, or NIST to ISO 27001.

### Data Model

**ControlMapping** represents the overall mapping collection:

```ruby
belongs_to :source_catalog, class_name: "ControlCatalog"
belongs_to :target_catalog, class_name: "ControlCatalog"
has_many   :control_mapping_entries, dependent: :destroy
```

Validated attributes:
- `name` -- required.
- `uuid` -- auto-generated, unique.
- `status` -- one of: `draft`, `complete`, `not-complete`, `deprecated`, `superseded`.
- `method_type` -- one of: `human`, `automation`, `hybrid`.
- `matching_rationale` -- one of: `syntactic`, `semantic`, `functional`.

**ControlMappingEntry** represents an individual source-to-target control relationship:

- `source_control_id` and `target_control_id` -- required.
- `source_type` and `target_type` -- either `"control"` or `"statement"`.
- `relationship` -- aligned with NIST IR 8477 set-theory relationships: `equal`, `equivalent`, `subset`, `superset`, `intersects`.
- Unique constraint on `(control_mapping_id, source_control_id, target_control_id)`.

### Lifecycle

Mappings follow a lifecycle with status transitions:

1. **Draft** -- initial state for authoring.
2. **Complete** (publish) -- mapping is finalized and ready for use.
3. **Deprecated** / **Superseded** -- end-of-life states.

The `published` scope returns mappings with `status: "complete"`.

### OSCAL Export

Mappings can be exported to OSCAL mapping-collection JSON via `OscalMappingExportService`.

### Related

- PR #118 (Issue #98), Issue #119

---

## 6. Evidence & Attestation Management

**Models:** `app/models/evidence.rb`, `app/models/attestation.rb`, `app/models/evidence_control_link.rb`

### Evidence

Evidence records support uploading compliance artifacts with Active Storage. Each evidence record tracks:

- **Evidence types** (enum): `artifact`, `screenshot`, `log`, `config_export`, `scan_result`, `signed_statement`, `policy_document`, `test_result`.
- **Status lifecycle** (enum): `draft` -> `collected` -> `reviewed` -> `attested` -> `expired`.
- **File integrity:** SHA256 hash computed via `compute_file_hash!` for verification:

```ruby
def compute_file_hash!
  return unless file.attached?
  self.file_hash = Digest::SHA256.hexdigest(file.download)
  self.file_content_type = file.content_type
  self.original_filename = file.filename.to_s
  self.file_size = file.byte_size
  save!
end
```

### Evidence Control Links

The `EvidenceControlLink` model links evidence to specific controls across any document type:

```ruby
DOCUMENT_TYPES = %w[SspDocument SarDocument SapDocument CdefDocument PoamDocument]
```

Each link stores `control_id`, `document_type`, and `document_id`, with a uniqueness constraint on the combination. This enables a single piece of evidence to be associated with controls across multiple documents.

### Attestations

The `Attestation` model provides formal verification by authorized personnel:

- `attester_name` -- required.
- `statement` -- the attestation text (required).
- `attested_at` -- timestamp (required).
- `role` -- one of: `control_owner`, `system_owner`, `isso`, `ciso`, `assessor`, `authorizing_official`.
- `attester_email` -- email address of the attester.
- `signature_hash` -- SHA256 hash generated from a payload of attester details, statement, timestamp, and evidence ID:

```ruby
def generate_signature!
  payload = "#{attester_name}|#{attester_email}|#{statement}|#{attested_at.iso8601}|#{evidence_id}"
  self.signature_hash = Digest::SHA256.hexdigest(payload)
  save!
end
```

### Related

- PR #75 (Issue #31)

---

## 7. Authorization Boundary Management

**Models:** `app/models/authorization_boundary.rb`, `app/models/boundary.rb`, `app/models/authorization_boundary_membership.rb`

Authorization boundaries serve as the top-level container for compliance artifacts, organizing them around a system boundary.

### Authorization Boundary

An authorization boundary aggregates:

- `ssp_document` (has_one)
- `sap_document` (has_one)
- `sar_document` (has_one)
- `poam_documents` (has_many)
- `evidences` (has_many)
- `boundaries` (has_many)
- `authorization_boundary_memberships` (has_many)

**Status** (enum): `draft`, `active`, `authorized`, `deauthorized`.

The `artifact_summary` method provides a quick overview:

```ruby
def artifact_summary
  {
    ssp: ssp_document&.name,
    sap: sap_document&.name,
    sar: sar_document&.name,
    poam_count: poam_documents.count,
    boundary_count: boundaries.count,
    component_count: boundaries.joins(:cdef_documents).count
  }
end
```

### Boundaries

System boundaries define network and security perimeters. Each boundary:

- Belongs to an authorization boundary.
- Has an `environment` enum: `production`, `development`, `staging`, `test`.
- Links to Component Definitions (CDEFs) via the `BoundaryCdefDocument` join table.

### Team Members

`AuthorizationBoundaryMembership` records assign team members to authorization boundaries with specific roles:

| Role Key                | Display Label                |
|-------------------------|------------------------------|
| `authorizing_official`  | Authorizing Official (AO)    |
| `system_owner`          | System Owner (SO/ISO)        |
| `ciso`                  | CISO                         |
| `isso`                  | ISSO                         |
| `project_member`        | Team Member                  |
| `assessor`              | Assessor / 3PAO              |
| `view_only`             | View Only                    |

Memberships can be linked to `User` records by matching email via `link_to_user!`.

### Related

- PR #71 (Issue #46)

---

## 8. Audit Logging

**Models:** `app/models/audit_event.rb`
**Concern:** `app/controllers/concerns/auditable.rb`
**Export:** `app/services/audit_csv_export_service.rb`
**Admin UI:** `app/controllers/admin/audit_logs_controller.rb`

### Design Principles

- **Immutable** -- `AuditEvent` has no `updated_at` column and no update methods. Records are write-once.
- **Subject tracking** -- polymorphic `subject_type` / `subject_id` columns record which resource was affected.
- **Structured JSON logging** -- every event is also emitted to `Rails.logger.info` as structured JSON for integration with CloudWatch, Datadog, or any log aggregator.

### Tracked Actions

Approximately 80 actions are tracked across 16 categories:

| Category           | Example Actions                                                                |
|--------------------|--------------------------------------------------------------------------------|
| Authentication     | `login_success`, `login_failure`, `logout`, `password_change`                  |
| Authorization      | `authorization_failure`                                                        |
| User Management    | `user_suspended`, `user_reactivated`, `admin_bootstrap`                        |
| Role Management    | `role_grant`, `role_revoke`, `role_created`, `role_updated`, `role_deleted`     |
| Team Members       | `project_member_added`, `project_member_removed`, `authorization_boundary_membership_*` |
| SSP Documents      | `ssp_document_created`, `_updated`, `_deleted`, `_exported`, `_imported`       |
| SAR Documents      | `sar_document_created`, `_updated`, `_deleted`, `_exported`, `_imported`       |
| CDEF Documents     | `cdef_document_created`, `_updated`, `_deleted`, `_exported`, `_copied`        |
| SAP Documents      | `sap_document_created`, `_updated`, `_deleted`, `_exported`, `_imported`       |
| POAM Documents     | `poam_document_created`, `_updated`, `_deleted`, `_exported`, `poam_item_*`    |
| Profiles           | `profile_document_created`, `_updated`, `_deleted`, `_exported`, `_copied`     |
| Control Catalogs   | `control_catalog_*`, `control_family_*`, `catalog_control_*`                   |
| Control Mappings   | `control_mapping_*`, `mapping_entry_*`                                         |
| Evidence           | `evidence_created`, `_updated`, `_deleted`, `attestation_created`, `_deleted`  |
| Authorization Boundaries | `authorization_boundary_created`, `_updated`, `_deleted`, `boundary_*`   |

### Auditable Concern

Controllers include the `Auditable` concern for a DRY logging helper that automatically captures the current user, IP address, and user agent:

```ruby
audit_log("ssp_document_created", subject: @ssp_document,
  metadata: { name: @ssp_document.name, file_type: file_type })
```

Authorization failures are logged automatically.

### Factory Method

The `AuditEvent.log` class method creates the record and emits the structured JSON log:

```ruby
AuditEvent.log(
  user: current_user,
  action: "login_success",
  provider: "local",
  ip_address: request.remote_ip,
  subject: @ssp_document
)
```

### Admin UI

The admin audit log interface is available at `/admin/audit_logs` and supports:

- **Filtering** by user, action, subject type, category, date range, and free-text search.
- **Pagination** at 50 events per page via Pagy.
- **CSV export** up to 10,000 rows via `AuditCsvExportService`, with columns: timestamp, user_email, action, category, subject_type, subject_id, ip_address, user_agent, metadata.
- **Detail view** for individual events.

### Related

- PR #121, PR #122 (Issue #101)

---

## 9. Heatmap Analytics

**Stimulus Controller:** `app/javascript/controllers/heatmap_controller.js`
**Aggregation Service:** `app/services/dashboard_aggregation_service.rb`

Interactive heatmap grids provide visual analytics showing control distribution by NIST family and a secondary dimension (status, severity, result, or priority).

### Heatmap Types

| Document Type | Secondary Dimension | Example Values                                                    |
|---------------|--------------------|--------------------------------------------------------------------|
| SSP           | Status             | Implemented, Deferred, Not Applicable, Planned, Partially Implemented |
| SAR           | Result             | Pass, Fail                                                         |
| CDEF          | Severity           | High, Medium, Low                                                  |
| Profile       | Priority           | P1, P2, P3                                                        |
| Dashboard     | Status (aggregate) | Compliance across all SSP documents                                |

### Dashboard Aggregation

The `DashboardAggregationService` aggregates implementation status counts across ALL SSP documents, grouped by NIST control family (AC, AU, CM, IA, etc.). It returns a triple of `[heatmap_data, families, ordered_statuses]` matching the contract expected by the shared `_heatmap.html.erb` partial.

### Stimulus Controller

The `heatmap_controller.js` Stimulus controller provides client-side interactivity:

- **Cell click** (`filterByCell`) -- filters controls by both family and status/severity.
- **Family click** (`filterByFamily`) -- filters controls by family only.
- **Chip click** (`filterByChip`) -- filters by status/severity only.
- **Clear** -- resets all filters.
- **Visual feedback** -- active cells are highlighted with an outline; inactive cells fade to 35% opacity.
- **Banner** -- displays "Showing: AC . Implemented -- 12 control(s)" when a filter is active.
- **URL sync** -- optionally pushes filter state into the URL via `history.replaceState`.
- **Keyboard navigation** -- Enter/Space activates cells; Escape clears the filter.
- **ARIA support** -- updates `aria-pressed` states on badge elements.

Configuration values:
- `filterKey` -- `"status"` or `"severity"` (the secondary dimension).
- `initialFamily` / `initialFilter` -- pre-applied filters from URL parameters.
- `urlSync` -- boolean to enable URL synchronization.
- `containerId` -- ID of the controls container element (default: `"controlsContainer"`).

### Related

- Issue #81 (PR #82), Issue #83 (PR #84)

---

## 10. Document Duplication & Copy

**File:** `app/services/document_duplication_service.rb`

The `DocumentDuplicationService` clones `ProfileDocument` and `CdefDocument` records with all their associated controls and fields.

### Supported Types

```ruby
SUPPORTED_TYPES = {
  "ProfileDocument" => { controls: :profile_controls, fields: :profile_control_fields, version_attr: :profile_version },
  "CdefDocument"    => { controls: :cdef_controls,    fields: :cdef_control_fields,    version_attr: :cdef_version }
}
```

### Duplication Process

1. **Build document copy** -- copies all attributes except `id`, timestamps, `status`, `error_message`, `original_filename`, `file_type`. Sets `status: "completed"`.
2. **Set import_metadata** -- records `copied_from` (source document ID) and `copied_at` (timestamp) for provenance tracking.
3. **Copy controls** -- iterates through source controls and their fields, creating new records linked to the copy.
4. All operations run within a single transaction.

```ruby
service = DocumentDuplicationService.new(source_profile)
copy = service.duplicate(new_name: "FY26 Baseline")
copy.import_metadata
# => { "copied_from" => 42, "copied_at" => "2026-03-08T..." }
```

Profiles can also be created from catalog control selection, producing a new `ProfileDocument` with selected controls.

### Related

- PR #76 (Issue #56)

---

## 11. SAP Generation

**File:** `app/services/sap_generator_service.rb`

The `SapGeneratorService` generates a Security Assessment Plan (SAP) from existing SSP and/or Profile data.

### Inputs

```ruby
SapGeneratorService.new(
  name: "FY26 Annual Assessment",
  ssp_document: ssp,
  profile_document: profile,
  assessment_type: "annual",
  assessment_start: Date.today,
  assessment_end: Date.today + 30,
  selected_control_ids: ["AC-1", "AC-2"],
  assessment_methods: { "AC-1" => "examine", "AC-2" => "test" }
).generate
```

### Control Gathering

Controls are gathered from the SSP (preferred) or Profile (fallback). When using an SSP, implementation status and description are carried forward.

### Auto-assigned Assessment Methods

Each control is assigned a default assessment method based on its family:

| Method      | Families                           |
|-------------|-------------------------------------|
| **Test**      | AC, AU, CM, IA, SC, SI             |
| **Interview** | AT, PS, PE                          |
| **Examine**   | All other families (CP, IR, MA, etc.) |

### Enrichment

The service enriches generated controls with data from two sources:

1. **Catalog guidance** -- looks up `CatalogControl` records to populate assessment objectives and descriptions.
2. **CDEF test mappings** -- looks up `CdefControl` records with `check_content` fields. If a control has an "examine" method but has available check content from a CDEF, the method is upgraded to "test".

### Output

Creates a `SapDocument` with `status: "completed"`, linked `SapControl` records (each with assessment method, status "planned", objective, and test case), and associated `SapControlField` records for implementation details.

### Related

- Issue #28

---

## 12. JSON Export

**File:** `app/services/json_export_service.rb`

The `JsonExportService` provides universal JSON export for all six document types. It delegates to each model's `to_json_data` method:

```ruby
JsonExportService.export_ssp(ssp_document)
JsonExportService.export_sar(sar_document)
JsonExportService.export_cdef(cdef_document)
JsonExportService.export_profile(profile_document)
JsonExportService.export_sap(sap_document)
JsonExportService.export_poam(poam_document)
```

Each export produces pretty-printed JSON via `JSON.pretty_generate`.

---

## 13. REST API

**Namespace:** `/api/v1/`
**Controller:** `app/controllers/api/v1/ssp_documents_controller.rb`

The API provides programmatic access to document operations.

### SSP Endpoints

| Endpoint                              | Method | Description                     |
|---------------------------------------|--------|---------------------------------|
| `/api/v1/ssp_documents/convert`       | POST   | Upload and convert a document file |
| `/api/v1/ssp_documents/:id/update_fields` | PUT    | Bulk update control fields      |
| `/api/v1/ssp_documents/:id/export`    | GET    | Export document as JSON          |

#### Convert

Accepts an uploaded file parameter. Creates a temporary file, processes it through the document conversion pipeline, and returns the parsed JSON data along with the `document_id`.

```json
{
  "success": true,
  "message": "Conversion successful",
  "data": { ... },
  "document_id": 42
}
```

#### Update Fields

Accepts a `controls` parameter with field updates. Uses `SspUpdateService` for bulk updates.

#### Export

Returns the document's JSON representation via `JsonExportService.export_ssp`.

### SAR Endpoints

SAR documents have a parallel set of API endpoints: `convert` (POST), `update_fields` (PUT), `export` (GET).

### Async Processing

For web UI uploads, the conversion runs asynchronously via `DocumentConversionJob`. The `convert` API endpoint returns a `document_id` that can be used to poll the status endpoint for completion.

---

## 14. Dark Mode & Theming

**Stimulus Controller:** `app/javascript/controllers/theme_controller.js`
**Stylesheet:** `app/assets/stylesheets/sparc-theme.css`

### System Preference Detection

On first visit (no saved preference), the theme follows the OS setting via `prefers-color-scheme` media query:

```javascript
const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches
document.documentElement.setAttribute("data-bs-theme", systemDark ? "dark" : "light")
```

### User Override

Clicking the theme toggle button saves the preference to `localStorage` under the `sparc-theme` key. Once a manual override is set, OS preference changes are ignored:

```javascript
toggle() {
  const current = document.documentElement.getAttribute("data-bs-theme")
  const next = current === "dark" ? "light" : "dark"
  localStorage.setItem("sparc-theme", next)
  document.documentElement.setAttribute("data-bs-theme", next)
}
```

If the user has not manually toggled, OS preference changes are tracked via `MediaQueryList.addEventListener("change", ...)` and applied automatically.

### Anti-FOUC

An inline `<script>` in the `<head>` reads `localStorage` and sets the `data-bs-theme` attribute on `<html>` before the first paint, preventing a flash of the wrong theme.

### Bootstrap Integration

Uses Bootstrap 5.3 color mode support via the `data-bs-theme` attribute on the root `<html>` element. Custom SPARC theme overrides are defined in `sparc-theme.css` for brand-specific colors and component styling.

### Related

- Issue #85 (PR #86), Issue #51 (PR #62)

---

## 15. HTTPS Enforcement & Security Headers

SPARC enforces encrypted communications in production per NIST SP 800-53 SC-8 (Transmission Confidentiality and Integrity) while allowing plain HTTP for local development.

### Production HTTPS Enforcement

Configured in `config/environments/production.rb`:

| Setting | Value | Purpose |
|---------|-------|---------|
| `config.assume_ssl` | `true` | Trust X-Forwarded-Proto from reverse proxy |
| `config.force_ssl` | `ENV.fetch("FORCE_SSL", "true")` | Redirect HTTP to HTTPS, set secure cookies |
| HSTS `max-age` | 1 year | Browsers remember to use HTTPS |
| HSTS `subdomains` | `true` | Covers all subdomains |
| HSTS `preload` | `true` | Eligible for browser preload lists |
| Health-check bypass | `/up` excluded | Container probes (ALB, K8s) use HTTP internally |

Set `FORCE_SSL=false` to disable (e.g., behind a proxy that already handles HTTPS).

### Security Headers Middleware

`config/initializers/security_headers.rb` sets defence-in-depth headers on every response:

| Header | Value | Purpose |
|--------|-------|---------|
| `X-Content-Type-Options` | `nosniff` | Prevent MIME-type sniffing |
| `X-Frame-Options` | `SAMEORIGIN` | Clickjacking protection |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Control Referer leakage |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=()` | Restrict unused browser APIs |
| `X-Permitted-Cross-Domain-Policies` | `none` | Block Flash/Acrobat cross-domain loading |

### Content Security Policy

`config/initializers/content_security_policy.rb` configures CSP in **report-only** mode. Violations appear in the browser console but do not block content. The Bootstrap 5.3 CDN (`cdn.jsdelivr.net`) is allowlisted for scripts, styles, and fonts.

To switch to enforcing mode set `config.content_security_policy_report_only = false`.

### Local Development

Development mode (`Rails.env.development?`) does not set `force_ssl`, so `http://localhost:3000` works without certificates.

### Container Deployment

The Docker image exposes port 80 (HTTP). HTTPS termination is handled at the reverse proxy / load balancer layer (Nginx, Traefik, ALB). The `/up` health-check endpoint responds over HTTP so internal probes work without TLS.

### Version Constant

The application version is centralized in `SparcConfig::VERSION` (defined in `app/models/sparc_config.rb`). Both layout files reference it dynamically via `<%= SparcConfig::VERSION %>`.

### Related

- Issue #106

---

## 16. Converters (CCI / AWS / STIG → NIST)

Converters translate external framework identifiers into NIST SP 800-53 control IDs so that findings expressed in another vocabulary can be mapped into SPARC's control model. They are managed from `/converters` and are **independently refreshable** by operators with the `converters.write` permission.

### Converter types

| Converter | Refresh action | Source |
|-----------|---------------|--------|
| DISA CCI → NIST | `POST /converters/:id/refresh_cci` | DISA CCI list |
| AWS Config → NIST | `POST /converters/:id/refresh_aws_config` (#494) | `AwsConfigRefreshService` |
| AWS Security Hub → NIST | `POST /converters/:id/refresh_aws_security_hub` (#494) | `AwsSecurityHubRefreshService` |
| STIG benchmark | `GET /converters/stig_parser`, `POST /converters/import_stig` | `StigConverterService` |

Each converter owns a set of `ConverterEntry` rows (`resources :converter_entries`) holding the individual source-ID → NIST-control-ID pairs. Converters seed via `db/seeds/converters.rb` under `SeedRunner.run_section("converters")` — **bump `SeedRunner::CURRENT_VERSIONS["converters"]` when editing those seeds** or production silently skips the change (see [Changelog](Changelog) v1.6.6).

A converter mapping can be **bulk-applied to a CDEF** via the CDEF `bulk_apply_converter` preview/apply flow (v1.8.0).

---

## 17. AWS Labs CDEF Ingestion

SPARC can ingest OSCAL Component Definitions published by AWS Labs at runtime (#466). The `AwsLabsCdefImportService` (via `AwsLabsCdefSourceClient`) pulls CDEFs from the configured repo/branch.

- **Recurring job:** `AwsLabsCdefRefreshJob` runs on a multi-day Solid Queue schedule (interval via `SPARC_AWS_LABS_CDEF_INTERVAL_DAYS`).
- **Bootstrap-on-first-deploy:** when `SPARC_AWS_LABS_CDEF_ENABLED=true` and no AWS-Labs-sourced rows exist, the first boot enqueues a refresh so tenants don't wait for the weekly tick (#487).
- **Manual refresh:** `POST /cdef_documents/refresh_aws_labs` (admin button).
- AWS Labs CDEFs use **Security Hub control IDs** (e.g. `IAM.1`, `S3.5`); the converters above bridge them to NIST (#491).

---

## 18. HDF ↔ OSCAL Translation Bridge

Three stateless `/api/v1/` endpoints let tenant compliance pipelines move scan data between the **HDF (Heimdall Data Format)** and OSCAL ecosystems without running the `hdf` CLI themselves (#449). The `hdf` binary is baked into the SPARC container.

| Endpoint | Direction |
|----------|-----------|
| `POST /api/v1/oscal/sar_from_hdf` | HDF results → OSCAL Assessment Results (SAR) |
| `POST /api/v1/oscal/poam_from_hdf` | HDF results → OSCAL POA&M |
| `POST /api/v1/hdf/amendments_from_oscal_poam` | OSCAL POA&M → HDF Amendments JSON |

Passing `?authorization_boundary_id=N` to either OSCAL emission endpoint merges the boundary's Evidence + Attestation records into the output as `back-matter.resources[]` (requires `evidence.read` on the boundary). Implemented by `HdfOscalTranslationService` + `HdfRunner`.

---

## 19. FedRAMP 20x KSI Catalog & Validations

SPARC tracks **Key Security Indicators (KSIs)** — FedRAMP 20x machine-checkable indicators grouped into themes.

- **Read-only catalog:** `GET /api/v1/ksi_catalog/themes`, `GET /api/v1/ksi_catalog/indicators` (seeded from `db/seeds/fedramp_20x_ksi.rb`).
- **Validations:** `KsiValidation` records are nested under an authorization boundary (`resources :ksi_validations`), with `summary` and `export` collection actions.
- **Export:** `KsiExportService` emits the boundary's KSI validation state.

---

## 20. Authoritative Sources & Federation

The authoritative-source system (#372) lets boundaries draw OSCAL back-matter resources from a trusted upstream library, and lets SPARC instances share those libraries peer-to-peer.

- **Authoritative sources:** `GET /authoritative_sources` — browse the shared back-matter library.
- **Promotion queue:** `resources :promotion_queue` plus per-resource `promote` / `approve_promotion` / `reject_promotion` actions move a candidate resource through review into the authoritative library, with `BackMatterResourceChange` audit rows.
- **Federation peers:** `resources :federation_peers` with a `sync` action exchange **HMAC-signed OSCAL bundles** between instances. Signing uses the `SPARC_HASH`-derived key material (`FederationBundleSigningService`); peer key rotation is handled by `FederationPeerReencryptionService`.

> SPARC is a **translation engine + UI** for OSCAL / policy-as-code, not a system of record — tenant systems own the source of truth; federation shares *references*, not authority.

---

## 21. Leveraged Authorizations

A leveraging system can inherit an authorization (and its provider-implemented controls) from an underlying system such as a cloud platform.

- **Create on the leveraging boundary:** `resources :leveraged_authorizations` (`new`/`create`/`show`/`destroy`), with a `populate` action that pulls inherited implementation data into the leveraging SSP (#396).
- **Read-only leveraged POA&Ms:** `resources :leveraged_poam_documents` (`index`/`show`) surface the leveraged system's POA&M items to the leveraging side (#415).
- Implemented by `LeveragedAuthorizationService`; inherited rows appear as **provider statements** in the SSP control view.

---

## 22. Organizations & Service Accounts

Admin-namespace features for tenant and automation identity management.

- **Organizations:** `resources :organizations` (admin) — organization entities with UUID-based audit traceability for multi-org instances.
- **Service accounts:** `resources :service_accounts` (admin) — non-interactive identities for API automation, each owning **API tokens** (`resources :api_tokens`, `create`/`destroy`). Tokens are `sparc_sa_<token>` Bearer credentials with a SHA-256 digest at rest.
- **User lifecycle:** admin users can be deactivated via `PATCH /admin/users/:id/deactivate`.
- **API session bridge:** `POST /api/v1/sessions/from_token` exchanges a service-account Bearer token (or OIDC JWT) for a Rails session cookie, enabling headless UI test automation (#573, v1.8.4).

See [RBAC](RBAC) for how service accounts and roles interact, and [Configuration](Configuration) for the `SPARC_API_AUTH` modes (token / jwt / hybrid).

---

## 23. Document Review & Approval Workflow

An optional review-and-approval gate for documents and baselines, added in **v1.9.0** (#640, #630–634). Off by default so existing publish flows are unchanged until an org opts in via `SPARC_REQUIRE_DOCUMENT_APPROVAL`.

- **`Approvable` model concern** — makes a document type reviewable: it carries an approval state and transitions through submit → review → approve/reject.
- **Review queue** (`review_queue`) — reviewers see documents awaiting their decision; **promotion queue** (`promotion_queue`) tracks items moving toward a published/authoritative state.
- **Services:** `DocumentApprovalService` drives the approve/reject transitions with audit events; `BaselineReviewService` handles baseline/profile review specifically.
- **Permission-gated** — approval actions require the corresponding `*.approve` permission keys (`catalogs.approve`, `profiles.approve`, `cdef.approve`, and the `back_matter.approve_promotion` gate for back-matter promotion). See [RBAC](RBAC).
- **Configuration:** `SPARC_REQUIRE_DOCUMENT_APPROVAL` (default off). When enabled, publishing requires an approved review.

See [Screens](Screens) for the review/promotion queue UI and [RBAC](RBAC) for the approval permission keys.
