---
title: Nested Components
description: Render reactive components inside other reactive components
---

## Overview

ReactiveComponent supports nesting. A reactive component can render another reactive component inside its ERB template. When the parent re-renders on the client in response to a broadcast, nested components are also re-rendered with fresh data — no extra subscriptions or wiring required.

## How It Works

When the Compiler processes an ERB template and encounters a `render` call for another reactive component, it:

1. Detects the nested component class via the `nestable_checker` lambda configured on `ReactiveComponent`
2. Compiles the nested component's template into its own JavaScript render function
3. Embeds the nested render function inside the parent's compiled output
4. During data evaluation, builds data for both the parent and the nested component
5. Produces a single compiled template that can render the full component tree on the client

The result is that a parent component's broadcast triggers a full re-render of itself and all nested reactive components, using up-to-date data for each.

## Example

### Child component — `MessageLabelsComponent`

```ruby
class MessageLabelsComponent < ViewComponent::Base
  include ReactiveComponent

  subscribes_to :message

  def initialize(message:)
    @message = message
  end
end
```

```erb
<%# app/components/message_labels_component.html.erb %>
<div class="labels">
  <% @message.labels.each do |label| %>
    <span class="badge"><%= label.name %></span>
  <% end %>
</div>
```

### Parent component — `MessageDetailComponent`

```ruby
class MessageDetailComponent < ViewComponent::Base
  include ReactiveComponent

  subscribes_to :message
  broadcasts stream: ->(message) { [message.recipient, :messages] }

  def initialize(message:)
    @message = message
  end
end
```

```erb
<%# app/components/message_detail_component.html.erb %>
<div class="message-detail">
  <h2><%= @message.subject %></h2>
  <p><%= @message.body %></p>

  <%= render MessageLabelsComponent.new(message: @message) %>
</div>
```

When `MessageDetailComponent` broadcasts an update, the compiled template re-renders both the parent's content and the nested `MessageLabelsComponent`, reflecting any label changes alongside the updated message body.

## Requirements

- Both the parent and the nested component must `include ReactiveComponent` and declare `subscribes_to`
- The nested component must be rendered via `<%= render ComponentClass.new(...) %>` directly in the parent's ERB template
- `ReactiveComponent.renderer` must be set to a controller class (e.g. `ApplicationController`) so that nested render calls can be evaluated during server-side data extraction:

```ruby
# config/initializers/reactive_component.rb
ReactiveComponent.renderer = ApplicationController
```

## Limitations

**Components with a different `subscribes_to` target** can only be nested inside collection loops (`.each` blocks), not as standalone nested renders. The framework requires a per-item record to build data for each iteration. Attempting to nest a component that subscribes to a different model outside of a loop will raise an error at compile time.

**Keep nesting shallow.** Every level of nesting embeds an additional compiled JavaScript render function inside the parent's output. Deeply nested component trees increase the size of the compiled template sent to the client. Prefer flat structures and extract deeply nested subtrees into separate top-level subscriptions when possible.
