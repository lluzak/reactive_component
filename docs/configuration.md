---
layout: default
title: Configuration
nav_order: 4
---

# Configuration

ReactiveComponent exposes a handful of configuration options. You can set them in an initializer (e.g. `config/initializers/reactive_component.rb`).

## `ReactiveComponent.debug`

Enables debug mode. Defaults to `false`.

```ruby
# config/initializers/reactive_component.rb
ReactiveComponent.debug = Rails.env.development?
```

When enabled:

- **Unencoded templates** -- Compiled JavaScript templates are embedded as plain text instead of Base64-encoded strings, making them easier to inspect in the browser.
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

## `ReactiveComponent::Channel.filter_callback`

Sets a callback for filtering whether a record matches the current subscription parameters. Defaults to `nil` (no filtering -- all records on the stream are accepted).

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

ReactiveComponent::Channel.compress = Rails.env.production?
ReactiveComponent::Channel.filter_callback = ->(record, params) {
  true # accept all by default
}
```
