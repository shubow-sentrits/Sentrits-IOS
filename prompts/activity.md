Work in: /Users/shubow/dev/VibeEverywhereIOS-activity
Branch: ios-activity

Goal:
Implement the Activity surface and app-level polish for the redesigned iOS client.

Product alignment:
- Follow /Users/shubow/dev/VibeEverywhereIOS/UI_design for tone/style.
- Activity is a lightweight chronological event surface, not a noisy debug console.
- It should summarize important client/session events cleanly.

References:
- /Users/shubow/dev/VibeEverywhere/development _memo/ios_client_screen_spec.md
- /Users/shubow/dev/VibeEverywhere/development _memo/ios_client_rebuild_plan.md
- /Users/shubow/dev/VibeEverywhereIOS/AGENT_OWNERSHIP.md

Scope ownership:
- Activity tab UI
- Event model and bounded client activity log
- Hooking important events from pairing, inventory, explorer, sockets
- General app polish that does not conflict with other tracks
- Shared small UI primitives only if necessary and low-conflict

Do not edit:
- Discovery UDP implementation
- Inventory/explorer feature logic outside activity integration points
- Terminal renderer internals

Implementation expectations:
- Keep the log bounded and readable
- Distinguish informational vs warning/error events cleanly
- Avoid overwhelming debug text by default
- Add tests where practical for log reducer/store behavior

Verification:
- Build app or relevant scheme
- Run unit tests you add

Final response:
- summarize changes
- list files changed
- list verification results
- include commit hash
