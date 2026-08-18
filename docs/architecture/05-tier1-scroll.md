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
  3b. If content fits → cancel fling/bounceback; force delta = 0
  4. If drag && boundary reachable → applyOverscrollResistance
  5. delta += tickFling
  6. delta += tickAnimate          // close: offset delta; far: fade only
     // skipped while span auto-scroll occupies the origin writer
  7. delta += tickBounceback
  7b. delta += span auto-scroll    // live span + pointer in edge band;
                                 // 0 if content fits, a boundary pin would
                                 // unstick, or select-span growth is at cap
  8. applyScrollDelta(delta)
  9. Update _scrollVelocity EMA
 10. _repositionFromAnchor
 11. _renormalizeAnchor            // unless close-path
 12. _clampBoundaries → cancel fling + animate if pinned
 13. Semantics + _publishControllerState
 14. _tickFloatingHeader
 15. tickHighlight / tryArmPendingHighlight / settle → _onAnimateSettled
 16. markNeedsLayout OR markNeedsPaint
 17. _stopTickerIfIdle
```

Inserting a new motion source must pick a slot in this order deliberately.
Animate sits **between** fling and bounceback so overlapping phases compose
predictably.

## Drag

| Event | Behavior |
|-------|----------|
| `_onDragStart` | `_cancelPendingTailPin()`, clear nav alignment, cancel fling/animate/bounceback, `_dragInProgress = true` |
| `_onDragUpdate` | `_pendingScrollDelta += details.delta.dy` — **no-op** when content fits |
| `_onDragEnd` | clear drag flag; `_maybeStartBounceback()`; fling if `\|v\| >= 50` — both skipped when content fits |

Resistance is applied **once per tick** on the combined pending delta, not per
`DragUpdate` — multiple updates in one frame see one resistance scale.

## Fling

- `_startFling` / `_cancelFling` via `ChatScrollPhysics` (`ClampingScrollSimulation`).
- **No-op** when [_contentFitsInViewport](./06-boundaries.md#short-content--_contentfitsinviewport).
- Per-tick clamp during fling (not suspended).
- Overscroll resistance is **drag-only**.
- Render emits `ChatFlingStart` / `ChatFlingEnd`; physics does not touch events.

## Bounceback

- Armed on drag end if overscrolled (`_maybeStartBounceback`).
- Locks `BouncebackSide` (top or bottom) at arm time; per-tick reads **only**
  that side so short-content / composed fling cannot flip sign mid-spring.
- Suspends `_clampBoundaries` while active.
- Composes additively with fling in `_onTick`.
- Cancelled by: new drag, `scrollBy`, `animateTo`, jump, overlay, controller swap.

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
  mode is on). Rows do not attach a competing detector. A host `spanYield`
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
