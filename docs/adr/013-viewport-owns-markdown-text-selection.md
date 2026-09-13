# ADR 013: Viewport owns markdown text selection

**Status**: Accepted  
**Date**: 2026-09-12  
**Supersedes**: [ADR 011](011-markdown-selection-bridge.md)

In-bubble **text selection** is a first-class engine responsibility inside
`chat_scroll_view`, peer to **message selection**, governed by **selection
policy** ([ADR 012](012-cross-platform-selection-policies.md)). The viewport
depends on the markdown library and reuses that library’s selection _model_
(positions, document surfaces, hit-test, copy formatting). Gesture authority
stays with the engine: the chat list is not wrapped in the library’s selection
scope as the chat authority.

Hosts consume one public selection facade (membership + **text selection
subject** / range). Character-range text stays one message. Public **span
yield** is not the text-entry contract; long-press routing between **span
gesture** and text is engine-internal from live membership, subject, range, and
policy ([ADR 003](003-viewport-owned-span-gesture.md) still owns the span).
Continuous in-bubble text gestures after that gate are owned by the per-body
markdown selection scope ([ADR 015](015-per-body-scope-owns-continuous-text-gestures.md)).

Selectable markdown bodies are a supported engine path. An optional
markdown-agnostic core plus sibling bridge package is rejected for this
viewport. Absorb the former bridge into core; do not keep a long-lived omit-bridge
path for this surface.

## Considered options

- **Optional bridge + markdown-agnostic core (ADR 011)** — rejected: the engine
  stays blind to text state, so idle tap, retarget, span-vs-text, and inline
  hits cannot share one authority; custom selection paint stays unreachable.
- **Library selection scope wrapping the chat list** — rejected: fights chat
  **selection policy** and bubble-aware rendering.
- **Core owns markdown + text selection; reuse the library model, own
  authority** — accepted.
