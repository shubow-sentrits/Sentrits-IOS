# Sentrits iOS MVP Alignment

This file tracks the current shipped MVP shape, not the old rebuild plan.

## In Scope

- native host discovery on iOS
- manual host verification
- pairing and token persistence
- saved host management
- device-grouped inventory
- connected-session Explorer
- focused terminal control
- local activity log
- local notification preferences and delivery
- renderer selection between SwiftTerm and xterm.js

## Current MVP Checklist

- done: UDP discovery and discovered host inspection
- done: manual add and host verification
- done: pairing request, claim polling, approval, rejection, and expiry handling
- done: keychain-backed token storage
- done: saved host persistence and dedupe by host identity
- done: inventory grouped by host
- done: create session
- done: stop session
- done: clear inactive sessions
- done: connect session into Explorer
- done: Explorer group tabs and group creation
- done: add and remove session group tags
- done: focused session route from Explorer
- done: request and release control in focused view
- done: focused terminal input and resize
- done: focused prompt editor and terminal control keys
- done: session-level notification subscription toggles
- done: group-level bulk notification toggles from Explorer
- done: Config toggles for quiet and stopped notifications
- done: quiet notification threshold selection
- done: local activity log and clear action
- done: SwiftTerm as default renderer
- done: xterm.js fallback renderer switch

## Still Rough

- focused terminal scroll behavior still needs tuning
- terminal redraw behavior under heavy live output still needs more polish
- canonical snapshot support should remain the preferred path when the runtime provides it consistently

## Out Of Scope

- APNs push notifications
- internet relay or tunnel access
- multi-user identity or account system
- multiple simultaneous controllers
- turning Explorer mini terminals into full control surfaces

## Working Rule

When notes conflict with the app, trust:

- [SentritsIOSApp.swift](SentritsIOS/App/SentritsIOSApp.swift)
- [AppShellView.swift](SentritsIOS/App/AppShellView.swift)
- [SessionViewModel.swift](SentritsIOS/ViewModels/SessionViewModel.swift)
- [TerminalTextView.swift](SentritsIOS/Views/TerminalTextView.swift)
