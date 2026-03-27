# VibeEverywhere iOS Notes

## Status

This repo is **not** the current product shape yet.

It contains an older SwiftUI MVP that proved basic connectivity, but it does not match the current runtime model or the new UI direction.

The real target is now:

- Pairing
- Inventory
- Explorer
- Activity
- Focused session view

with true native UDP discovery and a better terminal renderer.

## What Still Has Value

These parts are useful foundations:

- `HostClient.swift`
- `SessionSocket.swift`
- `SavedHostsStore.swift`
- `KeychainTokenStore.swift`

They should be treated as reusable building blocks, not proof that the current app structure is correct.

## What Is Outdated

The current UI/view-model structure is still from the old MVP:

- form-heavy connect flow
- old sessions list/detail flow
- lossy text terminal rendering
- no grouped inventory
- no explorer workspace
- no activity tab
- no true discovery flow

## Current Runtime Alignment

The runtime now supports:

- UDP discovery broadcast
- `GET /discovery/info`
- pairing request + claim
- session list/create/stop
- group tags
- overview and session websockets
- read-only snapshot/file/tail access

That means the iOS client can now be built as a real first-class native client.

## Implementation Direction

The rebuild should use:

- modern SwiftUI
- `NavigationStack` and data-driven navigation
- store-driven state instead of screen-local networking
- native UDP discovery
- a real terminal rendering path

## Design Source

The current visual direction lives in:

- `UI_design/vibeops_atmospheric/DESIGN.md`
- `UI_design/pairing`
- `UI_design/inventory`
- `UI_design/explorer`
- `UI_design/interactive_terminal_view`
- `UI_design/activity_log`

## Reference

For discovery and pairing behavior only, use:

- `/Users/shubow/dev/moonlight-ios`

Use it as a network-behavior reference, not as a UI or architecture template.

## Next Step

Treat this repo as a rebuild target, not as a nearly-finished app.
