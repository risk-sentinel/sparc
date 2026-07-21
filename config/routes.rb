Rails.application.routes.draw do
  # UUID (8-4-4-4-12 hex) constraint shared by the artifact resolver routes (#680).
  uuid_constraint = /[0-9a-fA-F-]{36}/

  root "home#index"
  get "oscal-overview", to: "home#oscal_overview", as: :oscal_overview
  get "about",          to: "about#index",         as: :about
  get "about/api",      to: "about#api_docs",      as: :about_api
  get "about/quickstart", to: "about#quickstart",  as: :about_quickstart
  get "about/resources", to: "about#resources",   as: :about_resources

  # ── Authentication ────────────────────────────────────────────────────
  get    "login",  to: "sessions#new",     as: :login
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  # Self-service registration
  get  "register", to: "registrations#new",    as: :register
  post "register", to: "registrations#create"

  # Password change (forced reset for bootstrapped admin)
  resource :password, only: [ :edit, :update ]

  # FIDO2 security keys — enroll (WebAuthn attestation ceremony), list, revoke (#779)
  resources :webauthn_credentials, only: [ :index, :create, :destroy ] do
    post :registration_options, on: :collection
  end

  # Passwordless FIDO2 sign-in — the security key + PIN is the login (#779)
  post "session/webauthn/options", to: "webauthn_sessions#options", as: :webauthn_authentication_options
  post "session/webauthn",         to: "webauthn_sessions#create",  as: :webauthn_session

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
        end
      end

      resources :sar_documents, only: [ :index, :show, :create, :update, :destroy ] do
        collection do
          post :convert
        end
        member do
          put :update_fields
          get :export
        end
      end

      resources :sap_documents, only: [ :index, :show, :create, :update, :destroy ]
      resources :poam_documents, only: [ :index, :show, :create, :update, :destroy ]

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
      resources :users, only: [ :index, :show, :create, :update, :destroy ]
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
        # KSI validation tracking (#107)
        resources :ksi_validations, only: [ :index, :show, :create, :update, :destroy ] do
          collection do
            get :summary
            get :export
          end
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
      end
    end
  end
end
