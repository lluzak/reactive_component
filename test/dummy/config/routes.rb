Rails.application.routes.draw do
  mount ReactiveComponent::Engine => "/reactive_component"
  resources :messages, only: [:index, :show]
  root "messages#index"
end
