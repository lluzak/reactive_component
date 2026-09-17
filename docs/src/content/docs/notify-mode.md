---
title: Notify Mode
description: Re-render a component from the server instead of the broadcast payload
---

## Overview

By default a component uses the **push** strategy: when its record changes, the broadcast carries the new data and every client renders it straight away.

In **notify** mode the broadcast is only a signal. The component asks the server for a fresh render of its record, and the server can answer with that render or with an instruction to remove the component. Use it when the pushed data isn't enough to decide what to show:

- A filtered list, where a row should leave once its record no longer matches the filter (a message unstarred while you look at Starred).
- A component whose output depends on page parameters the broadcast doesn't know about.

## Turning it on

Define a private `live_wrapper_options` method on the component and return `strategy: :notify`. It runs per instance, so the same component can push in one list and notify in another:

```ruby
class MessageRowComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :message
  broadcasts stream: ->(message) { [message.recipient, :messages] }

  def initialize(message:, folder: nil)
    @message = message
    @folder = folder
  end

  private

  def live_wrapper_options
    return {} unless @folder == "starred"

    { strategy: :notify, params: { folder: @folder } }
  end
end
```

```erb
<% @messages.each do |message| %>
  <%= render MessageRowComponent.new(message: message, folder: @folder) %>
<% end %>
```

`live_wrapper_options` accepts:

| Key | Description |
|:----|:------------|
| `strategy` | `:notify` to turn notify mode on. Anything else, or no key, keeps push, unless the class declares notify (below). |
| `params` | A hash sent back to the server with every re-render request and passed to the filter. |
| `component_name` | The component class the server renders. Defaults to the component's own class. |
| `skip_own_broadcasts` | Skip the re-render request after this component's own `live_action`. Defaults to [`ReactiveComponent.skip_own_broadcasts`](/reactive_component/configuration/#reactivecomponentskip_own_broadcasts). |

A notify wrapper also carries a signed id of its record, minted for this gem alone. It is what the server resolves the re-render request against, so nothing has to trust a raw id from the page.

## Declaring it on the class

When every instance notifies, declare it on `subscribes_to` instead:

```ruby
subscribes_to :message, strategy: :notify
```

A broadcast then carries only the signal, not a rendered payload nobody would read, and `live_wrapper_options` is only needed for `params` and the other keys. Such a class cannot be switched back to push per instance: the broadcast has no data for a push client to render, so `render_in` raises if `live_wrapper_options` tries.

## Filtering

`ReactiveComponent::Channel.filter_callback` decides whether the record still belongs on the page. Return `false` and the client removes the component:

```ruby
# config/initializers/reactive_component.rb
Rails.application.config.to_prepare do
  ReactiveComponent::Channel.filter_callback = ->(record, params) {
    params["folder"] != "starred" || record.starred?
  }
end
```

Set it inside `to_prepare`: the channel is autoloaded, so it doesn't exist yet while initializers run.

There is one callback for the whole app, so it sees records from every notify component. Check `params` (or the record's class) before applying a rule meant for one list. Without a callback every request re-renders.

## What happens on a change

1. The record commits and its component class broadcasts `update` on the stream.
2. Each client finds the component showing that record. Components for other records on the same stream ignore the message.
3. The component waits 50 ms, so a burst of changes becomes one request, then sends `request_update` over its cable subscription with its component name, its signed record id, and `params`.
4. The channel resolves the signed id, checks the record broadcasts to the stream this client subscribed to, then runs the filter.
5. It transmits `render` with fresh data, or `remove` when the filter returned `false`.

A destroyed record's component is removed straight from the `destroy` broadcast; there is nothing left to render. Creates are unaffected: `prepend_target` still inserts new rows.

## Cost

Push costs one render per change, on the server, shared by every viewer. Notify adds one request and one render per viewer showing the changed record. Ten viewers on a list mean ten renders of that one row per change. Other rows on the page don't take part.

## Security

A re-render request names its record with a signed global id, not a raw one. An id this gem did not sign, one signed elsewhere in the app for another purpose, one that has expired, or one whose row is gone: every one of them is a miss. The record must also broadcast to the signed stream this client subscribed to, and the component class must include `ReactiveComponent`. Anything else is ignored.

`params` are written into the page and sent back by the browser, so a user can change them. The filter decides what to display, never what a user may see: authorize through the stream.
