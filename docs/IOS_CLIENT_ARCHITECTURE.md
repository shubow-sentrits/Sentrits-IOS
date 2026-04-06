# iOS Client Architecture

## Scope

This document describes the current architecture of the iOS client itself. It does not try to document the full Sentrits runtime.

## Entry And Shell

The app entry point is [SentritsIOSApp.swift](../SentritsIOS/App/SentritsIOSApp.swift).

It creates and owns the main long-lived stores:

- `KeychainTokenStore`
- `HostsStore`
- `ActivityLogStore`
- `NotificationPreferencesStore`

The top-level UI shell is [AppShellView.swift](../SentritsIOS/App/AppShellView.swift). It owns:

- `InventoryStore`
- `ExplorerWorkspaceStore`
- focused session presentation state

The shell is responsible for:

- top-level tab navigation
- periodic inventory refresh
- periodic Explorer host and session reconciliation
- presenting the focused session view
- reacting to session-state change notifications

## Architectural Shape

The codebase is still organized by pragmatic app layers instead of a strict feature-module split:

- `App`
- `Services`
- `ViewModels`
- `Views`
- `Models`
- `Resources`

That split is the real current architecture. Older rewrite-planning docs that referenced a different layout are no longer authoritative.

## State Ownership

### App-wide stores

- [HostsStore.swift](../SentritsIOS/Services/HostsStore.swift)
  - discovered hosts
  - saved hosts
  - selected host for pairing and manual verification
  - discovery lifecycle
- [ActivityLogStore.swift](../SentritsIOS/Services/ActivityLogStore.swift)
  - bounded local activity stream
- `NotificationPreferencesStore` in [AppShellView.swift](../SentritsIOS/App/AppShellView.swift)
  - notification permission state
  - quiet and stopped event preferences
  - per-session subscription persistence
- [InventoryStore.swift](../SentritsIOS/Services/InventoryStore.swift)
  - device-grouped session inventory
  - create, stop, and clear actions
  - local notification transition detection
- `ExplorerWorkspaceStore` in [AppShellView.swift](../SentritsIOS/App/AppShellView.swift)
  - connected session set
  - group-tab state
  - session focus routing

### Per-session state

[SessionViewModel.swift](../SentritsIOS/ViewModels/SessionViewModel.swift) is the core per-session coordinator.

It owns:

- the current `SessionSummary`
- observer socket state
- controller socket state
- current `SessionSnapshot`
- terminal bootstrap state
- live terminal stream state through `TerminalEngine`
- focused-mode snapshot refresh logic

This is the main integration point between runtime protocol, terminal rendering, and focused-session UX.

## Networking And Persistence

### HTTP

[HostClient.swift](../SentritsIOS/Services/HostClient.swift) is the single HTTP client abstraction for the host API.

It handles:

- discovery info
- host info
- pairing request and claim
- session list, create, stop, and clear
- session snapshots
- group tag updates

The host runtime lives in [Sentrits-Core](https://github.com/shubow-sentrits/Sentrits-Core).

### WebSockets

[SessionSocket.swift](../SentritsIOS/Services/SessionSocket.swift) provides:

- observer socket
- controller socket
- input and resize sends on the controller path

`SessionViewModel` consumes both sockets and translates their events into UI, session, and terminal state.

### Persistence

- [SavedHostsStore.swift](../SentritsIOS/Services/SavedHostsStore.swift)
  - persisted saved host records
- [KeychainTokenStore.swift](../SentritsIOS/Services/KeychainTokenStore.swift)
  - bearer token persistence
- `UserDefaults`
  - notification preferences
  - subscribed sessions
  - selected terminal renderer

## Terminal Architecture

### Runtime-facing terminal state

[TerminalEngine.swift](../SentritsIOS/Services/TerminalEngine.swift) stores live terminal output chunks and sequence tracking. It is renderer-agnostic.

### Renderer boundary

[TerminalTextView.swift](../SentritsIOS/Views/TerminalTextView.swift) is the terminal surface boundary.

It exposes:

- `TerminalRendererKind`
- `TerminalSurface`
- a renderer-agnostic `TerminalSurfaceModel`

This layer allows the app to switch between:

- SwiftTerm
- xterm.js in `WKWebView`

without changing session logic above it.

### SwiftTerm path

- [SentritsSwiftTermView.swift](../SentritsIOS/Views/SentritsSwiftTermView.swift)
  - local wrapper around SwiftTerm’s `TerminalView`
  - viewport anchoring and scroll-behavior policy
- SwiftTerm is the default renderer

### xterm path

- [terminal.html](../SentritsIOS/Resources/Terminal/terminal.html)
  - embedded web renderer
- xterm remains a user-selectable fallback

### Focused terminal data flow

High-level flow:

1. `SessionViewModel` loads a snapshot or receives socket output.
2. It decides whether focused display should use canonical bootstrap or live output chunks.
3. `TerminalEngine` holds the live raw stream.
4. `TerminalTextView` maps session state into the active renderer.
5. The active renderer applies bootstrap replacement or incremental output append.

## Screen-Level Responsibilities

### Pairing

- [PairingView.swift](../SentritsIOS/Views/PairingView.swift)
- [PairingViewModel.swift](../SentritsIOS/ViewModels/PairingViewModel.swift)

Responsibilities:

- live discovery
- manual verification
- pairing request and claim
- trusted host save and remove

### Inventory

- [InventoryView.swift](../SentritsIOS/Views/InventoryView.swift)
- [InventoryStore.swift](../SentritsIOS/Services/InventoryStore.swift)

Responsibilities:

- group sessions by host
- create and stop sessions
- clear inactive sessions
- toggle visibility of ended sessions
- toggle per-session notification subscriptions
- connect sessions into Explorer

### Explorer

- [ExplorerWorkspaceView.swift](../SentritsIOS/Views/ExplorerWorkspaceView.swift)
- `ExplorerWorkspaceStore` in [AppShellView.swift](../SentritsIOS/App/AppShellView.swift)

Responsibilities:

- connected-session workspace
- group tabs
- bulk notification actions for a group
- connect, disconnect, focus, and stop actions
- preview terminals

### Focused session

- [SessionDetailView.swift](../SentritsIOS/Views/SessionDetailView.swift)
- [SessionViewModel.swift](../SentritsIOS/ViewModels/SessionViewModel.swift)

Responsibilities:

- focused terminal rendering
- request and release control
- input, resize, and prompt editor
- keyboard accessory controls
- session metadata and context panel

### Activity

- [ActivityView.swift](../SentritsIOS/Views/ActivityView.swift)
- [ActivityLogStore.swift](../SentritsIOS/Services/ActivityLogStore.swift)

Responsibilities:

- bounded local event history
- event summary
- clear log action

### Config

`NotificationConfigView` inside [AppShellView.swift](../SentritsIOS/App/AppShellView.swift)

Responsibilities:

- notification permission request
- quiet and stopped notification toggles
- quiet threshold
- renderer selection

## Legacy And Transitional Code

Some code remains from earlier flows and should be treated carefully:

- [ConnectView.swift](../SentritsIOS/Views/ConnectView.swift)
- [SessionsView.swift](../SentritsIOS/Views/SessionsView.swift)
- [SessionsViewModel.swift](../SentritsIOS/ViewModels/SessionsViewModel.swift)

These files are not the app’s primary current shell. The current product entry is `SentritsIOSApp -> AppShellView`.
