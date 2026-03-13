Rails.application.routes.draw do
  root "home#index"

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
    resources :boundaries, only: [ :new, :create, :edit, :update, :destroy ]
    resources :memberships,
      controller: "authorization_boundary_memberships",
      only: [ :new, :create, :edit, :update, :destroy ]
  end

  resources :ssp_documents do
    member do
      patch :update_metadata
      get :download_json
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :download_yaml
      get :download_xml
      get :status
      get :enrich
      patch :update_enrich
    end
    collection do
      post :import_json
      get :wizard
      post :create_from_wizard
    end
  end

  resources :sar_documents do
    member do
      patch :update_metadata
      get :download_json
      get :download_excel
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :download_yaml
      get :download_xml
      get :status
      get :editor
      get :enrich
      patch :update_enrich
      get "edit_control/:sar_control_id", action: :edit_control, as: :edit_control
    end
    collection do
      post :import_json
      get :wizard
      post :create_from_wizard
    end
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
      get :status
      post :copy
      patch :publish
      get :download_resolved_catalog
      get :manage_controls
      patch :update_controls
    end
    collection do
      get :select_catalog
      post :create_from_catalog
    end
    resources :profile_controls, only: [ :new, :create, :edit, :update, :destroy ]
  end

  resources :sap_documents do
    member do
      patch :update_metadata
      get :download_json
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :download_yaml
      get :download_xml
      get :status
    end
    collection do
      post :import_json
    end
  end

  resources :poam_documents do
    member do
      patch :update_metadata
      get :download_json
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :download_yaml
      get :download_xml
      get :status
    end
    resources :poam_items, only: [ :new, :create, :edit, :update, :destroy ]
  end

  resources :evidences do
    resources :attestations, only: [ :new, :create, :destroy ]
  end

  resources :cdef_documents do
    member do
      patch :update_metadata
      get :download_json
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :download_yaml
      get :download_xml
      get :status
      post :copy
    end
  end

  resources :control_catalogs do
    member do
      patch :update_metadata
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :download_yaml
      get :download_xml
      get :baseline_controls
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
      end
    end
  end

  resources :converters do
    member do
      get :export
    end
    collection do
      get :import
      post :do_import
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
      resources :ssp_documents, only: [] do
        collection do
          post :convert
        end
        member do
          put :update_fields
          get :export
        end
      end

      resources :sar_documents, only: [] do
        collection do
          post :convert
        end
        member do
          put :update_fields
          get :export
        end
      end
    end
  end
end
