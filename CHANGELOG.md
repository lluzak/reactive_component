# Changelog

## [0.4.0] - 2026-04-18

### Security
- **Broadcast payloads now refuse non-primitive values.** Previously
  `build_data` could ship full `ActiveRecord` records over ActionCable,
  leaking every column (including `password_digest`, tokens). The
  sanitizer now raises `ReactiveComponent::UnsafeBroadcastValueError`
  with a context-aware hint pointing at the offending ERB expression.

### Added
- `ReactiveComponent.sanitize_for_broadcast(value, source:)` — the
  strict gatekeeper. Allows primitives (`nil`, booleans, `Integer`,
  `Float`, `String`), `Symbol` (downcast to `String`), and `Array`/
  `Hash` of those; raises on everything else.
- Node-based compiler regression test: actually executes compiled
  templates so undefined-identifier runtime bugs fail the build.
- `RichRowComponent` + `WrapperComponent` dummy fixtures exercising
  every shape that has historically broken the extractor.

### Fixed
- `<%= tag.xxx(attrs) do %> … <% end %>` now compiles into
  `_tag_open` + body + `_tag_close`, so inner expressions stay
  per-field reactive instead of collapsing into invalid JS.
- `<%= raw bare_helper %>` extracts the inner call as a server-
  computed raw field (previously emitted an undefined JS identifier).
- `**@options` keyword-splat on `tag.xxx` no longer emits `#options`
  (a JS private-field reference, which is a syntax error outside a
  class body).
- Bare helper calls in conditions and tag attrs (`banner_visible?`,
  `row_classes`, `status_label(@x)`) are extracted as server-computed
  fields instead of surfacing as undefined JS identifiers.
- Bare `<%= @ivar %>` output alongside `<%= @ivar.chain %>` — both
  destructures are now provided in the broadcast payload.
- ViewComponent sidecar template layout (`foo_component/foo_component.html.erb`)
  is now supported by `Compiler.read_erb`.
- `escapeHTML` is aliased in the compiled preamble (ruby2js emits it
  in some nested-component paths).
- `_render_attrs` now expands `data:`/`aria:` hashes, handles mixed
  `class: [string, {name => cond}]` arrays, and emits bare boolean
  attributes — matching Rails tag-builder semantics.
- Live-model ivar (e.g. `@message` under `subscribes_to :message`) is
  excluded from broadcast payloads — it's the subscription key, not a
  data field.

## [0.3.0] - 2026-04-16

### Added
- `broadcast_reactive_update` public method on models for manual broadcasts without touching the record
- Client state rendering: `setState` now re-renders components after updating client state
- Exclusive client state: `setState` with `exclusive` param deselects sibling components
- Folder navigation (Inbox, Starred, Sent, Archive, Trash) in dummy app
- Documentation for `client_state` usage (setState, exclusive mode, selectable lists)
- Documentation for `broadcast_reactive_update` with examples
- DataEvaluator tests for path helper resolution

### Fixed
- Path helpers (e.g. `message_path`) returning nil in reactive broadcasts — added engine initializer to finalize DataEvaluator at boot
- `setState` not triggering re-render after updating client state
- Turbo frame navigation breaking when `setState` morphed the DOM synchronously — deferred with `requestAnimationFrame`
- `live_action` documentation using outdated Stimulus data attribute conventions

## [0.2.0] - 2026-03-25

### Added
- "How It Works" architecture documentation page
- "Nested Components" guide
- "Collections & Loops" guide
- "Troubleshooting" page
- Enriched README with architecture summary, advanced features, and license section
- Reorganized docs sidebar for logical learning path

## [0.1.0] - 2026-03-15

### Added
- Initial extraction of reactive component system
- Core `ReactiveComponent` concern with DSL: `subscribes_to`, `broadcasts`, `live_action`, `client_state`
- ERB-to-JavaScript compiler pipeline for client-side re-rendering
- ActionCable channel with configurable `filter_callback` for broadcast filtering
- Actions controller for secure server-side action invocation
- Stimulus controller and utilities for client-side rendering
- Rails Engine with automatic route mounting
- Multi-Rails version support (7.1, 7.2, 8.0)
