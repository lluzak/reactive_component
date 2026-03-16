Rails.application.configure do
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.active_support.deprecation = :stderr
  config.active_record.maintain_test_schema = false
end
