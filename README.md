# VibeEverywhere iOS

This repository is the native iOS client for `vibe-hostd`.

It is currently in transition from an older SwiftUI MVP to the new product shape.

## Product Direction

The target app is a session-centric remote companion with these top-level surfaces:

- Pairing
- Inventory
- Explorer
- Activity
- Focused session view

The app should support:

- true UDP discovery on iOS
- pairing and trusted host management
- session inventory grouped by device
- connected-session explorer grouped by tags
- focused remote session control
- lightweight activity/log visibility

## Runtime Assumptions

The current runtime already supports:

- discovery broadcast + `GET /discovery/info`
- pairing request + claim
- session list/create/stop
- group tag mutation
- overview/session websockets
- snapshot/file/tail read APIs

## Current Repo Reality

There is existing code here for:

- REST networking
- session websocket handling
- token persistence
- saved hosts

But the current screen structure is still from an older MVP and should not be treated as the final architecture.

## Design Source

See:

- `UI_design/vibeops_atmospheric/DESIGN.md`
- `UI_design/pairing`
- `UI_design/inventory`
- `UI_design/explorer`
- `UI_design/interactive_terminal_view`
- `UI_design/activity_log`

## Additional Reference

For discovery and pairing behavior only:

- `/Users/shubow/dev/moonlight-ios`

Do not copy Moonlight’s product model directly. Use it only as a technical reference for native discovery/pairing patterns.

## Terminal Rendering

The iOS client now uses a bundled `xterm.js` renderer inside `WKWebView` for session terminals.

This choice is deliberate:

- PTY output from `vibe-hostd` depends on real escape-sequence handling, not ANSI stripping.
- The assets are vendored under [VibeEverywhereIOS/Resources/Terminal](/Users/shubow/dev/VibeEverywhereIOS-terminal/VibeEverywhereIOS/Resources/Terminal) to avoid runtime CDN/network dependence.
- Swift owns websocket transport, ordering, control, and resize state; the embedded renderer is only responsible for terminal emulation and local keyboard handling.
