# Architecture

## Overview

SPARC follows a Rails monolith architecture with Hotwire (Turbo + Stimulus) for interactive frontend behavior, Sidekiq for background job processing, and PostgreSQL with JSONB columns for flexible schema storage. The domain model is organized around OSCAL document types, each following a consistent three-level hierarchy.

---

## Core Model Hierarchy

```
+------------------+       +------------------+       +------------------+
|   *Document      | 1---* |   *Control       | 1---* |  *ControlField   |
+------------------+       +------------------+       +------------------+
| - name           |       | - control_id_str |       | - field_name     |
| - metadata       |       | - title          |       | - field_value    |
| - status         |       | - status         |       | - editable       |
+------------------+       +------------------+       +------------------+

Concrete implementations:

  SspDocument  ------>  SspControl  ------>  SspControlField
  SarDocument  ------>  SarControl  ------>  SarControlField
  CdefDocument ------>  CdefControl ------>  CdefControlField
  SapDocument  ------>  SapControl  ------>  SapControlField
  ProfileDocument -->  ProfileControl -->  ProfileControlField

Special case:

  PoamDocument ------>  PoamItem
                         |------>  PoamRisk
                         |------>  PoamObservation
                         |------>  PoamFinding
```

---

## ASCII Relationship Diagram

```
                          +------------------+
                          |   ControlCatalog |
                          +--------+---------+
                                   | 1
                                   | *
                          +--------+---------+
                          |  ControlFamily   |
                          +--------+---------+
                                   | 1
                                   | *
                          +--------+---------+
                          |  CatalogControl  |
                          +------------------+
                                   ^
                                   | (reference)
     +-----------------------------+-----------------------------+
     |                             |                             |
+----+------+               +-----+-----+               +-------+----+
|SspControl |               |SarControl |               |CdefControl |
+----+------+               +-----+-----+               +-------+----+
     | *                          | *                          | *
     | 1                          | 1                          | 1
+----+--------+             +-----+-------+             +------+--------+
|SspDocument  |             |SarDocument  |             |CdefDocument   |
+----+--------+             +-----+-------+             +---------------+
     |
     | 1
     +------------+------------+--------------+--------------+
     | *           | *          | *             | *            | *
+----+------+ +----+----+ +----+--------+ +----+--------+ +---+----------+
|SspComponent| |SspUser  | |SspInfoType  | |SspLevAuth   | |SspInventory  |
+----+------+ +---------+ +-------------+ +-------------+ |    Item      |
     |                                                     +--------------+
     | *
+----+--------+
|SspByComponent|  (joins SspControl <-> SspComponent)
+-------------+


+---------+       +----------+       +--------------------+
|  User   | 1---* | UserRole | *---1 |       Role         |
+---------+       +----+-----+       +--------------------+
| email   |       | authorization    | name               |
| admin   |       | _boundary_id     | permissions (JSONB) |
+---------+       | (optional)       +--------------------+
     | 1          +----------+
     | *                | *
+----+------+           | 0..1
| Identity  |     +-----+-------------------+
+-----------+     | AuthorizationBoundary   |
| provider  |     +-------------------------+
| uid       |     | name                    |
| auth_data |     | status                  |
+-----------+     +-------------------------+


+------------+       +---------------------+
|  Evidence  | 1---* | EvidenceControlLink  |  (polymorphic to any document type)
+-----+------+       +---------------------+
      | 1
      | *
+-----+--------+
| Attestation  |
+--------------+


+--------------------+       +----------------------+
| ControlMapping     | 1---* | ControlMappingEntry  |
+--------------------+       +----------------------+
| source_catalog_id  |       | source_control       |
| target_catalog_id  |       | target_control       |
+--------------------+       | relationship         |
                              +----------------------+

+-------------+
| AuditEvent  |  (immutable log)
+-------------+
| action      |
| category    |
| subject_type|  (polymorphic)
| subject_id  |
| metadata    |  (JSONB)
| user_id     |
| ip_address  |
+-------------+
```

---

## Catalog Hierarchy

The control catalog system mirrors the NIST organizational structure:

| Model | Description |
|-------|-------------|
| `ControlCatalog` | A versioned catalog (e.g., "NIST SP 800-53 Rev 5"). Top-level container. |
| `ControlFamily` | A grouping of related controls within a catalog (e.g., AC, AU, SI). |
| `CatalogControl` | An individual control with `guidance_data` (JSONB) for supplemental guidance, references, and parameters. |

---

## Mapping System

Control mappings enable cross-framework analysis (e.g., NIST 800-53 to ISO 27001):

- `ControlMapping` links a source catalog to a target catalog
- `ControlMappingEntry` records individual control-to-control relationships with a relationship type based on NIST IR 8477 set-theory semantics: `equal`, `superset`, `subset`, `intersect`

---

## SSP OSCAL Entities

An `SspDocument` contains the full OSCAL SSP model beyond controls:

| Model | Purpose |
|-------|---------|
| `SspComponent` | A technology component implementing controls (with `port_protocols` JSONB) |
| `SspUser` | An authorized system user/role |
| `SspInformationType` | A categorized information type (FIPS 199 impact levels) |
| `SspLeveragedAuthorization` | A reference to a parent system's authorization |
| `SspInventoryItem` | A deployed instance of a component |
| `SspByComponent` | Join table linking `SspControl` to `SspComponent` with implementation details |

---

## SAR OSCAL Entities

An `SarDocument` contains the full OSCAL Assessment Results model:

| Model | Purpose |
|-------|---------|
| `SarResult` | A discrete assessment result set (e.g., one scan or review session) |
| `SarObservation` | An observation made during assessment |
| `SarFinding` | A finding derived from one or more observations |
| `SarRisk` | A risk identified from findings |

Junction tables connect results to observations, findings, and risks in many-to-many relationships.

---

## User & Auth System

```
Authentication Flow:

  Login Request
       |
       v
  +--- Local? ---> bcrypt verify ---> Session
  |
  +--- OAuth? ---> GitHub/GitLab callback ---> Identity lookup ---> Session
  |
  +--- OIDC? ----> Provider redirect ---> ID token validation ---> Session
  |
  +--- LDAP? ----> LdapAuthService (bind-and-search) ---> Session
```

- `User` holds core profile, `admin` flag, sign-in tracking, and `must_reset_password`
- `Identity` stores OAuth/OIDC/LDAP provider data (`provider`, `uid`, `auth_data` JSONB)
- `UserRole` assigns a `Role` to a `User`, optionally scoped to an `AuthorizationBoundary`
- `Role` contains a `permissions` JSONB field with 20 boolean permission keys

---

## Evidence System

- `Evidence` records are attached to documents via `EvidenceControlLink` (polymorphic association supporting any document type)
- `Attestation` records are linked to evidence for formal sign-off

---

## Audit System

`AuditEvent` provides an immutable audit trail:

- Approximately 80 tracked actions across 16 categories
- Polymorphic subject tracking (`subject_type`/`subject_id`) for any auditable resource
- `metadata` JSONB column for action-specific context (before/after values, parameters)
- Indexed by `user_id`, `action`, `category`, `subject_type`, and `created_at`

---

## Service Layer

### Parser Services (Import)

| Service | Input | Output |
|---------|-------|--------|
| `SspExcelParserService` | Excel (.xlsx) | `SspDocument` + controls + fields |
| `SarExcelParserService` | Excel (.xlsx) | `SarDocument` + controls + fields |
| `CdefJsonParserService` | OSCAL JSON | `CdefDocument` + controls + fields |
| `CdefXccdfParserService` | XCCDF (DISA STIG) | `CdefDocument` + controls + fields |
| `CatalogImportService` | OSCAL Catalog JSON | `ControlCatalog` + families + controls |

### Export Services

| Service | Output Format | Notes |
|---------|---------------|-------|
| `OscalSspExportService` | OSCAL JSON | Validated against NIST v1.1.2 schemas |
| `OscalComponentDefinitionExportService` | OSCAL JSON | Component definition export |
| `JsonExportService` | JSON | Simplified internal format |
| `SarExcelExportService` | Excel (.xlsx) | Round-trip with SAR import |
| `AuditCsvExportService` | CSV | Audit log export for compliance reporting |

### Validation

| Service | Purpose |
|---------|---------|
| `OscalSchemaValidationService` | Validates OSCAL JSON against official NIST v1.1.2 schemas using the `json_schemer` gem |

### Auth

| Service | Purpose |
|---------|---------|
| `LdapAuthService` | LDAP bind-and-search authentication |

### Generation

| Service | Purpose |
|---------|---------|
| `SapGeneratorService` | Generates Security Assessment Plans from templates |
| `SspWizardService` | Step-by-step SSP creation wizard logic |

### Utilities

| Service | Purpose |
|---------|---------|
| `DocumentDuplicationService` | Deep-copies a document with all associated records |
| `DashboardAggregationService` | Aggregates control status data across documents for the dashboard heatmap |
| `DataMappingSchema` | Vendor-neutral schema for mapping between data formats |
| `OscalMetadataInheritanceService` | Propagates OSCAL metadata from parent documents to children |

---

## Background Jobs

### DocumentConversionJob

The unified async document processing job:

1. Receives a `ConversionJob` record ID
2. Looks up the document type via `DocumentTypeRegistry`
3. Dispatches to the appropriate parser service
4. Updates `ConversionJob` status: `pending` -> `processing` -> `completed` | `failed`

All 6 document types (SSP, SAR, SAP, CDEF, POA&M, Profile) are processed through this single job class.

---

## Database

### Engine

PostgreSQL 15

### JSONB Usage

SPARC uses PostgreSQL JSONB columns extensively for flexible, schema-less data:

| Model | Column | Contents |
|-------|--------|----------|
| `Role` | `permissions` | 20 boolean permission keys |
| `CatalogControl` | `guidance_data` | Supplemental guidance, references, parameters |
| `Identity` | `auth_data` | OAuth tokens, OIDC claims, LDAP attributes |
| `AuditEvent` | `metadata` | Action-specific context (before/after, params) |
| `SspComponent` | `port_protocols` | Network port and protocol definitions |
| Various documents | `metadata_extra` | Additional OSCAL metadata fields |

### Port Configuration

| Service | Development Port | Notes |
|---------|-----------------|-------|
| PostgreSQL | 5433 | Offset from default 5432 to avoid conflicts |
| Redis | 6380 | Offset from default 6379 to avoid conflicts |
| Web (Rails) | 3000 | Standard Rails port |

### Database Names

- Development: `ssp_tpr_manager_development`
- Test: `ssp_tpr_manager_test`
