# Screens & UI Reference

This page provides a comprehensive inventory of every screen in the SPARC application, organized by the OSCAL layer structure. Each section includes route paths, access requirements, and key UI elements.

---

## Navigation Structure

The application uses a dark sticky navbar (`navbar-dark bg-dark sticky-top`) that adapts based on authentication state.

| Position | Element | Visibility | Details |
|----------|---------|------------|---------|
| Left | SPARC logo | Always | Responsive SVG logo linked to root path |
| Left | Version badge | Always | `v3.4.0` secondary badge |
| Center-Right | Home | Always | Nav link to `/` |
| Center-Right | Controls dropdown (blue) | Always | Control Catalogs, Baselines, Mappings |
| Center-Right | Implementation dropdown (green) | Auth required | System Security Plans, Component Definitions |
| Center-Right | Assessment dropdown (orange) | Auth required | Assessment Plans, Assessment Results, Evidence, POA&Ms |
| Center-Right | Projects | Auth required | Standalone nav link |
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
  - Projects -- `/admin/projects`
  - Audit Log -- `/admin/audit_logs`
- **Sign Out** -- `DELETE /logout`

### Controls Dropdown Items

| Item | Route | Icon |
|------|-------|------|
| Control Catalogs | `/control_catalogs` | Book |
| Baselines | `/profile_documents` | Clipboard |
| Mappings | `/control_mappings` | Arrows |

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
- **OSCAL Overview section**: Rendered via the `sessions/_oscal_overview` partial below the login form.
- **No Auth State**: If no authentication methods are configured, displays a message directing to `ENVIRONMENT_VARIABLES.md`.

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

1. **Statistics Tiles** -- A gradient header card with a responsive grid (up to 10 columns on large screens) showing counts for: Catalogs, Families, Controls, Projects, Baselines, CDEFs, SSPs, SAPs, SARs, POA&Ms, and Evidence.

2. **Aggregate Compliance Heatmap** -- An interactive heatmap showing compliance status across all SSPs, grouped by NIST control family. Uses `ssp_status_color` helper for color coding. Families are clickable, linking to the family drilldown view.

3. **Section Navigation Grid** -- A card grid (5 columns on large screens) with "View" and "New" buttons for each major document type: Projects, Control Catalogs, Baselines, CDEFs, SSPs, SAPs, SARs, POA&Ms, and Evidence.

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
| Source | Badge indicating creation method: Wizard, OSCAL Import, or Excel (with original filename) |
| Version | SSP version string |
| Status | Completed/pending badge |
| Controls | Control count |
| OSCAL | "Enriched" or "Basic" badge |
| Created | Timestamp (`YYYY-MM-DD HH:MM`) |
| Actions | View, Enrich (if not enriched), Delete (with confirmation) |

Buttons: "Create New SSP" (links to wizard), "Upload File" (direct Excel upload).

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

Export buttons: Download Excel, Download JSON, Download OSCAL, Enrich (if not enriched), Back.

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

Summary tiles. Lists all evidence items with filters for type, status, project, and associated control. Search functionality. "Upload" button for new evidence.

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

Items displayed with pagination. Filter options for risk status and impact level. Heatmap visualization of risk distribution. Editable metadata via inline toggle. Export buttons: OSCAL (validated/unvalidated), JSON. Nested POA&M item creation.

#### POA&M Item Create / Edit

| | |
|---|---|
| **Routes** | `GET /poam_documents/:poam_document_id/poam_items/new`, `GET /poam_documents/:poam_document_id/poam_items/:id/edit` |
| **Controller** | `PoamItemsController#new`, `#edit` |
| **Auth** | Required |

Form fields: risk ID, finding source, status, impact level, remediation plan, scheduled completion date, milestones.

---

### Projects

#### Projects List

| | |
|---|---|
| **Route** | `GET /projects` |
| **Controller** | `ProjectsController#index` |
| **Auth** | Required |

Lists all projects with name, description, member count. "Create New" button.

#### Project Detail

| | |
|---|---|
| **Route** | `GET /projects/:id` |
| **Controller** | `ProjectsController#show` |
| **Auth** | Required |

Shows project details with:
- System boundaries (with create/edit/delete)
- Team members and their roles (with add/edit/remove)
- Artifact summary linking to associated documents

#### Boundaries

| | |
|---|---|
| **Routes** | `GET /projects/:project_id/boundaries/new`, `GET /projects/:project_id/boundaries/:id/edit` |
| **Controller** | `BoundariesController#new`, `#edit` |
| **Auth** | Required |

Form fields: name, description, environment classification.

#### Project Memberships

| | |
|---|---|
| **Routes** | `GET /projects/:project_id/project_memberships/new`, `GET /projects/:project_id/project_memberships/:id/edit` |
| **Controller** | `ProjectMembershipsController#new`, `#edit` |
| **Auth** | Required |

Add, edit, or remove team members with role assignment via dropdown.

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
- Project roles assigned
- Recent audit events (last 50)

#### User Edit

| | |
|---|---|
| **Route** | `GET /admin/users/:id/edit` |
| **Controller** | `Admin::UsersController#edit` |
| **Auth** | Instance Admin |

Form fields: display name, instance role assignments, project-specific role assignments.

#### Roles List

| | |
|---|---|
| **Route** | `GET /admin/roles` |
| **Controller** | `Admin::RolesController#index` |
| **Auth** | Instance Admin |

Lists all roles with name, display name, scope (instance or project), user count. "Create New" button.

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

Form fields: name, display name, scope selector (instance/project), 20 permission checkboxes covering CRUD operations across document types and admin features.

#### Admin Projects List

| | |
|---|---|
| **Route** | `GET /admin/projects` |
| **Controller** | `Admin::ProjectsController#index` |
| **Auth** | Instance Admin |

Lists all projects with member management capabilities.

#### Admin Project Detail

| | |
|---|---|
| **Route** | `GET /admin/projects/:id` |
| **Controller** | `Admin::ProjectsController#show` |
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

---

### REST API Endpoints

The API lives under the `Api::V1::` namespace. No UI screens -- these are JSON-only endpoints.

#### SSP Document API

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/ssp_documents/convert` | Upload Excel workbook, queue async parsing via `DocumentConversionJob` |
| `PUT` | `/api/v1/ssp_documents/:id/update_fields` | Bulk update control fields (JSON body) |
| `GET` | `/api/v1/ssp_documents/:id/export` | Export SSP document as JSON |

#### SAR Document API

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/sar_documents/convert` | Upload Excel workbook, queue async parsing |
| `PUT` | `/api/v1/sar_documents/:id/update_fields` | Bulk update control fields (JSON body) |
| `GET` | `/api/v1/sar_documents/:id/export` | Export SAR document as JSON |

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

Documents uploaded via Excel go through async processing:
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
