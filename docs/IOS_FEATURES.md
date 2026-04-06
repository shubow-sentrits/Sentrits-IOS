# iOS Client Features

This list is intentionally product-facing and high level, but it uses the current code as truth.

## Pairing

### Discovery

- live UDP discovery of nearby hosts
- discovery cards show:
  - host name
  - endpoint
  - protocol version
  - freshness
  - paired, saved, or new state

### Host inspection and manual add

- inspect a discovered host before pairing
- manually verify a host by address and port
- optional alias for saved hosts
- TLS toggle
- allow self-signed TLS toggle

### Pairing flow

- start pairing request
- claim polling loop
- approval handling
- rejection handling
- expiry handling
- token saved to keychain on success

### Saved host management

- persist trusted hosts locally
- remove saved hosts
- dedupe by host identity where possible
- refresh host details from runtime

## Inventory

### Host sections

- sessions grouped by paired host
- host section shown even when there are zero sessions
- host info merged with saved host data
- clear error state per host section

### Session actions

- create session on a specific host
- stop a session
- clear inactive sessions for a host
- connect a session into Explorer

### Inventory controls

- pull to refresh
- automatic refresh on open
- periodic background refresh from app shell
- show and hide ended sessions

### Session notification controls

- toggle per-session notifications from inventory
- local transition detection for:
  - session became quiet
  - session stopped

## Explorer

### Connected workspace

- Explorer only shows sessions that have been connected into the workspace
- mini terminal preview per connected session
- focus action opens the full-screen session view

### Grouping

- permanent `All` group
- create additional groups
- filter connected sessions by group tag
- add selected group to a session
- remove a group tag from a session

### Explorer session actions

- stop session
- disconnect session from Explorer
- focus session
- toggle per-session notifications

### Group-level notification action

- bulk subscribe all visible sessions in a group
- bulk unsubscribe all visible sessions in a group

## Focused Session

### Focused terminal

- full-screen focused terminal view
- SwiftTerm renderer by default
- xterm.js fallback renderer available
- observer mode and controller mode

### Control lifecycle

- request control
- release control
- stop session from focused view
- controller-specific input path
- terminal resize handling

### Input tools

- direct keyboard input
- background tap to dismiss keyboard
- custom input bar for terminal control keys
- directional keys
- prompt editor
- keyboard-visible input bar controls:
  - hide and show bar
  - pin bar to top or bottom

### Session context

- session status badges
- socket and controller state badges
- notification toggle
- context panel for session metadata and recent context

## Activity

- bounded local activity log
- chronological event stream
- severity levels:
  - info
  - warning
  - error
- categories:
  - pairing
  - inventory
  - explorer
  - socket
  - control
  - system
- daily sectioning
- summary cards
- clear log action

## Notifications

### App-level preferences

- request local notification permission
- enable and disable quiet notifications
- enable and disable stopped notifications
- choose quiet notification threshold

### Subscription model

- subscriptions are per session
- subscriptions are stored per device and client
- session subscription timestamps are persisted
- notification delivery is local only

## Config

- notification permission action
- quiet event toggle
- quiet delay picker
- stopped event toggle
- terminal renderer picker

## Terminal Renderer Options

### SwiftTerm

- default native renderer
- current preferred path for focused and preview terminal rendering

### xterm.js

- manual fallback renderer
- retained for compatibility and debugging

## Known Rough Edges

- focused terminal scroll behavior is still being tuned
- heavy live output can still expose renderer polish gaps
- Explorer terminals remain preview surfaces, not full control surfaces
