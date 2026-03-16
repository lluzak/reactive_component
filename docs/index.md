---
layout: default
title: Home
nav_order: 1
---

# ReactiveComponent

**Reactive server-rendered components for Rails via ActionCable**
{: .fs-6 .fw-300 }

ReactiveComponent lets you build server-rendered [ViewComponent](https://viewcomponent.org/) components that automatically re-render on the client when data changes, without full page reloads. It compiles your ERB templates to JavaScript at boot time and uses ActionCable to push updates in real time.

[Get started]({% link quick-start.md %}){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/lluzak/reactive_component){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## Key Features

- **Declarative DSL** -- Define reactive behavior with `subscribes_to`, `broadcasts`, `live_action`, and `client_state` right inside your component class.
- **Automatic ERB-to-JS compilation** -- Your existing ERB templates are compiled to JavaScript render functions at boot time via ruby2js. No need to maintain separate client-side templates.
- **ActionCable-powered live updates** -- When a model changes on the server, broadcasts flow through ActionCable and the client re-renders the component instantly with fresh data.
- **Secure server actions** -- Trigger server-side logic from the client using `live_action`. Actions are verified with signed tokens so they cannot be tampered with.
- **Client-side state** -- Use `client_state` to declare ephemeral UI state (e.g. toggles, selections) that lives in the browser and is passed into the template on every render.

---

## Quick Example

```ruby
class MessageRowComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :message
  broadcasts stream: ->(message) { [message.recipient, :messages] },
             prepend_target: "message_items"
  live_action :toggle_star
  client_state :selected, default: false

  def initialize(message:, selected: false)
    @message = message
    @selected = selected
  end

  private

  def toggle_star
    @message.toggle_starred!
  end
end
```

```erb
<div class="message-row <%= "selected" if @selected %>">
  <span class="sender"><%= @message.sender.name %></span>
  <span class="subject"><%= @message.subject %></span>
  <span class="time"><%= time_ago_in_words(@message.created_at) %></span>
  <button data-action="click->reactive-renderer#action"
          data-reactive-action="toggle_star">
    <%= @message.starred? ? "Unstar" : "Star" %>
  </button>
</div>
```

Render it like any ViewComponent:

```erb
<%= render MessageRowComponent.new(message: @message) %>
```

When the message is updated anywhere in the system, the component re-renders on every connected client automatically.
