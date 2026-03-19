<!-- markdownlint-disable MD013 MD031 MD040 MD060 -->

# SSP (System Security Plan) -- OSCAL Data Mapping

OSCAL version: **1.1.2** | OSCAL root element: `system-security-plan`

Export service: `OscalSspExportService`

---

## Internal Model Hierarchy

```
SspDocument
  |-- has_many SspControl (tree structure via ancestry -- roots + provider_statements)
  |     |-- has_many SspControlField
  |     |-- has_many SspByComponent
  |-- has_many SspComponent
  |-- has_many SspUser
  |-- has_many SspInformationType
  |-- has_many SspLeveragedAuthorization
  |-- has_many SspInventoryItem
```

---

## Import Sources

| Source | Service | Notes |
|--------|---------|-------|
| Excel (.xlsx) | `SspExcelParserService` | Parses via `ssp_excel.json` field mapping; creates controls + fields |
| OSCAL JSON | `SspJsonParserService` | Full round-trip; preserves metadata_extra, components, users, info types |
| OSCAL XML / YAML | `SspJsonParserService` | XML/YAML converted to JSON hash, then delegated to JSON parser |
| Published Profile | `SspFromProfileService` | Creates SSP from profile resolved catalog; placeholder fields |
| Wizard | UI-driven | Step-by-step creation via wizard controller |

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
| `SspDocument#uuid` | `system-security-plan.uuid` | Yes | Regenerated on content change |
| `SspDocument#name` | `system-security-plan.metadata.title` | Yes | Document name |
| `SspDocument#ssp_version` | `system-security-plan.metadata.version` | Yes | Defaults to `"1.0.0"` |
| `SspDocument#oscal_version` | `system-security-plan.metadata.oscal-version` | Yes | Defaults to `"1.1.2"` |
| (generated) | `system-security-plan.metadata.last-modified` | Yes | `Time.current.iso8601` at export |
| `SspDocument#metadata_extra` | `system-security-plan.metadata.*` | No | Preserved roles, parties, revisions, etc. Merged into metadata |
| (default) | `system-security-plan.metadata.roles[]` | No | Defaults: prepared-by, system-owner, authorizing-official |
| (default) | `system-security-plan.metadata.parties[]` | No | Default: single organization party "SPARC Export" |

## Field Mapping -- Import Profile

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SspDocument#import_profile_href` | `system-security-plan.import-profile.href` | Yes | Defaults to `"#"` if blank |

## Field Mapping -- System Characteristics

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SspDocument#system_id` | `system-characteristics.system-ids[].id` | Yes | Falls back to `SspDocument#id` |
| `SspDocument#name` | `system-characteristics.system-name` | Yes | |
| `SspDocument#system_name_short` | `system-characteristics.system-name-short` | No | Only if present |
| `SspDocument#description` | `system-characteristics.description` | Yes | Default: "System Security Plan exported from SPARC for {name}" |
| `SspDocument#security_sensitivity_level` | `system-characteristics.security-sensitivity-level` | No | Only if present |
| `SspDocument#system_status` | `system-characteristics.status.state` | Yes | Defaults to `"operational"` |
| `SspDocument#date_authorized` | `system-characteristics.date-authorized` | No | ISO 8601 format |
| `SspDocument#authorization_boundary_description` | `system-characteristics.authorization-boundary.description` | Yes | Default placeholder if blank |
| `SspDocument#network_architecture_description` | `system-characteristics.network-architecture.description` | No | Only if present |
| `SspDocument#data_flow_description` | `system-characteristics.data-flow.description` | No | Only if present |

### Security Impact Level

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SspDocument#security_objective_confidentiality` | `system-characteristics.security-impact-level.security-objective-confidentiality` | No | Only if any objective present |
| `SspDocument#security_objective_integrity` | `system-characteristics.security-impact-level.security-objective-integrity` | No | |
| `SspDocument#security_objective_availability` | `system-characteristics.security-impact-level.security-objective-availability` | No | |

### System Information -- Information Types

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SspInformationType#uuid` | `system-characteristics.system-information.information-types[].uuid` | Yes | |
| `SspInformationType#title` | `system-characteristics.system-information.information-types[].title` | Yes | |
| `SspInformationType#description` | `system-characteristics.system-information.information-types[].description` | Yes | |
| `SspInformationType#categorizations_data` | `...information-types[].categorizations` | No | JSON array |
| `SspInformationType#confidentiality_impact_base` | `...information-types[].confidentiality-impact.base` | No | |
| `SspInformationType#confidentiality_impact_selected` | `...information-types[].confidentiality-impact.selected` | No | |
| `SspInformationType#confidentiality_impact_adjustment` | `...information-types[].confidentiality-impact.adjustment-justification` | No | |
| `SspInformationType#integrity_impact_base` | `...information-types[].integrity-impact.base` | No | |
| `SspInformationType#integrity_impact_selected` | `...information-types[].integrity-impact.selected` | No | |
| `SspInformationType#integrity_impact_adjustment` | `...information-types[].integrity-impact.adjustment-justification` | No | |
| `SspInformationType#availability_impact_base` | `...information-types[].availability-impact.base` | No | |
| `SspInformationType#availability_impact_selected` | `...information-types[].availability-impact.selected` | No | |
| `SspInformationType#availability_impact_adjustment` | `...information-types[].availability-impact.adjustment-justification` | No | |

Default: if no SspInformationType records exist, a single placeholder information type is generated.

## Field Mapping -- System Implementation

### Users

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SspUser#uuid` | `system-implementation.users[].uuid` | Yes | |
| `SspUser#title` | `system-implementation.users[].title` | No | |
| `SspUser#description` | `system-implementation.users[].description` | No | |
| `SspUser#short_name` | `system-implementation.users[].short-name` | No | |
| `SspUser#role_ids_data` | `system-implementation.users[].role-ids` | No | JSON array |
| `SspUser#authorized_privileges_data` | `system-implementation.users[].authorized-privileges` | No | JSON array |
| `SspUser#props_data` | `system-implementation.users[].props` | No | JSON array |
| `SspUser#links_data` | `system-implementation.users[].links` | No | JSON array |
| `SspUser#remarks` | `system-implementation.users[].remarks` | No | |

Default: if no SspUser records exist, a single "General User" with role "system-owner" is generated.

### Components

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SspComponent#uuid` | `system-implementation.components[].uuid` | Yes | |
| `SspComponent#component_type` | `system-implementation.components[].type` | Yes | e.g., "this-system", "software" |
| `SspComponent#title` | `system-implementation.components[].title` | Yes | |
| `SspComponent#description` | `system-implementation.components[].description` | Yes | |
| `SspComponent#purpose` | `system-implementation.components[].purpose` | No | |
| `SspComponent#status_state` | `system-implementation.components[].status.state` | Yes | Defaults to `"operational"` |
| `SspComponent#status_remarks` | `system-implementation.components[].status.remarks` | No | |
| `SspComponent#responsible_roles_data` | `system-implementation.components[].responsible-roles` | No | JSON array |
| `SspComponent#protocols_data` | `system-implementation.components[].protocols` | No | JSON array |
| `SspComponent#props_data` | `system-implementation.components[].props` | No | JSON array |
| `SspComponent#links_data` | `system-implementation.components[].links` | No | JSON array |
| `SspComponent#remarks` | `system-implementation.components[].remarks` | No | |

Default: if no SspComponent records exist, a single "this-system" component is generated with the document name.

### Leveraged Authorizations

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SspLeveragedAuthorization#uuid` | `system-implementation.leveraged-authorizations[].uuid` | Yes | |
| `SspLeveragedAuthorization#title` | `system-implementation.leveraged-authorizations[].title` | Yes | |
| `SspLeveragedAuthorization#party_uuid` | `system-implementation.leveraged-authorizations[].party-uuid` | Yes | |
| `SspLeveragedAuthorization#date_authorized` | `system-implementation.leveraged-authorizations[].date-authorized` | No | ISO 8601 |
| `SspLeveragedAuthorization#props_data` | `...leveraged-authorizations[].props` | No | JSON array |
| `SspLeveragedAuthorization#links_data` | `...leveraged-authorizations[].links` | No | JSON array |
| `SspLeveragedAuthorization#remarks` | `...leveraged-authorizations[].remarks` | No | |

Only included if SspLeveragedAuthorization records exist.

### Inventory Items

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SspInventoryItem#uuid` | `system-implementation.inventory-items[].uuid` | Yes | |
| `SspInventoryItem#description` | `system-implementation.inventory-items[].description` | Yes | |
| `SspInventoryItem#implemented_components_data` | `...inventory-items[].implemented-components` | No | JSON array |
| `SspInventoryItem#responsible_parties_data` | `...inventory-items[].responsible-parties` | No | JSON array |
| `SspInventoryItem#props_data` | `...inventory-items[].props` | No | JSON array |
| `SspInventoryItem#links_data` | `...inventory-items[].links` | No | JSON array |
| `SspInventoryItem#remarks` | `...inventory-items[].remarks` | No | |

Only included if SspInventoryItem records exist.

## Field Mapping -- Control Implementation

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| (generated) | `control-implementation.description` | Yes | "Control implementation for {name}" |
| `SspControl` (roots) | `control-implementation.implemented-requirements[]` | Yes | One entry per root control |

### Implemented Requirements (per SspControl)

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| (generated) | `implemented-requirements[].uuid` | Yes | Fresh UUID per export |
| `SspControl#control_id` | `implemented-requirements[].control-id` | Yes | Normalized: lowercase, dot notation for enhancements |

### Props (from SspControlField)

| SspControlField `field_name` | OSCAL JSON Path | Notes |
|------------------------------|----------------|-------|
| `status` | `implemented-requirements[].props[name=implementation-status]` | Lowercased, spaces to hyphens |
| `control_application` | `implemented-requirements[].props[name=control-type]` | ns: `https://sparc.local/ns` |
| `coverage_level` | `implemented-requirements[].props[name=provided-as]` | ns: `https://sparc.local/ns` |
| `control_type` | `implemented-requirements[].props[name=control-origination]` | ns: `https://sparc.local/ns` |
| `responsible_entities` | `implemented-requirements[].props[name=responsible-entities]` | ns: `https://sparc.local/ns` |

### By-Components (SspByComponent)

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SspByComponent#ssp_component.uuid` | `...by-components[].component-uuid` | Yes | References parent SspComponent |
| `SspByComponent#uuid` | `...by-components[].uuid` | Yes | |
| `SspByComponent#description` | `...by-components[].description` | Yes | Default: "Implementation of this control by {component title}." |
| `SspByComponent#implementation_status` | `...by-components[].implementation-status.state` | No | |
| `SspByComponent#remarks` | `...by-components[].implementation-status.remarks` | No | |
| `SspByComponent#export_data` | `...by-components[].export` | No | JSON object |
| `SspByComponent#inherited_data` | `...by-components[].inherited` | No | JSON object |
| `SspByComponent#satisfied_data` | `...by-components[].satisfied` | No | JSON object |
| `SspByComponent#responsible_roles_data` | `...by-components[].responsible-roles` | No | JSON array |
| `SspByComponent#set_parameters_data` | `...by-components[].set-parameters` | No | JSON array |
| `SspByComponent#props_data` | `...by-components[].props` | No | JSON array |
| `SspByComponent#links_data` | `...by-components[].links` | No | JSON array |

### Statements (from SspControlField)

| SspControlField `field_name` | OSCAL JSON Path | Notes |
|------------------------------|----------------|-------|
| `implementation_statement` | `...statements[statement-id={control-id}_priv].remarks` | Private implementation narrative |
| `implementation_summary` | `...statements[statement-id={control-id}_pub].remarks` | Public implementation narrative |
| (provider_statements children) | `...statements[statement-id={control-id}_inherited_{n}].remarks` | Legacy Excel inherited/provider statements; concatenated private + public |

### Remarks (from SspControlField)

| SspControlField `field_name` | OSCAL JSON Path | Notes |
|------------------------------|----------------|-------|
| `stated_requirement` | `implemented-requirements[].remarks` | Prefixed with "Stated Requirement: " |
| `notes` | `implemented-requirements[].remarks` | Prefixed with "Notes: " |
| `expected_completion` | `implemented-requirements[].remarks` | Prefixed with "Expected Completion: " |
| `inherited_from` | `implemented-requirements[].remarks` | Prefixed with "Inherited From: " |
| `history` | `implemented-requirements[].remarks` | Prefixed with "History: " |

All non-empty remarks fields are joined with double newlines into a single `remarks` string.

## Field Mapping -- Back Matter

| Internal Field | OSCAL JSON Path | Required | Notes |
|---------------|----------------|----------|-------|
| `SspDocument#build_oscal_back_matter` | `system-security-plan.back-matter` | No | Shared concern; includes resources, citations, attachments |

## Control ID Normalization

The `normalize_control_id` method transforms raw control IDs to OSCAL TokenDatatype format:

- Stripped and lowercased
- Spaces replaced with hyphens
- Parenthesized enhancements converted to dot notation: `AC-2 (1)` becomes `ac-2.1`
- Multiple dots collapsed; trailing/leading dot-hyphen artifacts cleaned
