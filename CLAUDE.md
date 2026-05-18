# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SPARC (Systematic and Regulatory Compliance) is a Rails 8.1 application for managing NIST 800-53 compliance documentation — System Security Plans (SSPs), Security Assessment Results (SARs), Component Definitions (CDEFs), and control catalogs. It replaces spreadsheet-based workflows with a web UI and REST API, with OSCAL export support.

## Tech Stack

Ruby 3.4.4, Rails 8.1.2, PostgreSQL 15, Sidekiq + Redis for background jobs, Hotwire (Turbo + Stimulus), Propshaft asset pipeline, importmap (no Node build step).

## Common Commands

```bash
# Run the full app with Docker
docker compose up --build

# Seed NIST catalogs (Rev 4 + Rev 5)
docker compose exec web bin/rails db:seed

# Local development
bundle install
bin/rails db:create db:migrate db:seed
bin/rails server

# Run full RSpec test suite
bundle exec rspec

# Run a single spec file
bundle exec rspec spec/models/ssp_document_spec.rb

# Run a single test by line number
bundle exec rspec spec/models/ssp_document_spec.rb:18

# Lint
bundle exec rubocop

# Security scan
bundle exec brakeman

# Rails console
bin/rails console

# Background jobs (Solid Queue is default in production; Sidekiq optional)
bundle exec sidekiq
```

## Architecture

### Domain Model Hierarchy

Each document type follows the same three-level structure:

- **Document** → has_many **Controls** → has_many **ControlFields**
- `SspDocument` → `SspControl` → `SspControlField`
- `SarDocument` → `SarControl` → `SarControlField`
- `CdefDocument` → `CdefControl` → `CdefControlField`

Control catalogs have a parallel hierarchy: `ControlCatalog` → `ControlFamily` → `CatalogControl`

### Key Services (app/services/)

- `JsonExportService` — serialize documents to downloadable JSON
- `SspUpdateService` — handle inline field updates from the UI
- `CatalogImportService` — import NIST control catalogs
- `OscalSspExportService` / `OscalComponentDefinitionExportService` — OSCAL v1.1.2 JSON exports
- `OscalSchemaValidationService` — validate OSCAL JSON against NIST schemas
- `AwsLabsCdefImportService` — runtime ingestion of OSCAL CDEFs from AWS Labs (#466)
- `SspExcelParserService` / `SarExcelParserService` / `SarExcelExportService` — parse/export Excel files (.xlsx). Code preserved for API consumers; no longer surfaced in the UI as of #479.

### Background Jobs

- `DocumentConversionJob` — async file-to-JSON parsing for document imports (large files)
- `AwsLabsCdefRefreshJob` — recurring Solid Queue job that ingests AWS Labs OSCAL CDEFs (#466, weekly default)
- Job status is tracked via the `ConversionJob` model

### API

REST API under `Api::V1::` namespace at `/api/v1/`. SSP and SAR documents have API controllers. Endpoints: `convert`, `update_fields`, `export`.

### Frontend

Hotwire-based (Turbo Frames/Streams + Stimulus controllers). No SPA framework. Interactive heat maps show control status by NIST family. Inline editing for designated editable fields.

### Database

Database name: `ssp_tpr_manager_development` (dev), `ssp_tpr_manager_test` (test). Docker Compose maps Postgres to port 5433 and Redis to port 6380 to avoid conflicts with local services.

## Testing

Uses RSpec with FactoryBot and Faker. Specs live under `spec/` with `spec/models/`, `spec/services/`, and `spec/factories/`. There is also a `test/` directory with Rails default Minitest structure — the project primarily uses RSpec.

## Linting

Uses `rubocop-rails-omakase` (Rails default style guide) with no custom overrides.

## Developer Docs

Developer documentation lives in `docs/dev/`:

- `docs/dev/issue_rules.md` — **mandatory** issue process workflow, hard guardrails, compliance artifact update requirements, authentication mode coverage matrix
- `docs/dev/Implemenation_plan.md` — phased roadmap and issue tracking
- `docs/dev/Developer_Collision_Avoidance_Plan.md` — domain ownership, hot files, migration coordination
- `docs/dev/release_notes.md` — stacked release notes

## Compliance Documentation

NIST SP 800-53 Rev 5 compliance docs live in `docs/compliance/`:

- `docs/compliance/README.md` — process guide, sparc-iac integration model
- `docs/compliance/nist-sp800-53-rev5-mapping.md` — central control mapping (HIGH baseline, 370 controls)
- `docs/compliance/oscal/cdefs/*.json` — OSCAL v1.1.2 component definitions (5 files, 46 controls)

When touching security-critical code, update the relevant CDEFs and add inline NIST control comments. See `docs/dev/issue_rules.md` for the full process.
