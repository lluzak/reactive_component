# frozen_string_literal: true

# This file should be required from the main lib/reactive_component.rb module file.

module ReactiveComponent
  class Engine < ::Rails::Engine
    isolate_namespace ReactiveComponent

    initializer 'reactive_component.data_evaluator' do
      ReactiveComponent::DataEvaluator.finalize!
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
