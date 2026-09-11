---
title: Configuration
description: Configure ReactiveComponent options for your Rails application
---

ReactiveComponent exposes a handful of configuration options. You can set them in an initializer (e.g. `config/initializers/reactive_component.rb`).

## `ReactiveComponent.debug`

Enables debug mode. Defaults to `false`.

```ruby
# config/initializers/reactive_component.rb
ReactiveComponent.debug = Rails.env.development?
```

When enabled:

- **Unencoded templates** -- Compiled JavaScript templates are embedded as plain text instead of Base64-encoded strings, making them easier to inspect in the browser.
- **Strict payloads** -- Renders go through a Proxy that throws the moment a template reads a key the broadcast does not carry (`template read "v0.0.blocked" but the payload only has: v3, v7`), instead of rendering an `undefined` that is silently falsy in an `if`.
- **Debug wrapper divs** -- Each reactive component's wrapper `<div>` receives a `data-reactive-debug` attribute with a human-readable label (e.g. `"Message row component #message_42"`) and a `reactive-debug-wrapper` CSS class so you can visually identify reactive components during development.

## `ReactiveComponent.renderer`

Sets the renderer used when evaluating nested component `render` calls during data extraction. Defaults to `nil`, which falls back to `ActionController::Base`.

```ruby
ReactiveComponent.renderer = ApplicationController
```

This is useful if your components call `render` for nested ViewComponents and the rendering requires application-specific route helpers or configuration that `ActionController::Base` does not provide.

## `ReactiveComponent::Channel.compress`

Enables gzip compression for ActionCable broadcasts. Defaults to `false`.

```ruby
ReactiveComponent::Channel.compress = true
```

When enabled, broadcast payloads are JSON-encoded, gzip-compressed, and Base64-encoded before being sent over ActionCable. The client-side Stimulus controller automatically detects and decompresses these payloads. This can significantly reduce bandwidth for components with large data payloads.

## `ReactiveComponent.action_token_ttl`

How long the signed `live_action` token minted into a wrapper stays valid. Defaults to `1.day`. After that, actions from a page rendered before the cutoff respond 404 until the page is re-rendered.

```ruby
ReactiveComponent.action_token_ttl = 4.hours
```

## `ReactiveComponent.presence_identity`

Says who a connection belongs to, which is what turns presence on. Defaults to `nil`, meaning presence is off and no frame is broadcast.

```ruby
ReactiveComponent.presence_identity = lambda do |connection|
  user = connection.current_user or next nil

  { id: user.id, name: user.first_name, color: user.avatar_color }
end
```

The lambda receives the ActionCable connection and returns a Hash of primitives, or `nil` to leave that connection out of every roster. Returning a record raises `UnsafeBroadcastValueError` rather than broadcasting every column to everyone on the stream. See [Presence](/reactive_component/presence/).

## `ReactiveComponent.presence_state_limit`

The largest presence state a client may broadcast, in bytes of encoded JSON. Defaults to `1024`. Frames above it are dropped.

```ruby
ReactiveComponent.presence_state_limit = 2048
```

Presence state is the only client-authored payload this gem broadcasts, so unlike every other broadcast it needs a ceiling as well as a type check.

## `ReactiveComponent::Channel.filter_callback`

Sets a callback for filtering whether a record matches the current subscription parameters. Defaults to `nil` (no filtering -- all records on the stream are accepted).

This is a display filter, not an authorization hook. Authorization happens before it runs: a client can only request records whose `broadcasts` stream is the signed stream it subscribed to, and only for classes that include `ReactiveComponent`. Requests for anything else are ignored.

```ruby
ReactiveComponent::Channel.filter_callback = ->(record, params) {
  # Only re-render if the record belongs to the requested category
  params["category_id"].blank? || record.category_id.to_s == params["category_id"]
}
```

The callback receives two arguments:

| Argument | Description |
|:---------|:------------|
| `record` | The ActiveRecord model instance being broadcast |
| `params` | A hash of subscription parameters sent by the client |

Return `true` to allow the component to re-render with this record, or `false` to skip it. When `false` is returned on an update request, the channel transmits a `"remove"` action instead, causing the client to remove the component from the DOM.

## Full example

```ruby
# config/initializers/reactive_component.rb

ReactiveComponent.debug = Rails.env.development?
ReactiveComponent.renderer = ApplicationController

ReactiveComponent.presence_identity = ->(connection) { connection.current_user&.then { |u| { id: u.id, name: u.name } } }

ReactiveComponent::Channel.compress = Rails.env.production?
ReactiveComponent::Channel.filter_callback = ->(record, params) {
  true # accept all by default
}
```
