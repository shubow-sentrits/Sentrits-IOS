# Sentrits iOS

This repository is the maintained native iOS client for `vibe-hostd`.

## Product Direction

The app is a session-centric remote companion with these top-level surfaces:

- Pairing
- Inventory
- Explorer
- Activity
- Config
- Focused session view

## Current Setup

The current app supports:

- true UDP discovery on iOS
- pairing and trusted host management
- session inventory grouped by device
- connected-session Explorer grouped by tags
- focused remote session control through the dedicated controller socket
- lightweight activity/log visibility
- local client-side session notifications for subscribed quiet and stopped events

## Current MVP Behavior

Current product behavior:

- Inventory is the place to create, stop, clear, connect, and subscribe sessions
- Explorer is a connected-session workspace with preview-only terminal tiles
- the focused session view is the only interactive control surface
- focused control uses the dedicated remote controller WebSocket
- observer-only views keep following the normal session observer socket
- notification subscriptions are per session and per device
- notification delivery is local-only for now, not APNs-backed

## Runtime Assumptions

The current runtime already supports:

- discovery broadcast + `GET /discovery/info`
- pairing request + claim
- session list/create/stop
- group tag mutation
- overview/session websockets
- dedicated remote controller websocket
- snapshot/file/tail read APIs
- supervision state and controller identity in session summaries/events

## Terminal Rendering

The iOS client currently uses a bundled `xterm.js` renderer inside `WKWebView` for session terminals.

This is the current practical choice:

- PTY output depends on real escape-sequence handling
- focused control works through Swift-owned socket, resize, and state plumbing
- compact Explorer previews can stay lower-fidelity than the focused terminal

The assets are vendored under [VibeEverywhereIOS/Resources/Terminal](/Users/shubow/dev/VibeEverywhereIOS/VibeEverywhereIOS/Resources/Terminal).

## Current Repo Reality

The maintained code here includes:

- REST networking
- session websocket handling
- controller websocket handling
- token persistence
- saved hosts
- notification preferences and local notification delivery
- the current tabbed product shell and focused terminal flow

There are still stale or transitional files in the repo, but the shipping app shape is no longer the old MVP described in earlier notes.

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

## Current Limits

Current known limits:

- first-frame rendering after attach/control can still be imperfect until the remote program repaints
- notifications are local only and do not work like APNs push for a fully closed app
- Explorer mini terminals are intentionally preview-oriented, not full control surfaces
- `xterm.js` in `WKWebView` is still the renderer baseline while native alternatives remain future work
