---
title: How It Works
description: Understand the architecture and data flow behind ReactiveComponent
---

ReactiveComponent turns ERB templates into live-updating UI without writing JavaScript. At boot time, it compiles your templates into JavaScript render functions. At runtime, when data changes, it evaluates only the dynamic expressions, sends a compact JSON payload over ActionCable, and the client re-renders the component in place.

## Architecture Overview

```
Server                                      Client
------                                      ------
ERB template                                Stimulus controller
    |                                           |
    v                                           v
Compiler (ERB -> Prism -> extract -> emit JS)    JS render function
    |                                           ^
    v                                           |
DataEvaluator (extracts expression values)  ActionCable subscription
    |                                           ^
    v                                           |
Broadcastable (after_commit callbacks) ---> Channel (broadcast_data)
```

## Boot-Time Compilation

When the Rails application boots, the `Compiler` processes each component's ERB template and turns it into a self-contained JavaScript render function. This happens once, not per-request.

The process has several steps:

1. **ERB to Ruby.** Erubi turns the template into a Ruby program that appends to a buffer; Prism parses it.

2. **Expression extraction.** One pass over Prism's tree lifts every expression the server must evaluate — `@message.subject`, `Label.count`, `helper(x)`, `content.present?` — to a short key: `v0`, `v1`, and so on. Inside a `.each`, anything touching the loop variable becomes a per-item key (`item.v3`), and a per-item value used in a condition keeps its type (`false` stays `false`; `"false"` would be truthy in JavaScript).

3. **JS function generation.** The same pass emits the template's skeleton — literals, data reads, `if`/`unless`/ternaries, boolean and comparison operators, `.each` as `for..of`, tag-builder and nested-component helpers — as a JavaScript function. It is a whitelist, not a Ruby-to-JS converter: anything outside it raises `ReactiveComponent::CompileError` naming the source, at compile time, instead of being translated on a best-effort basis. Wherever a server expression appeared, the function reads from a data object (e.g. `data.v0`).

4. **Embedding.** The compiled JavaScript function is embedded in the page inside a `<script type="text/template">` tag. In production, the script content is Base64-encoded. In debug mode, it is stored as plain text for easier inspection.

The result is a render function that knows the shape of the template but holds no data of its own.

## Data Evaluation

When a model record changes, the `DataEvaluator` runs the extracted expressions against that record's context and collects their current values.

For simple scalar expressions like `@message.subject`, evaluation is straightforward. For expressions inside `.each` loops, the evaluator handles per-item computed values and keeps track of which values belong to which iteration.

The output is a flat JSON object:

```json
{ "v0": "Hello, world", "v1": 42 }
```

This compact representation — expression keys mapped to their values — is what travels over the wire. ReactiveComponent never sends rendered HTML fragments. It sends only the data needed to re-render.

## Broadcast Flow

The `subscribes_to` declaration on a component automatically includes the `Broadcastable` module on the specified model. This registers three Active Record callbacks: `after_create_commit`, `after_update_commit`, and `after_destroy_commit`.

When any of those callbacks fires:

1. `ReactiveComponent.broadcast_for` is called for each component class registered to that model.
2. `DataEvaluator` produces the data payload for the changed record.
3. `Channel.broadcast_data` signs the ActionCable stream for that record and component, serializes the payload (optionally gzip-compressing it for large payloads), and pushes the message to ActionCable.

The signed stream name ensures that clients only receive data intended for the specific component instance they are subscribed to.

## Client-Side Rendering

The `reactive-renderer` Stimulus controller manages the client side. On page load it reads the signed stream name and template identifier from the component's wrapper element, subscribes to the ActionCable channel, and locates the compiled JS render function from the embedded `<script type="text/template">` tag.

When a broadcast arrives:

1. The controller receives the JSON data payload.
2. Any client-managed state (for example `{ expanded: true }`) is merged with the incoming server data.
3. The compiled render function is called with the merged data object.
4. The component's inner HTML is morphed to the function's output — with [Idiomorph](https://github.com/bigskysoftware/idiomorph) when `window.Idiomorph` is present (scroll positions and nested Stimulus controllers survive a push), or by replacing `innerHTML` otherwise.

Because the render function was compiled at boot time and the data payload is minimal, re-renders are fast and require no round-trip to generate HTML on the server.

## The Wrapper Element

The `Wrapper` module is responsible for generating the outer `<div>` that ties everything together. It sets the Stimulus `data-controller` attribute and populates the data values the controller needs:

- `id` — the wrapper's DOM id, prefixed with the component (`message_row_message_1`). Broadcasts are routed to a component by this id, so two components rendering the same record must never share one; `dom_id_prefix` overrides the default.
- `data-reactive-renderer-stream-value` — the signed ActionCable stream name for this record and component.
- `data-reactive-renderer-template-id-value` — the identifier used to locate the compiled JS function.
- Action token and URL attributes for `live_action` support, enabling server-side callbacks triggered from the component.
- State and data attributes for seeding initial client state and the first render.

This means each component instance on the page is fully self-contained: it carries its own subscription credentials, its own template reference, and its own initial data, all in HTML attributes.
