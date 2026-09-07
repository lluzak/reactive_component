# frozen_string_literal: true

# Suppress Ruby warnings originating from third-party gems (e.g. ruby2js circular requires)
module Warning
  GEM_HOME = Gem.paths.home.freeze

  def self.warn(msg, category: nil, **kwargs)
    return if msg.include?(GEM_HOME)

    super
  end
end

ENV['RAILS_ENV'] = 'test'
ENV['RAILS_ROOT'] = File.expand_path('dummy', __dir__)

require_relative 'dummy/config/environment'

ActiveRecord::Schema.verbose = false
ActiveRecord::Tasks::DatabaseTasks.drop_current rescue nil # rubocop:disable Style/RescueModifier
ActiveRecord::Tasks::DatabaseTasks.create_current
ActiveRecord::MigrationContext.new(File.expand_path('dummy/db/migrate', __dir__)).migrate

require 'minitest/autorun'
require 'action_cable/channel/test_case'

# Anonymous components built in tests register on Message through
# subscribes_to; drop them so a later broadcast doesn't try to compile them.
class ActiveSupport::TestCase
  teardown do
    next unless Message.respond_to?(:reactive_component_classes)

    Message.reactive_component_classes = Message.reactive_component_classes.reject { |k| k.name.nil? }.to_set
  end
end
