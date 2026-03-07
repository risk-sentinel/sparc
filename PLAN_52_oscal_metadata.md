# Plan: OSCAL Metadata Management & Inheritance Across Artifacts (#52)

## Problem Statement

OSCAL artifacts require standardized metadata (title, version, roles, parties, props, links, revisions, etc.) for traceability, versioning, and compliance reporting. Currently:
- Only `name` and version are editable via UI
- `metadata_extra` (jsonb) exists on SSP, SAR, POAM but is missing from SAP, CDEF, Profile
- `oscal_version` is missing from CDEF
- No inheritance logic when artifacts are linked (e.g., SSP imports Profile)
- Export services for Profile and CDEF generate hardcoded default metadata instead of using preserved data

## Implementation Phases

### Phase 1: Database Migration
Add missing columns to normalize metadata support:
- `sap_documents`: add `metadata_extra` jsonb column
- `cdef_documents`: add `metadata_extra` jsonb column, `oscal_version` string column
- `profile_documents`: add `metadata_extra` jsonb column

### Phase 2: OscalMetadata Concern
Shared ActiveSupport::Concern providing:
- Common accessors for `metadata_extra` sub-fields (roles, parties, responsible_parties, revisions, props, links, document_ids)
- `oscal_metadata_title` / `oscal_metadata_version` / `oscal_metadata_oscal_version` methods
- `merge_metadata_from(source_document)` for inheritance
- Validation helpers for required OSCAL fields

### Phase 3: Metadata Inheritance Service
`OscalMetadataInheritanceService` that propagates metadata along the artifact chain:
- Catalog -> Profile: inherit props, merge roles/parties
- Profile -> SSP: inherit roles/parties from profile, merge with SSP's own
- SSP -> SAP: inherit system-related metadata
- SAP -> SAR: inherit assessment metadata
- SSP -> POAM: inherit system metadata

Uses OSCAL resolution rules: child overrides parent for conflicts.

### Phase 4: Controller Updates
Expand `document_metadata_params` in all 6 controllers to accept:
- `oscal_version`, `description` (where missing)
- `metadata_extra` sub-fields: roles, parties, responsible_parties, props, links, document_ids, revisions

### Phase 5: Metadata Editing UI
Add collapsible "OSCAL Metadata" card section to all 6 show pages:
- Roles table (id, title) with add/remove
- Parties table (uuid, type, name, email) with add/remove
- Responsible Parties list
- Document properties (key-value pairs)
- Links list
- Revisions history (read-only display)

### Phase 6: Export Service Updates
Update Profile and CDEF export services to use `metadata_extra` (like SSP/SAR/POAM already do) instead of hardcoded defaults.

### Phase 7: Parser Service Updates
Ensure all JSON/XML parsers preserve full metadata into `metadata_extra`:
- SAP parser: store roles/parties/props/revisions
- CDEF parser: store roles/parties/props/revisions
- Profile parser: store roles/parties/props/revisions

## Artifact Inheritance Chain
```
ControlCatalog
  -> ProfileDocument (imports catalog)
    -> SspDocument (imports profile)
      -> SapDocument (references SSP)
        -> SarDocument (imports SAP)
      -> PoamDocument (references SSP system)
```

## Files Modified
- `db/migrate/XXXXXX_add_metadata_fields.rb` (new)
- `app/models/concerns/oscal_metadata.rb` (new)
- `app/models/{ssp,sar,sap,poam,cdef,profile}_document.rb`
- `app/services/oscal_metadata_inheritance_service.rb` (new)
- `app/controllers/{ssp,sar,sap,poam,cdef,profile}_documents_controller.rb`
- `app/views/{ssp,sar,sap,poam,cdef,profile}_documents/show.html.erb`
- `app/views/shared/_oscal_metadata_section.html.erb` (new)
- `app/services/oscal_{profile,component_definition}_export_service.rb`
- `app/services/{sap,cdef,profile}_json_parser_service.rb`
