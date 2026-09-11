ReactiveComponent.presence_identity = lambda do |connection|
  viewer = connection.viewer or next nil

  { id: viewer.id, name: viewer.name }
end
