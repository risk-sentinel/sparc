Rails.application.routes.draw do
  root "home#index"

  # Login page — available but NOT enforced (no before_action :authenticate_user!)
  # Future: post "login", to: "sessions#create"
  # Future: delete "logout", to: "sessions#destroy", as: :logout
  get "login", to: "sessions#new", as: :login

  resources :ssp_documents do
    member do
      patch :update_metadata
      get :download_json
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :status
    end
    collection do
      post :import_json
    end
  end

  resources :sar_documents do
    member do
      patch :update_metadata
      get :download_json
      get :download_excel
      get :status
      get :editor
      get "edit_control/:sar_control_id", action: :edit_control, as: :edit_control
    end
    collection do
      post :import_json
    end
  end

  resources :profile_documents do
    member do
      patch :update_metadata
      get :download_json
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :status
    end
    resources :profile_controls, only: [ :new, :create, :edit, :update, :destroy ]
  end

  resources :poam_documents do
    member do
      patch :update_metadata
      get :download_json
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :status
    end
    resources :poam_items, only: [ :new, :create, :edit, :update, :destroy ]
  end

  resources :cdef_documents do
    member do
      patch :update_metadata
      get :download_json
      get :download_oscal
      get :download_oscal_validated
      get :download_oscal_unvalidated
      get :status
    end
  end

  resources :control_catalogs do
    collection do
      get  :import
      post :import
    end
    resources :control_families, shallow: true do
      resources :catalog_controls, shallow: true
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
