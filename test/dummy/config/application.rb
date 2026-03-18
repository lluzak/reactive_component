require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"

Bundler.require(*Rails.groups)
require "turbo-rails"
require "view_component"
require "reactive_component"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.hosts.clear
    config.secret_key_base = "test_secret_key_base_for_reactive_component"

    config.after_initialize do
      ReactiveComponent.renderer = ApplicationController
    end
  end
end
