# ADR 011: Markdown text selection lives in a bridge package

**Status**: Accepted  
**Date**: 2026-09-11

The chat viewport core stays markdown-agnostic: it owns **message selection**, span gestures, and the **span yield** seam, and does not depend on a markdown engine. In-bubble **text selection** for markdown bodies is integrated via an optional bridge package (`chat_md_selection`) that depends on the viewport and a pinned markdown renderer fork, orchestrates yield → programmatic text entry (and desktop direct entry under **selection policy**, ADR 012), single-subject gating, and host chrome defaults (Copy / Select all).

Hosts that do not use markdown simply omit the bridge. Selectable bodies that want this path render through the markdown widget; plain-text dual stacks are out of scope for v1.

Default markdown selection autoscroll (ancestor `Scrollable.jumpTo`) does not drive the anchor viewport; v1 disables it, with a follow-on to wire edge motion through the viewport writer (same class of seam as span auto-scroll).

## Considered options

- **Core depends on markdown** — rejected: forces every host to take the engine and couples layout to one renderer.
- **Example-only wiring, no package** — rejected: duplicates Telegram-order gating and registry policy in every app.
- **Optional bridge package + pinned git commit of the renderer fork** — accepted.
