# Sentrits iOS MVP Notes

## Current Status

The iOS client is now a working first-class remote client for `vibe-hostd`.

Current top-level app surfaces:

- Pairing
- Inventory
- Explorer
- Activity
- Config
- focused session view

## Current MVP Scope

The current iOS MVP supports:

- native UDP discovery on iOS
- pairing and saved host management
- bearer-token-based authenticated host access
- session inventory by paired host
- connected-session Explorer workspace
- focused session control over the dedicated remote controller WebSocket
- observer vs controller state in the focused terminal
- local client-side notifications for subscribed:
  - session became quiet
  - session stopped

## Current Screen Roles

- Pairing
  - discover hosts
  - request pairing
  - claim and save trusted hosts
- Inventory
  - list sessions by host
  - create, stop, clear ended sessions
  - subscribe a session for notifications
- Explorer
  - connected-session workspace
  - compact terminal previews only
  - no direct control from the mini view
- Focused session
  - primary interactive terminal
  - request or release control
  - direct terminal input and resize
  - prompt editor and session context
- Activity
  - local audit-style event log
- Config
  - notification preferences
  - quiet notification threshold

## Runtime Alignment

The iOS client assumes the current runtime model:

- one PTY per session
- many observers
- one active controller
- observer session WebSocket for metadata and replay-style updates
- dedicated controller WebSocket for low-latency focused control

The intended iOS flow is:

- Inventory and Explorer stay observer-oriented
- the focused session requests control only when needed
- the focused terminal is the only interactive control surface

## Known MVP Limits

- initial render after attach/control can still be imperfect until the remote program repaints
- the terminal renderer is still `xterm.js` inside `WKWebView`
- local notifications only work while the app is alive enough to observe runtime changes
- there is no APNs push system yet
- compact Explorer previews are intentionally lower fidelity than the focused terminal

## Explicit Non-Goals

Current MVP does not try to solve:

- internet relay or tunnel access
- user-account or multi-user identity management
- push notifications through APNs
- perfect first-frame terminal reconstruction
- multiple simultaneous controllers
- full native terminal replacement for `xterm.js`

## Current Direction

The iOS client should keep moving toward:

- a clean native supervision client
- focused-view-first terminal quality
- preview-only compact explorer tiles
- stricter reuse of shared session badge and formatting utilities
