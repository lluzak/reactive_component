# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
ENV["RAILS_ROOT"] = File.expand_path("dummy", __dir__)

require_relative "dummy/config/environment"

ActiveRecord::Schema.verbose = false
ActiveRecord::Tasks::DatabaseTasks.drop_current rescue nil # rubocop:disable Style/RescueModifier
ActiveRecord::Tasks::DatabaseTasks.create_current
load File.expand_path("dummy/db/schema.rb", __dir__)

require "minitest/autorun"
require "action_cable/channel/test_case"
