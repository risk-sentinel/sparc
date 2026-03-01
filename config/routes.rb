Rails.application.routes.draw do
  root 'home#index'
  
  resources :ssp_documents do
    member do
      get :download_json
    end
    collection do
      post :import_json
    end
  end
  
  resources :tpr_documents do
    member do
      get :download_json
      get :editor
    end
    collection do
      post :import_json
    end
  end
  
  resources :control_catalogs do
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
      
      resources :tpr_documents, only: [] do
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