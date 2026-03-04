# Control Catalog Schema

This document describes the data structures used by SPARC's **Control Catalog** feature, including the Excel import format for loading custom catalogs, families, and controls.

---

## Overview

SPARC organizes control catalogs in a three-level hierarchy:

```
ControlCatalog
  └── ControlFamily  (one per control family, e.g., "Access Control")
        └── CatalogControl  (one per base control, e.g., "AC-1")
```

NIST SP 800-53 Rev 4 and Rev 5 are pre-loaded via `db:seed`. Custom catalogs can be added via the UI or by importing Excel files using the column structure below.

---

## Pre-Loaded Catalogs

SPARC ships with two catalogs seeded out of the box:

| Catalog Name | Version | Families | Controls |
|-------------|---------|----------|----------|
| NIST SP 800-53 Rev 5 | 5.1.1 | 20 | 323 |
| NIST SP 800-53 Rev 4 | 4.0 | 18 | 256 |

Run `bin/rails db:seed` (or `docker compose exec web bin/rails db:seed`) to load or refresh the pre-loaded catalog data.

---

## Catalog File Columns

Use this format to import a new control catalog or add controls to an existing catalog. Each row represents a single base control.

| Column Name | Accepted Values / Format | Required | Description |
|-------------|-------------------------|----------|-------------|
| `family` | String, e.g., `ACCESS CONTROL` | **Yes** | Full name of the control family |
| `control_id` | String, e.g., `AC-1` | **Yes** | NIST-style control identifier |
| `title` | String | **Yes** | Control title |
| `priority` | `P0`, `P1`, `P2`, `P3` | No | Implementation priority level |
| `overlay` | Comma-separated string, e.g., `LOW, MODERATE, HIGH` | No | Applicable baselines or overlays |
| `language` | Text | No | Base control requirement language |
| `related_controls` | Comma-separated IDs, e.g., `PM-9, SI-12` | No | Related control identifiers |
| `supplemental_guidance` | Text | No | Supplemental guidance text |
| `implementation_guidance` | Text | No | Guidance for satisfying the control |
| `nist_references` | String, e.g., `NIST-800-53v5` | No | Supporting NIST references |
| `internal_references` | String, e.g., `PR.AC-001` | No | Applicable internal policy references |
| `check` | Text | No | How the control is validated |
| `fix` | Text | No | Remediation approach for a failing control |

> **Note:** Column order does not matter. Null or blank values are stored as `"Not Available"` at creation.

---

## Part A (Assessment Objectives) Columns

Assessment objective data follows the same file structure but uses different columns. Part A rows represent individual assessment objectives for each control.

| Column Name | Accepted Values / Format | Required | Description |
|-------------|-------------------------|----------|-------------|
| `family` | String, e.g., `ACCESS CONTROL` | **Yes** | Full name of the control family |
| `control_id` | String, e.g., `AC-1` | **Yes** | NIST-style control identifier |
| `title` | String | **Yes** | Control title |
| `decision` | Text | No | Criteria for determining pass/fail |
| `examine` | Text | No | Documentation and artifacts to examine |
| `test` | Text | No | Test procedures to perform |
| `interview` | Text | No | Interview guidance for assessors |

---

## Catalog Data Model

### ControlCatalog

Represents a versioned control framework (e.g., "NIST SP 800-53 Rev 5").

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `id` | integer | PK | Auto-generated |
| `name` | string | unique, required | Catalog name |
| `version` | string | — | Version identifier (e.g., `5.1.1`) |
| `description` | text | — | Free-text description |
| `source` | string | — | Originating organization (e.g., `NIST`) |
| `created_at` | datetime | — | Auto-set |
| `updated_at` | datetime | — | Auto-set |

---

### ControlFamily

Groups controls within a catalog by their functional area.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `id` | integer | PK | Auto-generated |
| `control_catalog_id` | integer | FK, required | Parent catalog |
| `code` | string | unique per catalog, required | Two-letter family code (e.g., `AC`) |
| `name` | string | required | Full family name (e.g., `Access Control`) |
| `description` | text | — | Optional description |
| `sort_order` | integer | — | Display order within the catalog |
| `created_at` | datetime | — | Auto-set |
| `updated_at` | datetime | — | Auto-set |

---

### CatalogControl

Individual base control within a family.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `id` | integer | PK | Auto-generated |
| `control_family_id` | integer | FK, required | Parent family |
| `control_id` | string | unique per family, required | Control identifier (e.g., `AC-1`) |
| `title` | string | — | Control title |
| `description` | text | — | Control requirement language |
| `priority` | string | — | `P0`–`P3` |
| `baseline_impact` | string | — | Applicable baselines (e.g., `LOW, MODERATE, HIGH`) |
| `created_at` | datetime | — | Auto-set |
| `updated_at` | datetime | — | Auto-set |

---

## NIST SP 800-53 Rev 5 Control Families

| Code | Family Name | Base Controls |
|------|-------------|--------------|
| AC | Access Control | 26 |
| AT | Awareness and Training | 6 |
| AU | Audit and Accountability | 16 |
| CA | Assessment, Authorization, and Monitoring | 9 |
| CM | Configuration Management | 14 |
| CP | Contingency Planning | 13 |
| IA | Identification and Authentication | 13 |
| IR | Incident Response | 10 |
| MA | Maintenance | 7 |
| MP | Media Protection | 8 |
| PE | Physical and Environmental Protection | 23 |
| PL | Planning | 11 |
| PM | Program Management | 32 |
| PS | Personnel Security | 9 |
| PT | PII Processing and Transparency | 8 |
| RA | Risk Assessment | 10 |
| SA | System and Services Acquisition | 23 |
| SC | System and Communications Protection | 51 |
| SI | System and Information Integrity | 23 |
| SR | Supply Chain Risk Management | 12 |
| **Total** | | **323** |

---

## NIST SP 800-53 Rev 4 Control Families

| Code | Family Name | Base Controls |
|------|-------------|--------------|
| AC | Access Control | 26 |
| AT | Awareness and Training | 5 |
| AU | Audit and Accountability | 16 |
| CA | Security Assessment and Authorization | 9 |
| CM | Configuration Management | 11 |
| CP | Contingency Planning | 13 |
| IA | Identification and Authentication | 11 |
| IR | Incident Response | 10 |
| MA | Maintenance | 6 |
| MP | Media Protection | 8 |
| PE | Physical and Environmental Protection | 20 |
| PL | Planning | 9 |
| PM | Program Management | 16 |
| PS | Personnel Security | 8 |
| RA | Risk Assessment | 6 |
| SA | System and Services Acquisition | 22 |
| SC | System and Communications Protection | 44 |
| SI | System and Information Integrity | 17 |
| **Total** | | **257** |

---

## Creating a Custom Catalog via the UI

1. Navigate to **Control Catalogs** → **New Catalog**
2. Enter the catalog name, version, description, and source
3. Click **Create Catalog**, then add families via **Add Family**
4. Within each family, add controls via **Add Control**

---

## Seeding Custom Catalogs Programmatically

Use `find_or_create_by!` with `update!` to keep seeds idempotent:

```ruby
catalog = ControlCatalog.find_or_create_by!(name: "My Custom Framework") do |c|
  c.version     = "1.0"
  c.source      = "Internal"
  c.description = "Custom security framework for internal use."
end

family = catalog.control_families.find_or_create_by!(code: "DP") do |f|
  f.name       = "Data Protection"
  f.sort_order = 1
end

family.catalog_controls.find_or_create_by!(control_id: "DP-1") do |c|
  c.title            = "Data Classification Policy"
  c.priority         = "P1"
  c.baseline_impact  = "LOW, MODERATE, HIGH"
end
```
