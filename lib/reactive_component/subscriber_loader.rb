# frozen_string_literal: true

module ReactiveComponent
  # A component wires its model up when the class loads, so an app that does
  # not eager load broadcasts nothing from a process that has not rendered that
  # component yet. This loads the components that subscribe, and nothing else.
  module SubscriberLoader
    mattr_accessor :paths, default: ['app/components']

    SUBSCRIBER = /include\s+ReactiveComponent\b/

    module_function

    def load_all
      loader = Rails.autoloaders.main

      files.each { |file| loader.cpath_expected_at(file)&.safe_constantize }
    end

    # The files under `paths` that include the concern, read rather than
    # loaded, so an app keeps lazy loading for everything else.
    def files
      paths.flat_map do |path|
        dir = Rails.root.join(path)
        next [] unless Dir.exist?(dir)

        Dir.glob(dir.join('**', '*.rb')).select { |file| File.read(file).match?(SUBSCRIBER) }
      end
    end
  end
end
