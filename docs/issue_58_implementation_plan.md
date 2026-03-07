# Issue #58: OSCAL Full Schema Uplift - Implementation Plan & Test Plan

## Overview
Expand OSCAL implementation to fully align with NIST OSCAL v1.1.2 schemas for Catalogs, Profiles, Component Definitions (CDEF), and SAR. Maintain backwards compatibility with existing data and workflows.

## Strategy
- Use JSONB columns (following existing SAR/POAM patterns) for complex OSCAL structures
- No breaking changes to existing tables or data
- Leverage the OscalMetadata concern (from PR #64) for shared metadata handling
- Store arrays (params, parts, props, links) as JSONB rather than creating new join tables

---

## Phase 1: Database Migrations

### Migration: Catalog Schema Uplift
Add to `control_catalogs`:
- `uuid` (string) - OSCAL catalog UUID
- `oscal_version` (string) - OSCAL version
- `metadata_extra` (jsonb, default: {}) - roles, parties, revisions, props, links, document-ids
- `back_matter_data` (jsonb, default: []) - OSCAL back-matter resources

Add to `control_families`:
- `uuid` (string) - group UUID
- `props_data` (jsonb, default: []) - OSCAL group props
- `links_data` (jsonb, default: []) - OSCAL group links
- `parts_data` (jsonb, default: []) - OSCAL group parts (prose)

Add to `catalog_controls`:
- `uuid` (string) - control UUID (OSCAL id attribute, e.g., "ac-1")
- `control_class` (string) - OSCAL class attribute (e.g., "SP800-53")
- `params_data` (jsonb, default: []) - OSCAL parameters
- `props_data` (jsonb, default: []) - OSCAL properties
- `links_data` (jsonb, default: []) - OSCAL links
- `parts_data` (jsonb, default: []) - structured OSCAL parts (statement, guidance, etc.)

### Migration: Profile Schema Uplift
Add to `profile_documents`:
- `back_matter_data` (jsonb, default: []) - back-matter resources

Add to `profile_controls`:
- `exclude` (boolean, default: false) - marks control as excluded
- `alters_data` (jsonb, default: []) - full alter/remove operations
- `additions_data` (jsonb, default: []) - alter/add operations

### Migration: CDEF Schema Uplift
Add to `cdef_documents`:
- `back_matter_data` (jsonb, default: []) - back-matter resources
- `components_data` (jsonb, default: []) - multi-component metadata (uuid, type, title, desc, status, protocols, responsible-roles)

Add to `cdef_controls`:
- `uuid` (string) - implemented-requirement UUID
- `props_data` (jsonb, default: []) - OSCAL properties
- `links_data` (jsonb, default: []) - OSCAL links
- `set_parameters_data` (jsonb, default: []) - set-parameter values
- `responsible_roles_data` (jsonb, default: []) - responsible roles
- `statements_data` (jsonb, default: {}) - by-component statements
- `component_uuid` (string) - which component this requirement belongs to

### Migration: SAR Schema Uplift
Add to `sar_documents`:
- `attestations_data` (jsonb, default: []) - result attestations
- `back_matter_data` (jsonb, default: []) - back-matter resources (currently in import_metadata)

Add to `sar_results`:
- `local_definitions_data` (jsonb, default: {}) - result-level local-definitions
- `attestations_data` (jsonb, default: []) - result-level attestations

---

## Phase 2: Model Updates

### Catalog Models
- `ControlCatalog`: include OscalMetadata, add uuid/oscal_version accessors
- `ControlFamily`: serialize JSONB fields, add helper methods for props/links
- `CatalogControl`: serialize JSONB fields, add helper methods for params/parts/props/links

### Profile Models
- `ProfileDocument`: add back_matter_data accessor, update include OscalMetadata
- `ProfileControl`: add exclude/alters/additions accessors

### CDEF Models
- `CdefDocument`: include OscalMetadata (already has metadata_extra from PR #64), add back_matter, components_data accessors
- `CdefControl`: add JSONB accessors for props, links, set_parameters, responsible_roles, statements

### SAR Models
- `SarDocument`: add attestations_data, back_matter_data accessors
- `SarResult`: add local_definitions_data, attestations_data accessors

---

## Phase 3: Service Updates

### NEW: OscalCatalogExportService
- Export control_catalogs to OSCAL v1.1.2 catalog JSON
- Build metadata, groups, controls, params, parts, props, links, back-matter
- Schema validation via OscalSchemaValidationService

### Update: CatalogImportService
- Preserve UUID, params[], parts[], props[], links[], class attribute during import
- Store structured parts instead of flattening to guidance_data text
- Maintain backwards compatibility: continue populating guidance_data for existing UI

### Update: OscalProfileExportService
- Include back-matter from back_matter_data
- Export exclude-controls in imports section
- Export full parameter attributes (class, constraints, guidelines, select)
- Export alter.removes operations

### Update: ProfileJsonParserService
- Parse include-all flag
- Parse exclude-controls
- Parse alter.removes
- Store full parameter attributes (not just value)
- Preserve back-matter resources

### Update: OscalComponentDefinitionExportService
- Support multiple components from components_data
- Export capabilities if present
- Export responsible-roles per implemented-requirement
- Export set-parameters
- Export back-matter
- Export by-component statements

### Update: CdefJsonParserService
- Parse multiple components (not just first)
- Parse responsible-roles, set-parameters per requirement
- Parse capabilities
- Store component UUID mapping

### Update: OscalSarExportService
- Export result-level local-definitions
- Export attestations
- Move back-matter from import_metadata to dedicated column

---

## Phase 4: Controller & UI Updates

### Catalog Controller
- Add download_oscal, download_oscal_validated, download_oscal_unvalidated actions
- Add update_metadata action
- Add status action for async processing

### Catalog Views
- Show page: display OSCAL metadata panel (uuid, version, parties)
- Show page: display params/props for each control
- Show page: add OSCAL download buttons
- Add metadata edit modal

### Profile Views
- Show page: display back-matter resources section
- Show page: display excluded controls indicator
- Show page: display full parameter details (constraints, guidelines)

### CDEF Views
- Show page: display components list panel
- Show page: display responsible-roles per control
- Show page: display set-parameters

### SAR Views
- Show page: display attestations section
- Enrich page: add attestations form

---

## Test Plan

### TP-01: Database Migration Integrity
- [ ] Migration runs without errors on existing database
- [ ] All new columns have correct types and defaults
- [ ] Existing data in catalog, profile, CDEF, SAR tables is preserved unchanged
- [ ] Rollback migration works cleanly

### TP-02: Catalog OSCAL Export (NEW)
- [ ] OscalCatalogExportService generates valid OSCAL v1.1.2 catalog JSON
- [ ] Export includes metadata with uuid, title, version, oscal-version
- [ ] Export includes groups with uuid, title, props, parts
- [ ] Export includes controls with uuid, class, title, params, props, links, parts
- [ ] Export includes back-matter resources when present
- [ ] Export passes OscalSchemaValidationService validation
- [ ] Empty/minimal catalog exports without errors

### TP-03: Catalog Import Preservation
- [ ] CatalogImportService preserves control UUIDs from OSCAL JSON
- [ ] Parameters (params[]) stored in params_data JSONB
- [ ] Structured parts stored in parts_data JSONB
- [ ] Props and links stored in respective JSONB columns
- [ ] guidance_data continues to be populated for backwards compatibility
- [ ] Existing NIST XML import path still works

### TP-04: Profile Full Schema
- [ ] ProfileJsonParserService parses exclude-controls
- [ ] ProfileJsonParserService parses include-all
- [ ] ProfileJsonParserService preserves full parameter attributes
- [ ] ProfileJsonParserService stores back-matter resources
- [ ] OscalProfileExportService exports back-matter
- [ ] OscalProfileExportService exports alter.removes operations
- [ ] Round-trip: import OSCAL profile → export → valid OSCAL JSON

### TP-05: CDEF Full Schema
- [ ] CdefJsonParserService parses multiple components
- [ ] CdefJsonParserService stores component UUIDs and metadata
- [ ] CdefJsonParserService parses set-parameters
- [ ] CdefJsonParserService parses responsible-roles
- [ ] OscalComponentDefinitionExportService exports multiple components
- [ ] OscalComponentDefinitionExportService exports set-parameters
- [ ] OscalComponentDefinitionExportService exports back-matter
- [ ] Existing STIG/InSpec import paths still work (backwards compat)

### TP-06: SAR Full Schema
- [ ] SarJsonParserService parses result-level attestations
- [ ] OscalSarExportService exports attestations
- [ ] OscalSarExportService exports result-level local-definitions
- [ ] Back-matter migration from import_metadata to dedicated column works
- [ ] Existing SAR data displays correctly (no regression)

### TP-07: OscalMetadata Integration
- [ ] ControlCatalog includes OscalMetadata concern
- [ ] build_oscal_metadata works for catalog documents
- [ ] metadata_extra JSONB stores roles, parties, revisions correctly
- [ ] Metadata inheritance works when applicable

### TP-08: UI Updates
- [ ] Catalog show page displays OSCAL metadata panel
- [ ] Catalog show page has OSCAL download buttons
- [ ] Profile show page displays back-matter section
- [ ] CDEF show page displays components panel
- [ ] SAR show page displays attestations section
- [ ] All existing views render without errors (no regression)

### TP-09: Backwards Compatibility
- [ ] Existing documents without new JSONB fields load without errors
- [ ] All JSONB columns default to empty hash/array (nil-safe)
- [ ] Existing export services produce same output for pre-uplift data
- [ ] No breaking changes to API endpoints
- [ ] No changes to background job processing

### TP-10: Code Quality
- [ ] rubocop passes with no new offenses
- [ ] brakeman reports no new security warnings
- [ ] No N+1 queries introduced in show pages
- [ ] All new JSONB columns have proper defaults
