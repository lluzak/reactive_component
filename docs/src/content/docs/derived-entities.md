---
title: Derived Entities
description: Subscribe a component to an object built from several models
---

## Overview

Not every component maps to one ActiveRecord model. An order summary may combine an order, its payments, and its shipments. `ReactiveComponent::Entity` lets you describe such an object once, in its own class, and subscribe a component to it exactly like a model.

The entity owns the whole declaration: which record it is keyed on, which models feed it, and which columns matter. Nothing is added to the source models.

## Declaring an entity

```ruby
class OrderSummary
  include ReactiveComponent::Entity

  root :order
  rebuilds_on Order,    fields: %i[status total_cents]
  rebuilds_on Payment,  via: :order_id, fields: %i[amount]
  rebuilds_on Shipment, via: :order_id, fields: %i[delivered_at]

  def total    = order.payments.sum(:amount)
  def shipped? = order.shipments.any?(&:delivered?)
end
```

### `root(name, class_name: nil)`

The record the entity is keyed on. It defines:

- `initialize(order:)` and an `order` reader
- `id`, delegated to the root
- `OrderSummary.find(id)` and `OrderSummary.find_by(id:)`, used by the channel and the actions controller

`class_name` defaults to `name.classify`.

### `rebuilds_on(model, via: nil, fields: nil)`

Rebroadcast the entity after `model` commits.

- Omit `via:` when `model` is the root. Create, update and destroy map to the component's `:create`, `:update` and `:destroy` events.
- `via:` names the foreign key on a child model that points at the root. Child commits, including destroys, rebroadcast an `:update` for the parent entity.
- `fields:` limits updates to the listed columns. Creates and destroys always broadcast.

## Subscribing a component

```ruby
class OrderSummaryComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :summary, class_name: "OrderSummary"
  broadcasts stream: ->(summary) { [summary.order, :summary] }

  def initialize(summary:)
    @summary = summary
  end
end
```

```erb
<div>
  <span><%= @summary.total %></span>
  <% if @summary.shipped? %><span>Shipped</span><% end %>
</div>
```

## Live actions

`live_action` and `client_state` work unchanged. The entity is not a database row, so an action mutates the underlying records through it. The commits then flow back through `rebuilds_on`, and the component re-renders on every client.

```ruby
class OrderSummaryComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :summary, class_name: "OrderSummary"
  broadcasts stream: ->(summary) { [summary.order, :summary] }
  live_action :cancel

  def initialize(summary:)
    @summary = summary
  end

  private

  def cancel
    @summary.order.update!(status: "cancelled")   # Order commit → rebuilds_on Order → broadcast
  end
end
```

```erb
<button data-action="click->reactive-renderer#performAction"
        data-reactive-renderer-action-param="cancel">Cancel</button>
```

The action token carries the entity class and root id. The actions controller resolves it with `OrderSummary.find(id)`, so an entity that skips `root` must define `find` itself.

## Notes

- The default stream is `"order_summary/<id>"`, so two entity types keyed on the same id do not collide. Declare `broadcasts stream:` when you want a scoped stream.
- Entities keyed on something other than one root record skip `root` and define `initialize`, `id`, `find` and `find_by(id:)` themselves.
- Component classes must be loaded for the wiring to exist, as with models. Eager loading in production covers this.
- Several source records saved in one transaction broadcast once each.
