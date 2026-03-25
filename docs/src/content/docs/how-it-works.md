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
Compiler (ERB -> ruby2js -> JS function)    JS render function
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

1. **ERB to Ruby.** The template is parsed using `Ruby2JS::Erubi`, which converts the ERB markup into a Ruby expression tree.

2. **Expression extraction.** The `ErbExtractor` filter walks the AST and identifies expressions that must be evaluated on the server — things like `@message.subject` or `Label.count`. Each expression is assigned a short, unique key: `v0`, `v1`, `v2`, and so on.

3. **JS function generation.** `ruby2js` converts the remaining template logic — conditionals, loops, interpolation — into a JavaScript function. Wherever a server expression appeared, the function now reads from a data object (e.g. `data.v0`).

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
4. The component's inner HTML is replaced with the function's output.

Because the render function was compiled at boot time and the data payload is minimal, re-renders are fast and require no round-trip to generate HTML on the server.

## The Wrapper Element

The `Wrapper` module is responsible for generating the outer `<div>` that ties everything together. It sets the Stimulus `data-controller` attribute and populates the data values the controller needs:

- `data-reactive-renderer-stream-value` — the signed ActionCable stream name for this record and component.
- `data-reactive-renderer-template-id-value` — the identifier used to locate the compiled JS function.
- Action token and URL attributes for `live_action` support, enabling server-side callbacks triggered from the component.
- State and data attributes for seeding initial client state and the first render.

This means each component instance on the page is fully self-contained: it carries its own subscription credentials, its own template reference, and its own initial data, all in HTML attributes.
