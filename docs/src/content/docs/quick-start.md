---
title: Quick Start
description: Build your first reactive component from scratch
---

This guide walks you through building your first reactive component from scratch.

## 1. Create a component

Generate a standard ViewComponent (or create the files manually):

```bash
bin/rails generate component Notification notification
```

This creates `app/components/notification_component.rb` and `app/components/notification_component.html.erb`.

## 2. Include ReactiveComponent and declare the model

Open the component class and include `ReactiveComponent`. Use `subscribes_to` to tell the framework which instance variable holds the model record:

```ruby
class NotificationComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :notification

  def initialize(notification:)
    @notification = notification
  end
end
```

`subscribes_to :notification` does two things: it tells the framework which ivar holds the record, and it **automatically wires `after_commit` callbacks on the `Notification` model** — no changes to the model are required.

## 3. Declare the broadcast stream

Use `broadcasts` to specify which ActionCable stream carries updates for this component. The `stream:` option is a lambda that receives the record and returns a streamable identifier:

```ruby
class NotificationComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :notification
  broadcasts stream: ->(notification) { [notification.user, :notifications] }

  def initialize(notification:)
    @notification = notification
  end
end
```

`broadcasts` is optional. When omitted, the record itself is used as the default stream. When a broadcast is sent to `[user, :notifications]`, every `NotificationComponent` subscribed to that stream will re-render.

## 4. Write the ERB template

Write a normal ERB template. ReactiveComponent compiles it to a JavaScript render function automatically at boot time -- you do not need to write any JavaScript:

```erb
<div class="notification <%= "unread" unless @notification.read? %>">
  <strong><%= @notification.title %></strong>
  <p><%= truncate(@notification.body, length: 100) %></p>
  <span class="time"><%= time_ago_in_words(@notification.created_at) %> ago</span>
</div>
```

The ERB expressions (e.g. `@notification.title`) are extracted and evaluated on the server when data changes. The resulting values are sent to the client, where the compiled JavaScript template re-renders the HTML.

## 5. Render the component in a view

Render the component like any ViewComponent:

```erb
<%# app/views/notifications/index.html.erb %>

<h1>Notifications</h1>

<div id="notifications">
  <% @notifications.each do |notification| %>
    <%= render NotificationComponent.new(notification: notification) %>
  <% end %>
</div>
```

The initial render happens server-side as usual. ReactiveComponent wraps each component in a `<div>` with Stimulus data attributes that connect it to ActionCable.

## 6. How updates flow

When the underlying model changes, updates flow through the system like this:

1. **Model changes on the server** -- A `Notification` record is created or updated.
2. **Broadcast** -- ReactiveComponent's `after_commit` callbacks (auto-wired by `subscribes_to`) broadcast the change to all relevant components.
3. **ActionCable delivers the data** -- The broadcast reaches all connected clients subscribed to the matching stream.
4. **Client re-renders** -- The Stimulus controller receives the new data and runs the compiled JavaScript template to produce fresh HTML, replacing the component's content in the DOM.

No full page reload occurs. The user sees the update instantly.

## Adding server actions

You can add interactive actions that execute on the server. Define them with `live_action` and implement the logic as a private method:

```ruby
class NotificationComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :notification
  broadcasts stream: ->(notification) { [notification.user, :notifications] }
  live_action :mark_as_read

  def initialize(notification:)
    @notification = notification
  end

  private

  def mark_as_read
    @notification.update!(read: true)
  end
end
```

Trigger the action from the template:

```erb
<div class="notification <%= "unread" unless @notification.read? %>">
  <strong><%= @notification.title %></strong>
  <p><%= truncate(@notification.body, length: 100) %></p>

  <% unless @notification.read? %>
    <button data-action="click->reactive-renderer#action"
            data-reactive-action="mark_as_read">
      Mark as read
    </button>
  <% end %>
</div>
```

When the button is clicked, the Stimulus controller sends a signed request to the server, which executes `mark_as_read`, updates the record, and broadcasts the change back to all clients.
