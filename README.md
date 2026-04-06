# Sentrits iOS

Native iOS client for Sentrits hosts.

The app is session-centric. It discovers and pairs with hosts, lists sessions by device, keeps a connected Explorer workspace, opens a focused terminal control surface, records local activity, and manages local notification preferences.

## Current Product Shape

Top-level tabs:

- Pairing
- Inventory
- Explorer
- Activity
- Config

Focused session control is presented as a full-screen cover from Explorer.

## Current Renderer State

Focused and preview terminals now use SwiftTerm by default.

- default renderer: SwiftTerm
- fallback renderer: xterm.js in `WKWebView`
- renderer selection lives in Config

The focused terminal is the only interactive control surface. Explorer mini terminals remain preview-oriented.

## Runtime Alignment

The client assumes the current host/runtime model:

- UDP discovery plus `GET /discovery/info`
- host verification through `GET /host/info`
- pairing request and claim
- authenticated session listing and creation
- observer and controller WebSockets
- focused session snapshots
- session group tags
- session supervision and controller state

The corresponding runtime lives in [Sentrits-Core](https://github.com/shubow-sentrits/Sentrits-Core).

## Key Repo Areas

- [SentritsIOS/App](SentritsIOS/App)
- [SentritsIOS/Services](SentritsIOS/Services)
- [SentritsIOS/ViewModels](SentritsIOS/ViewModels)
- [SentritsIOS/Views](SentritsIOS/Views)
- [SentritsIOS/Resources](SentritsIOS/Resources)
- [SentritsIOSTests](SentritsIOSTests)
- [Sources/ExplorerLogic](Sources/ExplorerLogic)

## Docs

- [MVP_NOTES.md](MVP_NOTES.md)
- [IOS_CLIENT_ARCHITECTURE.md](docs/IOS_CLIENT_ARCHITECTURE.md)
- [IOS_FEATURES.md](docs/IOS_FEATURES.md)
- [IOS_DEBUGGING_AND_TRACING.md](docs/IOS_DEBUGGING_AND_TRACING.md)

## Current Limits

- focused terminal handoff and rendering are much better than before, but terminal behavior is still being polished
- SwiftTerm scroll and cursor-follow behavior still need tuning
- xterm.js remains in the app as a manual fallback
- notifications are local device notifications, not APNs push
- Explorer terminals are previews, not full control surfaces

## Source Of Truth

Use the code as truth over any stale branch-era note. The app entry point is [SentritsIOSApp.swift](SentritsIOS/App/SentritsIOSApp.swift), and the current shell is [AppShellView.swift](SentritsIOS/App/AppShellView.swift).
