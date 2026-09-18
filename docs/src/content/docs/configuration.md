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

## `ReactiveComponent.compress`

Enables gzip compression for ActionCable broadcasts. Defaults to `false`.

```ruby
ReactiveComponent.compress = true
```

Set it once in an initializer, like `debug`. The older `ReactiveComponent::Channel.compress` still works, but the channel is autoloaded, so it has to be set in `to_prepare`.

When enabled, broadcast payloads are JSON-encoded, gzip-compressed, and Base64-encoded before being sent over ActionCable. The client-side Stimulus controller automatically detects and decompresses these payloads. This can significantly reduce bandwidth for components with large data payloads.

## `ReactiveComponent.action_token_ttl`

How long the signed `live_action` token minted into a wrapper stays valid. Defaults to `1.day`. After that, actions from a page rendered before the cutoff respond 404 until the page is re-rendered.

```ruby
ReactiveComponent.action_token_ttl = 4.hours
```

## `ReactiveComponent.skip_own_broadcasts`

Whether a component ignores the broadcast caused by its own `live_action`. Defaults to `false`: the component that ran the action applies the broadcast like every other viewer.

```ruby
ReactiveComponent.skip_own_broadcasts = true
```

When `true`, `performAction` sends Turbo's `X-Turbo-Request-Id` header. turbo-rails holds that id while the action runs, and the broadcasts sent during it carry it. The component that sent the request ignores the resulting `update`; other viewers, and other components on the same page, still apply it. Destroys are always applied.

That saves a second render in push mode and a round trip in [notify mode](/reactive_component/notify-mode/). The catch: the action endpoint returns no render, so the acting component only shows what its optimistic update changed. Turn it on where actions only flip the `optimistic` field, and leave it off where an action changes more than that.

The broadcast must happen during the request (an `after_commit` callback does). A broadcast from a background job carries no id and is always applied.

Override it per component instance from `live_wrapper_options`:

```ruby
private

def live_wrapper_options
  { skip_own_broadcasts: true }
end
```

## `ReactiveComponent::Channel.filter_callback`

Decides whether a [notify mode](/reactive_component/notify-mode/) component still belongs on the page after its record changes. Defaults to `nil` (no filtering -- every request re-renders).

This is a display filter, not an authorization hook. Authorization happens before it runs: a client can only request records whose `broadcasts` stream is the signed stream it subscribed to, and only for classes that include `ReactiveComponent`. Requests for anything else are ignored.

```ruby
Rails.application.config.to_prepare do
  ReactiveComponent::Channel.filter_callback = ->(record, params) {
    # Only re-render if the record belongs to the requested category
    params["category_id"].blank? || record.category_id.to_s == params["category_id"]
  }
end
```

Set it inside `to_prepare`. The channel is autoloaded, so referencing it directly in an initializer raises `NameError`.

The callback receives two arguments:

| Argument | Description |
|:---------|:------------|
| `record` | The ActiveRecord model instance being broadcast |
| `params` | The `params` the component declared in `live_wrapper_options`, sent back by the client |

Return `true` to re-render the component with this record, or `false` to remove it from the page.

## Full example

```ruby
# config/initializers/reactive_component.rb

ReactiveComponent.debug = Rails.env.development?
ReactiveComponent.renderer = ApplicationController
ReactiveComponent.skip_own_broadcasts = false
ReactiveComponent.compress = Rails.env.production?

Rails.application.config.to_prepare do
  ReactiveComponent::Channel.filter_callback = ->(record, params) {
    true # accept all by default
  }
end
```
