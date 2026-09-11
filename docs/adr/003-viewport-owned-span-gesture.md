# ADR 003: Viewport owns the span gesture

**Status**: Accepted  
**Date**: 2026-08-18  
**Updated**: 2026-09-11 (yield semantics; see ADR 010)

Whole-message **span gestures** (long-press, then move) are owned by the viewport, not by per-row widgets. A host may **yield** a long-press at a **global** point so a span does not start; the host is notified of the claim and may start **text selection** programmatically. Unclaimed long-presses on a **selection-allowed** message still start a span.

Per-row detectors cannot produce a **span hit** on another row, drive **span auto-scroll** as the sole origin **writer**, or abort cleanly when the **gesture origin** becomes **absent**. Exclusive capture of long-press without a yield seam would make text selection a breaking rewrite. Rows keep tap / long-press chrome only while no span is live.

Yield does **not** mean the child wins the gesture arena. The viewport keeps the long-press; text selection enters by host API after the claim (ADR 010).

## Considered options

- **Per-row gesture detectors** — rejected: they cannot hit-test across rows or own auto-scroll as a writer.
- **Viewport always wins the long-press with no yield** — rejected: closes the door on in-bubble text selection.
- **Viewport owns the span; long-press is yieldable; text starts programmatically** — accepted.
