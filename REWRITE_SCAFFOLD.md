# Rewrite Scaffold

This file marks the intended rewrite structure for downstream agents.

## Target App Surfaces

- Pairing
- Inventory
- Explorer
- Activity
- Focused Session

## Intended Directory Layout

The current Xcode project has not been fully rewired yet, but downstream work should converge toward:

- `VibeEverywhereIOS/App`
- `VibeEverywhereIOS/Core/Models`
- `VibeEverywhereIOS/Core/Networking`
- `VibeEverywhereIOS/Core/Persistence`
- `VibeEverywhereIOS/Core/Terminal`
- `VibeEverywhereIOS/Features/Pairing`
- `VibeEverywhereIOS/Features/Inventory`
- `VibeEverywhereIOS/Features/Explorer`
- `VibeEverywhereIOS/Features/Activity`
- `VibeEverywhereIOS/Features/FocusedSession`
- `VibeEverywhereIOSTests`

## Rewrite Rules

- prefer modern SwiftUI state and typed navigation
- do not expand the old form-based MVP screen model
- reuse networking and persistence foundations when they help
- treat terminal rendering as a dedicated subsystem
- keep discovery and pairing native-first

## Current Reusable Foundations

- `HostClient.swift`
- `SessionSocket.swift`
- `SavedHostsStore.swift`
- `KeychainTokenStore.swift`

## Current Non-Goals For Cleanup

- do not preserve existing screen layout assumptions
- do not overfit to the old connect/session-detail flow
