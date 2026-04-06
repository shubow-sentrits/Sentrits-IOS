# iOS Terminal Integration

This document describes how the iOS client integrates terminal state, transport, and renderers.

## Scope

The iOS terminal stack currently supports two renderers:

- SwiftTerm
- xterm.js fallback in `WKWebView`

The app uses the same session and transport model for both. Renderer choice changes only the final presentation layer.

## Main Components

### Session coordinator

[SessionViewModel.swift](../SentritsIOS/ViewModels/SessionViewModel.swift)

Owns:

- observer socket lifecycle
- controller socket lifecycle
- snapshot loading
- focused snapshot refresh scheduling
- bootstrap selection
- handoff between observer and controller state

### Raw terminal state

[TerminalEngine.swift](../SentritsIOS/Services/TerminalEngine.swift)

Owns:

- raw output chunk ingestion
- output chunk ordering
- sequence tracking
- reset and clear behavior

This layer is renderer-agnostic.

### Renderer boundary

[TerminalTextView.swift](../SentritsIOS/Views/TerminalTextView.swift)

Defines:

- `TerminalRendererKind`
- `TerminalSurface`
- `TerminalSurfaceModel`

This is the adapter seam between app state and renderer implementation.

### SwiftTerm wrapper

[SentritsSwiftTermView.swift](../SentritsIOS/Views/SentritsSwiftTermView.swift)

Owns:

- SwiftTerm-specific viewport behavior
- local wrapper logic around `TerminalView`

### xterm fallback

[terminal.html](../SentritsIOS/Resources/Terminal/terminal.html)

Owns:

- embedded web terminal behavior for the xterm path

## Transport Model

### Observer path

The observer socket carries normal session events, including terminal output.

Source:

- [SessionSocket.swift](../SentritsIOS/Services/SessionSocket.swift)

Used for:

- preview terminals
- observer-focused state
- general session metadata updates

### Controller path

The controller socket is the dedicated focused control path.

Source:

- [SessionSocket.swift](../SentritsIOS/Services/SessionSocket.swift)

Used for:

- request control
- release control
- send input
- send resize
- receive low-latency controller output

## Snapshot Model

Snapshot loading is done through:

- [HostClient.swift](../SentritsIOS/Services/HostClient.swift)

Focused snapshot data is represented by:

- `SessionSnapshot`
- `SessionTerminalScreenSnapshot`
- `SessionTerminalViewportSnapshot`

Defined in:

- [SessionModels.swift](../SentritsIOS/Models/SessionModels.swift)

## Bootstrap Strategy

Focused view uses a bootstrap-first strategy.

Preferred order:

1. `terminalViewport.bootstrapAnsi`
2. `terminalScreen.bootstrapAnsi`
3. structured fallback rebuilt from:
   - viewport visible lines
   - screen visible lines
   - scrollback lines
4. `recentTerminalTail`

The decision and synthesis happen in:

- [SessionViewModel.swift](../SentritsIOS/ViewModels/SessionViewModel.swift)

## Focused Rendering Modes

### Canonical-focused display

When focused bootstrap is available and the view is in observer-oriented state, iOS can seed the renderer from bootstrap content.

This is represented by:

- `terminalBootstrapChunksBase64`
- `terminalBootstrapToken`
- `usesCanonicalFocusedDisplay`

### Live controller display

When the session is actively controlled, the view uses the controller stream for live updates.

Important detail:

- stale raw backlog is cleared on control handoff before fresh controller bytes are appended

That behavior is part of the control-handoff fix in:

- [TerminalEngine.swift](../SentritsIOS/Services/TerminalEngine.swift)
- [SessionViewModel.swift](../SentritsIOS/ViewModels/SessionViewModel.swift)

## Preview Vs Focused

### Preview terminals

Preview terminals in Explorer use:

- mode `.preview`
- input disabled
- no focused bootstrap behavior

Previews are intentionally lightweight and not full control surfaces.

### Focused terminal

Focused terminals use:

- mode `.focused`
- conditional input enablement
- focused bootstrap state
- resize callbacks
- keyboard-aware UI in the focused screen

## Renderer Selection

Renderer selection is controlled by app storage:

- `terminal.renderer.kind`

Configured in:

- [AppShellView.swift](../SentritsIOS/App/AppShellView.swift)

Values:

- `swiftterm`
- `xterm`

## Debugging Notes

When debugging terminal issues, start with:

- [IOS_DEBUGGING_AND_TRACING.md](IOS_DEBUGGING_AND_TRACING.md)

Most useful checks:

- whether focused view loaded bootstrap at all
- whether control handoff cleared stale raw backlog
- whether output is arriving from observer or controller path
- whether the issue reproduces in both SwiftTerm and xterm

## Cross-Repo Dependencies

The host/runtime side of snapshots, controller transport, and session APIs lives in:

- [Sentrits-Core](https://github.com/shubow-sentrits/Sentrits-Core)

The web client provides a useful comparison point for focused snapshot behavior:

- [Sentrits-Web](https://github.com/shubow-sentrits/Sentrits-Web)
