---
title: Troubleshooting
description: Solutions for common ReactiveComponent issues
---

## Component does not update in real time

**Symptoms:** The component renders correctly on initial page load, but does not update when the underlying model changes.

### ActionCable is running

Open the browser console and check for WebSocket connection errors. A failed connection typically appears as a `WebSocket connection to 'ws://...' failed` message.

Verify `config/cable.yml` is configured with a working adapter (Redis for production, async for development):

```yaml
development:
  adapter: async

production:
  adapter: redis
  url: <%= ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" } %>
```

Confirm ActionCable is mounted in `config/routes.rb`:

```ruby
mount ActionCable.server => "/cable"
```

### Stream is subscribed

In the browser DevTools, open the **Network** tab and filter by **WS**. Find the `/cable` connection and inspect its messages. You should see a subscription confirmation frame for `ReactiveComponent::Channel`. If the subscription is rejected, check your `ApplicationCable::Connection` authentication logic.

### Model callbacks are wired

`subscribes_to` automatically adds `after_commit` callbacks to the target model. Verify this in a Rails console:

```ruby
YourModel.reactive_component_classes
# => [YourComponent, ...]
```

If the list is empty, ensure `subscribes_to YourModel` is declared in the component class and the component file has been loaded (eager loading is required in production).

### Renderer is configured

If you use `prepend_target` for create broadcasts (rendering a new record into a list), `ReactiveComponent.renderer` must be set to a renderer instance. Add this to an initializer:

```ruby
# config/initializers/reactive_component.rb
ReactiveComponent.renderer = ApplicationController.renderer
```

---

## "Cannot find ERB template" error

The compiler resolves templates by inspecting the component's `initialize` source location and swapping the `.rb` extension for `.html.erb`. If the component file lives in a non-standard directory, or the template has a different base name, the lookup fails.

**Fix:** Ensure the `.html.erb` template is in the same directory as the `.rb` file and shares the same base name.

```
app/components/
  card_component.rb
  card_component.html.erb   # must be alongside the .rb file
```

---

## Server action returns 404

**Symptoms:** Clicking a `live_action` button results in a 404 or routing error.

### Engine is mounted

Verify the engine is mounted in `config/routes.rb`:

```ruby
mount ReactiveComponent::Engine => "/reactive_component"
```

### Action is registered

The `data-reactive-action` attribute on the button must match a `live_action` declaration in the component class. For example:

```ruby
live_action :submit
```

```html
<button data-reactive-action="submit">Submit</button>
```

### Token is present

The wrapper div rendered by ReactiveComponent must include the `data-reactive-renderer-action-token-value` attribute. This is added automatically when using the standard view helpers. If you are rendering the wrapper manually, ensure the token attribute is present.

---

## Stimulus controller not connecting

**Symptoms:** The wrapper div has the correct `data-controller="reactive-renderer"` attribute, but no live behavior occurs and no Stimulus lifecycle logs appear.

### Controller is registered

Ensure the Stimulus controller is imported and registered in your JavaScript entry point:

```javascript
import ReactiveRendererController from "reactive_component/reactive_renderer_controller"
application.register("reactive-renderer", ReactiveRendererController)
```

### Importmap pins are loaded

If you are using importmap, verify the pin is present:

```bash
bin/rails importmap:pins
```

The output should include a pin for `reactive_component`. If it is missing, re-run the install generator or add the pin manually to `config/importmap.rb`.

---

## Debug mode

To get additional diagnostic information, enable debug mode in an initializer:

```ruby
# config/initializers/reactive_component.rb
ReactiveComponent.debug = true
```

When debug mode is active, ReactiveComponent adds `data-reactive-debug` attributes to wrapper elements and serves component templates as plain text, making it easier to inspect what is being rendered and broadcast.

Disable debug mode before deploying to production.
