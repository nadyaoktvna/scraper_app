Rails.application.routes.draw do
  root 'books#index'

  resources :books, only: [:index, :edit, :update, :destroy] do
    collection do
      post :scrape
      delete :stop_scrape
      get :scrape_status
      delete :dismiss_notification
    end
    member do
      post :purchase
    end
  end
  
  get "up" => "rails/health#show", as: :rails_health_check
end
