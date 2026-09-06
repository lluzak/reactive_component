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

The `data-reactive-renderer-action-param` on the button must match a `live_action` declaration in the component class. For example:

```ruby
live_action :submit
```

```html
<button data-action="click->reactive-renderer#performAction"
        data-reactive-renderer-action-param="submit">Submit</button>
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

## `TypeError: v0.map is not a function` (or another `vN` deep in a template)

Two reactive components are rendering the **same record** and sharing a wrapper id, so each receives the other's broadcast and runs its template over the wrong data. Since 0.6 every wrapper id is prefixed with the component (`message_row_message_1`) so this cannot happen by default; check the console for a `[reactive-renderer] … share id` error — it means two components resolved to the same `dom_id_prefix`. Give each a distinct one:

```ruby
class MessageDetailComponent < ApplicationComponent
  include ReactiveComponent

  def self.dom_id_prefix = :detail
end
```

## `ReactiveComponent::CompileError: \`.upcase\` reached the client`

The compiler lifts every expression it can to the server: anything touching an ivar, a helper, a constant, or the loop variable. What is left has to run in JavaScript, and only a small whitelist does — data reads, `if`/`unless`/ternaries, `&&`/`||`/`!`, comparisons, `.each`. A Ruby method call that survives (typically on a literal, or on a template-local variable) is refused by name rather than guessed at. Move it into an expression the server evaluates — a helper or a component method — or into an output position.

The same error with *"reads the loop variable … in a way the client cannot resolve"* means the item itself is used as a value (`<%= item %>`): an item is shipped only as its extracted expressions. Read a property or call a method on it instead.

## `[reactive-renderer] 2 components share id "message_1"` in the console

Two components on the page resolved to the same wrapper id, so each will render the other's broadcast. That happens only when two components rendering the same record set identical `dom_id_prefix`es (the default prefix is the component name). Give one of them a different prefix.

## Debug mode

To get additional diagnostic information, enable debug mode in an initializer:

```ruby
# config/initializers/reactive_component.rb
ReactiveComponent.debug = true
```

When debug mode is active, ReactiveComponent adds `data-reactive-debug` attributes to wrapper elements and serves component templates as plain text, making it easier to inspect what is being rendered and broadcast.

Disable debug mode before deploying to production.
