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

## `subscribes_to(attr_name, class_name: nil)`

Declares which instance variable holds the model record that drives the component.

**Parameters:**

| Name | Type | Description |
|:-----|:-----|:------------|
| `attr_name` | `Symbol` | The name of the instance variable (without the `@` prefix). |
| `class_name:` | `String` or `nil` | Optional explicit model class name. Use this when the class name cannot be inferred from the attribute name (e.g. namespaced models). |

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

The framework uses this to:
- Look up the record for data extraction and re-rendering
- Generate DOM IDs for the component wrapper
- Resolve the model class when handling channel updates and executing server actions

---

## `broadcasts(stream:, prepend_target: nil)`

Declares the ActionCable stream that carries updates for this component.

**Parameters:**

| Name | Type | Description |
|:-----|:-----|:------------|
| `stream:` | `Proc` or streamable | The stream identifier. Typically a lambda that receives the record and returns a streamable value (an array, string, or ActiveRecord object). |
| `prepend_target:` | `String` or `nil` | Optional DOM ID of a container element. When set, new records are prepended to this target instead of replacing existing components. |

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

When `prepend_target` is provided, newly created records broadcast to the stream will be rendered and prepended to the specified DOM element.

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

Actions are triggered using Stimulus data attributes on interactive elements:

```erb
<button data-action="click->reactive-renderer#action"
        data-reactive-action="toggle_complete">
  Done
</button>
```

For actions that accept parameters, pass them as `data-reactive-param-*` attributes:

```erb
<button data-action="click->reactive-renderer#action"
        data-reactive-action="update_title"
        data-reactive-param-title="New Title">
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

```erb
<div class="accordion">
  <button data-action="click->reactive-renderer#toggleState"
          data-reactive-state="expanded">
    <%= @section.title %>
  </button>

  <% if @expanded %>
    <div class="accordion-body">
      <%= @section.content %>
    </div>
  <% end %>
</div>
```

Client state fields are:
- Serialized as JSON in the component wrapper's `data-reactive-renderer-state-value` attribute
- Maintained across server-driven re-renders (the client merges server data with current client state)
- Available in the ERB template as regular instance variables
- Initialized from the `default:` value on first render, or from the constructor argument if provided
