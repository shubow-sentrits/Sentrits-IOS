# Agent Ownership

Use these boundaries to reduce merge pain during the iOS rewrite.

## Track A: Discovery + Pairing

Own:

- host discovery listener
- host merge/dedupe state
- pairing flow
- trusted host persistence updates
- Pairing tab UI

Avoid touching:

- explorer terminal rendering
- inventory grouping logic unless required by shared models

## Track B: Inventory

Own:

- grouped session inventory
- create/connect/disconnect/stop flows from inventory
- inventory card models and presentation

Avoid touching:

- pairing/discovery internals
- focused terminal implementation

## Track C: Explorer + Focused Session

Own:

- connected-session workspace
- group tabs and tag actions
- focused session navigation and presentation

Avoid touching:

- host discovery
- low-level terminal engine internals unless coordinated with Track D

## Track D: Terminal Renderer

Own:

- terminal adapter
- terminal rendering integration
- input/resize/output correctness

Avoid touching:

- higher-level tab navigation
- pairing/inventory stores except via clear interfaces

## Track E: Activity + Visual Polish

Own:

- activity log surface
- shell polish
- design-system consistency

Avoid touching:

- transport semantics
- discovery and terminal protocol logic
