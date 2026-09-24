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

An entry expires **90 seconds** after that viewer was last heard from, and every viewer announces every **10 seconds**. A `presence_leave` on disconnect is a fast path, not the mechanism: a killed tab, a closed laptop and a dead cable worker never run the unsubscribe callback, and all three resolve the same way, by expiry.

The gap between those two numbers is deliberate. Browsers throttle timers in a hidden tab to roughly once a minute, so a backgrounded viewer's heartbeat can be a minute late even though their connection is perfectly healthy. An expiry near the heartbeat interval would drop anyone who switches tabs, taking their cursor with them. A returning tab also announces immediately on `visibilitychange`, so it reappears without waiting out a beat.

```erb
<div data-controller="presence"
     data-presence-ttl-value="60000"
     data-presence-stream-value="...">
```

## Live cursors

A cursor is more presence state, on a stream of its own. Turn it on per element:

```erb
<div data-controller="presence"
     data-presence-cursors-value="true"
     data-presence-anchor="<%= dom_id(@board) %>"
     data-presence-stream-value="<%= ReactiveComponent.signed_stream(@board, :collaborators) %>">
```

Then give people the two controls. Both are opt-in, and both are needed before a single frame moves:

```erb
<button data-action="presence#shareCursor">Share my cursor</button>

<%# one per peer, rendered from the changed event %>
<button data-action="presence#watch" data-presence-user-id-param="<%= peer.id %>">Follow</button>
```

### Routed, not filtered

Each sharer publishes to a stream named for them, and you receive it only after asking:

```
<signed stream>:cursor:<user id>
```

Filtering in the browser would be no help at all: the frames would already have crossed the wire. Routing per user means they are never sent, so a sharer nobody follows costs one publish into an empty channel.

Authorization needs no server-side roster. A cursor stream is a child of the stream the connection already verified, and a sharer can only ever publish to their own, so the worst a watcher can do is subscribe to somebody who never opted in and receive nothing.

Watching is one person at a time.

### Silence is the default

A watch is announced like any other state, so a sharer can read off their own roster whether anybody is actually looking. If nobody is, the browser never installs a `mousemove` listener. Cursor traffic is exactly zero until two people both ask for it.

### Coordinates are fractions, never pixels

A frame carries a fraction of a named anchor:

```json
{ "a": "board_42", "x": 0.42, "y": 0.61 }
```

The receiver multiplies back through *its own* rect, so a different viewport width, a scroll offset or a reflowed sidebar still land the ghost on the element the sender was pointing at. Absolute pixels are right only when both windows happen to be the same size. A frame whose anchor is not on this page is skipped rather than guessed at.

The anchor name is yours to choose; `dom_id(record)` is already unique and already in your markup.

### Rendering

Ghosts are `div.reactive-presence-cursor` inside a `div.reactive-presence-layer` the controller appends to your element. They live outside any reactive wrapper and move by `transform` alone, so 20 Hz never reaches a component's DOM and never goes through a morph. Style them yourself:

```css
.reactive-presence-layer { position: absolute; inset: 0; pointer-events: none; overflow: hidden; }

.reactive-presence-cursor {
  position: absolute;
  top: 0;
  left: 0;
  transition: transform 85ms linear;
  background: var(--presence-color);
}

.reactive-presence-cursor::after { content: attr(data-presence-user); }
```

Give the element itself `position: relative` so the layer has something to sit in.

For anything that should travel with somebody's pointer -- a drag preview, a follow-the-leader viewport -- listen for the cursor event rather than repeating the anchor arithmetic:

```js
element.addEventListener("reactive-presence:cursor", (event) => {
  const { user, at, layer } = event.detail

  if (!at) return removePreviewFor(user)   // they stopped, or let go
  movePreviewFor(user, at.x, at.y, layer)  // pixels inside the cursor layer
})
```

`at` is already resolved into this page's own coordinates, so a card dragged in one browser can be drawn under the right pointer in another whatever the window size.

### What cursors cost

Sampling is throttled to 20 Hz with a dead band, and the throttle *is* the batch: coalescing to the newest point beats shipping an array of them, because every older point is garbage the moment a newer one exists.

Even so, 20 frames a second against the roster's one per ten seconds is three orders of magnitude more traffic per watcher. That is why cursors are off by default and why the routing exists. Before switching them on, multiply 20 by the number of watch relationships you expect, not by the number of viewers.

## What it costs

Two limits worth knowing before you switch this on:

**Joining answers back.** A viewer who receives a frame from somebody not already in their roster answers at once, and at most once every half second. The reply is deliberately not on a timer: the viewer who has to answer is often the one in a background tab, where a timer is throttled to about once a minute, which is exactly the wait the reply exists to avoid. That costs one reply per arrival rather than per heartbeat, and it is what makes a newcomer visible immediately instead of after a beat.

This matters more than it sounds. A browser throttles timers in a hidden tab to roughly once a minute, so without the reply a newcomer could sit for a full minute before an existing viewer in a background tab announced itself.

**Announce traffic is O(n²) per stream.** Every viewer's heartbeat reaches every other viewer. At one frame per 10 seconds that is nothing for a handful of people on a document. Past roughly 50 concurrent viewers on a single stream it wants a Redis-backed roster on the server instead.
