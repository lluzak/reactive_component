# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "reactive_component"

require "minitest/autorun"

# Load Rails test helpers if available
if defined?(Rails)
  require "rails/test_help"
  require "action_cable/testing/test_case"
end
