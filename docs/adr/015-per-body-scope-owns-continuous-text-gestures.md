# ADR 015: Per-body scope owns continuous text gestures

**Status**: Accepted  
**Date**: 2026-09-13  
**Relates to**: [ADR 013](013-viewport-owns-markdown-text-selection.md), [ADR 003](003-viewport-owned-span-gesture.md), [ADR 012](012-cross-platform-selection-policies.md)  
**Amends**: ADR 003 — when long-press routes to **text selection**, the viewport does **not** keep that pointer; it yields so the per-body markdown selection scope can own the continuous press.

Engine ownership of **text selection** (ADR 013) means the public facade, **selection policy**, document registry, and **span vs text** routing — not that the viewport’s span long-press recognizer must drive character ranges. Continuous in-bubble text gestures (mobile long-press → word → drag-extend, handles, adaptive toolbar; desktop mouse drag / double-click / triple-click) are owned by the per-message markdown selection scope that mounts with each selectable body. The chat list is still not wrapped in a list-wide library scope as the chat authority.

Under mobile **selection policy**, the viewport **gates** message-then-text: on pointer-down, if the hit would route to text (already **message-selected** body text, or retarget onto another selected body while text-active), it does not register its long-press for that pointer. The scope’s content-gated touch long-press wins, stays live for drag-extend, and shows chrome. The facade **adopts** the **text selection subject** from the first non-collapsed markdown range (and retargets the same way). While several messages are message-selected and text is inactive, every selected mounted body may be registered; adopt collapses the registry to the subject only (single-message ranges). Touch consecutive-tap word/block entry stays off; mouse multi-click remains desktop. Programmatic `enterTextSelection` stays for hosts/tests and is not the mobile gesture hot path. Single tap still dismisses text and keeps membership (viewport idle-tap path).

## Considered options

- **Viewport keeps the long-press and one-shots a word** — rejected: drops drag-extend, forces `enableTouchGestures: false` workarounds, dead chrome under multi-select.
- **Viewport reimplements the full text helper** — rejected: duplicates the markdown scope; high cost, weak parity.
- **Per-body scope owns continuous text gestures; viewport only gates and adopts** — accepted.
