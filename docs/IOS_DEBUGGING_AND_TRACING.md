# iOS Debugging And Tracing

This document describes the current logging and trace hooks for the iOS client.

## Enable Debug Trace

The iOS trace is gated behind an environment variable checked in [SessionModels.swift](../SentritsIOS/Models/SessionModels.swift).

Enable it in Xcode:

1. Edit the `SentritsIOS` scheme.
2. Open `Run` -> `Arguments`.
3. Add environment variable `SENTRITS_DEBUG_TRACE=1`.

The trace gate is implemented by `SentritsDebugTrace.isEnabled`.

## Main Trace Scopes

### `ios.focus`

Focused-session and terminal trace.

Main sources:

- [SessionViewModel.swift](../SentritsIOS/ViewModels/SessionViewModel.swift)
- [TerminalTextView.swift](../SentritsIOS/Views/TerminalTextView.swift)
- [SessionSocket.swift](../SentritsIOS/Services/SessionSocket.swift)
- [HostClient.swift](../SentritsIOS/Services/HostClient.swift)
- [SessionDetailView.swift](../SentritsIOS/Views/SessionDetailView.swift)

Typical events:

- `view.appear`
- `focused.activate`
- `activate.begin`
- `snapshot.refresh.request`
- `snapshot.refresh.response`
- `bootstrap.applied`
- `bootstrap.unchanged`
- `control.request`
- `control.ready`
- `controller.output.raw`
- `swiftterm.bootstrap`
- `swiftterm.append`
- `renderer.bootstrap`
- `renderer.append`
- `decode.failed`

Use this scope when debugging:

- focus open and close
- request control and release control
- terminal bootstrap vs raw output handoff
- renderer behavior in SwiftTerm or xterm fallback
- snapshot decode failures

### `ios.inventory`

Inventory refresh and host-section trace.

Main source:

- [InventoryStore.swift](../SentritsIOS/Services/InventoryStore.swift)

Typical events:

- `refresh.begin`
- `refresh.host`
- `refresh.host.error`
- `refresh.end`

Use this scope when debugging:

- session list mismatches
- token issues
- host identity mismatch problems
- empty inventory sections

### `ios.explorer`

Explorer connection and focus routing trace.

Main source:

- [AppShellView.swift](../SentritsIOS/App/AppShellView.swift)

Typical events:

- `connect`
- `focus`

Use this scope when debugging:

- which host and session Explorer is acting on
- whether focus navigation is using the expected saved host record

## HTTP Trace Policy

The trace intentionally does not log all HTTP calls.

The HTTP filter lives in [SessionModels.swift](../SentritsIOS/Models/SessionModels.swift):

- traced:
  - `/snapshot`
  - controller-related paths
  - websocket-related paths
- not traced by default:
  - routine `/sessions`
  - routine `/host/info`

This keeps focus debugging readable.

## Decode Failure Logging

Snapshot and JSON decode failures are logged from [HostClient.swift](../SentritsIOS/Services/HostClient.swift).

The error log includes:

- request path
- HTTP status
- `DecodingError` type and coding path when available
- a compact response body preview

Look for:

- `[ios.focus][decode.failed]`

Use this first when a snapshot request succeeds with `200` but the client still fails to load the response model.

## Useful Debugging Sequences

### Focus open

Watch for:

- `view.appear`
- `focused.activate`
- `snapshot.refresh.request`
- `snapshot.refresh.response`
- `bootstrap.applied`
- `swiftterm.bootstrap` or `renderer.bootstrap`

### Request control

Watch for:

- `ui.request_control.tap`
- `control.request`
- `controller.connect`
- `control.ready`
- `controller.output.raw`
- `swiftterm.append` or `renderer.append`

If control handoff breaks the view, compare:

- `bootstrapToken`
- `bootstrapChunks`
- `rawChunksBeforeClear`
- `rawChunksAfterClear`

These are logged from [SessionViewModel.swift](../SentritsIOS/ViewModels/SessionViewModel.swift).

### Inventory mismatch

Watch for:

- `refresh.host`
- `refresh.host.error`

These lines include:

- host display label
- saved host UUID
- endpoint
- session count

Use them to detect:

- stale saved hosts
- wrong endpoint
- invalid token
- host identity mismatch

## Related Runtime And Web Trace

The iOS trace is designed to line up with the host and web traces when they are enabled.

Related repos:

- [Sentrits-Core](https://github.com/shubow-sentrits/Sentrits-Core)
- [Sentrits-Web](https://github.com/shubow-sentrits/Sentrits-Web)

When comparing cross-client behavior, keep the same session and reproduce the same sequence:

1. open focus
2. request control
3. type or resize
4. compare host, web, and iOS traces for the same moment
