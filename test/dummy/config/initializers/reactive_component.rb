Rails.application.config.to_prepare do
  ReactiveComponent::Channel.filter_callback = ->(record, params) {
    params["folder"] != "starred" || record.starred?
  }
end
