Rails.application.routes.draw do
  mount ReactiveComponent::Engine => "/reactive_component"
  resources :messages, only: [:index, :show] do
    member do
      post :toggle_star
      post :toggle_read
    end
  end
  root "messages#index"
end
