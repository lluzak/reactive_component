---
title: Presence
description: Show who else is on the page and what they are working on, over the same ActionCable stream
---

Presence shows who else is looking at the same thing, and what they are doing with it -- the field they are typing in, the row they have open. It rides the stream your components already broadcast on, keeps no server-side state, and stamps attributes rather than rendering markup, so what any of it looks like stays your decision.

## Identify the viewer

Presence is off until you say who a connection belongs to. Set a lambda that receives the ActionCable connection and returns a Hash, or `nil` to leave that connection out:

```ruby
# config/initializers/reactive_component.rb
ReactiveComponent.presence_identity = lambda do |connection|
  user = connection.current_user or next nil

  { id: user.id, name: user.first_name, color: user.avatar_color }
end
```

Every value must be a primitive, because the Hash is broadcast to everyone on the stream. Returning a record raises `UnsafeBroadcastValueError` rather than shipping every column, including `password_digest`.

Anonymous viewers returning `nil` never enter a roster and never broadcast. That is also the switch for turning presence off entirely.

## Add the controller

The controller needs the signed name of the stream to join. Components get one from their wrapper; a plain element needs `ReactiveComponent.signed_stream`:

```erb
<div data-controller="presence"
     data-presence-stream-value="<%= ReactiveComponent.signed_stream(@board, :collaborators) %>">

  <textarea name="body"
            data-presence-field="body"
            data-action="focus->presence#claim blur->presence#release"></textarea>
</div>
```

`claim` records the `data-presence-field` of whatever was focused and announces it. `release` clears it. Everything else is automatic.

## What gets stamped

The controller writes attributes and nothing else. It never re-renders the component and never touches the morph path:

| Attribute | Where | Meaning |
| --- | --- | --- |
| `data-presence-here` | the controller element | at least one other viewer is on this stream |
| `data-presence-busy="Ana, Tom"` | each `[data-presence-field]` | those people are in that field |

Style them however you like. Nothing below ships with the gem:

```css
.field:has([data-presence-busy]) textarea {
  border-color: var(--presence-accent);
}

.field:has([data-presence-busy])::after {
  content: attr(data-presence-busy) " is editing";
}
```

For anything richer than an attribute, listen for the event the controller dispatches on every change:

```js
element.addEventListener("reactive-presence:changed", (event) => {
  renderAvatars(event.detail.others)  // [{ user, state, lastSeen }, ...]
})
```

## The wire

Three frames, all on the stream you already subscribe to:

```js
// client → server, on connect and every 10s
announce({ state: { field: "body" } })

// server → everyone on the stream
{ action: "presence",       user: { id: 5, name: "Ana" }, state: { field: "body" } }
{ action: "presence_leave", user: { id: 5, name: "Ana" } }

// server → this connection only, on its first announce
{ action: "presence_self",  user: { id: 5, name: "Ana" } }
```

`presence_self` exists because ActionCable echoes a broadcast back to its sender. Without it a viewer would end up in their own roster, and you would be looking at your own avatar.

Renderer components on the same stream ignore these frames, so a presence controller and a reactive component can share one subscription.

## What can be trusted

**Identity is server-stamped. State is not.** A client sends `state` and only `state`; the identity in every frame comes from your lambda, by way of the connection. A tampered frame can misreport what someone is doing. It can never misreport who they are.

State is the only client-authored payload this gem broadcasts, so it is capped:

```ruby
ReactiveComponent.presence_state_limit = 1024 # bytes of encoded JSON
```

The cap is the real protection. State also passes through `sanitize_for_broadcast`, but over a JSON transport that can only ever see primitives anyway. It stays as defence in depth, and because it is what catches an identity lambda that returns a record.

## How a roster stays honest

Each browser keeps its own roster in memory. There is no Redis set, no table, and no sweeper job -- ActionCable's existing fan-out already crosses app servers.

An entry expires **30 seconds** after that viewer was last heard from, and every viewer announces every **10 seconds**. A `presence_leave` on disconnect is a fast path, not the mechanism: a killed tab, a closed laptop and a dead cable worker never run the unsubscribe callback, and all three resolve the same way, by expiry.

```erb
<div data-controller="presence"
     data-presence-ttl-value="60000"
     data-presence-stream-value="...">
```

## What it costs

Two limits worth knowing before you switch this on:

**Joining is not instant.** There is no hello handshake, so a newcomer waits up to one heartbeat to see the room. The alternative was every peer re-announcing at once on every arrival.

**Announce traffic is O(n²) per stream.** Every viewer's heartbeat reaches every other viewer. At one frame per 10 seconds that is nothing for a handful of people on a document. Past roughly 50 concurrent viewers on a single stream it wants a Redis-backed roster on the server instead.
