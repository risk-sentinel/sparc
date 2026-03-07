# SAP (Security Assessment Plan) Feature — Change Summary

## Overview

Added OSCAL-compliant Security Assessment Plan (SAP) generation to SPARC. This feature sits between the SSP and SAR in the RMF artifact lifecycle, enabling users to generate the gatekeeper document for every 3PAO assessment in minutes instead of weeks.

## What Was Built

### Database (1 migration, 3 tables)
- `sap_documents` — Plan metadata, SSP/Profile references, assessment type/dates/scope
- `sap_controls` — Controls to assess with method (examine/interview/test), status, assessor, objective, test case
- `sap_control_fields` — Standard field_name/field_value/editable pattern

### Models (3 new)
- `SapDocument` — Links to SSP and Profile, status enum, assessment types
- `SapControl` — Assessment methods/statuses, auto-computed control family
- `SapControlField` — Editable flag auto-set based on field name

### Controller
- `SapDocumentsController` — Dual creation path:
  1. **Wizard flow** — Select SSP + Profile, set dates/type, auto-generates SAP
  2. **File upload** — Upload existing OSCAL Assessment Plan JSON
- Full CRUD, OSCAL export (validated/unvalidated), JSON export, inline control editing

### Services (3 new)
- `SapGeneratorService` — Core logic: pulls controls from SSP/Profile, auto-assigns assessment methods by control family heuristic, enriches with catalog guidance and CDEF/InSpec test cases
- `OscalAssessmentPlanExportService` — Full OSCAL v1.1.2 assessment-plan JSON export with metadata, roles, activities, reviewed-controls, and assessment-assets
- `SapJsonParserService` — Parses uploaded OSCAL Assessment Plan JSON files

### Views (3 new)
- **Index** — Document list with type, SSP reference, schedule, status
- **New (wizard)** — 3-step form: Plan Details, Source Documents, Assessment Methods
- **Show** — Dashboard with method/status breakdowns, interactive heatmap by control family + assessment method, control cards with inline edit modal

### Integration Updates
- **Routes** — Full resource routes with OSCAL export actions
- **DocumentTypeRegistry** — SAP entry with JSON parser
- **FileUploadable** — Added `sap` safe prefix
- **JsonExportService** — Added `export_sap` method
- **Navigation** — "Assessment Plans" link in navbar
- **Home page** — SAP count stat, feature card, feature list entry
- **HomeController** — `@sap_count`

### Tests (5 spec files, 3 factories)
- Model specs for SapDocument, SapControl, SapControlField
- Service specs for SapGeneratorService and OscalAssessmentPlanExportService
- Factories for all three models

### Bugfix
- Fixed invalid `windows` platform in Gemfile (changed to `mswin mingw` for Bundler compatibility)

## File Inventory

| Action | File |
|--------|------|
| New | `db/migrate/20260307200000_create_sap_documents.rb` |
| New | `app/models/sap_document.rb` |
| New | `app/models/sap_control.rb` |
| New | `app/models/sap_control_field.rb` |
| New | `app/controllers/sap_documents_controller.rb` |
| New | `app/services/sap_generator_service.rb` |
| New | `app/services/sap_json_parser_service.rb` |
| New | `app/services/oscal_assessment_plan_export_service.rb` |
| New | `app/views/sap_documents/index.html.erb` |
| New | `app/views/sap_documents/new.html.erb` |
| New | `app/views/sap_documents/show.html.erb` |
| New | `spec/factories/sap_documents.rb` |
| New | `spec/factories/sap_controls.rb` |
| New | `spec/factories/sap_control_fields.rb` |
| New | `spec/models/sap_document_spec.rb` |
| New | `spec/models/sap_control_spec.rb` |
| New | `spec/models/sap_control_field_spec.rb` |
| New | `spec/services/sap_generator_service_spec.rb` |
| New | `spec/services/oscal_assessment_plan_export_service_spec.rb` |
| Modified | `config/routes.rb` |
| Modified | `app/models/document_type_registry.rb` |
| Modified | `app/controllers/concerns/file_uploadable.rb` |
| Modified | `app/services/json_export_service.rb` |
| Modified | `app/controllers/home_controller.rb` |
| Modified | `app/views/layouts/application.html.erb` |
| Modified | `app/views/home/index.html.erb` |
| Modified | `Gemfile` (bugfix) |

## RMF Lifecycle Position

```
Catalog → Profile → CDEF → SSP → [SAP] → SAR → POA&M
                                    ^^^
                              This feature
```

The SAP references the Profile and SSP, and its results feed into SAR Creation and POA&M generation.
