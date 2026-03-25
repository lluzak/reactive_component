---
title: Collections & Loops
description: Using .each loops and collections in reactive component templates
---

## Basic Collection Rendering

Use standard Ruby `.each` loops in your ERB templates to render collections reactively:

```erb
<ul>
  <% @task.subtasks.each do |subtask| %>
    <li class="<%= subtask.completed? ? "done" : "" %>">
      <%= subtask.title %>
    </li>
  <% end %>
</ul>
```

When `@task` changes on the server, the entire list re-renders on the client with the updated subtasks.

## How It Works

When the compiler encounters a `.each` block, it processes it in several stages:

### Collection Extraction

The collection source (e.g. `@task.subtasks`) is extracted as a server-evaluated expression. The server evaluates it, serializes the full collection as JSON, and sends it to the client as part of the component's data payload.

### Block Variable Tracking

The block variable (e.g. `subtask`) is tracked by the compiler. Any expression inside the loop block that references the block variable is identified and handled specially.

### Per-Item Evaluation

Expressions inside the block that reference **both** server data (constants, class methods, other instance variables) and the block variable are recorded as "collection computed" expressions. During data evaluation, the `DataEvaluator` iterates over the collection and evaluates these expressions for each item separately, producing a per-item results array.

### Client-Side Loop

The compiled JavaScript uses a `for...of` loop over the collection data. For each item, it applies the corresponding per-item computed values produced by the server, then renders the item's markup.

## Mixed Expressions in Loops

Expressions inside a loop can mix server-side constants or helpers with block variables:

```erb
<% @message.labels.each do |label| %>
  <span class="badge" style="background: <%= LabelBadgeComponent::COLORS.fetch(label.color) %>">
    <%= label.name %>
  </span>
<% end %>
```

Here is how the compiler handles each expression:

- `@message.labels` — extracted as the collection source, evaluated on the server and sent as JSON.
- `label.name` — treated as a simple property access on the loop item; resolved client-side from the collection data.
- `LabelBadgeComponent::COLORS.fetch(label.color)` — a **block computed** expression. It references both a server-side constant (`LabelBadgeComponent::COLORS`) and the block variable (`label.color`), so it cannot be resolved purely on the client. The server evaluates it once per item and includes the results alongside the collection data.

## Limitations

- **Only `.each` is supported.** Other Enumerable methods such as `.map`, `.select`, `.reject`, and `.flat_map` are not compiled to client-side loops. If you need filtering or transformation, do it before passing data to the template (e.g. compute a filtered collection in a helper or model method and iterate over that).
- **Nested loops are not currently supported.** A `.each` loop inside another `.each` block will not compile correctly. Flatten the data structure on the server before rendering, or extract the inner loop into a sub-component.
- **The entire collection is serialized as JSON.** For very large collections this can result in a large payload. Consider pagination or loading strategies to keep collection sizes manageable.
