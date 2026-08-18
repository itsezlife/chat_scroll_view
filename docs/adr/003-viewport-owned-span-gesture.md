# ADR 003: Viewport owns the span gesture

**Status**: Accepted  
**Date**: 2026-08-18

Whole-message **span gestures** (long-press, then move) are owned by the viewport, not by per-row widgets. A host may **yield** the long-press so a future in-bubble text selector can claim it; until that selector exists, every unclaimed long-press on a **selection-allowed** message starts a span.

Per-row detectors cannot produce a **span hit** on another row, drive **span auto-scroll** as the sole origin **writer**, or abort cleanly when the **gesture origin** becomes **absent**. Exclusive capture of long-press would make text selection a breaking rewrite. Rows keep tap / long-press chrome only while no span is live.

## Considered options

- **Per-row gesture detectors** — rejected: they cannot hit-test across rows or own auto-scroll as a writer.
- **Viewport always wins the long-press** — rejected: closes the door on in-bubble text selection.
- **Viewport owns the span; long-press is yieldable** — accepted.
