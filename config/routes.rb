# frozen_string_literal: true

ReactiveComponent::Engine.routes.draw do
  post "actions", to: "actions#create", as: :reactive_component_actions
end
