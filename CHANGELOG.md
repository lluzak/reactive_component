# Changelog

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
