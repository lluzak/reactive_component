# Changelog

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
