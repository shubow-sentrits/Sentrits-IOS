# iOS Test Checklist

Use this as the current smoke and regression checklist for the iOS client.

## Pairing

- discovery shows nearby hosts
- discovered host can be inspected
- manual host verification works
- pairing request starts successfully
- approval path stores token
- rejection path surfaces correctly
- expiry path surfaces correctly
- saved host persists across relaunch

## Inventory

- Inventory loads all saved hosts
- host section remains visible with zero sessions
- create session works
- stop session works
- clear inactive sessions works
- show ended sessions toggle works
- per-session notification toggle works
- host error state renders correctly when token or endpoint is bad

## Explorer

- connecting a session from Inventory adds it to Explorer
- Explorer `All` tab shows connected sessions
- creating a group tab works
- adding group tag to session works
- removing group tag from session works
- group filter shows expected sessions
- group-level notification bulk action works
- disconnect removes session from Explorer
- stop action works from Explorer

## Focused Session

- focus route opens correctly from Explorer
- focused terminal shows content on open
- request control succeeds
- release control succeeds
- stop session works from focused view
- keyboard input works
- terminal resize works
- prompt editor opens and sends content
- directional and control keys send expected input
- background tap dismisses keyboard
- keyboard-visible input bar can hide and show
- keyboard-visible input bar can pin top and bottom
- context panel opens and closes

## Terminal Rendering

### SwiftTerm

- SwiftTerm is default renderer
- preview terminals render basic content
- focused terminal renders content
- request control does not immediately corrupt the view

### xterm fallback

- Config can switch to xterm.js
- preview terminals still render
- focused terminal still opens
- request control still works

## Notifications

- permission request path works
- quiet notification toggle works
- stopped notification toggle works
- quiet threshold changes persist
- subscribed session quiet event can notify
- subscribed session stopped event can notify

## Activity

- activity entries appear for major user flows
- activity summary cards update
- clear activity log works

## Config

- renderer picker persists
- notification settings persist

## Cross-Repo Regression Checks

When terminal behavior changes, compare with:

- [Sentrits-Core](https://github.com/shubow-sentrits/Sentrits-Core)
- [Sentrits-Web](https://github.com/shubow-sentrits/Sentrits-Web)

Most important parity checks:

- session list matches runtime
- request control works
- focused terminal shows expected content
- renderer fallback remains usable
