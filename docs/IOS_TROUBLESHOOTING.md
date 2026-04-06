# iOS Troubleshooting

This document is a short operator-style guide for the current iOS client.

## Focused Terminal Looks Wrong After Request Control

Check:

1. enable `SENTRITS_DEBUG_TRACE=1`
2. inspect `ios.focus`
3. look for:
   - `control.ready`
   - `bootstrapToken`
   - `bootstrapChunks`
   - `rawChunksBeforeClear`
   - `rawChunksAfterClear`

Relevant docs:

- [IOS_DEBUGGING_AND_TRACING.md](IOS_DEBUGGING_AND_TRACING.md)
- [IOS_TERMINAL_INTEGRATION.md](IOS_TERMINAL_INTEGRATION.md)

Likely causes:

- stale raw backlog replay
- fallback bootstrap instead of canonical snapshot
- incremental controller redraw without a strong baseline

## Focused Terminal Scroll Feels Bad

Current state:

- this is still a known rough edge
- SwiftTerm is much better than the old xterm path overall, but scroll and cursor-follow behavior still need tuning

Quick check:

- switch renderer in Config to xterm.js
- compare whether the issue is renderer-specific or transport-specific

If the issue only appears in SwiftTerm:

- inspect [SentritsSwiftTermView.swift](../SentritsIOS/Views/SentritsSwiftTermView.swift)

## Snapshot Request Succeeds But UI Fails To Update

Check:

- `[ios.focus][decode.failed]`

That log comes from:

- [HostClient.swift](../SentritsIOS/Services/HostClient.swift)

It includes:

- request path
- HTTP status
- decoding reason
- body preview

Common cause:

- response shape drift between runtime and iOS models

## Inventory Shows Wrong Sessions Or Empty Sections

Check:

- `ios.inventory`
- `refresh.host`
- `refresh.host.error`

Look for:

- wrong endpoint
- token failure
- host identity mismatch
- actual session count returned by the host

Relevant source:

- [InventoryStore.swift](../SentritsIOS/Services/InventoryStore.swift)

## Keyboard Will Not Dismiss In Focused View

Current expected behavior:

- tapping the background should dismiss the keyboard

If this breaks, inspect:

- [SessionDetailView.swift](../SentritsIOS/Views/SessionDetailView.swift)

## Renderer Theme Or Background Looks Wrong

For SwiftTerm:

- inspect [TerminalTextView.swift](../SentritsIOS/Views/TerminalTextView.swift)

For xterm fallback:

- inspect [terminal.html](../SentritsIOS/Resources/Terminal/terminal.html)

## Renderer Switch Does Not Seem To Take Effect

Check:

- Config tab renderer picker
- stored key `terminal.renderer.kind`

Relevant source:

- [AppShellView.swift](../SentritsIOS/App/AppShellView.swift)
- [TerminalTextView.swift](../SentritsIOS/Views/TerminalTextView.swift)

## Pairing Works But Inventory Or Explorer Uses The Wrong Host

Check:

- saved host identity
- host endpoint
- `ios.inventory` and `ios.explorer` logs

Relevant sources:

- [HostsStore.swift](../SentritsIOS/Services/HostsStore.swift)
- [InventoryStore.swift](../SentritsIOS/Services/InventoryStore.swift)
- [AppShellView.swift](../SentritsIOS/App/AppShellView.swift)

## Notification Behavior Is Missing

Remember:

- iOS notifications here are local, not APNs push
- subscriptions are per session and persisted locally

Check:

- permission state in Config
- quiet and stopped toggles
- per-session subscription toggle

Relevant sources:

- `NotificationPreferencesStore` in [AppShellView.swift](../SentritsIOS/App/AppShellView.swift)
- [InventoryStore.swift](../SentritsIOS/Services/InventoryStore.swift)

## First Things To Compare Cross-Repo

When behavior differs across clients, compare against:

- [Sentrits-Core](https://github.com/shubow-sentrits/Sentrits-Core)
- [Sentrits-Web](https://github.com/shubow-sentrits/Sentrits-Web)

Use the same session and same sequence:

1. open focus
2. request control
3. type or resize
4. compare runtime, web, and iOS traces
