# ADR 011: Markdown text selection lives in a bridge package

**Status**: Superseded by [ADR 013](013-viewport-owns-markdown-text-selection.md)  
**Date**: 2026-09-11

The chat viewport core stays markdown-agnostic: it owns **message selection**, span gestures, and the **span yield** seam, and does not depend on a markdown engine. In-bubble **text selection** for markdown bodies is integrated via an optional bridge package (`chat_md_selection`) that depends on the viewport and a pinned markdown renderer fork, orchestrates yield → programmatic text entry (and desktop direct entry under **selection policy**, ADR 012), single-subject gating, and host chrome defaults (Copy / Select all).

Hosts that do not use markdown simply omit the bridge. Selectable bodies that want this path render through the markdown widget; plain-text dual stacks are out of scope for v1.

Default markdown selection autoscroll (ancestor `Scrollable.jumpTo`) does not drive the anchor viewport; v1 disables it. **Follow-on (landed):** `ChatMarkdownAutoscroll` drives edge motion through `ChatScrollController.scrollBy`. Hosts override via `ChatMarkdownAutoscrollOptions` (enabled / velocity / edge zone). Defaults: [$Mobile] half-line × display Hz; [$Desktop] fixed ~15ms near-edge product. Subject-flush stop when the text-selection subject no longer sticks past the pad. Desktop text→message promotion at flush is not in scope here.

## Considered options

- **Core depends on markdown** — rejected: forces every host to take the engine and couples layout to one renderer.
- **Example-only wiring, no package** — rejected: duplicates selection-order gating and registry policy in every app.
- **Optional bridge package + pinned git commit of the renderer fork** — accepted.
