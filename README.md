# ReactiveComponent

[![CI](https://github.com/lluzak/reactive_component/actions/workflows/ci.yml/badge.svg)](https://github.com/lluzak/reactive_component/actions/workflows/ci.yml)
[![Docs](https://github.com/lluzak/reactive_component/actions/workflows/docs.yml/badge.svg)](https://lluzak.github.io/reactive_component/)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.1-red.svg)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-%3E%3D%207.1-red.svg)](https://rubyonrails.org/)

Reactive server-rendered components for Rails via ActionCable. Build [ViewComponent](https://viewcomponent.org/) components that automatically re-render on the client when data changes — no full page reloads needed.

ReactiveComponent compiles your ERB templates to JavaScript at boot time and uses ActionCable to push updates in real time.

**[Documentation](https://lluzak.github.io/reactive_component/)** | **[Quick Start](https://lluzak.github.io/reactive_component/quick-start.html)** | **[DSL Reference](https://lluzak.github.io/reactive_component/dsl-reference.html)**

## Quick Example

```ruby
class MessageRowComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :message
  broadcasts stream: ->(message) { [message.recipient, :messages] }
  live_action :toggle_star
  client_state :selected, default: false

  def initialize(message:)
    @message = message
  end

  private

  def toggle_star
    @message.toggle_starred!
  end
end
```

```erb
<div class="message-row">
  <span><%= @message.sender.name %></span>
  <span><%= @message.subject %></span>
  <button data-action="click->reactive-renderer#action"
          data-reactive-action="toggle_star">
    <%= @message.starred? ? "Unstar" : "Star" %>
  </button>
</div>
```

When the message is updated anywhere in the system, the component re-renders on every connected client automatically.

## Installation

Add to your Gemfile:

```ruby
gem "reactive_component"
gem "ruby2js", github: "ruby2js/ruby2js"
```

Mount the engine in your routes:

```ruby
# config/routes.rb
mount ReactiveComponent::Engine => "/reactive_component"
```

See the [Installation guide](https://lluzak.github.io/reactive_component/installation.html) for full setup instructions.

## Features

- **Declarative DSL** — `subscribes_to`, `broadcasts`, `live_action`, `client_state`
- **Automatic ERB-to-JS compilation** — no separate client templates to maintain
- **ActionCable-powered live updates** — instant re-renders when data changes
- **Secure server actions** — HMAC-signed tokens prevent tampering
- **Client-side state** — ephemeral UI state managed in the browser
- **Multi-Rails support** — tested against Rails 7.1, 7.2, and 8.0

## Development

```bash
bin/setup
bundle exec rake test
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/lluzak/reactive_component.
