# ADR 003: Viewport owns the span gesture

**Status**: Accepted  
**Date**: 2026-08-18  
**Updated**: 2026-09-13 (engine-owned text routing contracted; public span-yield predicate removed — [ADR 013](013-viewport-owns-markdown-text-selection.md); continuous text gesture yield — [ADR 015](015-per-body-scope-owns-continuous-text-gestures.md))

Whole-message **span gestures** (long-press, then move) are owned by the viewport, not by per-row widgets. Unclaimed long-presses on a **selection-allowed** message still start a span. Rows keep tap / long-press chrome only while no span is live.

Per-row detectors cannot produce a **span hit** on another row, drive **span auto-scroll** as the sole origin **writer**, or abort cleanly when the **gesture origin** becomes **absent**.

**Text selection** is engine-owned ([ADR 013](013-viewport-owns-markdown-text-selection.md)). Long-press **routing** between span and text is fully internal under **selection policy** ([ADR 012](012-cross-platform-selection-policies.md)) from live membership, **text selection subject**, and range. The transitional public **span yield** host predicate has been removed.

When routing claims the press for **text selection**, the viewport **yields** that pointer: it does not register its long-press recognizer, so the per-body markdown selection scope owns the continuous press (drag-extend, handles, toolbar) — [ADR 015](015-per-body-scope-owns-continuous-text-gestures.md). Unclaimed long-presses still start a **span gesture** on the viewport.

## Considered options

- **Per-row gesture detectors** — rejected: they cannot hit-test across rows or own auto-scroll as a writer.
- **Public span-yield predicate as the lasting text-entry API** — rejected: the engine owns long-press routing ([ADR 013](013-viewport-owns-markdown-text-selection.md)). That does not restore per-row span ownership.
- **Viewport owns the span; long-press routing into text is engine-internal under selection policy** — accepted.
