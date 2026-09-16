# frozen_string_literal: true

# This file should be required from the main lib/reactive_component.rb module file.

# Entities and signed stream ids are GlobalIDs. ActiveJob pulls this railtie in
# for its own arguments; an app without ActiveJob would otherwise have no
# `GlobalID.app` and could not create one.
require 'global_id/railtie'

module ReactiveComponent
  class Engine < ::Rails::Engine
    isolate_namespace ReactiveComponent

    initializer 'reactive_component.data_evaluator' do
      ReactiveComponent::DataEvaluator.finalize!
    end

    # A component wires its model up when the class loads, so an app that does
    # not eager load (development, test) would broadcast nothing from a process
    # that has not rendered that component yet: a job, or a turbo-stream
    # request. Load the subscribing components on boot and after each reload.
    initializer 'reactive_component.load_subscribers' do |app|
      next if app.config.eager_load

      app.config.to_prepare { ReactiveComponent::SubscriberLoader.load_all }
    end

    initializer 'reactive_component.importmap', before: 'importmap' do |app|
      if defined?(Importmap)
        app.config.importmap.paths <<
          Engine.root.join('config/importmap.rb')

        if app.config.respond_to?(:assets)
          app.config.assets.paths <<
            Engine.root.join('app/javascript')
        end
      end
    end
  end
end
