# Changelog

## [0.7.2] - 2026-09-07

### Security
- The actions endpoint enforces CSRF itself with `protect_from_forgery`
  instead of relying on the host's `load_defaults`.
- `live_action` tokens expire after `ReactiveComponent.action_token_ttl`
  (default one day). Before, a token stayed valid forever.
- `request_update` passes only declared `client_state` fields to the
  component. Any other client key was set as an instance variable and
  handed to the constructor.
- `request_update` over the channel only answers for records whose
  `broadcasts` stream is the one the subscriber verified. Before, any
  subscriber could pull the rendered data of any record id of the model.
- The channel resolves the component name with `safe_constantize` and
  requires a class that includes `ReactiveComponent`.

### Fixed
- The renderer controller imports its utils by bare specifier again. The
  0.7.1 relative import resolved to an undigested `/assets/` URL under
  Propshaft and 404ed, which left Turbo stream sources never connecting and
  every system test failing. The bare specifier works for both importmap
  (`pin_all_from`) and npm (`exports`).

## [0.7.1] - 2026-09-06

### Added
- The JavaScript is an npm package too: `package.json` exports
  `reactive_component/controllers/*` and `reactive_component/lib/*`, so an app
  can `npm install` the gem's GitHub tag tarball instead of aliasing the
  bundler path (which a Node-only Docker stage cannot resolve).

### Changed
- The renderer controller imports its utils by relative path, so it resolves
  without an alias or importmap pin for the lib file.

## [0.7.0] - 2026-09-06

### Fixed
- `live_action` params are filtered with `permit` against the declared
  list, so a nested hash or array sent for a scalar param no longer reaches
  the action method.

### Added
- `live_action` `params:` accepts the full `permit` spec, so an action can
  declare arrays and nested hashes: `params: [:title, { tags: [] }]`.

## [0.6.2] - 2026-09-06

### Changed
- Gem metadata points at the right places: homepage and documentation
  are the GitHub Pages docs, source/changelog/issues are
  `lluzak/reactive_component`. (First release on RubyGems since 0.1.0.)

## [0.6.1] - 2026-09-06

### Changed
- Docs describe the 0.6 compiler (Prism, prefixed ids, typed conditions,
  compile errors); the live-action examples use the real Stimulus params.
- RuboCop pinned to `~> 1.90.0` so CI and local lint agree. The 0.6.0 tag
  was never published: its commit failed lint on CI.

## [0.6.0] - 2026-09-05

### Changed
- **ruby2js is gone; the compiler runs on Prism's own tree.** One pass
  over the Prism AST lifts every Ruby expression to a server-evaluated
  data key and emits the template skeleton as JavaScript — a whitelist
  (literals, data reads, `if`/`unless`/ternaries, boolean and comparison
  operators, `.each`, the `_tag*`/`_render_*` helpers). Anything else raises
  `ReactiveComponent::CompileError` naming the source, where ruby2js used
  to guess (`present?` became a `.present` property read). Dependencies:
  `ruby2js` out, `erubi` in; no `parser` gem. The compiled JS keeps the
  same shape (`function render({ … })`, `_buf +=`, `for..of`,
  `_tag_open(...)`).
- `"#{@x}!"` — an interpolated string with an ivar or helper — is now
  server-evaluated and escaped like any other expression, instead of being
  emitted as an unescaped template literal.
- The extractor now lifts a chain rooted at a self call
  (`content.present?`, `current_user.name`) whole, like an ivar chain.
- **Wrapper ids are now component-prefixed by default** —
  `message_row_message_1` instead of `message_1`. Two components rendering
  the same record previously shared one id, and because broadcasts are
  routed by id each rendered the *other's* payload: a `TypeError` deep in
  the compiled template as soon as the shapes differed, plus duplicate ids
  in the page. `dom_id_prefix` still overrides the default. Anything that
  targeted the old bare ids (CSS, Turbo Stream targets, tests) needs the
  new prefix.

### Fixed
- **Block variables in conditions.** Inside a `.each`, an item read in a
  non-output position — `<% if item.flag %>`, a ternary, `"x" if item.y` —
  passed through ruby2js as `item.flag`, a property the client never
  receives (items ship as their extracted expressions only, never the raw
  record). Conditions were silently false after every broadcast and
  `item.x.present?` threw `Cannot read properties of undefined`. They are
  now server-evaluated per item like output expressions, but keep their
  type (`"false"` is truthy in JS).

### Added
- **Compile-time invariant for loops.** After a `.each` body is processed,
  any surviving read of the loop variable that is not an extracted
  `item["vN"]` raises `ReactiveComponent::CompileError` naming the
  expression — an item ships only as its extracted expressions, so such a
  read could never resolve on the client. Guards the block-variable fix
  against new syntactic positions.
- **Debug-mode strict payloads.** With `ReactiveComponent.debug` on, the
  client renders through a Proxy that throws on reading a key the payload
  does not carry, naming the key, its path, and the keys present — instead
  of an `undefined` that is silently falsy in an `if`.
- The Stimulus controller checks for other elements sharing its id on
  connect and logs a `console.error` naming the collision and the fix.
  Piggybacks on Stimulus's own MutationObserver, so it also catches
  hand-picked `dom_id_prefix`es that collide.

## [0.4.1] - 2026-05-29

### Changed
- Bumped Rails to 8.1.3 (and matching patches across the 8.1.x stack)
  in development and test gemfiles.
- Upgraded `view_component` to 4.11.0 — full test suite (119 runs,
  308 assertions) green on Rails 7.1, 7.2, and 8.0 appraisals.
- Refreshed transitive dependencies (rack 3.2.6, nokogiri 1.19.3,
  loofah 2.25.1, zeitwerk 2.8.2, propshaft 1.3.2, sqlite3 2.9.4,
  rubocop 1.86.2, etc.).

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
