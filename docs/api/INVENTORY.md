<!-- markdownlint-disable MD013 MD024 MD032 MD033 -->

# SPARC API Inventory

Authoritative cross-reference between SPARC's `/api/v1/` routes (as defined in code), per-endpoint markdown documentation under `docs/api/endpoints/`, and the Postman collection at `docs/api/sparc-api.postman_collection.json`.

This file is the work-tracking spine for issue [#413](https://github.com/risk-sentinel/sparc/issues/413). Phase 1 work closes "**MISSING**" rows below; Phase 2 will add a parallel column for "covered by Python pytest suite" once that suite lands on `sparc-api-automated-testing-phase2`.

## Summary (as of 2026-04-30)

- **Code:** 95 logical endpoints across 18 controller groups (PATCH+PUT aliases collapsed)
- **Documentation:** **95 / 95 endpoints documented** in `endpoints/*.md` (**100%**) ✅
- **Postman collection:** **95 / 95 endpoints covered** (**100%**) ✅
  - 99 individual requests — PATCH/PUT update aliases each get their own request
  - 18 folders, mirroring the controller groups
- **Pytest suite:** **95 / 95 endpoints covered** by `tests/api/` (**100%**) ✅
  - 247 tests across 18 test modules — one module per controller group
  - Coverage classes: happy / auth / authz / validation / pagination / idempotency

### Phase status

**Both Phase 1 and Phase 2 are complete.** `bin/api_inventory_check.rb --check` exits 0 against this commit — every code route has per-endpoint documentation, at least one Postman collection entry, and at least one pytest test class.

The remaining open Phase 1 item is the 30% independent validation pass against this stable inventory + suite — a separate review activity.

#### Doc files needed (3 new files / 9 endpoints) — ✅ closed 2026-04-29

| Controller | Endpoints | Origin | Doc file |
|---|---|---|---|
| `admin/credentials` | 1 | #402/#403 admin credential rotation | [`admin-credentials.md`](endpoints/admin-credentials.md) |
| `authoritative_sources` | 2 | #372 federation export/import | [`authoritative-sources.md`](endpoints/authoritative-sources.md) |
| `federation_peers` | 6 | #372 federation peer registry | [`federation-peers.md`](endpoints/federation-peers.md) |

#### Existing doc files updated — ✅ closed 2026-04-29

| Doc file | Endpoints added |
|---|---|
| `back-matter-resources.md` | `approve_promotion`, `archive`, `changes`, `promote`, `reject_promotion`, `restore`, `bulk`, `promotion_queue` (8) |
| `ssp-documents.md` | `update_fields` (1) |
| `sar-documents.md` | `update_fields` (1) |
| `ksi-validations.md` | overview-table paths normalized to full nested form so the inventory script and human readers see the same identifier (1) |

#### Postman gaps closed — ✅ closed 2026-04-29

| Folder added or extended | Requests added |
|---|---|
| Admin Credentials (new) | 1 |
| Authoritative Sources (new) | 2 |
| Authorization Boundaries (new) | 5 |
| Back-Matter Resources (new) | 15 |
| Baseline Parameters (new) | 3 |
| Federation Peers (new) | 6 |
| KSI Validations (new) | 7 |
| Users (new) | 5 |
| SSP Documents (existing, +1) | `update_fields` |
| SAR Documents (existing, +1) | `update_fields` |

### Validation

Generated from a script that cross-references `bin/rails routes`, every `docs/api/endpoints/*.md`, and every item in `sparc-api.postman_collection.json`. The procedure is documented in [`SPARC-API-Review-and-Automated-Testing-Procedure.md`](SPARC-API-Review-and-Automated-Testing-Procedure.md). Re-running the procedure on a future commit will detect drift.

---

## Full inventory

One row per logical endpoint (PATCH/PUT aliases collapsed; nested routes shown with their full path). Sorted by controller, then path, then method.

| Method | Path | Controller#action | In `endpoints/*.md` | In Postman collection | Covered by pytest |
|--------|------|-------------------|---------------------|------------------------|-------------------|
| `POST` | `/api/v1/admin/refresh_credentials` | `admin/credentials#refresh` | yes | yes | yes |
| `GET` | `/api/v1/authoritative_sources/export` | `authoritative_sources#export` | yes | yes | yes |
| `POST` | `/api/v1/authoritative_sources/import` | `authoritative_sources#import` | yes | yes | yes |
| `GET` | `/api/v1/authorization_boundaries` | `authorization_boundaries#index` | yes | yes | yes |
| `POST` | `/api/v1/authorization_boundaries` | `authorization_boundaries#create` | yes | yes | yes |
| `DELETE` | `/api/v1/authorization_boundaries/:id` | `authorization_boundaries#destroy` | yes | yes | yes |
| `GET` | `/api/v1/authorization_boundaries/:id` | `authorization_boundaries#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/authorization_boundaries/:id` | `authorization_boundaries#update` | yes | yes | yes |
| `GET` | `/api/v1/back_matter_resources` | `back_matter_resources#index` | yes | yes | yes |
| `POST` | `/api/v1/back_matter_resources` | `back_matter_resources#create` | yes | yes | yes |
| `DELETE` | `/api/v1/back_matter_resources/:id` | `back_matter_resources#destroy` | yes | yes | yes |
| `GET` | `/api/v1/back_matter_resources/:id` | `back_matter_resources#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/back_matter_resources/:id` | `back_matter_resources#update` | yes | yes | yes |
| `POST` | `/api/v1/back_matter_resources/:id/approve_promotion` | `back_matter_resources#approve_promotion` | yes | yes | yes |
| `POST` | `/api/v1/back_matter_resources/:id/archive` | `back_matter_resources#archive` | yes | yes | yes |
| `GET` | `/api/v1/back_matter_resources/:id/changes` | `back_matter_resources#changes` | yes | yes | yes |
| `POST` | `/api/v1/back_matter_resources/:id/link` | `back_matter_resources#link` | yes | yes | yes |
| `POST` | `/api/v1/back_matter_resources/:id/promote` | `back_matter_resources#promote` | yes | yes | yes |
| `POST` | `/api/v1/back_matter_resources/:id/reject_promotion` | `back_matter_resources#reject_promotion` | yes | yes | yes |
| `POST` | `/api/v1/back_matter_resources/:id/restore` | `back_matter_resources#restore` | yes | yes | yes |
| `DELETE` | `/api/v1/back_matter_resources/:id/unlink` | `back_matter_resources#unlink` | yes | yes | yes |
| `POST` | `/api/v1/back_matter_resources/bulk` | `back_matter_resources#bulk` | yes | yes | yes |
| `GET` | `/api/v1/back_matter_resources/promotion_queue` | `back_matter_resources#promotion_queue` | yes | yes | yes |
| `GET` | `/api/v1/profile_documents/:profile_document_id/parameters` | `baseline_parameters#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/profile_documents/:profile_document_id/parameters` | `baseline_parameters#update` | yes | yes | yes |
| `GET` | `/api/v1/profile_documents/:profile_document_id/parameters/export` | `baseline_parameters#export` | yes | yes | yes |
| `GET` | `/api/v1/cdef_documents` | `cdef_documents#index` | yes | yes | yes |
| `POST` | `/api/v1/cdef_documents` | `cdef_documents#create` | yes | yes | yes |
| `DELETE` | `/api/v1/cdef_documents/:id` | `cdef_documents#destroy` | yes | yes | yes |
| `GET` | `/api/v1/cdef_documents/:id` | `cdef_documents#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/cdef_documents/:id` | `cdef_documents#update` | yes | yes | yes |
| `GET` | `/api/v1/control_catalogs` | `control_catalogs#index` | yes | yes | yes |
| `POST` | `/api/v1/control_catalogs` | `control_catalogs#create` | yes | yes | yes |
| `DELETE` | `/api/v1/control_catalogs/:id` | `control_catalogs#destroy` | yes | yes | yes |
| `GET` | `/api/v1/control_catalogs/:id` | `control_catalogs#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/control_catalogs/:id` | `control_catalogs#update` | yes | yes | yes |
| `GET` | `/api/v1/control_mappings` | `control_mappings#index` | yes | yes | yes |
| `POST` | `/api/v1/control_mappings` | `control_mappings#create` | yes | yes | yes |
| `DELETE` | `/api/v1/control_mappings/:id` | `control_mappings#destroy` | yes | yes | yes |
| `GET` | `/api/v1/control_mappings/:id` | `control_mappings#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/control_mappings/:id` | `control_mappings#update` | yes | yes | yes |
| `GET` | `/api/v1/available` | `discovery#available` | yes | yes | yes |
| `GET` | `/api/v1/federation_peers` | `federation_peers#index` | yes | yes | yes |
| `POST` | `/api/v1/federation_peers` | `federation_peers#create` | yes | yes | yes |
| `DELETE` | `/api/v1/federation_peers/:id` | `federation_peers#destroy` | yes | yes | yes |
| `GET` | `/api/v1/federation_peers/:id` | `federation_peers#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/federation_peers/:id` | `federation_peers#update` | yes | yes | yes |
| `POST` | `/api/v1/federation_peers/:id/sync` | `federation_peers#sync` | yes | yes | yes |
| `GET` | `/api/v1/ksi_catalog/indicators` | `ksi_catalog#indicators` | yes | yes | yes |
| `GET` | `/api/v1/ksi_catalog/indicators/:id` | `ksi_catalog#show_indicator` | yes | yes | yes |
| `GET` | `/api/v1/ksi_catalog/mappings` | `ksi_catalog#mappings` | yes | yes | yes |
| `GET` | `/api/v1/ksi_catalog/themes` | `ksi_catalog#themes` | yes | yes | yes |
| `GET` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations` | `ksi_validations#index` | yes | yes | yes |
| `POST` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations` | `ksi_validations#create` | yes | yes | yes |
| `DELETE` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/:id` | `ksi_validations#destroy` | yes | yes | yes |
| `GET` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/:id` | `ksi_validations#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/:id` | `ksi_validations#update` | yes | yes | yes |
| `GET` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/export` | `ksi_validations#export` | yes | yes | yes |
| `GET` | `/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/summary` | `ksi_validations#summary` | yes | yes | yes |
| `GET` | `/api/v1/poam_documents` | `poam_documents#index` | yes | yes | yes |
| `POST` | `/api/v1/poam_documents` | `poam_documents#create` | yes | yes | yes |
| `DELETE` | `/api/v1/poam_documents/:id` | `poam_documents#destroy` | yes | yes | yes |
| `GET` | `/api/v1/poam_documents/:id` | `poam_documents#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/poam_documents/:id` | `poam_documents#update` | yes | yes | yes |
| `GET` | `/api/v1/profile_documents` | `profile_documents#index` | yes | yes | yes |
| `POST` | `/api/v1/profile_documents` | `profile_documents#create` | yes | yes | yes |
| `DELETE` | `/api/v1/profile_documents/:id` | `profile_documents#destroy` | yes | yes | yes |
| `GET` | `/api/v1/profile_documents/:id` | `profile_documents#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/profile_documents/:id` | `profile_documents#update` | yes | yes | yes |
| `GET` | `/api/v1/sap_documents` | `sap_documents#index` | yes | yes | yes |
| `POST` | `/api/v1/sap_documents` | `sap_documents#create` | yes | yes | yes |
| `DELETE` | `/api/v1/sap_documents/:id` | `sap_documents#destroy` | yes | yes | yes |
| `GET` | `/api/v1/sap_documents/:id` | `sap_documents#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/sap_documents/:id` | `sap_documents#update` | yes | yes | yes |
| `GET` | `/api/v1/sar_documents` | `sar_documents#index` | yes | yes | yes |
| `POST` | `/api/v1/sar_documents` | `sar_documents#create` | yes | yes | yes |
| `DELETE` | `/api/v1/sar_documents/:id` | `sar_documents#destroy` | yes | yes | yes |
| `GET` | `/api/v1/sar_documents/:id` | `sar_documents#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/sar_documents/:id` | `sar_documents#update` | yes | yes | yes |
| `GET` | `/api/v1/sar_documents/:id/export` | `sar_documents#export` | yes | yes | yes |
| `PUT` | `/api/v1/sar_documents/:id/update_fields` | `sar_documents#update_fields` | yes | yes | yes |
| `POST` | `/api/v1/sar_documents/convert` | `sar_documents#convert` | yes | yes | yes |
| `GET` | `/api/v1/ssp_documents` | `ssp_documents#index` | yes | yes | yes |
| `POST` | `/api/v1/ssp_documents` | `ssp_documents#create` | yes | yes | yes |
| `DELETE` | `/api/v1/ssp_documents/:id` | `ssp_documents#destroy` | yes | yes | yes |
| `GET` | `/api/v1/ssp_documents/:id` | `ssp_documents#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/ssp_documents/:id` | `ssp_documents#update` | yes | yes | yes |
| `GET` | `/api/v1/ssp_documents/:id/export` | `ssp_documents#export` | yes | yes | yes |
| `PUT` | `/api/v1/ssp_documents/:id/update_fields` | `ssp_documents#update_fields` | yes | yes | yes |
| `POST` | `/api/v1/ssp_documents/convert` | `ssp_documents#convert` | yes | yes | yes |
| `GET` | `/api/v1/users` | `users#index` | yes | yes | yes |
| `POST` | `/api/v1/users` | `users#create` | yes | yes | yes |
| `DELETE` | `/api/v1/users/:id` | `users#destroy` | yes | yes | yes |
| `GET` | `/api/v1/users/:id` | `users#show` | yes | yes | yes |
| `PATCH/PUT` | `/api/v1/users/:id` | `users#update` | yes | yes | yes |

