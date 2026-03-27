Work in: /Users/shubow/dev/VibeEverywhereIOS-terminal
Branch: ios-terminal

Goal:
Implement or integrate a real terminal renderer for the redesigned iOS client.

Product alignment:
- The current placeholder or lossy terminal behavior is not enough.
- Mini explorer tiles need lightweight live preview behavior.
- Focused session view needs the best terminal quality.
- Follow runtime behavior proven by the existing web/runtime-served client.

References:
- /Users/shubow/dev/VibeEverywhere/development _memo/ios_client_rebuild_plan.md
- /Users/shubow/dev/VibeEverywhere/development _memo/ios_client_screen_spec.md
- Current runtime websocket protocol in /Users/shubow/dev/VibeEverywhere

Scope ownership:
- Terminal rendering strategy/integration
- PTY stream rendering quality
- Input handling
- Resize handling
- Terminal-focused state objects or wrappers
- Integration points for compact preview vs focused session

Do not edit:
- Discovery/pairing flow
- Inventory and explorer product layout beyond terminal integration points

Implementation expectations:
- Prefer a proven native terminal component/library if appropriate
- Support websocket-driven output/input/resize semantics from vibe-hostd
- Focus on correctness and responsiveness first
- Add tests where practical around terminal transport glue/state
- Document any external dependency decision clearly

Verification:
- Build app or relevant scheme
- Run unit tests you add
- If external dependency is added, document setup clearly

Final response:
- summarize changes
- list files changed
- list verification results
- include commit hash
