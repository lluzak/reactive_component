Rails.application.config.to_prepare do
  ReactiveComponent::Channel.filter_callback = ->(record, params) {
    params["folder"] != "starred" || record.starred?
  }
end

ReactiveComponent.presence_identity = lambda do |connection|
  viewer = connection.viewer or next nil

  { id: viewer.id, name: viewer.name }
end
