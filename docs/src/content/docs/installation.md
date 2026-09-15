---
title: Installation
description: How to install ReactiveComponent in your Rails application
---

## 1. Add the gems

Add ReactiveComponent and its dependencies to your `Gemfile`:

```ruby
gem "reactive_component"
```

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
import ReactiveRendererController from "reactive_component/controllers/reactive_renderer_controller"

application.register("reactive-renderer", ReactiveRendererController)
```

### Other bundlers

If you are using esbuild, Vite, Rspack, or another bundler, install the JavaScript package from npm. Install it under the `reactive_component` alias, matching the gem version. The controller imports its helpers by that name, the same way the importmap pins it:

```bash
npm install reactive_component@npm:@lluzak/reactive_component@0.8.1
# or
pnpm add reactive_component@npm:@lluzak/reactive_component@0.8.1
```

Either command writes the alias to your `package.json`. You can also add it by hand and run `npm install` or `pnpm install`:

```json
"dependencies": {
  "reactive_component": "npm:@lluzak/reactive_component@0.8.1"
}
```

No bundler configuration is needed. Register the controller as shown above:

```javascript
import ReactiveRendererController from "reactive_component/controllers/reactive_renderer_controller"
```

The package lists `@hotwired/stimulus` and `@rails/actioncable` as peer dependencies, so install them too if your app doesn't have them yet.

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
| `prism` | ~> 1.0 | Parsing the ERB-compiled Ruby; the extractor and emitter walk its tree |
| `erubi` | ~> 1.11 | ERB to Ruby |
