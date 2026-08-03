Rails.application.routes.draw do
  # UUID (8-4-4-4-12 hex) constraint shared by the artifact resolver routes (#680).
  uuid_constraint = /[0-9a-fA-F-]{36}/

  # #881 — the catalog-scoped control member path, and the options that make it
  # work. `format: false` plus the constraint are load-bearing: canonical
  # control ids contain dots (1478 of 2447 distinct ids), and Rails would
  # otherwise read `/controls/ac-19.4.b.1` as id `ac-19.4.b` with format `1`,
  # silently resolving the PARENT control.
  control_member       = "controls/:id"
  control_member_opts  = { constraints: { id: /[^\/]+/ }, format: false }

  root "home#index"
  get "oscal-overview", to: "home#oscal_overview", as: :oscal_overview
  get "about",          to: "about#index",         as: :about
  get "about/api",      to: "about#api_docs",      as: :about_api
  get "about/quickstart", to: "about#quickstart",  as: :about_quickstart
  get "about/resources", to: "about#resources",   as: :about_resources

  # ── In-app Help Center / User Guides (#784) ───────────────────────────
  # The image route is declared BEFORE the :slug show route so "images" is
  # not swallowed as a guide slug.
  get "help",                  to: "help#index",  as: :help
  get "help/images/:filename", to: "help#image",  as: :help_image,
      constraints: { filename: /[\w\-.]+\.(?:png|jpe?g|gif|svg|webp)/i }
  # The guide slug derives from the wiki filename, so renaming
  # User-Guide-Trust-Store.md -> User-Guide-Compliance-Library.md moved the URL.
  # Keep the old link working for bookmarks and anything already published.
  get "help/trust-store", to: redirect("/help/compliance-library")
  get "help/:slug",            to: "help#show",    as: :help_guide,
      constraints: { slug: /[a-z0-9-]+/ }

  # ── Authentication ────────────────────────────────────────────────────
  get    "login",  to: "sessions#new",     as: :login
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  # Self-service registration
  get  "register", to: "registrations#new",    as: :register
  post "register", to: "registrations#create"

  # Password change (forced reset for bootstrapped admin)
  resource :password, only: [ :edit, :update ]

  # #841 — redeeming an admin-issued reset. Unauthenticated by necessity: the
  # user cannot sign in, which is the problem being solved. Authority is the
  # single-use, expiring token.
  get   "password/reset/:token", to: "password_resets#edit",   as: :edit_password_reset
  patch "password/reset/:token", to: "password_resets#update", as: :password_reset

  # FIDO2 security keys — enroll (WebAuthn attestation ceremony), list, revoke (#779)
  resources :webauthn_credentials, only: [ :index, :create, :destroy ] do
    post :registration_options, on: :collection
  end

  # Passwordless FIDO2 sign-in — the security key + PIN is the login (#779)
  post "session/webauthn/options", to: "webauthn_sessions#options", as: :webauthn_authentication_options
  post "session/webauthn",         to: "webauthn_sessions#create",  as: :webauthn_session

  # PIV / CAC smart-card sign-in — the proxy-validated client cert is the login (#779)
  get "auth/piv", to: "piv_sessions#create", as: :piv_session

  # User profile (avatar upload)
  resource :profile, only: [ :edit ] do
    patch :update_avatar, on: :member
    delete :remove_avatar, on: :member
  end

  # OmniAuth callbacks (GitHub, GitLab, OIDC)
  match "auth/:provider/callback", to: "omniauth_callbacks#create", via: [ :get, :post ]
  get "auth/failure", to: "omniauth_callbacks#failure"

  # ── Security telemetry ────────────────────────────────────────────────
  # CSP violation report sink (#528, epic #650). The CSP header's report-uri
  # points here; browsers POST violation reports which we log as structured
  # telemetry. Rate-limited per-IP by Rack::Attack.
  post "security/csp-violations", to: "security/csp_reports#create", as: :csp_violation_reports

  resources :authorization_boundaries do
    collection do
      # #629 — admin-only multi-row delete from the index.
      delete "bulk_destroy", to: "authorization_boundaries#bulk_destroy"
    end
    member do
      get  :ato_wizard
      post :create_ato_package
      get  :download_ato_package
      # #447 — HDF Amendment triage UI (thin client over the triage services).
      get    :triage,              to: "hdf_triage#show"
      post   "triage/ingest",      to: "hdf_triage#ingest",            as: :triage_ingest
      post   "triage/disposition", to: "hdf_triage#disposition",       as: :triage_disposition
      delete "triage/disposition", to: "hdf_triage#clear_disposition", as: :triage_clear_disposition
      # #809 — approve/reject an amendment disposition; aggregate findings; signed package.
      post   "triage/disposition/approve", to: "hdf_triage#approve_disposition", as: :triage_approve_disposition
      post   "triage/disposition/reject",  to: "hdf_triage#reject_disposition",  as: :triage_reject_disposition
      post   "triage/aggregate",   to: "hdf_triage#aggregate",         as: :triage_aggregate
      get    "triage/amendments",  to: "hdf_triage#amendments",        as: :triage_amendments
      get    "triage/package",     to: "hdf_triage#package",           as: :triage_package
    end
    resources :boundaries, only: [ :new, :create, :edit, :update, :destroy ]
    resources :memberships,
      controller: "authorization_boundary_memberships",
      only: [ :new, :create, :edit, :update, :destroy ]
    # #396: leveraged authorizations are created on the leveraging boundary
    resources :leveraged_authorizations, only: [ :new, :create, :show, :destroy ] do
      member do
        post :populate
      end
    end
  end

  resources :ssp_documents do
    member do
      patch :update_metadata
      patch :update_statement
      patch :publish
      get :publish_check
      get :download_json
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :download_yaml
      get :download_xml
      get :validate_oscal_export
      get :status
      get :enrich
      patch :update_enrich
      # #737: pull system users from authorization-boundary members
      post :import_boundary_users
      # #737: import system components from linked / org-wide component definitions
      post :import_cdef_components
      # #737: link existing (reusable) back-matter resources onto this SSP
      post :import_back_matter
      post :create_control_resource
      post :link_control_resource
      delete :unlink_control_resource
      # #398: bulk refresh inherited statements from all linked CDEFs
      post :refresh_inherited_statements
      post :reset_inherited_statement
      # #628: populate an existing empty SSP from a published profile so a
      # metadata-only shell isn't a dead end.
      get :attach_profile
      post :populate_from_profile
    end
    collection do
      post :import_json
      get :wizard
      post :create_from_wizard
      get :select_profile
      post :create_from_profile
    end
    resources :back_matter_resources, only: [ :create, :update, :destroy ]
  end

  resources :sar_documents do
    member do
      patch :update_metadata
      patch :publish
      get :publish_check
      get :download_json
      get :download_excel
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :download_yaml
      get :download_xml
      get :validate_oscal_export
      get :status
      get :editor
      get :enrich
      patch :update_enrich
      patch :update_objective
      patch :associate_source
      get "edit_control/:sar_control_id", action: :edit_control, as: :edit_control
    end
    collection do
      post :import_json
      get :wizard
      post :create_from_wizard
      get :select_profile
      post :create_from_profile
      get :select_ssp
      post :create_from_ssp
    end
    resources :back_matter_resources, only: [ :create, :update, :destroy ]
  end

  resources :profile_documents do
    member do
      patch :update_metadata
      get :download_json
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :download_yaml
      get :download_xml
      get :validate_oscal_export
      get :status
      post :copy
      patch :publish
      get :publish_check
      get :download_resolved_catalog
      get :manage_controls
      patch :update_controls
      # #630/#632/#633 — review/approval workflow (profile + baseline).
      post :submit_for_review, to: "profile_documents#submit_for_review"
      post :approve, to: "profile_documents#approve"
      post :reject, to: "profile_documents#reject"
    end
    collection do
      get :select_catalog
      post :create_from_catalog
      get :select_profile
      post :create_from_profile
    end
    resources :profile_controls, only: [ :new, :create, :edit, :update, :destroy ] do
      resources :control_back_matter_links, only: [ :create, :destroy ]
      post :link_resource, on: :member, controller: "control_back_matter_links", action: "link"
    end
    resources :back_matter_resources, only: [ :create, :update, :destroy ]
  end

  resources :sap_documents do
    member do
      patch :update_metadata
      patch :publish
      get :publish_check
      get :download_json
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :download_yaml
      get :download_xml
      get :validate_oscal_export
      get :status
      patch :associate_source
      patch :update_objective
    end
    collection do
      post :import_json
    end
    resources :back_matter_resources, only: [ :create, :update, :destroy ]
  end

  resources :poam_documents do
    member do
      patch :update_metadata
      patch :publish
      get :publish_check
      get :download_json
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :download_yaml
      get :download_xml
      get :validate_oscal_export
      get :status
    end
    resources :poam_items, only: [ :new, :create, :edit, :update, :destroy ]
    # POAM child entities (#423) — full admin UI for OSCAL extensibility
    resources :poam_risks, only: [ :new, :create, :edit, :update, :destroy ]
    resources :poam_remediations, only: [ :new, :create, :edit, :update, :destroy ] do
      resources :poam_milestones, only: [ :new, :create, :edit, :update, :destroy ]
    end
    resources :poam_observations, only: [ :new, :create, :edit, :update, :destroy ]
    resources :poam_findings, only: [ :new, :create, :edit, :update, :destroy ]
    resources :poam_local_components, only: [ :new, :create, :edit, :update, :destroy ]
    resources :back_matter_resources, only: [ :create, :update, :destroy ]
  end

  # Leveraging-side read-only view of leveraged-system POA&Ms (#415 Scenario A)
  resources :leveraged_poam_documents, only: %i[index show]

  resources :evidences do
    resources :attestations, only: [ :new, :create, :destroy ]
  end

  # Durable artifact resolver (#680) — stable UUID → freshly-signed download;
  # versions/:uuid resolves a specific retained content version.
  get "artifacts/versions/:uuid", to: "artifacts#version", as: :artifact_version,
      constraints: { uuid: uuid_constraint }
  get "artifacts/:uuid", to: "artifacts#show", as: :artifact,
      constraints: { uuid: uuid_constraint }

  resources :cdef_documents do
    member do
      patch :update_metadata
      patch :update_field
      patch :update_statement
      patch :publish
      get :publish_check
      # #630/#634 — review/approval workflow.
      post :submit_for_review, to: "cdef_documents#submit_for_review"
      post :approve, to: "cdef_documents#approve"
      post :reject, to: "cdef_documents#reject"
      get :download_json
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :download_yaml
      get :download_xml
      get :validate_oscal_export
      get :status
      post :copy
      post :create_control_resource
      post :link_control_resource
      delete :unlink_control_resource
      # #499 slice 5 — bulk-apply Converter UI (preview-then-confirm).
      get  :bulk_apply
      post :bulk_apply_preview
      post :bulk_apply_confirm
      # #628: populate an existing empty CDEF from a published profile so a
      # metadata-only shell isn't a dead end.
      get :attach_profile
      post :populate_from_profile
    end
    collection do
      get :select_profile
      post :create_from_profile
      # #629 — admin-only multi-row delete from the index.
      delete "bulk_destroy", to: "cdef_documents#bulk_destroy"
      # #488 — admin trigger for AwsLabsCdefRefreshJob, RBAC gated on
      # converters.write to match the DISA CCI refresh button precedent.
      post :refresh_aws_labs
    end
    resources :back_matter_resources, only: [ :create, :update, :destroy ]
  end

  resources :control_catalogs do
    member do
      patch :update_metadata
      patch :publish
      get :publish_check
      # #630/#631 — review/approval workflow.
      post :submit_for_review, to: "control_catalogs#submit_for_review"
      post :approve, to: "control_catalogs#approve"
      post :reject, to: "control_catalogs#reject"
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :download_yaml
      get :download_xml
      get :validate_oscal_export
      get :baseline_controls
      patch :update_baseline
      patch :bulk_update_baselines
      patch :acknowledge_warnings
      patch :revalidate
    end
    collection do
      get  :import
      post :import
    end
    resources :control_families, shallow: true do
      resources :catalog_controls, shallow: true do
        collection do
          get :batch_new
          post :batch_create
        end
        resources :control_back_matter_links, only: [ :create, :destroy ]
        post :link_resource, on: :member, controller: "control_back_matter_links", action: "link"
      end
    end
    resources :back_matter_resources, only: [ :create, :update, :destroy ]

    # #881 — the readable control URL:
    #   /control_catalogs/nist-800-53-rev5/controls/ac-19.4.b.1
    #
    # Catalog-scoped rather than family-scoped: control_id is unique per family,
    # but it already encodes its family, and (catalog, canonical_id) is unique —
    # verified across all 4054 seeded controls. A family segment would be noise.
    #
    # `format: false` and the constraint are load-bearing, not decoration.
    # Canonical ids contain dots (1478 of 2447 distinct ids do), and Rails would
    # otherwise parse `/controls/ac-19.4.b.1` as id `ac-19.4.b` with format `1`.
    # That does not raise — it silently resolves the PARENT control, i.e. the
    # exact "stops before the sub-part" failure this issue is about.
    # #881 — families are catalog-scoped and addressed by their code (`ac`),
    # not a database id. Declared before the control routes so "control_families"
    # is never swallowed by the `controls/:id` pattern.
    get "control_families/:id", to: "control_families#show", as: :family,
        constraints: { id: /[^\/]+/ }, format: false

    get    "#{control_member}/edit", to: "catalog_controls#edit",   **control_member_opts, as: :edit_control
    get    control_member,           to: "catalog_controls#show",   **control_member_opts
    patch  control_member,           to: "catalog_controls#update", **control_member_opts, as: :control
    put    control_member,           to: "catalog_controls#update", **control_member_opts
    delete control_member,           to: "catalog_controls#destroy", **control_member_opts
  end

  resources :converters do
    member do
      get :export
      post :refresh_cci
      post :refresh_aws_config          # #494
      post :refresh_aws_security_hub    # #494
    end
    collection do
      get :import
      post :do_import
      get :stig_parser
      post :import_stig
    end
    resources :converter_entries, only: [ :create, :destroy ], as: :entries, path: "entries"
  end

  resources :control_mappings do
    member do
      patch :publish
      patch :deprecate
      get :download_oscal
    end
    resources :control_mapping_entries, only: [ :create, :destroy ], as: :entries, path: "entries"
  end

  # ── Admin ───────────────────────────────────────────────────────────
  namespace :admin do
    resources :users, only: [ :index, :show, :new, :create, :edit, :update ] do
      member do
        patch :suspend
        patch :reactivate
        patch :deactivate
        delete :reset_security_keys   # revoke all of a user's FIDO2 keys (#779 lockout recovery)
        # #841 lockout recovery, two routes because deployments differ:
        patch  :reset_password        # temporary password, handed over out of band
        patch  :email_password_reset  # emailed one-time link (requires SMTP)
      end
      resources :api_tokens, only: [ :create, :destroy ], controller: "api_tokens"
    end
    resources :service_accounts do
      member do
        patch :disable
        patch :enable
        post :regenerate_token
      end
    end
    resources :roles
    # #809 — remediation-timeline (SLA) grid: days to remediate by baseline × criticality.
    get   "remediation_timelines", to: "remediation_timelines#index", as: :remediation_timelines
    patch "remediation_timelines", to: "remediation_timelines#update"
    resources :audit_logs, only: [ :index, :show ]
    # v1.8.3 — deferred data migration status
    resources :data_migrations, only: [ :index ]
    resources :authorization_boundaries, except: :destroy do
      member do
        post :add_member
        delete :remove_member
      end
    end
    resources :organizations, except: :destroy do
      member do
        patch :deactivate
        patch :reactivate
        post :assign_boundary    # #770 bug 6 — associate a boundary with this org
        post :add_member
        delete :remove_member
      end
    end
  end

  # ── Authoritative back-matter library (#372) ───────────────────────────
  # #646 — any authenticated user can add a source (org/boundary-scoped by
  # default; instance-wide via the existing promotion approval).
  resources :authoritative_sources, only: %i[index show new create]

  resources :promotion_queue, only: %i[index] do
    member do
      post :approve
      post :reject
    end
  end

  # #630 — review queue for trust-store documents (Catalog/Profile/CDEF).
  resources :review_queue, only: %i[index]

  resources :federation_peers do
    member do
      post :sync
    end
  end

  namespace :api do
    namespace :v1 do
      # API discovery (#250)
      get "available", to: "discovery#available"

      # In-app User Guides (#784) — read-only help content, versioned with
      # the deployment. Backs the Help Center; also lets integrators pull docs.
      resources :guides, only: [ :index, :show ], param: :slug

      # #573 — Bearer-token → Rails session cookie bridge. Lets a
      # test runner (Playwright/etc.) acquire a valid session cookie
      # from a SPARC API token so it can drive the UI without screen-
      # scraping the login form. Authenticated via the same Bearer
      # token path as every other /api/v1/* endpoint.
      post "sessions/from_token", to: "sessions#from_token", as: :sessions_from_token

      # Document CRUD + legacy actions (#229)
      resources :ssp_documents, only: [ :index, :show, :create, :update, :destroy ] do
        collection do
          post :convert
        end
        member do
          put :update_fields
          get :export
          # #628 — populate an existing empty SSP from a published profile.
          post :populate_from_profile
          # #716 — bulk editable-field file import (preview → confirm).
          post "fields/import/preview", to: "ssp_documents#import_fields_preview", as: :import_fields_preview
          post "fields/import/confirm", to: "ssp_documents#import_fields_confirm", as: :import_fields_confirm
        end
      end

      resources :sar_documents, only: [ :index, :show, :create, :update, :destroy ] do
        collection do
          post :convert
        end
        member do
          put :update_fields
          get :export
          # #716 — bulk editable-field file import (preview → confirm).
          post "fields/import/preview", to: "sar_documents#import_fields_preview", as: :import_fields_preview
          post "fields/import/confirm", to: "sar_documents#import_fields_confirm", as: :import_fields_confirm
        end
      end

      resources :sap_documents, only: [ :index, :show, :create, :update, :destroy ] do
        collection do
          # #844 — generate a POPULATED SAP from an SSP or profile. Without
          # this the API could only create an empty shell, leaving SAP the one
          # document in the chain with no programmatic generation path.
          post :generate
        end
        member do
          # #716 — bulk editable-field file import (preview → confirm).
          post "fields/import/preview", to: "sap_documents#import_fields_preview", as: :import_fields_preview
          post "fields/import/confirm", to: "sap_documents#import_fields_confirm", as: :import_fields_confirm
        end
      end
      # #832 — risks are addressable so an incomplete one is rejected with a 422
      # naming the missing fields at entry, rather than surfacing much later as
      # a POA&M that fails OSCAL schema validation at export.
      resources :poam_documents, only: [ :index, :show, :create, :update, :destroy ] do
        collection do
          # #843 — build a POPULATED POA&M from a SAR's open risks. Explicit
          # action mapping per rubydre:S7875.
          post "generate", to: "poam_documents#generate", as: :generate
        end
        resources :risks, only: [ :index, :create ], controller: "poam_risks"
      end
      resources :poam_risks, only: [ :show, :update, :destroy ]

      # Evidence CRUD (#756 — file upload + Control/CDEF association) plus
      # attestations (#440 — periodic-review records + CMS schema export).
      # API surface mirrors the UI nesting (`/evidences/:evidence_id/...`).
      resources :evidences, only: [ :index, :show, :create, :update, :destroy ] do
        resources :attestations, only: [ :index, :show, :create, :destroy ] do
          collection do
            get :export
          end
        end
        resources :control_links, only: [ :index, :create, :destroy ],
                  controller: "evidence_control_links"
      end

      # Durable artifact resolver (#680) — stable UUID → signed download URL;
      # versions/:uuid resolves a specific retained content version.
      get "artifacts/versions/:uuid", to: "artifacts#version", as: :artifact_version,
          constraints: { uuid: uuid_constraint }
      # #685 — artifact review-cadence enablement: version timeline + freshness
      # (last reviewed / next due / overdue) as DATA for external ODP validation.
      get "artifacts/:uuid/versions", to: "artifacts#versions", as: :artifact_version_history,
          constraints: { uuid: uuid_constraint }
      get "artifacts/:uuid/freshness", to: "artifacts#freshness", as: :artifact_freshness,
          constraints: { uuid: uuid_constraint }
      get "artifacts/:uuid", to: "artifacts#show", as: :artifact,
          constraints: { uuid: uuid_constraint }

      # Catalog, Profile, CDEF, and Mapping CRUD (#242)
      resources :control_catalogs, only: [ :index, :show, :create, :update, :destroy ] do
        # #895 — catalog CONTENTS. The catalog container had a full API while
        # its families and controls had none. Families are addressed by code
        # (`ac`), scoped to the catalog, matching the web routes from #881.
        resources :control_families, only: [ :index, :show, :create, :update, :destroy ],
                  param: :id, constraints: { id: /[^\/]+/ } do
          # Creation is family-scoped — a control has to be put somewhere — and
          # so is the family listing. Reads and updates of an existing control
          # are catalog-scoped below, because `(catalog, canonical_id)` is
          # already unique.
          resources :catalog_controls, only: [ :index, :create ], path: "controls",
                    constraints: { id: /[^\/]+/ }, format: false
        end

        # #881 identity: `ac-2`, `ac-19.4.b.1`. The `id` constraint is the
        # load-bearing part — 1478 of 2447 canonical ids contain a dot, and the
        # default segment pattern stops at one, so without it every sub-part
        # 404s. (Verified by mutation: dropping the constraint reddens the
        # dotted-identifier spec; dropping `format: false` alone does not,
        # because the greedy constraint already swallows the dots. It stays as
        # an explicit statement that these paths have no format suffix.)
        resources :catalog_controls, only: [ :index, :show, :update, :destroy ], path: "controls",
                  param: :id, constraints: { id: /[^\/]+/ }, format: false
        member do
          # #630/#631 — review/approval workflow.
          post :submit_for_review, to: "control_catalogs#submit_for_review"
          post :approve, to: "control_catalogs#approve"
          post :reject, to: "control_catalogs#reject"
        end
      end
      resources :profile_documents, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          # #630/#632/#633 — review/approval workflow.
          post :submit_for_review, to: "profile_documents#submit_for_review"
          post :approve, to: "profile_documents#approve"
          post :reject, to: "profile_documents#reject"
          # #633 — baseline diff (selected vs expected controls + ODP values).
          get :baseline_review, to: "profile_documents#baseline_review"
          # #757 — select/deselect baseline controls from the linked catalog.
          put :controls, to: "profile_documents#update_controls", as: :controls
        end
        # Baseline parameter management (#240)
        resource :parameters, only: [ :show, :update ], controller: "baseline_parameters" do
          get :export, on: :member
          # #697 — bulk ODP file import (JSON/YAML/XML), preview → confirm.
          post "import/preview", to: "baseline_parameters#import_preview", on: :member, as: :import_preview
          post "import/confirm", to: "baseline_parameters#import_confirm", on: :member, as: :import_confirm
        end
      end
      resources :cdef_documents, only: [ :index, :show, :create, :update, :destroy ] do
        collection do
          # #629 — admin-only bulk delete; ids[] body, partial-success result.
          delete "bulk", to: "cdef_documents#bulk_destroy"
        end
        member do
          # #499 slice 3 — bulk-apply Converter output to a CDEF clone.
          # Preview returns a signed token; confirm (slice 4) replays it.
          post "bulk_apply_converter/preview", action: :bulk_apply_converter_preview, as: :bulk_apply_converter_preview
          post "bulk_apply_converter/confirm", action: :bulk_apply_converter_confirm, as: :bulk_apply_converter_confirm
          # #628 — populate an existing empty CDEF from a published profile.
          post :populate_from_profile
          # #630/#634 — review/approval workflow.
          post :submit_for_review, to: "cdef_documents#submit_for_review"
          post :approve, to: "cdef_documents#approve"
          post :reject, to: "cdef_documents#reject"
          # #716 — bulk editable-field file import (preview → confirm).
          post "fields/import/preview", to: "cdef_documents#import_fields_preview", as: :import_fields_preview
          post "fields/import/confirm", to: "cdef_documents#import_fields_confirm", as: :import_fields_confirm
        end
      end
      resources :control_mappings, only: [ :index, :show, :create, :update, :destroy ]

      # Back-matter resource management (#375) + authoritative workflow (#372)
      resources :back_matter_resources, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :link
          delete :unlink
          post :promote
          post :approve_promotion
          post :reject_promotion
          post :archive
          post :restore
          get  :changes
        end
        collection do
          get  :promotion_queue
          post :bulk
        end
      end

      # #646 — add a library source (POST /api/v1/authoritative_sources).
      # Federation: signed bundle export/import for cross-instance
      # authoritative source sharing (#372). The peer is identified by name
      # via the `peer` query/body param.
      resource :authoritative_sources, only: [ :create ], controller: "authoritative_sources" do
        get  :export,  on: :collection
        post :import,  on: :collection
      end

      resources :federation_peers, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :sync
        end
      end

      # FedRAMP 20x KSI catalog (read-only, #107)
      resource :ksi_catalog, only: [], controller: "ksi_catalog" do
        get :themes, on: :collection
        get :indicators, on: :collection
        get "indicators/:id", action: :show_indicator, on: :collection, as: :indicator
        get :mappings, on: :collection
      end

      # CRUD API endpoints (#95)
      # #841 — issuing a reset is a user-facing admin function, so it has an API
      # surface too. Returns the one-time link; the token is never persisted.
      resources :users, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :password_reset
        end
      end
      resources :authorization_boundaries, only: [ :index, :show, :create, :update, :destroy ] do
        # #770 bug 6 — assign/move/clear the boundary's organization, enforcing
        # the org-admin authorization matrix (instance admin may move; org_admin
        # may attach an unassigned boundary only).
        member do
          patch "organization", to: "authorization_boundaries#assign_organization"
        end
        collection do
          # #629 — admin-only bulk delete; ids[] body, partial-success result.
          delete "bulk", to: "authorization_boundaries#bulk_destroy"
        end
        # Legacy personnel roster entries (#875). The UI could add, edit and
        # remove boundary members with no API equivalent — the one mutation
        # path that was UI-only. `roles` reports the configured vocabulary so a
        # client does not have to guess what the enum will accept.
        resources :memberships, only: [ :index, :show, :create, :update, :destroy ],
                  controller: "authorization_boundary_memberships" do
          collection do
            # Explicit path => controller#action rather than a bare `get :roles`
            # (Sonar rubydre:S7875): the inferred form relies on the enclosing
            # `controller:` override to resolve, which is exactly the kind of
            # action-at-a-distance that makes a route hard to follow.
            get "roles", to: "authorization_boundary_memberships#roles"
          end
        end
        # KSI validation tracking (#107)
        resources :ksi_validations, only: [ :index, :show, :create, :update, :destroy ] do
          collection do
            get :summary
            get :export
          end
        end
        # HDF Amendment triage (#447) — ingest scanner output + list findings,
        # and export the boundary's dispositions as an HDF Amendments artefact.
        resources :scan_runs, only: [ :index, :show, :create ]
        resources :scanner_findings, only: [ :index ]
        resource :hdf_amendments, only: [ :show ], controller: "hdf_amendments"
        # #809 — aggregate findings into SSP/SAP/SAR/POA&M (sync, or ?async=true).
        post :aggregate, to: "aggregations#create"
        # #809 — signed package (amendments + findings + dispositions) for the consumer.
        resource :hdf_package, only: [ :show ], controller: "hdf_packages"
      end

      # HDF Amendment triage (#447) — flat show of a single finding by uuid,
      # with its one disposition (create acts as upsert; keyed by boundary+control).
      resources :scanner_findings, only: [ :show ] do
        resource :disposition, only: [ :show, :create, :destroy ],
                 controller: "finding_dispositions" do
          # #809 — amendment approval flow. Mapped explicitly (rather than relying
          # on Rails inferring the action) so the target is unambiguous.
          post :approve, to: "finding_dispositions#approve"
          post :reject,  to: "finding_dispositions#reject"
        end
      end

      # HDF ↔ OSCAL translation bridge (#449). Stateless — does not persist
      # tenant state; SPARC is the translation engine, not the source of
      # truth. See `Api::V1::TranslationsController` for full surface.
      scope :oscal do
        post :sar_from_hdf,         to: "translations#sar_from_hdf"
        post :poam_from_hdf,        to: "translations#poam_from_hdf"
        post :poam_from_amendments, to: "translations#poam_from_amendments"
      end
      scope :hdf do
        post :amendments_from_oscal_poam, to: "translations#amendments_from_oscal_poam"
      end

      # Admin credential rotation (#403) — receives a new admin password
      # from the sparc-iac rotation Lambda. See sparc-iac#197.
      namespace :admin do
        post "refresh_credentials", to: "credentials#refresh"
        # #809 — remediation-timeline (SLA) table management.
        get "remediation_timelines", to: "remediation_timelines#index"
        put "remediation_timelines", to: "remediation_timelines#update"
      end
    end
  end
end
