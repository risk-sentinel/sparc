Rails.application.routes.draw do
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

  # User profile (avatar upload)
  resource :profile, only: [ :edit ] do
    patch :update_avatar, on: :member
    delete :remove_avatar, on: :member
  end

  # OmniAuth callbacks (GitHub, GitLab, OIDC)
  match "auth/:provider/callback", to: "omniauth_callbacks#create", via: [ :get, :post ]
  get "auth/failure", to: "omniauth_callbacks#failure"

  resources :authorization_boundaries do
    member do
      get  :ato_wizard
      post :create_ato_package
      get  :download_ato_package
    end
    resources :boundaries, only: [ :new, :create, :edit, :update, :destroy ]
    resources :memberships,
      controller: "authorization_boundary_memberships",
      only: [ :new, :create, :edit, :update, :destroy ]
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
      post :create_control_resource
      post :link_control_resource
      delete :unlink_control_resource
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
    resources :back_matter_resources, only: [ :create, :update, :destroy ]
  end

  resources :evidences do
    resources :attestations, only: [ :new, :create, :destroy ]
  end

  resources :cdef_documents do
    member do
      patch :update_metadata
      patch :update_field
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
      post :copy
      post :create_control_resource
      post :link_control_resource
      delete :unlink_control_resource
    end
    collection do
      get :select_profile
      post :create_from_profile
    end
    resources :back_matter_resources, only: [ :create, :update, :destroy ]
  end

  resources :control_catalogs do
    member do
      patch :update_metadata
      patch :publish
      get :publish_check
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
    resources :users, only: [ :index, :show, :edit, :update ] do
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
        post :add_member
        delete :remove_member
      end
    end
  end

  namespace :api do
    namespace :v1 do
      # API discovery (#250)
      get "available", to: "discovery#available"

      # Document CRUD + legacy actions (#229)
      resources :ssp_documents, only: [ :index, :show, :create, :update, :destroy ] do
        collection do
          post :convert
        end
        member do
          put :update_fields
          get :export
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

      # Catalog, Profile, CDEF, and Mapping CRUD (#242)
      resources :control_catalogs, only: [ :index, :show, :create, :update, :destroy ]
      resources :profile_documents, only: [ :index, :show, :create, :update, :destroy ] do
        # Baseline parameter management (#240)
        resource :parameters, only: [ :show, :update ], controller: "baseline_parameters" do
          get :export, on: :member
        end
      end
      resources :cdef_documents, only: [ :index, :show, :create, :update, :destroy ]
      resources :control_mappings, only: [ :index, :show, :create, :update, :destroy ]

      # Back-matter resource management (#375)
      resources :back_matter_resources, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :link
          delete :unlink
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
        # KSI validation tracking (#107)
        resources :ksi_validations, only: [ :index, :show, :create, :update, :destroy ] do
          collection do
            get :summary
            get :export
          end
        end
      end
    end
  end
end
