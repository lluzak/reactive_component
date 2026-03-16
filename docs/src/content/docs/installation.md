---
title: Installation
description: How to install ReactiveComponent in your Rails application
---

## 1. Add the gems

Add ReactiveComponent and its dependencies to your `Gemfile`:

```ruby
gem "reactive_component"
```

:::caution
ruby2js must be installed from the GitHub HEAD until the required ERB compilation features are released:

```ruby
gem "ruby2js", github: "ruby2js/ruby2js"
```
:::

Then install:

```bash
bundle install
```

## 2. Mount the engine

Add the engine to your `config/routes.rb` so the server-action endpoint is available:

```ruby
Rails.application.routes.draw do
  mount ReactiveComponent::Engine => "/reactive_component"

  # ... your other routes
end
```

This mounts a single `POST /reactive_component/actions` endpoint used by `live_action` to execute server-side actions securely.

## 3. JavaScript setup

### importmap-rails (default)

If your application uses [importmap-rails](https://github.com/rails/importmap-rails), ReactiveComponent automatically registers its import map pins when the engine loads. The engine pins all files under `app/javascript/reactive_component` so they are available to the asset pipeline.

You need to register the Stimulus controller in your application. In your JavaScript entrypoint (e.g. `app/javascript/controllers/index.js`), import and register the controller:

```javascript
import { application } from "controllers/application"
import ReactiveRendererController from "reactive_component/reactive_renderer_controller"

application.register("reactive-renderer", ReactiveRendererController)
```

### Other bundlers

If you are using esbuild, Vite, or another bundler, you can import the controller from the gem's `app/javascript` directory. Add the gem's JavaScript path to your bundler's configuration and import the controller as shown above.

## 4. ActionCable

ReactiveComponent requires ActionCable to be configured and running. Make sure your `config/cable.yml` is set up (Redis is recommended for production) and that ActionCable is mounted in your routes:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount ActionCable.server => "/cable"
  mount ReactiveComponent::Engine => "/reactive_component"
end
```

## Dependencies

ReactiveComponent depends on the following gems (declared in the gemspec):

| Gem | Version | Purpose |
|:----|:--------|:--------|
| `rails` | >= 7.1 | Framework |
| `view_component` | any | Base component library |
| `turbo-rails` | any | Stream signing and Turbo integration |
| `ruby2js` | GitHub HEAD | ERB-to-JavaScript template compilation |
| `prism` | any | Ruby source code parsing for ivar extraction |
