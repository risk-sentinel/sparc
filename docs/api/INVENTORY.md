<!-- markdownlint-disable MD013 MD024 MD032 MD033 -->

# SPARC API Inventory

Authoritative cross-reference between SPARC's `/api/v1/` routes (as defined in code), per-endpoint markdown documentation under `docs/api/endpoints/`, and the Postman collection at `docs/api/sparc-api.postman_collection.json`.

This file is the work-tracking spine for issue [#413](https://github.com/Rebel-Raiders/sparc/issues/413). Phase 1 work closes "**MISSING**" rows below; Phase 2 will add a parallel column for "covered by Python pytest suite" once that suite lands on `sparc-api-automated-testing-phase2`.

## Summary (as of 2026-04-29)

- **Code:** 95 logical endpoints across 18 controller groups (PATCH+PUT aliases collapsed)
- **Documentation:** 75 / 95 endpoints documented in `endpoints/*.md` (79%)
  - 11 endpoints missing from the doc file that should cover them
  - 9 endpoints with no doc file at all (3 controller groups)
- **Postman collection:** 49 / 95 endpoints in collection (52%)
  - 46 endpoints not in the collection
  - 6 controller groups missing from the collection entirely

### Phase 1 gap summary

#### Doc files needed (3 new files / 9 endpoints)

| Controller | Endpoints | Origin |
|---|---|---|
| `admin/credentials` | 1 | #402/#403 admin credential rotation |
| `authoritative_sources` | 2 | #372 federation export/import |
| `federation_peers` | 6 | #372 federation peer registry |

#### Existing doc files needing updates (5 files / 11 endpoints)

| Doc file | Missing endpoints | Origin |
|---|---|---|
| `back-matter-resources.md` | `approve_promotion`, `archive`, `changes`, `promote`, `reject_promotion`, `restore`, `bulk`, `promotion_queue` (8) | #372 promotion workflow |
| `ssp-documents.md` | `update_fields` (1) | bulk-field-edit feature |
| `sar-documents.md` | `update_fields` (1) | bulk-field-edit feature |
| `ksi-validations.md` | nested `DELETE` (1) | nested-route detail |

#### Postman gaps by controller (46 endpoints)

| Controller | Missing | Notes |
|---|---|---|
| `back_matter_resources` | 15 | Folder absent from collection entirely |
| `ksi_validations` | 7 | Folder absent from collection entirely |
| `federation_peers` | 6 | New controller |
| `users` | 5 | Folder absent from collection entirely |
| `authorization_boundaries` | 5 | Folder absent from collection entirely |
| `baseline_parameters` | 3 | Folder absent from collection entirely |
| `authoritative_sources` | 2 | New controller |
| `ssp_documents` | 1 | `update_fields` |
| `sar_documents` | 1 | `update_fields` |
| `admin/credentials` | 1 | New controller |

### Validation

Generated from a script that cross-references `bin/rails routes`, every `docs/api/endpoints/*.md`, and every item in `sparc-api.postman_collection.json`. The procedure is documented in [`SPARC-API-Review-and-Automated-Testing-Procedure.md`](SPARC-API-Review-and-Automated-Testing-Procedure.md). Re-running the procedure on a future commit will detect drift.

---

## Full inventory

One row per logical endpoint (PATCH/PUT aliases collapsed; nested routes shown with their full path). Sorted by controller, then path, then method.

| Method | Path | Controller#action | In `endpoints/*.md` | In Postman collection |
|--------|------|-------------------|---------------------|------------------------|
| `POST` | `/api/v1/admin/refresh_credentials` | `admin/credentials#refresh` | NO (no doc file) | **MISSING** |
| `GET` | `/api/v1/authoritative_sources/export` | `authoritative_sources#export` | NO (no doc file) | **MISSING** |
| `POST` | `/api/v1/authoritative_sources/import` | `authoritative_sources#import` | NO (no doc file) | **MISSING** |
| `GET` | `/api/v1/authorization_boundaries` | `authorization_boundaries#index` | yes | **MISSING** |
| `POST` | `/api/v1/authorization_boundaries` | `authorization_boundaries#create` | yes | **MISSING** |
| `DELETE` | `/api/v1/authorization_boundaries/:id` | `authorization_boundaries#destroy` | yes | **MISSING** |
| `GET` | `/api/v1/authorization_boundaries/:id` | `authorization_boundaries#show` | yes | **MISSING** |
| `PATCH/PUT` | `/api/v1/authorization_boundaries/:id` | `authorization_boundaries#update` | yes | **MISSING** |
| `GET` | `/api/v1/back_matter_resources` | `back_matter_resources#index` | yes | **MISSING** |
| `POST` | `/api/v1/back_matter_resources` | `back_matter_resources#create` | yes | **MISSING** |
| `DELETE` | `/api/v1/back_matter_resources/:id` | `back_matter_resources#destroy` | yes | **MISSING** |
| `GET` | `/api/v1/back_matter_resources/:id` | `back_matter_resources#show` | yes | **MISSING** |
| `PATCH/PUT` | `/api/v1/back_matter_resources/:id` | `back_matter_resources#update` | yes | **MISSING** |
| `POST` | `/api/v1/back_matter_resources/:id/approve_promotion` | `back_matter_resources#approve_promotion` | **MISSING** | **MISSING** |
| `POST` | `/api/v1/back_matter_resources/:id/archive` | `back_matter_resources#archive` | **MISSING** | **MISSING** |
| `GET` | `/api/v1/back_matter_resources/:id/changes` | `back_matter_resources#changes` | **MISSING** | **MISSING** |
| `POST` | `/api/v1/back_matter_resources/:id/link` | `back_matter_resources#link` | yes | **MISSING** |
| `POST` | `/api/v1/back_matter_resources/:id/promote` | `back_matter_resources#promote` | **MISSING** | **MISSING** |
| `POST` | `/api/v1/back_matter_resources/:id/reject_promotion` | `back_matter_resources#reject_promotion` | **MISSING** | **MISSING** |
| `POST` | `/api/v1/back_matter_resources/:id/restore` | `back_matter_resources#restore` | **MISSING** | **MISSING** |
| `DELETE` | `/api/v1/back_matter_resources/:id/unlink` | `back_matter_resources#unlink` | yes | **MISSING** |
| `POST` | `/api/v1/back_matter_resources/bulk` | `back_matter_resources#bulk` | **MISSING** | **MISSING** |
| `GET` | `/api/v1/back_matter_resources/promotion_queue` | `back_matter_resources#promotion_queue` | **MISSING** | **MISSING** |
| `GET` | `/api/v1/profile_documents/:profile_document_id/parameters` | `baseline_parameters#show` | yes | **MISSING** |
| `PATCH/PUT` | `/api/v1/profile_documents/:profile_document_id/parameters` | `baseline_parameters#update` | yes | **MISSING** |
| `GET` | `/api/v1/profile_documents/:profile_document_id/parameters/export` | `baseline_parameters#export` | yes | **MISSING** |
| `GET` | `/api/v1/cdef_documents` | `cdef_documents#index` | yes | yes |
| `POST` | `/api/v1/cdef_documents` | `cdef_documents#create` | yes | yes |
| `DELETE` | `/api/v1/cdef_documents/:id` | `cdef_documents#destroy` | yes | yes |
| `GET` | `/api/v1/cdef_documents/:id` | `cdef_documents#show` | yes | yes |
| `PATCH/PUT` | `/api/v1/cdef_documents/:id` | `cdef_documents#update` | yes | yes |
| `GET` | `/api/v1/control_catalogs` | `control_catalogs#index` | yes | yes |
| `POST` | `/api/v1/control_catalogs` | `control_catalogs#create` | yes | yes |
| `DELETE` | `/api/v1/control_catalogs/:id` | `control_catalogs#destroy` | yes | yes |
| `GET` | `/api/v1/control_catalogs/:id` | `control_catalogs#show` | yes | yes |
| `PATCH/PUT` | `/api/v1/control_catalogs/:id` | `control_catalogs#update` | yes | yes |
| `GET` | `/api/v1/control_mappings` | `control_mappings#index` | yes | yes |
| `POST` | `/api/v1/control_mappings` | `control_mappings#create` | yes | yes |
| `DELETE` | `/api/v1/control_mappings/:id` | `control_mappings#destroy` | yes | yes |
| `GET` | `/api/v1/control_mappings/:id` | `control_mappings#show` | yes | yes |
| `PATCH/PUT` | `/api/v1/control_mappings/:id` | `control_mappings#update` | yes | yes |
| `GET` | `/api/v1/available` | `discovery#available` | yes | yes |
| `GET` | `/api/v1/federation_peers` | `federation_peers#index` | NO (no doc file) | **MISSING** |
| `POST` | `/api/v1/federation_peers` | `federation_peers#create` | NO (no doc file) | **MISSING** |
| `DELETE` | `/api/v1/federation_peers/:id` | `federation_peers#destroy` | NO (no doc file) | **MISSING** |
| `GET` | `/api/v1/federation_peers/:id` | `federation_peers#show` | NO (no doc file) | **MISSING** |
| `PATCH/PUT` | `/api/v1/federation_peers/:id` | `federation_peers#update` | NO (no doc file) | **MISSING** |
| `POST` | `/api/v1/federation_peers/:id/sync` | `federation_peers#sync` | NO (no doc file) | **MISSING** |
| `GET` | `/api/v1/ksi_catalog/indicators` | `ksi_catalog#indicators` | yes | yes |
| `GET` | `/api/v1/ksi_catalog/indicators/:id` | `ksi_catalog#show_indicator` | yes | yes |
| `GET` | `/api/v1/ksi_catalog/mappings` | `ksi_catalog#mappings` | yes | yes |
| `GET` | `/api/v1/ksi_catalog/themes` | `ksi_catalog#themes` | yes | yes |
| `GET` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations` | `ksi_validations#index` | yes | **MISSING** |
| `POST` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations` | `ksi_validations#create` | yes | **MISSING** |
| `DELETE` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/:id` | `ksi_validations#destroy` | **MISSING** | **MISSING** |
| `GET` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/:id` | `ksi_validations#show` | yes | **MISSING** |
| `PATCH/PUT` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/:id` | `ksi_validations#update` | yes | **MISSING** |
| `GET` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/export` | `ksi_validations#export` | yes | **MISSING** |
| `GET` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/summary` | `ksi_validations#summary` | yes | **MISSING** |
| `GET` | `/api/v1/poam_documents` | `poam_documents#index` | yes | yes |
| `POST` | `/api/v1/poam_documents` | `poam_documents#create` | yes | yes |
| `DELETE` | `/api/v1/poam_documents/:id` | `poam_documents#destroy` | yes | yes |
| `GET` | `/api/v1/poam_documents/:id` | `poam_documents#show` | yes | yes |
| `PATCH/PUT` | `/api/v1/poam_documents/:id` | `poam_documents#update` | yes | yes |
| `GET` | `/api/v1/profile_documents` | `profile_documents#index` | yes | yes |
| `POST` | `/api/v1/profile_documents` | `profile_documents#create` | yes | yes |
| `DELETE` | `/api/v1/profile_documents/:id` | `profile_documents#destroy` | yes | yes |
| `GET` | `/api/v1/profile_documents/:id` | `profile_documents#show` | yes | yes |
| `PATCH/PUT` | `/api/v1/profile_documents/:id` | `profile_documents#update` | yes | yes |
| `GET` | `/api/v1/sap_documents` | `sap_documents#index` | yes | yes |
| `POST` | `/api/v1/sap_documents` | `sap_documents#create` | yes | yes |
| `DELETE` | `/api/v1/sap_documents/:id` | `sap_documents#destroy` | yes | yes |
| `GET` | `/api/v1/sap_documents/:id` | `sap_documents#show` | yes | yes |
| `PATCH/PUT` | `/api/v1/sap_documents/:id` | `sap_documents#update` | yes | yes |
| `GET` | `/api/v1/sar_documents` | `sar_documents#index` | yes | yes |
| `POST` | `/api/v1/sar_documents` | `sar_documents#create` | yes | yes |
| `DELETE` | `/api/v1/sar_documents/:id` | `sar_documents#destroy` | yes | yes |
| `GET` | `/api/v1/sar_documents/:id` | `sar_documents#show` | yes | yes |
| `PATCH/PUT` | `/api/v1/sar_documents/:id` | `sar_documents#update` | yes | yes |
| `GET` | `/api/v1/sar_documents/:id/export` | `sar_documents#export` | yes | yes |
| `PUT` | `/api/v1/sar_documents/:id/update_fields` | `sar_documents#update_fields` | **MISSING** | **MISSING** |
| `POST` | `/api/v1/sar_documents/convert` | `sar_documents#convert` | yes | yes |
| `GET` | `/api/v1/ssp_documents` | `ssp_documents#index` | yes | yes |
| `POST` | `/api/v1/ssp_documents` | `ssp_documents#create` | yes | yes |
| `DELETE` | `/api/v1/ssp_documents/:id` | `ssp_documents#destroy` | yes | yes |
| `GET` | `/api/v1/ssp_documents/:id` | `ssp_documents#show` | yes | yes |
| `PATCH/PUT` | `/api/v1/ssp_documents/:id` | `ssp_documents#update` | yes | yes |
| `GET` | `/api/v1/ssp_documents/:id/export` | `ssp_documents#export` | yes | yes |
| `PUT` | `/api/v1/ssp_documents/:id/update_fields` | `ssp_documents#update_fields` | **MISSING** | **MISSING** |
| `POST` | `/api/v1/ssp_documents/convert` | `ssp_documents#convert` | yes | yes |
| `GET` | `/api/v1/users` | `users#index` | yes | **MISSING** |
| `POST` | `/api/v1/users` | `users#create` | yes | **MISSING** |
| `DELETE` | `/api/v1/users/:id` | `users#destroy` | yes | **MISSING** |
| `GET` | `/api/v1/users/:id` | `users#show` | yes | **MISSING** |
| `PATCH/PUT` | `/api/v1/users/:id` | `users#update` | yes | **MISSING** |

