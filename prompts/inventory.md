Work in: /Users/shubow/dev/VibeEverywhereIOS-inventory
Branch: ios-inventory

Goal:
Implement the Inventory surface for the redesigned iOS client.

Product alignment:
- Follow /Users/shubow/dev/VibeEverywhereIOS/UI_design for style and composition.
- Session information must match the real runtime API, not placeholder image text.
- Inventory is grouped by device.
- Each device section should remain visible even with zero sessions.
- New session creation is per-device.

References:
- /Users/shubow/dev/VibeEverywhere/development _memo/ios_client_screen_spec.md
- /Users/shubow/dev/VibeEverywhere/development _memo/ios_client_rebuild_plan.md
- /Users/shubow/dev/VibeEverywhereIOS/AGENT_OWNERSHIP.md

Scope ownership:
- Inventory tab UI
- Device-grouped session cards
- Per-device create session affordance
- Connect / disconnect / stop actions on session cards
- Hide/show stopped sessions if it fits the design cleanly
- Empty state per host/device
- Session loading from real runtime APIs

Do not edit:
- Discovery / pairing flow beyond consuming saved devices
- Explorer group workflows
- Terminal renderer internals

Runtime/API expectations:
- GET /sessions
- POST /sessions
- POST /sessions/{id}/stop
- Sessions include lifecycle, attention, controller state, git/file hints, groupTags

Implementation expectations:
- Compact card design, mobile-first
- Device identity visible
- New session should be clearly scoped to selected device/host
- Prefer store-driven state, not view-local network logic everywhere
- Add tests where practical for data mapping / grouping / inventory state

Verification:
- Build app or relevant scheme
- Run unit tests you add

Final response:
- summarize changes
- list files changed
- list verification results
- include commit hash
