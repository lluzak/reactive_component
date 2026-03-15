# frozen_string_literal: true

# This file should be required from the main lib/reactive_component.rb module file.

module ReactiveComponent
  class Engine < ::Rails::Engine
    isolate_namespace ReactiveComponent
  end
end
