---
type: Architecture Reference
title: Tier-1 Scroll
description: Ticker path composition, physics, paint versus layout; short-content no-scroll suppression on Tier-1.
tags: [scroll, tier1, physics]
timestamp: 2026-07-04T00:00:00Z
resource: lib/src/chat_widgets/render_chat_scroll_view.dart
---

# Tier-1 Scroll

Tier-1 is the hot path: scroll **without** layout or widget rebuild. The render
object owns a `Ticker`; drag, fling, bounceback, and close-path animate feed
deltas into `_onTick`, which mutates `anchorPixelOffset`, repositions children,
and calls `markNeedsPaint` (or `markNeedsLayout` only when the built range no
longer covers the viewport / the floating header’s day changes).

## Tick composition order (must stay stable)

```
_onTick:
  1. Overlay guard → abort scroll state, stop ticker
  2. Highlight-only early exit (no _markScrollActive)
  3. Drain _pendingScrollDelta
  3b. If content fits → cancel fling (stretch still allowed)
  4. delta += tickFling
  5. delta += tickAnimate          // close: offset delta; far: fade only
     // skipped while span auto-scroll occupies the origin writer
  6. delta += span auto-scroll
  7. Split delta: unconsumed at a reached edge vs consumed travel
  8. applyScrollDelta(consumed only)
  9. Update _scrollVelocity EMA
 10. _repositionFromAnchor
 11. _renormalizeAnchor            // unless close-path
 12. _clampBoundaries
 13. Stretch: pull unconsumed (drag) / absorb (fling) / release into content
 14. Semantics + _publishControllerState
 15. _tickFloatingHeader
 16. tickHighlight / tryArmPendingHighlight / settle → _onAnimateSettled
 17. markNeedsLayout OR markNeedsPaint
 18. _stopTickerIfIdle
```

Unconsumed remainder is measured from oldest/newest **box geometry**, never from
`anchorPixelOffset` after renormalize. Mid-conversation travel must not stretch.

## Drag

| Event | Behavior |
|-------|----------|
| `_onDragStart` | `_cancelPendingTailPin()`, clear nav alignment, cancel fling/animate, `_stretch.onDragStart()`, `_dragInProgress = true` |
| `_onDragUpdate` | `_pendingScrollDelta += details.delta.dy` (including short content) |
| `_onDragEnd` | `_stretch.onDragEnd` (spring only if stretch ≠ 0); fling if `\|v\| ≥ 50` and not stretching and content does not fit |

## Fling

- `_startFling` / `_cancelFling` via `ChatScrollPhysics` (`ClampingScrollSimulation`).
- **No-op** when [_contentFitsInViewport](./06-boundaries.md#short-content--_contentfitsinviewport).
- Per-tick clamp during fling (not suspended).
- Overscroll resistance is **not** used; unconsumed dy at a reached edge
  feeds paint-time [ChatStretchOverscroll] (Android EdgeEffect).
- Render emits `ChatFlingStart` / `ChatFlingEnd`; physics does not touch events.

## Stretch overscroll

- Paint-only scale-from-edge. Layout pins stay clamped.
- Pull only the overflow past remaining pin travel
  (`_unconsumedOverscrollDelta`). Missing boundary box → not that edge.
  Short content: zero travel on both pins, so the full delta.
- `onDragEnd`: reverse velocity drops the glow for content fling; same-
  direction velocity absorbs then springs back; idle release springs from
  the current stretch with zero initial velocity (no slam).
- Fling that reaches a pin (including the frame that consumes the last travel
  pixels): `absorbImpact` with leftover velocity, then cancel fling.
- Cancelled by: jump, `scrollBy`, `animateTo`, overlay, controller swap,
  bottom-pad change.
- Paint stretch wraps **messages only** — floating date header and scrollbar
  stay viewport-fixed.

## `_repositionFromAnchor`

Recomputes every built child’s `ChatMessageParentData.offset` from the current
anchor without rebuild or `child.layout`.

- Fast path `_repositionMessagesOnly` when `_chunkErrors.isEmpty`.
- General path interleaves chunk-error tiles at chunk boundaries.
- Null slots: **skip** (`continue`), never `break`.

Also updates `dividerOpacity` for `startsDay` rows via `_setOffset` (Tier-1
safe parent-data write).

## `_rangeNoLongerCovers`

Returns `true` (need layout) when:

1. No messages and no chunk-errors.
2. Entire built range off-screen (`topY > height` or `bottomY < 0`).
3. Bottom of built range inside cache margin **and** not at conversation newest
   (`lastId < newest`).
4. Top of built range inside cache margin **and** more older content exists
   (`!reachedOldest && firstId > 0`, or `firstId > oldest`).

Tick decision:

```
if (_rangeNoLongerCovers() || headerDayChanged)
  markNeedsLayout();
else
  markNeedsPaint();
```

`headerDayChanged` comes from `_tickFloatingHeader` — the topmost day bucket
changed; header **text** needs a layout rebuild (opacity alone does not).

## Velocity EMA and directional lead

```
_scrollVelocity = _scrollVelocity * 0.7 + delta * 0.3
```

Positive velocity = revealing older. Fan-out uses this for directional lead
(see [04-layout-pipeline.md](04-layout-pipeline.md)). When the ticker goes idle,
velocity is cleared and `markNeedsLayout` runs so the next fan-out is
symmetric and lead children are collected.

## Ticker lifecycle

- `_ensureTicker` starts the ticker if inactive.
- `_stopTickerIfIdle` stops when no fling, pending delta, highlight, animate,
  bounceback, drag, or span auto-scroll occupying the origin writer.
- `_ticking` follows `TickerMode` — inactive routes do not animate fling
  off-screen.
- Overlay mode aborts all scroll work and stops the ticker.

## Programmatic `scrollBy`

`_onScrollBy` cancels fling/animate/bounceback, clears pending drag delta, and
calls **`markNeedsLayout`** (not Tier-1). Intentional full settle so physics
and follow-tail converge on the next layout.

## Pointer / wheel

- Mouse wheel: `_pendingScrollDelta -= event.scrollDelta.dy` (sign maps to
  anchor convention), Tier-1.
- Pointer down during fling: cancel fling and set
  `flingCancelSuppressesLongPress` so the viewport-owned selection
  long-press does not fire on the cancel tap.
- When a selection controller is wired, the same pointer down is also
  offered to `ChatSelectionPointer` (long-press enters selection or starts
  an unselect span if the origin was already selected; tap toggles while
  mode is on). The pinned floating date header is not a hit — the
  message underneath receives the long-press or tap. Rows do not attach
  a competing detector. A host `spanYield`
  that returns true claims the long-press so selection does not start.
  A host `selectionAllowed` that returns false is not a span hit and does
  not join the selected set, even on the present-neighbor walk. Emptying
  the selected set does not end the span; membership stays empty.
  If the gesture origin becomes absent, the span aborts (set kept, origin
  not retargeted) so delete recovery may write the origin.
- While a live span pointer occupies the top or bottom edge band, span
  auto-scroll is the sole origin writer (follow-tail and close-path
  animate yield). Delta is zero when content fits, applying it would
  unstick a boundary pin, or a select span is at the selection cap in
  the grow direction (unselect spans ignore the cap; auto-scroll toward
  the origin still runs). A refused grow bumps `capHits` once per wall.
  Newly laid-out present messages can become
  the span hit. Lift or span abort releases the writer.
- Scrollbar drag: maps Y → progress → `_jumpToScrollbar` → `jumpTo(id)`
  (layout path).

## Semantics

`_updateScrollSemantics` exposes scroll actions based on whether older/newer
content can still be revealed (agrees with clamp geometry via `_boundaryBox`).
In `reverse: true` (chat), assistive “scroll up” maps to revealing older
history.

`visitChildrenForSemantics` is **not** filtered by on-screen position —
filtering by scroll would let a child become a semantic node during a paint-only
frame with stale parent data. Off-screen cache-extent children contribute
semantics (same trade-off as `ListView` cache extent).

## What Tier-1 must not do

- Inflate or remove children.
- Call `child.layout`.
- Snap navigation alignment while close-path animate owns the offset (layout
  does that; tick only applies animate deltas).
- Use `scrollBy` from the tick path (use silent `applyScrollDelta`).
