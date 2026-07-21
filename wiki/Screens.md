# Screens & UI Reference

This page provides a comprehensive inventory of every screen in the SPARC application, organized by the OSCAL layer structure. Each section includes route paths, access requirements, and key UI elements.

_Current as of app version **v1.13.0**. Routes are authoritative per `config/routes.rb`; the version badge in the navbar renders dynamically from `SparcConfig::VERSION`._

> **Looking for how-to instructions?** This page is a reference inventory. For
> step-by-step, task-oriented walkthroughs of each area, see the
> [User Guides](User-Guides).

---

## Navigation Structure

The application uses a dark sticky navbar (`navbar-dark bg-dark sticky-top`) that adapts based on authentication state.

| Position | Element | Visibility | Details |
|----------|---------|------------|---------|
| Left | SPARC logo | Always | Responsive SVG logo linked to root path |
| Left | Version badge | Always | Secondary badge rendered dynamically from `SparcConfig::VERSION` (the running app version) |
| Center-Right | Home | Always | Nav link to `/` |
| Center-Right | Controls dropdown (blue) | Always | Control Catalogs, Baselines, Mappings, Converters |
| Center-Right | Implementation dropdown (green) | Auth required | System Security Plans, Component Definitions |
| Center-Right | Assessment dropdown (orange) | Auth required | Assessment Plans, Assessment Results, Evidence, POA&Ms |
| Center-Right | Authorization Boundaries | Auth required | Standalone nav link |
| Center-Right | Trust Store / workflow | Auth required | Authoritative Sources, Review Queue, Promotion Queue, Federation Peers (surfaced per role/config) |
| Right | Theme toggle | Always | Light/dark mode button, persisted via `localStorage` key `sparc-theme` |
| Right | User menu | Signed in | Avatar/initials, display name, dropdown with Profile, Change Password, Admin section (Instance Admin only), Sign Out |
| Right | Login button | Not signed in | `btn-outline-info` button linking to `/login` |

### User Menu Dropdown (signed in)

- User avatar (or initials) with display name and email
- **Profile** -- `/profile/edit`
- **Change Password** -- `/password/edit`
- **Administration** (Instance Admin only):
  - Users -- `/admin/users`
  - Roles -- `/admin/roles`
  - Authorization Boundaries -- `/admin/authorization_boundaries`
  - Audit Log -- `/admin/audit_logs`
- **Sign Out** -- `DELETE /logout`

### Controls Dropdown Items

| Item | Route | Icon |
|------|-------|------|
| Control Catalogs | `/control_catalogs` | Book |
| Baselines | `/profile_documents` | Clipboard |
| Mappings | `/control_mappings` | Arrows |
| Converters | `/converters` | Refresh |

### Implementation Dropdown Items

| Item | Route | Icon |
|------|-------|------|
| System Security Plans | `/ssp_documents` | Document |
| Component Definitions | `/cdef_documents` | Wrench |

### Assessment Dropdown Items

| Item | Route | Icon |
|------|-------|------|
| Assessment Plans | `/sap_documents` | Memo |
| Assessment Results | `/sar_documents` | Chart |
| Evidence | `/evidences` | Paperclip |
| POA&Ms | `/poam_documents` | Warning |

---

## Flash Notifications

Flash messages appear as a fixed top-right overlay container managed by a `flash` Stimulus controller. Three severity levels are supported:

| Flash Key | Bootstrap Class | Usage |
|-----------|----------------|-------|
| `success` | `alert-success` | Successful operations |
| `error` | `alert-danger` | Errors and failures |
| `warning` | `alert-warning` | Non-critical alerts |

Each alert is dismissible with auto-dismiss behavior handled by the Stimulus controller.

---

## Screens by Section

### Public / Authentication

#### Login Page

| | |
|---|---|
| **Route** | `GET /login` |
| **Controller** | `SessionsController#new` |
| **Layout** | `layouts/login` |
| **Auth** | Public |

The login page uses a tabbed interface that adapts based on enabled authentication methods via `SparcConfig`:

- **Local Login tab** (if `SPARC_ENABLE_LOCAL_LOGIN`): Email/password form with sign-in button. If `SPARC_ENABLE_USER_REGISTRATION=true`, shows a "Create Account" button linking to `/register`.
- **OIDC tab** (if `SPARC_ENABLE_OIDC`): Single SSO button labeled with the configured provider title. Uses a POST form to `/auth/oidc`.
- **LDAP tab** (if `SPARC_ENABLE_LDAP`): Username/password form with hidden `auth_method=ldap` field.
- **SSO Buttons** (GitHub/GitLab): Shown below the tabs when either `SparcConfig.github_enabled?` or `SparcConfig.gitlab_enabled?` returns true. POST forms to `/auth/github` and `/auth/gitlab`.
- **Security key button** (if `SparcConfig.fido2_enabled?`): "Sign in with a security key" — triggers a WebAuthn assertion (key + PIN) via the `webauthn` Stimulus controller; POST to `/session/webauthn` (options at `/session/webauthn/options`). Passwordless. (#779)
- **CAC / PIV button** (if `SparcConfig.enable_piv?`): "Sign in with your CAC / smart card" — `GET /auth/piv`, mapping the gateway-forwarded validated client certificate to a user. (#779)
- **OSCAL Overview section**: Rendered via the `sessions/_oscal_overview` partial below the login form.
- **No Auth State**: If no authentication methods are configured, displays a message directing to `ENVIRONMENT_VARIABLES.md`.

#### Security Keys (FIDO2 management)

| | |
|---|---|
| **Route** | `GET /webauthn_credentials`, `POST /webauthn_credentials/registration_options`, `POST /webauthn_credentials`, `DELETE /webauthn_credentials/:id` |
| **Controller** | `WebauthnCredentialsController` |
| **Auth** | Signed-in users; only present when `SPARC_FIDO2_ENABLED=true` (returns 404 otherwise) |

Reached from the account menu (**Security Keys**). Enroll a FIDO2 key (optional nickname → browser prompt → key + PIN), view registered keys, and remove one. Admins reset a locked-out user's keys from the user admin page (`DELETE /admin/users/:id/reset_security_keys`). See [User Guide: Security Keys](User-Guide-Security-Keys) and [Authentication and MFA](Authentication-and-MFA).

#### Registration Page

| | |
|---|---|
| **Route** | `GET /register`, `POST /register` |
| **Controller** | `RegistrationsController#new`, `#create` |
| **Auth** | Public (only available when `SPARC_ENABLE_USER_REGISTRATION=true`) |

Self-service account creation form with email, password, and name fields.

#### Profile Edit

| | |
|---|---|
| **Route** | `GET /profile/edit` |
| **Controller** | `ProfilesController#edit` |
| **Auth** | Signed in |
| **Actions** | `PATCH /profile/update_avatar`, `DELETE /profile/remove_avatar` |

Avatar upload and removal, display name information.

#### Change Password

| | |
|---|---|
| **Route** | `GET /password/edit`, `PATCH /password` |
| **Controller** | `PasswordsController#edit`, `#update` |
| **Auth** | Signed in |

Current password and new password fields. Also used for forced password reset on bootstrapped admin accounts.

---

### Dashboard

#### Home

| | |
|---|---|
| **Route** | `GET /` |
| **Controller** | `HomeController#index` |
| **Auth** | Varies (public when auth disabled) |

The dashboard consists of three main sections:

1. **Statistics Tiles** -- A gradient header card with a responsive grid (up to 10 columns on large screens) showing counts for: Catalogs, Families, Controls, Authorization Boundaries, Baselines, CDEFs, SSPs, SAPs, SARs, POA&Ms, and Evidence.

2. **Aggregate Compliance Heatmap** -- An interactive heatmap showing compliance status across all SSPs, grouped by NIST control family. Uses `ssp_status_color` helper for color coding. Families are clickable, linking to the family drilldown view.

3. **Section Navigation Grid** -- A card grid (5 columns on large screens) with "View" and "New" buttons for each major document type: Authorization Boundaries, Control Catalogs, Baselines, CDEFs, SSPs, SAPs, SARs, POA&Ms, and Evidence.

#### Family Drilldown

| | |
|---|---|
| **Route** | `GET /dashboard/family/:family` |
| **Controller** | `HomeController#family_drilldown` |
| **Auth** | Varies |

Displays controls filtered by a specific NIST control family code (e.g., `AC`, `AU`, `SC`). Reached by clicking a family cell in the dashboard heatmap.

---

### Controls Layer (mostly public)

#### Control Catalogs List

| | |
|---|---|
| **Route** | `GET /control_catalogs` |
| **Controller** | `ControlCatalogsController#index` |
| **Auth** | Public |

Summary tiles showing total catalogs, families, and controls. Table listing all catalogs with name, version, source, family count, control count, creation date, and action buttons. Actions include "View", "Import" (links to `/control_catalogs/import`), and "New".

#### Catalog Detail

| | |
|---|---|
| **Route** | `GET /control_catalogs/:id` |
| **Controller** | `ControlCatalogsController#show` |
| **Auth** | Public |

Displays the catalog with:
- Editable metadata (name, version) via inline toggle
- Control families listed with their controls
- Metadata panel with catalog properties
- Export buttons: OSCAL (validated and unvalidated variants)
- Nested navigation to individual families and controls

#### Catalog Create / Edit

| | |
|---|---|
| **Routes** | `GET /control_catalogs/new`, `GET /control_catalogs/:id/edit` |
| **Controller** | `ControlCatalogsController#new`, `#edit` |
| **Auth** | Authenticated |

Form fields: name, version, source, description. Template selector for creating from blank, NIST SP 800-53 Rev 4, or Rev 5 seed data.

#### Catalog Import

| | |
|---|---|
| **Route** | `GET /control_catalogs/import`, `POST /control_catalogs/import` |
| **Controller** | `ControlCatalogsController#import` |
| **Auth** | Authenticated |

File upload form accepting JSON and XML catalog files for import.

#### Control Family Detail / Edit

| | |
|---|---|
| **Routes** | `GET /control_families/:id`, `GET /control_families/:id/edit` |
| **Controller** | `ControlFamiliesController#show`, `#edit` |
| **Auth** | Public (show), Authenticated (edit) |

Family detail shows controls within the family. Edit form includes family code, name, and description fields. Scoped within a catalog (`/control_catalogs/:catalog_id/control_families`).

#### Catalog Control Edit

| | |
|---|---|
| **Routes** | `GET /catalog_controls/:id/edit` |
| **Controller** | `CatalogControlsController#edit` |
| **Auth** | Authenticated |

Edit form for individual catalog controls with control ID, title, description, and statement fields.

#### Batch Create Controls

| | |
|---|---|
| **Route** | `GET /control_families/:control_family_id/catalog_controls/batch_new` |
| **Controller** | `CatalogControlsController#batch_new` |
| **Auth** | Authenticated |

Multiple control rows for bulk addition to a family. Submits via `POST batch_create`.

#### Baselines List

| | |
|---|---|
| **Route** | `GET /profile_documents` |
| **Controller** | `ProfileDocumentsController#index` |
| **Auth** | Public |

Summary tiles with document and control counts. Lists all baseline profiles with name, control count, and priority heatmap. Buttons for "Create New" and "Create from Catalog".

#### Baseline Detail

| | |
|---|---|
| **Route** | `GET /profile_documents/:id` |
| **Controller** | `ProfileDocumentsController#show` |
| **Auth** | Public |

Shows the baseline profile with:
- Controls listed with priority information
- Priority heatmap grouped by NIST family
- Copy button (creates a duplicate profile)
- Export buttons: JSON, OSCAL (validated/unvalidated)
- Editable metadata via inline toggle

#### Create Baseline from Catalog

| | |
|---|---|
| **Route** | `GET /profile_documents/select_catalog` |
| **Controller** | `ProfileDocumentsController#select_catalog` |
| **Auth** | Authenticated |

Two-step flow: first select a source catalog, then choose which controls to include via a checklist interface. Submits via `POST create_from_catalog`.

#### Profile Control Edit

| | |
|---|---|
| **Routes** | `GET /profile_documents/:profile_document_id/profile_controls/:id/edit` |
| **Controller** | `ProfileControlsController#edit` |
| **Auth** | Authenticated |

Edit form for individual profile controls with control ID, title, and priority fields.

#### Control Mappings List

| | |
|---|---|
| **Route** | `GET /control_mappings` |
| **Controller** | `ControlMappingsController#index` |
| **Auth** | Public |

Lists all control mappings showing name, source catalog, target catalog, status (draft/complete/deprecated), entry count, and creation date. "Create New" button.

#### Mapping Detail

| | |
|---|---|
| **Route** | `GET /control_mappings/:id` |
| **Controller** | `ControlMappingsController#show` |
| **Auth** | Public (view), Write permission required for editing |

Two-column layout:
- **Left column**: Mapping details card -- status badge, version, method, rationale, OSCAL version, timestamps, description
- **Right column**: Catalog references card -- source and target catalogs (linked), entry count

Below the detail cards:
- **Mapping Entries table** -- columns for source control, source type, arrow indicator, target control, target type, relationship badge, remarks, and remove button (for authorized users)
- **Add Entry form row** (authorized users only) -- inline form with fields for source control ID, source type, target control ID, target type, relationship dropdown, remarks, and "Add Entry" button

Action buttons: Edit, Publish (for draft/not-complete status), Deprecate (for complete status), Export OSCAL, Back.

**Relationship types** (per NIST IR 8477): equal, equivalent, subset, superset, intersects.

#### Converters List

| | |
|---|---|
| **Route** | `GET /converters` |
| **Controller** | `ConvertersController#index` |
| **Auth** | Public (view); `converters.write` permission for mutations |

Lists rule-to-NIST converter registries (e.g. DISA CCI, AWS Config, AWS Security Hub) with name, source, entry count, and last-refresh timestamp. Buttons: "New", "Import" (`/converters/import`), and the STIG parser (`/converters/stig_parser`).

#### Converter Detail

| | |
|---|---|
| **Route** | `GET /converters/:id` |
| **Controller** | `ConvertersController#show` |
| **Auth** | Public (view); `converters.write` for mutations |

Shows the converter's mapping entries (source rule ID → NIST control IDs). Actions include Export (`GET export`), and refresh buttons that pull the latest upstream mappings: Refresh CCI (`POST refresh_cci`), Refresh AWS Config (`POST refresh_aws_config`, #494), Refresh AWS Security Hub (`POST refresh_aws_security_hub`, #494). Nested entry add/remove via `converter_entries` (`POST/DELETE /converters/:id/entries`) rendered as inline form rows.

#### Converter Create / Edit / Import / STIG Parser

| | |
|---|---|
| **Routes** | `GET /converters/new`, `GET /converters/:id/edit`, `GET /converters/import` (`POST do_import`), `GET /converters/stig_parser` (`POST import_stig`) |
| **Controller** | `ConvertersController#new`, `#edit`, `#import`, `#stig_parser` |
| **Auth** | `converters.write` |

Metadata form (name, source, description); import form accepting converter definition files; STIG parser upload that extracts rule → control mappings from a DISA STIG XCCDF file.

---

### Implementation Layer (auth required)

#### SSP List

| | |
|---|---|
| **Route** | `GET /ssp_documents` |
| **Controller** | `SspDocumentsController#index` |
| **Auth** | Required |

Summary tiles: total SSP count, total controls, completed controls.

Table columns:
| Column | Description |
|--------|-------------|
| Name | Document name (truncated with tooltip) |
| Source | Badge indicating creation method: Wizard, OSCAL Import, or File Upload (with original filename) |
| Version | SSP version string |
| Status | Completed/pending badge |
| Controls | Control count |
| OSCAL | "Enriched" or "Basic" badge |
| Created | Timestamp (`YYYY-MM-DD HH:MM`) |
| Actions | View, Enrich (if not enriched), Delete (with confirmation) |

Buttons: "Create New SSP" (links to wizard), "Upload File" (direct file upload).

#### SSP Detail

| | |
|---|---|
| **Route** | `GET /ssp_documents/:id` |
| **Controller** | `SspDocumentsController#show` |
| **Auth** | Required |

**Processing state**: If the document is not yet completed, shows either a processing spinner with auto-refresh (every 5 seconds via `<meta http-equiv="refresh">`) or a failure banner with error message.

**Completed state** displays:

1. **Header dashboard**:
   - Document type label ("System Security Plan")
   - Editable name and version (inline toggle)
   - Source filename, status, total control count
   - Compliance percentage score with color coding (green >= 80%, yellow >= 50%, red < 50%)
   - Status summary chips (clickable to filter heatmap)
   - Multi-segment progress bar showing status distribution

2. **OSCAL enrichment panels** (if enriched):
   - System Characteristics card -- description, sensitivity level, system status badges
   - Components card -- up to 5 components with type badges, "+N more" indicator
   - Users card -- up to 5 users with role information
   - If not enriched, shows a yellow prompt banner with "Enrich SSP" button

3. **Compliance heatmap** -- interactive grid by control family, color-coded by status, with URL sync for filter state

4. **Control cards** -- each card shows:
   - Control ID, status pill, type/use badge, provided-as badge, family code
   - Control title
   - Collapsible details section with:
     - Stated requirement block (highlighted)
     - Ordered field table (editable fields marked with pencil icon)
     - Inherited/provider statements (collapsible, purple-accented)
     - Catalog guidance (collapsible, reference from source catalog)
   - Edit button toggling an inline edit form with dropdowns for status, control_application, coverage_level, control_type, date picker for expected_completion, and text areas for other fields
   - Read-only fields shown in a collapsible sub-section

Export buttons: Export OSCAL, Download JSON, Enrich, Back.

#### SSP Wizard

| | |
|---|---|
| **Route** | `GET /ssp_documents/wizard`, `POST /ssp_documents/create_from_wizard` |
| **Controller** | `SspDocumentsController#wizard`, `#create_from_wizard` |
| **Auth** | Required |

Multi-step creation flow: profile/baseline selector, CDEF selector, system details form (name, version, description).

#### SSP Enrichment

| | |
|---|---|
| **Route** | `GET /ssp_documents/:id/enrich`, `PATCH /ssp_documents/:id/update_enrich` |
| **Controller** | `SspDocumentsController#enrich`, `#update_enrich` |
| **Auth** | Required |

Form for adding OSCAL-required metadata: system characteristics (description, sensitivity level, status, authorization boundary), components (title, type, description), system users (title, role IDs), and information types.

#### SSP Editor

| | |
|---|---|
| **Route** | `GET /ssp_documents/:id/editor` |
| **Controller** | `SspDocumentsController#editor` |
| **Auth** | Required |

Dedicated inline editing interface using Turbo Frames for control field updates without full page reloads.

#### CDEF List

| | |
|---|---|
| **Route** | `GET /cdef_documents` |
| **Controller** | `CdefDocumentsController#index` |
| **Auth** | Required |

Summary tiles with document and control counts. Lists all component definitions with severity heatmap visualization. "Create New" button.

#### CDEF Detail

| | |
|---|---|
| **Route** | `GET /cdef_documents/:id` |
| **Controller** | `CdefDocumentsController#show` |
| **Auth** | Required |

Controls organized by family with severity heatmap. Action buttons: Copy (duplicates the document), Export OSCAL (validated/unvalidated), Download JSON, Back. Editable metadata via inline toggle.

---

### Assessment Layer (auth required)

#### SAP List

| | |
|---|---|
| **Route** | `GET /sap_documents` |
| **Controller** | `SapDocumentsController#index` |
| **Auth** | Required |

Summary tiles. Lists all assessment plans. "Create New" button, "Upload" for JSON import.

#### SAP Detail

| | |
|---|---|
| **Route** | `GET /sap_documents/:id` |
| **Controller** | `SapDocumentsController#show` |
| **Auth** | Required |

Controls organized by family with assessment method heatmap. Editable metadata via inline toggle. Export buttons: OSCAL (validated/unvalidated), JSON.

#### SAR List

| | |
|---|---|
| **Route** | `GET /sar_documents` |
| **Controller** | `SarDocumentsController#index` |
| **Auth** | Required |

Summary tiles: total SARs, total controls, pass/fail counts. Table listing all assessment results with name, source, version, status, control count, OSCAL status, creation date, and actions. Buttons: "Create New SAR" (wizard), "Upload File".

#### SAR Detail

| | |
|---|---|
| **Route** | `GET /sar_documents/:id` |
| **Controller** | `SarDocumentsController#show` |
| **Auth** | Required |

**Processing state**: Same spinner/failure pattern as SSP with auto-refresh.

**Completed state**:

1. **Header dashboard**:
   - Document type label ("Security Assessment Results")
   - Editable name and version
   - Metadata line: filename, status, test count, section count, asset count, creation method badge, OSCAL enriched badge
   - Pass rate percentage with color coding
   - Status summary chips (clickable, link-based filtering)
   - Multi-segment progress bar

2. **Filter bar** (shown when assets/environments exist):
   - Asset dropdown selector
   - Environment pill filter bar (toggleable)

3. **Section tabs** (shown when multiple sections exist): pill-style tabs for filtering by section name, with "All" option showing total count.

4. **Active filter banner**: Shows current filter state ("Showing X of Y controls") with a "Clear All" link.

5. **Results heatmap** -- interactive grid by family, color-coded by result status. Server-side link mode for family/status filtering via URL parameters.

6. **Control cards** (paginated, 50 per page):
   - Control ID, asset tag, environment tag, result pill, working status outline badge, family code
   - Control title
   - Collapsible details with:
     - Assessment Context panel (collapsible): subject, control status, responsibility, impact statement, control text, catalog description, SSP implementation
     - Ordered field table: date, tester, notes/weakness, recommended fix, working comments, working status, coverage_level, inherited, row number
   - Edit button with inline form: result dropdown, working status dropdown, text areas for other editable fields, read-only reference fields

**Filter parameters** (all combinable): `section`, `family`, `status`, `asset`, `environment`. Pagination preserved across filters.

Export buttons: Download JSON, Download OSCAL, Enrich (if not enriched), Back.

#### SAR Wizard

| | |
|---|---|
| **Route** | `GET /sar_documents/wizard`, `POST /sar_documents/create_from_wizard` |
| **Controller** | `SarDocumentsController#wizard`, `#create_from_wizard` |
| **Auth** | Required |

SAP selector and assessment date configuration.

#### SAR Enrichment

| | |
|---|---|
| **Route** | `GET /sar_documents/:id/enrich`, `PATCH /sar_documents/:id/update_enrich` |
| **Controller** | `SarDocumentsController#enrich`, `#update_enrich` |
| **Auth** | Required |

Form for adding OSCAL assessment result metadata: results, observations, findings, and risks.

#### Evidence List

| | |
|---|---|
| **Route** | `GET /evidences` |
| **Controller** | `EvidencesController#index` |
| **Auth** | Required |

Summary tiles. Lists all evidence items with filters for type, status, authorization boundary, and associated control. Search functionality. "Upload" button for new evidence.

#### Evidence Detail

| | |
|---|---|
| **Route** | `GET /evidences/:id` |
| **Controller** | `EvidencesController#show` |
| **Auth** | Required |

File preview, linked controls, and attestation list. Actions: Edit, Delete. Nested attestation creation.

#### Attestation Create

| | |
|---|---|
| **Route** | `GET /evidences/:evidence_id/attestations/new` |
| **Controller** | `AttestationsController#new` |
| **Auth** | Required |

Form fields: attester name, date, role, attestation statement. Scoped within an evidence record.

---

### POA&M Layer (auth required)

Plans of Action & Milestones. The `PoamDocument` carries a rich set of OSCAL-extensibility child entities (#423), each with its own nested admin CRUD UI, plus a leveraging-side read-only view of leveraged-system POA&Ms (#415).

#### POA&M List

| | |
|---|---|
| **Route** | `GET /poam_documents` |
| **Controller** | `PoamDocumentsController#index` |
| **Auth** | Required |

Summary tiles with document and item counts. Lists all POA&M documents with name, item count, and creation date. "Create New" button.

#### POA&M Detail

| | |
|---|---|
| **Route** | `GET /poam_documents/:id` |
| **Controller** | `PoamDocumentsController#show` |
| **Auth** | Required |

Items displayed with pagination. Filter options for risk status and impact level. Heatmap visualization of risk distribution. Editable metadata via inline toggle. Publish/publish-check actions. Export buttons: OSCAL (validated/unvalidated), JSON, YAML, XML. Sections for each child-entity type (items, risks, remediations, observations, findings, local components) with "New" buttons linking to the nested forms below. Nested back-matter resource management.

#### POA&M Item Create / Edit

| | |
|---|---|
| **Routes** | `GET /poam_documents/:poam_document_id/poam_items/new`, `.../poam_items/:id/edit` |
| **Controller** | `PoamItemsController#new`, `#edit` |
| **Auth** | Required |

Form fields: risk ID, finding source, status, impact level, remediation plan, scheduled completion date, milestones.

#### POA&M Risk Create / Edit

| | |
|---|---|
| **Routes** | `GET /poam_documents/:poam_document_id/poam_risks/new`, `.../poam_risks/:id/edit` |
| **Controller** | `PoamRisksController#new`, `#edit` |
| **Auth** | Required |

OSCAL `risk` form: title, description, statement, status, deadline, threat/characterization fields.

#### POA&M Remediation Create / Edit (with nested Milestones)

| | |
|---|---|
| **Routes** | `GET /poam_documents/:poam_document_id/poam_remediations/new`, `.../poam_remediations/:id/edit`; nested `.../poam_remediations/:poam_remediation_id/poam_milestones/new`, `.../poam_milestones/:id/edit` |
| **Controller** | `PoamRemediationsController`, `PoamMilestonesController` |
| **Auth** | Required |

OSCAL `response` (remediation) form: lifecycle, title, description, remarks. Milestones are nested under a remediation with their own new/edit forms (title, description, target date).

#### POA&M Observation Create / Edit

| | |
|---|---|
| **Routes** | `GET /poam_documents/:poam_document_id/poam_observations/new`, `.../poam_observations/:id/edit` |
| **Controller** | `PoamObservationsController#new`, `#edit` |
| **Auth** | Required |

OSCAL `observation` form: title, description, methods, collected/expires timestamps.

#### POA&M Finding Create / Edit

| | |
|---|---|
| **Routes** | `GET /poam_documents/:poam_document_id/poam_findings/new`, `.../poam_findings/:id/edit` |
| **Controller** | `PoamFindingsController#new`, `#edit` |
| **Auth** | Required |

OSCAL `finding` form: title, description, target/objective status, related-observation and related-risk references.

#### POA&M Local Component Create / Edit

| | |
|---|---|
| **Routes** | `GET /poam_documents/:poam_document_id/poam_local_components/new`, `.../poam_local_components/:id/edit` |
| **Controller** | `PoamLocalComponentsController#new`, `#edit` |
| **Auth** | Required |

OSCAL `local-definitions` component form: type, title, description, status — components referenced by the POA&M but not defined in a linked SSP.

#### Leveraged POA&M Documents (read-only)

| | |
|---|---|
| **Routes** | `GET /leveraged_poam_documents`, `GET /leveraged_poam_documents/:id` |
| **Controller** | `LeveragedPoamDocumentsController#index`, `#show` |
| **Auth** | Required |

Leveraging-side read-only view of POA&Ms inherited from a leveraged (underlying) system (#415, Scenario A). Index lists inherited POA&Ms; detail shows their items without edit controls, since the leveraging system does not own them.

---

### Authorization Boundaries

#### Authorization Boundaries List

| | |
|---|---|
| **Route** | `GET /authorization_boundaries` |
| **Controller** | `AuthorizationBoundariesController#index` |
| **Auth** | Required |

Lists all authorization boundaries with name, description, member count. "Create New" button.

#### Authorization Boundary Detail

| | |
|---|---|
| **Route** | `GET /authorization_boundaries/:id` |
| **Controller** | `AuthorizationBoundariesController#show` |
| **Auth** | Required |

Shows authorization boundary details with:
- System boundaries (with create/edit/delete)
- Team members and their roles (with add/edit/remove)
- Artifact summary linking to associated documents

#### Boundaries

| | |
|---|---|
| **Routes** | `GET /authorization_boundaries/:authorization_boundary_id/boundaries/new`, `GET /authorization_boundaries/:authorization_boundary_id/boundaries/:id/edit` |
| **Controller** | `BoundariesController#new`, `#edit` |
| **Auth** | Required |

Form fields: name, description, environment classification.

#### Authorization Boundary Memberships

| | |
|---|---|
| **Routes** | `GET /authorization_boundaries/:authorization_boundary_id/authorization_boundary_memberships/new`, `GET /authorization_boundaries/:authorization_boundary_id/authorization_boundary_memberships/:id/edit` |
| **Controller** | `AuthorizationBoundaryMembershipsController#new`, `#edit` |
| **Auth** | Required |

Add, edit, or remove team members with role assignment via dropdown.

#### ATO Package Wizard

| | |
|---|---|
| **Routes** | `GET /authorization_boundaries/:id/ato_wizard`, `POST .../create_ato_package`, `GET .../download_ato_package` |
| **Controller** | `AuthorizationBoundariesController#ato_wizard`, `#create_ato_package`, `#download_ato_package` |
| **Auth** | Required |

Assembles an Authorization-to-Operate package (bundled SSP/SAP/SAR/POA&M/evidence artifacts) for the boundary, then offers it as a downloadable archive.

#### Leveraged Authorizations

| | |
|---|---|
| **Routes** | `GET /authorization_boundaries/:authorization_boundary_id/leveraged_authorizations/new`, `.../leveraged_authorizations/:id` (show), `POST .../leveraged_authorizations/:id/populate` |
| **Controller** | `LeveragedAuthorizationsController#new`, `#show` |
| **Auth** | Required |

Records a leveraged (inherited) authorization on the leveraging boundary (#396). New form captures the leveraged system name/ID and party; the detail view shows the leveraged authorization with a "Populate" action that pulls inherited controls/components from the underlying system. Created on the leveraging boundary, not the leveraged one.

---

### Administration (Instance Admin only)

#### Users List

| | |
|---|---|
| **Route** | `GET /admin/users` |
| **Controller** | `Admin::UsersController#index` |
| **Auth** | Instance Admin |

Search input, status filter, paginated user list (25 per page). Each row shows email, display name, status, creation date. Actions: View, Suspend/Reactivate.

#### User Detail

| | |
|---|---|
| **Route** | `GET /admin/users/:id` |
| **Controller** | `Admin::UsersController#show` |
| **Auth** | Instance Admin |

Displays:
- User identities (local, OIDC, LDAP, GitHub, GitLab)
- Instance roles assigned
- Authorization boundary roles assigned
- Recent audit events (last 50)

#### User Edit

| | |
|---|---|
| **Route** | `GET /admin/users/:id/edit` |
| **Controller** | `Admin::UsersController#edit` |
| **Auth** | Instance Admin |

Form fields: display name, instance role assignments, authorization-boundary-specific role assignments.

#### Roles List

| | |
|---|---|
| **Route** | `GET /admin/roles` |
| **Controller** | `Admin::RolesController#index` |
| **Auth** | Instance Admin |

Lists all roles with name, display name, scope (instance or authorization boundary), user count. "Create New" button.

#### Role Detail

| | |
|---|---|
| **Route** | `GET /admin/roles/:id` |
| **Controller** | `Admin::RolesController#show` |
| **Auth** | Instance Admin |

Shows assigned users and the full permission matrix for the role.

#### Role Create / Edit

| | |
|---|---|
| **Routes** | `GET /admin/roles/new`, `GET /admin/roles/:id/edit` |
| **Controller** | `Admin::RolesController#new`, `#edit` |
| **Auth** | Instance Admin |

Form fields: name, display name, scope selector (instance/authorization boundary), 20 permission checkboxes covering CRUD operations across document types and admin features.

#### Admin Authorization Boundaries List

| | |
|---|---|
| **Route** | `GET /admin/authorization_boundaries` |
| **Controller** | `Admin::AuthorizationBoundariesController#index` |
| **Auth** | Instance Admin |

Lists all authorization boundaries with member management capabilities.

#### Admin Authorization Boundary Detail

| | |
|---|---|
| **Route** | `GET /admin/authorization_boundaries/:id` |
| **Controller** | `Admin::AuthorizationBoundariesController#show` |
| **Auth** | Instance Admin |

User-role assignments table. Actions: Add member (`POST add_member`), Remove member (`DELETE remove_member`).

#### Audit Log

| | |
|---|---|
| **Route** | `GET /admin/audit_logs` |
| **Controller** | `Admin::AuditLogsController#index` |
| **Auth** | Instance Admin |

Header with event count badge and "Export CSV" button (appends `format=csv` to current filters).

**Filter panel** (card with form):

| Filter | Type | Description |
|--------|------|-------------|
| Search | Text input | Free-text search across actions and metadata |
| User | Select dropdown | Filter by specific user (populated from all users) |
| Category | Select dropdown | Filter by event category |
| Resource Type | Select dropdown | Filter by subject type (model name) |
| Date Range | Two date inputs | Start and end date range |

Buttons: "Filter" (submit), "Clear" (reset to unfiltered).

**Results table** columns:

| Column | Description |
|--------|-------------|
| Time | Timestamp (`YYYY-MM-DD HH:MM:SS`) |
| User | Email linked to admin user detail, or "(system)" |
| Action | Color-coded badge: green (created/imported), red (failure), yellow (deleted), blue (exported/copied), primary (published), secondary (other) |
| Category | Event category text |
| Subject | Humanized subject type with ID |
| IP Address | Client IP |
| (action) | "Details" link to event detail |

Pagination below the table (shown when more than one page exists).

#### Audit Event Detail

| | |
|---|---|
| **Route** | `GET /admin/audit_logs/:id` |
| **Controller** | `Admin::AuditLogsController#show` |
| **Auth** | Instance Admin |

Full event metadata display: timestamp, user, action, category, subject type and ID, IP address, user agent, and any additional stored metadata.

#### Organizations

| | |
|---|---|
| **Routes** | `GET /admin/organizations`, `…/new`, `…/:id`, `…/:id/edit` (no destroy); member ops `PATCH deactivate`/`reactivate`, `POST add_member`, `DELETE remove_member` |
| **Controller** | `Admin::OrganizationsController` |
| **Auth** | Instance Admin |

Manage organization entities (UUID-based audit traceability) for multi-org instances. Create/edit/detail plus soft deactivate/reactivate and member add/remove — organizations are never hard-deleted.

#### Service Accounts & API Tokens

| | |
|---|---|
| **Routes** | `GET /admin/service_accounts` (full CRUD); nested `POST/DELETE /admin/service_accounts/:id/api_tokens` |
| **Controller** | `Admin::ServiceAccountsController`, `Admin::ApiTokensController` |
| **Auth** | Instance Admin |

Create non-interactive automation identities and issue/revoke their `sparc_sa_<token>` Bearer tokens. The plaintext token is shown **once** on creation; only a SHA-256 digest is stored. Service accounts authenticate the REST API and can bridge to a UI session via `POST /api/v1/sessions/from_token`.

#### Data Migrations

| | |
|---|---|
| **Route** | `GET /admin/data_migrations` |
| **Controller** | `Admin::DataMigrationsController` |
| **Auth** | Instance Admin |

Status view for **deferred data migrations** (v1.8.3) — migrations that register at `db:migrate` time and run their body post-boot via a Solid Queue job. Shows each migration's state (pending / running / completed / failed) so operators can confirm a long-running backfill finished after a deploy.

---

### Trust Store & Document Workflow (auth required)

The trust store holds authoritative back-matter sources and drives the document review/approval and cross-instance federation workflows.

#### Authoritative Sources

| | |
|---|---|
| **Routes** | `GET /authoritative_sources`, `GET /authoritative_sources/:id`, `GET /authoritative_sources/new`, `POST /authoritative_sources` |
| **Controller** | `AuthoritativeSourcesController#index`, `#show`, `#new`, `#create` |
| **Auth** | Required (any authenticated user may add a source, #646) |

Library of authoritative back-matter resources (#372) usable across documents. Sources are org/boundary-scoped by default and become instance-wide via the promotion approval workflow. Index lists sources with scope; detail shows the resource and its usages; new/create adds a source.

#### Review Queue

| | |
|---|---|
| **Route** | `GET /review_queue` |
| **Controller** | `ReviewQueueController#index` |
| **Auth** | Required (reviewer permission) |

Consolidated queue of trust-store documents (Control Catalog, Baseline/Profile, CDEF) submitted for review (#630). Each row links to the underlying document's approve/reject actions (`POST submit_for_review`, `POST approve`, `POST reject` on the respective document controllers).

#### Promotion Queue

| | |
|---|---|
| **Routes** | `GET /promotion_queue`, `POST /promotion_queue/:id/approve`, `POST /promotion_queue/:id/reject` |
| **Controller** | `PromotionQueueController#index` |
| **Auth** | Required (approver permission) |

Queue of back-matter resources requesting promotion from org/boundary scope to instance-wide authoritative scope (#372). Approve/Reject actions per row.

#### Federation Peers

| | |
|---|---|
| **Routes** | `GET /federation_peers`, `GET /federation_peers/:id`, `GET /federation_peers/new`, `GET /federation_peers/:id/edit`, `POST /federation_peers/:id/sync` |
| **Controller** | `FederationPeersController` |
| **Auth** | Required (admin/federation permission) |

Manage trusted peer SPARC instances for cross-instance authoritative-source sharing (#372). List/detail/create/edit peers (name, base URL, shared-secret config); the per-peer "Sync" action exchanges HMAC-signed authoritative-source bundles with the peer.

---

### Artifacts & Back-Matter (auth required)

Durable OSCAL back-matter and evidence artifacts. Documents carry nested back-matter resources; the artifact resolver serves stable-UUID downloads.

#### Artifact Resolver

| | |
|---|---|
| **Routes** | `GET /artifacts/:uuid`, `GET /artifacts/versions/:uuid` |
| **Controller** | `ArtifactsController#show`, `#version` |
| **Auth** | Required |

No HTML screen — resolves a stable back-matter UUID to a freshly-signed download and returns a 302 redirect (#680). `versions/:uuid` resolves a specific retained content version. Referenced by durable OSCAL back-matter `href` values so links survive slug/content changes.

#### Back-Matter Resources (nested)

| | |
|---|---|
| **Routes** | `POST/PATCH/DELETE /<document>/:id/back_matter_resources/...` on `ssp_documents`, `sar_documents`, `sap_documents`, `poam_documents`, `profile_documents`, `cdef_documents`, `control_catalogs` |
| **Controller** | `BackMatterResourcesController` |
| **Auth** | Required (document write permission) |

Attach, edit, or remove OSCAL back-matter resources on a parent document, rendered as inline forms within the document detail page (no standalone index). Reusable resources can be linked from the trust store rather than re-uploaded.

#### Control Back-Matter Links (nested)

| | |
|---|---|
| **Routes** | `POST/DELETE /control_catalogs/.../catalog_controls/:catalog_control_id/control_back_matter_links/...`, and `POST/DELETE /profile_documents/:profile_document_id/profile_controls/:profile_control_id/control_back_matter_links/...` (plus a `link_resource` member action) |
| **Controller** | `ControlBackMatterLinksController` |
| **Auth** | Required (write permission) |

Inline controls (within a catalog control or profile control edit view) for linking existing back-matter resources to an individual control, or unlinking them.

#### Evidence

Evidence list/detail and attestation screens are documented under the **Assessment Layer** above (`/evidences`, `/evidences/:evidence_id/attestations`).

---

### Informational / About (public)

#### About Pages

| | |
|---|---|
| **Routes** | `GET /about`, `GET /about/api`, `GET /about/quickstart`, `GET /about/resources` |
| **Controller** | `AboutController#index`, `#api_docs`, `#quickstart`, `#resources` |
| **Auth** | Public |

Static informational pages: project overview (`/about`), REST API documentation (`/about/api`), a getting-started quickstart (`/about/quickstart`), and external OSCAL/NIST resource links (`/about/resources`).

#### OSCAL Overview

| | |
|---|---|
| **Route** | `GET /oscal-overview` |
| **Controller** | `HomeController#oscal_overview` |
| **Auth** | Public |

Standalone page explaining the OSCAL layer model (also embedded as a partial on the login page).

---

### REST API Endpoints

The API lives under the `Api::V1::` namespace. No UI screens -- these are JSON-only endpoints.

#### SSP Document API

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/ssp_documents/convert` | Upload document file, queue async parsing via `DocumentConversionJob` |
| `PUT` | `/api/v1/ssp_documents/:id/update_fields` | Bulk update control fields (JSON body) |
| `GET` | `/api/v1/ssp_documents/:id/export` | Export SSP document as JSON |

#### SAR Document API

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/sar_documents/convert` | Upload document file, queue async parsing |
| `PUT` | `/api/v1/sar_documents/:id/update_fields` | Bulk update control fields (JSON body) |
| `GET` | `/api/v1/sar_documents/:id/export` | Export SAR document as JSON |

#### Document CRUD API

`index/show/create/update/destroy` JSON CRUD is exposed for the document types below. UI screens are thin clients over these endpoints (API-first).

| Resource | Base path |
|----------|-----------|
| SSP documents | `/api/v1/ssp_documents` (+ `POST populate_from_profile`) |
| SAR documents | `/api/v1/sar_documents` |
| SAP documents | `/api/v1/sap_documents` |
| POA&M documents | `/api/v1/poam_documents` |
| Control catalogs | `/api/v1/control_catalogs` (+ review workflow) |
| Baselines/profiles | `/api/v1/profile_documents` (+ review workflow, nested `parameters`) |
| CDEF documents | `/api/v1/cdef_documents` (+ `DELETE bulk`, bulk-apply-converter, review workflow) |
| Control mappings | `/api/v1/control_mappings` |
| Users | `/api/v1/users` |
| Authorization boundaries | `/api/v1/authorization_boundaries` (+ `DELETE bulk`, nested `ksi_validations`) |
| Federation peers | `/api/v1/federation_peers` (+ `POST :id/sync`) |

#### Trust Store / Federation API

| Method | Endpoint | Description |
|--------|----------|-------------|
| various | `/api/v1/back_matter_resources` | Back-matter CRUD + `link`/`unlink`/`promote`/`approve_promotion`/`reject_promotion`/`archive`/`restore`/`changes`, plus `promotion_queue` and `bulk` (#375/#372) |
| `POST` | `/api/v1/authoritative_sources` | Add a library source (#646) |
| `GET/POST` | `/api/v1/authoritative_sources/export|import` | Signed-bundle federation exchange (peer via `peer` param, #372) |

#### KSI Catalog & Validation API (#107)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/ksi_catalog/themes|indicators|indicators/:id|mappings` | Read-only FedRAMP 20x KSI catalog |
| various | `/api/v1/authorization_boundaries/:id/ksi_validations` | Per-boundary KSI validation tracking CRUD + `summary`/`export` |

#### Translation Bridge API (#449)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/oscal/sar_from_hdf` | HDF → OSCAL SAR |
| `POST` | `/api/v1/oscal/poam_from_hdf` | HDF → OSCAL POA&M |
| `POST` | `/api/v1/oscal/poam_from_amendments` | HDF amendments → OSCAL POA&M (#663) |
| `POST` | `/api/v1/hdf/amendments_from_oscal_poam` | OSCAL POA&M → HDF amendments |

#### Evidence, Artifacts, Discovery & Session Bridge API

| Method | Endpoint | Description |
|--------|----------|-------------|
| various | `/api/v1/evidences/:evidence_id/attestations` | Attestation records + `export` (CMS schema, #440) |
| `GET` | `/api/v1/artifacts/:uuid` | Durable UUID → signed download URL (#680) |
| `GET` | `/api/v1/artifacts/:uuid/versions|freshness` | Version timeline + review-cadence freshness data (#685) |
| `GET` | `/api/v1/available` | API discovery / endpoint listing (#250) |
| `POST` | `/api/v1/sessions/from_token` | Bearer-token → Rails session cookie bridge for UI test runners (#573) |
| `POST` | `/api/v1/admin/refresh_credentials` | Admin password rotation receiver (sparc-iac, #403) |

---

## Common UI Patterns

### Heatmaps

Rendered via the shared `_heatmap.html.erb` partial. Configuration is passed via locals:

| Parameter | Purpose |
|-----------|---------|
| `heatmap_data` | Hash of `{ family => { status => count } }` |
| `heatmap_families` | Ordered array of family codes |
| `heatmap_statuses` | Ordered array of status values |
| `title` | Grid title text |
| `color_helper` | Symbol for the color method (`:ssp_status_color`, `:sar_status_color`) |
| `filter_key` | URL parameter name for filtering |
| `legend_items` | Array of `[label, color]` pairs |
| `show_percentage` | Boolean to display percentage in cells |
| `family_url_builder` | Lambda for generating family drill-down URLs |
| `link_mode` | `:server` for server-side filtering via links, or client-side JS |

Heatmaps appear on: Dashboard (aggregate), SSP detail, SAR detail, SAP detail, CDEF detail, Baseline detail, POA&M detail.

### Summary Tiles

Rendered via the shared `_section_summary.html.erb` partial. Each section index page shows 2-4 compact statistic tiles at the top (e.g., document count, control count, completed count).

### Turbo Frames

Used for inline editing of control fields in SSP and SAR detail views. The edit/view toggle is handled via vanilla JavaScript (`toggleEdit()` function) rather than Turbo Frame replacement, but the SSP editor view (`/ssp_documents/:id/editor`) uses full Turbo Frame-based field updates.

### Status Polling

Documents uploaded via file go through async processing:
1. Initial state: `pending`
2. Background job picks up: `processing`
3. Completion: `completed` or `failed`

The detail view uses `<meta http-equiv="refresh" content="5">` for auto-polling every 5 seconds until the document reaches a terminal state. The processing banner shows a CSS spinner animation and the original filename.

### OSCAL Metadata Section

Rendered via `_oscal_metadata_section.html.erb` partial at the bottom of document detail pages. Provides editable OSCAL-specific metadata fields (title, version, last-modified, etc.) with inline edit toggle.

### Dark Mode

Implemented via Bootstrap 5.3 `data-bs-theme` attribute on the `<html>` element:

1. **Initial load**: A synchronous `<script>` in `<head>` checks `localStorage.getItem("sparc-theme")` to prevent flash of unstyled content (FOUC). Falls back to `prefers-color-scheme` media query.
2. **Toggle**: A Stimulus controller (`theme`) bound to the navbar button toggles between `light` and `dark`, persisting the choice to `localStorage`.
3. **Styling**: Uses Bootstrap's built-in dark mode CSS variables plus custom `sparc-theme.css` overrides.

### Flash Notifications

Fixed-position overlay in the top-right corner. Managed by a `flash` Stimulus controller that auto-dismisses messages after a timeout. Supports dismissal via close button (`data-action="click->flash#dismiss"`).

---

## Related Issues and Pull Requests

| Reference | Description |
|-----------|-------------|
| PR #104 | Restructured login page, added OSCAL overview section (#90, #102) |
| PR #113 | Rebranded Controls Implementation to System Security Plan (#97) |
| PR #115 | Summary tiles across all index sections |
| PR #82 | Interactive heat maps by NIST family |
| Issue #81 | Interactive heat maps |
| Issue #83 | Dashboard aggregate heatmap |
| Issue #85 | Dark mode |
| Issue #87 | Responsive SPARC logo |
| PR #121 | Audit log with CSV export |
| Issue #423 | POA&M child entities (risks, remediations, milestones, observations, findings, local components) |
| Issue #415 | Leveraged-system POA&M inheritance (read-only leveraged POA&M views) |
| Issue #396 | Leveraged authorizations on the leveraging boundary |
| Issue #372 | Authoritative back-matter library + federation peers |
| Issue #646 | Any authenticated user can add an authoritative source |
| Issues #630–#634 | Review queue + document approval workflow (Catalog/Profile/CDEF) |
| Issue #680 / #685 | Durable artifact resolver + review-cadence freshness |
| Issue #494 / #499 | AWS Config / Security Hub converters + bulk-apply |
| Issue #107 | FedRAMP 20x KSI catalog + validation tracking |
| Issue #449 | HDF ↔ OSCAL translation bridge |
