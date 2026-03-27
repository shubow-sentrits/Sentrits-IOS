Work in: /Users/shubow/dev/VibeEverywhereIOS-discovery-pairing
Branch: ios-discovery-pairing

Goal:
Implement the iOS native discovery and pairing foundation for the VibeEverywhere app.

Product alignment:
- Follow the visual direction in /Users/shubow/dev/VibeEverywhereIOS/UI_design.
- Treat the UI images as style/layout guidance.
- Do not copy placeholder session text/details from design images blindly.
- Runtime-facing details must conform to the real vibe-hostd API.
- Use modern SwiftUI patterns: TabView, NavigationStack, typed/data-driven navigation, async/await, state/store driven UI.

References:
- /Users/shubow/dev/VibeEverywhere/development _memo/ios_client_rebuild_plan.md
- /Users/shubow/dev/VibeEverywhere/development _memo/ios_client_screen_spec.md
- /Users/shubow/dev/VibeEverywhereIOS/README.md
- /Users/shubow/dev/VibeEverywhereIOS/MVP_NOTES.md
- /Users/shubow/dev/moonlight-ios for UDP discovery / pairing behavior reference only

Scope ownership:
- Discovery listener for UDP broadcast hosts
- Manual add/verify host flow
- Saved devices / selected device model
- Pairing request / polling claim / rejected-expired handling
- Host identity persistence (hostId, displayName, alias if appropriate)
- Pairing screen only

Do not edit:
- Inventory / Explorer / focused session UI beyond what is required for app shell wiring
- Terminal implementation
- Activity screen beyond minimal logging hooks if needed

Runtime/API expectations:
- GET /discovery/info
- GET /host/info
- POST /pairing/request
- POST /pairing/claim
- Runtime host identity should drive dedupe more than raw endpoint strings

Implementation expectations:
- Native UDP discovery on iOS, no browser-style helper
- Clear distinction between connection target, discovered host, and saved device
- Good error handling and pairing status transitions
- Avoid boolean soup; prefer typed state
- Add tests where practical, especially for stores / parsing / pairing state transitions

Verification:
- Build the app or relevant scheme
- Run unit tests you add

Final response:
- summarize changes
- list files changed
- list verification results
- include commit hash
