Work in: /Users/shubow/dev/VibeEverywhereIOS-explorer
Branch: ios-explorer

Goal:
Implement the Explorer and focused session experience for the redesigned iOS client.

Product alignment:
- Follow /Users/shubow/dev/VibeEverywhereIOS/UI_design for the visual language.
- Details like session metadata must reflect the real runtime API.
- Explorer shows connected sessions only.
- The permanent All tab shows all connected sessions.
- Additional group tabs filter connected sessions by session group tags.
- Focused session view is where larger terminal + detailed metadata belong.

References:
- /Users/shubow/dev/VibeEverywhere/development _memo/ios_client_screen_spec.md
- /Users/shubow/dev/VibeEverywhere/development _memo/ios_client_rebuild_plan.md
- /Users/shubow/dev/VibeEverywhereIOS/UI_design

Scope ownership:
- Explorer tab shell
- Connected-session tiles
- Group creation / group tab selection
- Tag-based filtering using groupTags
- Focused session route / sheet / destination
- Session detail presentation in focused view
- Wiring to per-session websocket state at the view-model/store layer

Do not edit:
- UDP discovery implementation
- Inventory session creation flow beyond invoking existing actions
- Terminal renderer internals except integration points

Implementation expectations:
- Use typed/data-driven navigation
- Avoid generic dashboard language
- Keep compact tiles focused on terminal space
- Group operations should work well on touch, no drag/drop required for v1
- Add tests where practical for explorer grouping / navigation state

Verification:
- Build app or relevant scheme
- Run unit tests you add

Final response:
- summarize changes
- list files changed
- list verification results
- include commit hash
