---
title: DSL Reference
description: Complete reference for ReactiveComponent DSL methods
---

All DSL methods are available as class methods after you `include ReactiveComponent` in your ViewComponent.

```ruby
class MyComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :record
  broadcasts stream: ->(record) { [record.user, :items] }
  live_action :do_something, params: [:value]
  client_state :expanded, default: false
end
```

---

## `subscribes_to(attr_name, class_name: nil, only: %i[create update destroy])`

Declares which instance variable holds the model record that drives the component. Calling this method also **automatically wires the model** — no changes to the model class are needed. ReactiveComponent includes `ReactiveComponent::Broadcastable` on the model and registers `after_create_commit`, `after_update_commit`, and `after_destroy_commit` callbacks that trigger broadcasts.

**Parameters:**

| Name | Type | Description |
|:-----|:-----|:------------|
| `attr_name` | `Symbol` | The name of the instance variable (without the `@` prefix). |
| `class_name:` | `String` or `nil` | Optional explicit model class name. Use this when the class name cannot be inferred from the attribute name (e.g. namespaced models). |
| `only:` | `Symbol` or `Array<Symbol>` | Limits which lifecycle events trigger a broadcast. Accepts any combination of `:create`, `:update`, `:destroy`. Defaults to all three. |

**Examples:**

```ruby
# Simple model — @comment ivar, resolves to Comment
class CommentComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :comment

  def initialize(comment:)
    @comment = comment
  end
end
```

```ruby
# Namespaced model — @notification ivar, resolves to Inbox::Notification
class NotificationRowComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :notification, class_name: "Inbox::Notification"

  def initialize(notification:)
    @notification = notification
  end
end
```

```ruby
# Only re-render on update — ignore creates and destroys
class OrderStatusComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :order, only: :update

  def initialize(order:)
    @order = order
  end
end
```

The framework uses this to:
- Look up the record for data extraction and re-rendering
- Generate DOM IDs for the component wrapper
- Resolve the model class when handling channel updates and executing server actions
- Auto-wire the model with `after_commit` callbacks (idempotent — safe to call from multiple components)

---

## `broadcasts(stream:, prepend_target: nil)`

Declares the ActionCable stream that carries updates for this component. **Optional** — when omitted, the record itself is used as the default stream.

**Parameters:**

| Name | Type | Description |
|:-----|:-----|:------------|
| `stream:` | `Proc` or streamable | The stream identifier. Typically a lambda that receives the record and returns a streamable value (an array, string, or ActiveRecord object). |
| `prepend_target:` | `String` or `nil` | Optional DOM ID of a container element. When set, newly created records are rendered via Turbo Streams and prepended to this target. Requires `ReactiveComponent.renderer` to be configured. |

**Example:**

```ruby
class TaskComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :task
  broadcasts stream: ->(task) { [task.project, :tasks] },
             prepend_target: "task_list"

  def initialize(task:)
    @task = task
  end
end
```

The stream value is signed using `Turbo::StreamsChannel.signed_stream_name` before being sent to the client, preventing unauthorized subscriptions.

When `prepend_target` is provided, newly created records are rendered server-side and prepended to the specified DOM element via Turbo Streams. This requires `ReactiveComponent.renderer` to be set (e.g. `ApplicationController`) in your application initializer.

---

## `broadcast_reactive_update`

Manually triggers a reactive broadcast for the model record. This is a public instance method available on any model that has been wired by `subscribes_to`. It broadcasts an `:update` event to all connected components without requiring the record to be saved or touched.

This is useful when a related record changes (e.g. a join table) and the component needs to re-render, but the model itself wasn't modified.

**Example — broadcasting after a join table change:**

```ruby
class MessageLabelsComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :message
  broadcasts stream: ->(message) { [message.recipient, :messages] }
  live_action :add_label, params: [:label_id]
  live_action :remove_label, params: [:label_id]

  def initialize(message:)
    @message = message
  end

  private

  def add_label(label_id:)
    @message.labels << Label.find(label_id)
    @message.broadcast_reactive_update
  end

  def remove_label(label_id:)
    @message.labelings.find_by(label_id: label_id)&.destroy
    @message.broadcast_reactive_update
  end
end
```

In this example, adding or removing a label modifies the `labelings` join table — not the `Message` record itself. Without `broadcast_reactive_update`, the `after_update_commit` callback on `Message` would never fire, and connected clients would not see the change.

**When to use:**

- After modifying associated records (join tables, `has_many` children) that affect the component's rendered output
- After external events (webhooks, background jobs) that change data the component displays
- Any time you need to push an update without touching the record's own attributes

**When not to use:**

- After `save!` or `update!` on the record itself — the `after_commit` callbacks already handle this automatically

---

## `live_action(action_name, params: [])`

Registers a server-side action that can be invoked from the client.

**Parameters:**

| Name | Type | Description |
|:-----|:-----|:------------|
| `action_name` | `Symbol` | The name of the action. A private method with this name must be defined on the component. |
| `params:` | `Array<Symbol>` | Optional list of parameter names the action accepts from the client. Only these parameters will be passed through. |

**Example:**

```ruby
class TodoComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :todo
  broadcasts stream: ->(todo) { [todo.list, :todos] }
  live_action :toggle_complete
  live_action :update_title, params: [:title]

  def initialize(todo:)
    @todo = todo
  end

  private

  def toggle_complete
    @todo.update!(completed: !@todo.completed?)
  end

  def update_title(title:)
    @todo.update!(title: title)
  end
end
```

**Triggering from the template:**

Actions are triggered using the `performAction` Stimulus action with params:

```erb
<button data-action="click->reactive-renderer#performAction"
        data-reactive-renderer-action-param="toggle_complete">
  Done
</button>
```

For actions that accept parameters, pass them as additional Stimulus params:

```erb
<button data-action="click->reactive-renderer#performAction"
        data-reactive-renderer-action-param="update_title"
        data-reactive-renderer-title-param="New Title">
  Rename
</button>
```

**Security:** Each component instance generates a signed token (`live_action_token`) that is embedded in the wrapper `<div>`. The server verifies this token before executing any action, ensuring that the component class and record cannot be tampered with.

---

## `client_state(name, default: nil)`

Declares a client-only state field managed in JavaScript. Client state is useful for ephemeral UI concerns like toggles, selections, or expanded/collapsed sections that do not need to be persisted on the server.

**Parameters:**

| Name | Type | Description |
|:-----|:-----|:------------|
| `name` | `Symbol` | The name of the state field. An instance variable with this name will be available in the template. |
| `default:` | any | The default value for the state field when the component is first rendered. Defaults to `nil`. |

**Example:**

```ruby
class AccordionComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :section
  broadcasts stream: ->(section) { [section.page, :sections] }
  client_state :expanded, default: false

  def initialize(section:, expanded: false)
    @section = section
    @expanded = expanded
  end
end
```

### Toggling client state

Use the `setState` Stimulus action to update client state from the template. Pass the state field name and value as Stimulus params:

```erb
<div class="accordion">
  <button data-action="click->reactive-renderer#setState"
          data-reactive-renderer-expanded-param="true">
    <%= @section.title %>
  </button>

  <% if @expanded %>
    <div class="accordion-body">
      <%= @section.content %>
    </div>
  <% end %>
</div>
```

When `setState` is called, the component immediately re-renders on the client using the compiled template, merging the new client state with the last server data. No server round-trip occurs.

### Exclusive state

When multiple sibling components share a client state field that should be mutually exclusive (e.g. selecting one row deselects the others), pass the `exclusive` param:

```erb
<a data-action="click->reactive-renderer#setState"
   data-reactive-renderer-selected-param="true"
   data-reactive-renderer-exclusive-param="true">
  <%= @message.subject %>
</a>
```

When `exclusive` is set to `true`, `setState` will:
1. Find all sibling elements (direct children of the same parent) that use the `reactive-renderer` controller
2. Set the matching state fields to `false` on each sibling
3. Re-render any siblings whose state changed
4. Set the state to `true` on the clicked component and re-render it

This is useful for list selections, tab groups, or any UI where only one item can be active at a time.

**Full example — selectable message list:**

```ruby
class MessageRowComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :message
  broadcasts stream: ->(message) { [message.recipient, :messages] }
  client_state :selected, default: false

  def initialize(message:, selected: false)
    @message = message
    @selected = selected
  end
end
```

```erb
<a href="<%= message_path(@message) %>"
   class="<%= @selected ? 'bg-blue-50' : 'hover:bg-gray-50' %>"
   data-turbo-frame="message_detail"
   data-action="click->reactive-renderer#setState"
   data-reactive-renderer-selected-param="true"
   data-reactive-renderer-exclusive-param="true">
  <strong><%= @message.subject %></strong>
</a>
```

Clicking a row highlights it and deselects any previously selected row — all without a server request. Turbo frame navigation still works because the re-render is deferred with `requestAnimationFrame`.

### How client state works

Client state fields are:
- Serialized as JSON in the component wrapper's `data-reactive-renderer-state-value` attribute
- Maintained across server-driven re-renders (the client merges server data with current client state)
- Available in the ERB template as regular instance variables
- Initialized from the `default:` value on first render, or from the constructor argument if provided
- Updated on the client only — they never trigger a server request or broadcast
