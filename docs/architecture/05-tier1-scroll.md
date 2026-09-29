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
object owns a `Ticker`; drag, fling, edge-effect spring, and close-path animate feed
deltas into `_onTick`, which mutates `anchorPixelOffset`, repositions children,
and calls `markNeedsPaint` (or `markNeedsLayout` only when the built range no
longer covers the viewport / the floating header’s day changes).

## Tick composition order (must stay stable)

```
_onTick:
  1. Overlay guard → abort scroll state, stop ticker
  2. Highlight-only early exit (no _markScrollActive)
  3. Drain _pendingScrollDelta
  3b. If content fits → cancel fling (edge effect still allowed)
  4. delta += fling.tickFling
  5. delta += tickAnimate          // close: offset delta; far: fade only
     // skipped while span auto-scroll occupies the origin writer
  6. delta += span auto-scroll
  7. Drag only: delta = edge.claim(delta, travel)   // first claim on reverse
     then split: unconsumed at a reached edge vs consumed travel
  8. applyScrollDelta(consumed only)
  9. Update _scrollVelocity EMA
 10. _repositionFromAnchor
 11. _renormalizeAnchor            // unless close-path
 12. _clampBoundaries
 13. Edge effect: pull unconsumed (drag) / absorbImpact (fling), then
     edge.tick (spring) → markNeedsPaint while active
 14. Semantics + _publishControllerState
 15. _tickFloatingHeader
 16. tickHighlight / tryArmPendingHighlight / settle → _onAnimateSettled
 17. markNeedsLayout OR markNeedsPaint
 18. _stopTickerIfIdle
```

Unconsumed remainder is measured from oldest/newest **box geometry**, never from
`anchorPixelOffset` after renormalize. Mid-conversation travel must not feed
the edge effect.

## Drag

| Event | Behavior |
|-------|----------|
| `_onDragStart` | `_cancelPendingTailPin()`, clear nav alignment, cancel fling/animate, `edge.onDragStart()` (freeze), `_dragInProgress = true` |
| `_onDragUpdate` | `_pendingScrollDelta += details.delta.dy` (including short content) |
| `_onDragEnd` | `flingAllowed = edge.onDragEnd(v)`; fling if `flingAllowed`, `\|v\| ≥ 50`, and content does not fit |

## Scroll physics

The host passes an immutable `ChatScrollPhysics` (`ChatScrollView.physics`,
`null` → `.forPlatform()`): one `ChatFling` plus one `ChatEdgeEffect`, each a
closed set with tunable params. The default reads `defaultTargetPlatform`
(never the theme): Android / Fuchsia → spline + stretch, iOS / macOS →
decay + rubber-band, Windows / Linux → spline + none; web follows the
browser OS through the same table. The render object
owns the runtime `ChatScrollMotion` built from it (`_motion.fling`,
`_motion.edge`). Physics governs the **drag path only**. Wheel, keyboard,
scrollbar, jump, `scrollBy`, and animate never read it.

Swap (`physics =`): an equal value is a no-op, so an in-flight fling or
spring survives. An unequal value cancels the fling (emits `ChatFlingEnd`),
resets the edge effect, rebuilds the motion, and republishes row chrome
paint tops.

## Fling

- `_startFling` / `_cancelFling` via `ChatFlingMotion`. `ChatFling.spline`
  runs `ChatSplineFlingSimulation`: Android's `OverScroller` spline, the same
  distance as `ClampingScrollSimulation` with the full native duration and
  tail, so idle-driven chrome waits as long as on a native list. `friction`
  scales travel (∝ friction^-0.74). `ChatFling.decay` runs Flutter's
  `FrictionSimulation` with drag `decelerationRate^1000` (iOS normal
  `0.998` → `0.135`), stopping below 10 px/s.
- **No-op** when [_contentFitsInViewport](./06-boundaries.md#short-content--_contentfitsinviewport).
- Per-tick clamp during fling (not suspended).
- Layout has no overscroll resistance. Unconsumed dy at a reached edge feeds
  the paint-only edge effect, which owns any resistance (rubber-band).
- Render emits `ChatFlingStart` / `ChatFlingEnd`; physics does not touch events.

## Edge effect

The render object drives the edge effect only through `ChatEdgeEffectState`.
The release rules live in the strategy: `ChatStretchOverscroll` for
`ChatEdgeEffect.stretch`, `ChatRubberBandOverscroll` for
`ChatEdgeEffect.rubberBand`, `ChatNoOverscroll` for `ChatEdgeEffect.none`.

- Paint-only message-layer transform (`_edgeTransform`). Layout pins stay
  clamped.
- **Claim first** (drag ticks): before the edge-unconsumed split, `claim`
  sees the whole delta, the viewport height, and the travel content can
  absorb. Stretch passes all of it through. Reverse travel of more than 1 px
  into content (with no more than 1 px spilling past a pin) starts its
  release, so content moves at once instead of unwinding the pull first.
  Short content has zero travel, so reverse motion unwinds the pull.
  Rubber-band consumes reverse motion along its resistance curve and returns
  only what is left once the layer is back at the pin. None passes
  everything through.
- **Pull** only the overflow past the remaining pin travel
  (`_unconsumedOverscrollDelta`, > 1 px). A missing boundary box means that
  edge is not in play.
- **Drag end**: `onDragEnd(v)` answers whether a content fling may start.
  Stretch: a reverse flick releases and allows it; same-direction velocity
  absorbs, then springs back; an idle release springs from the current
  stretch with zero initial velocity (no slam). Rubber-band: a flick
  toward content (≥ 50 px/s) keeps the displacement and allows the fling;
  the tick feeds fling deltas through `claim`, so the fling unwinds the
  band before content moves. Any other visible displacement springs back
  at the layer's speed — the release velocity times the band's slope
  `c·((d − b)/d)²` — and blocks the fling; the spring stops at the pin.
  None: always allows the fling.
- **Stranded edge**: an edge effect still active with no drag, no fling,
  no catching press, and no spring (a carried fling that never started,
  was cancelled, or died mid-unwind) is released with `onDragEnd(0)` on
  the next tick.
- **Fling impact**: a fling that reaches a pin (including the frame that
  consumes the last travel pixels) calls `absorbImpact` with its velocity,
  then the fling is cancelled. Rubber-band launches its spring from the pin
  with that velocity, uncapped: its critically damped spring peaks at
  `v / (ω·e)`, so the overshoot keeps scaling with the impact. Every edge
  spring's clock (`ChatSpringClock`) starts at the previous tick (≤ 34 ms
  back), so neither the release nor the impact frame repeats the launch
  position.
  None discards it.
- **Press catch**: a pointer down while the edge springs (not dragging)
  freezes it (`onDragStart`) and sets `flingCancelSuppressesLongPress` for
  that pointer, exactly like catching a fling. If the press becomes a drag,
  `_onDragEnd` releases the effect. Otherwise the matching pointer up does
  (`onDragEnd(0)`); the render object sees that up before the drag
  recognizer does.
- **Reset** by jump, `scrollBy`, `animateTo`, overlay, controller or physics
  swap, and bottom-pad change.
- **One transform everywhere**: message-layer paint, `hitTestChildren`,
  `_selectionMessageIdAt`, `applyPaintTransform`, and row chrome `paintTop`
  all read `_edgeTransform`. The floating date header, scrollbar, and overlay
  stay viewport-fixed and outside it.

## `_repositionFromAnchor`

Recomputes every built child’s `ChatMessageParentData.offset` from the current
anchor without rebuild or `child.layout`.

- Fast path `_repositionMessagesOnly` when `_chunkErrors.isEmpty`.
- General path interleaves chunk-error tiles at chunk boundaries.
- Null slots: **skip** (`continue`), never `break`.

Row chrome inputs (`paintTop`, `headerZone`, `scrollActivity`) are published
afterwards by `_resolveRowChromeFrame` on the same tick (Tier-1-safe
parent-data writes).

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
  active edge effect, drag, or span auto-scroll occupying the origin writer.
- `_ticking` follows `TickerMode` — inactive routes do not animate fling
  off-screen.
- Overlay mode aborts all scroll work and stops the ticker.

## Programmatic `scrollBy`

`_onScrollBy` cancels fling/animate, resets the edge effect, clears pending drag delta, and
calls **`markNeedsLayout`** (not Tier-1). Intentional full settle so physics
and follow-tail converge on the next layout.

## Pointer / wheel

- Mouse wheel: `_pendingScrollDelta -= event.scrollDelta.dy` (sign maps to
  anchor convention), Tier-1. Wheel also calls `_cancelPendingTailPin` and
  clears pending `jumpTo` / `jumpToCenterBand` navigation (same user-preemption
  as drag start) so open-at-newest / leave-reopen settle cannot yank the
  viewport back under the wheel. Fling / animate cancel with the same path.
- Pointer down during a fling or edge spring: cancel the fling or freeze the
  spring, and set `flingCancelSuppressesLongPress` so the viewport-owned
  selection tap and long-press do not fire on the catching press.
- When a selection controller is wired, the same pointer down is also
  offered to `ChatSelectionPointer` (long-press enters selection or starts
  an unselect span if the origin was already selected; tap toggles while
  mode is on). The pinned floating date header is not a hit — the
  message underneath receives the long-press or tap. Rows do not attach
  a competing detector. A host `spanYield`
  that returns true at `(messageId, globalOffset)` claims the long-press:
  no span starts, membership does not change from that press, and
  `addSpanYieldedListener` is notified once.
  A host `selectionAllowed` that is not selectable is not a span hit and
  does not join the selected set, even on the present-neighbor walk. Emptying
  the selected set does not end the span; membership stays empty.
  Chrome wrap follows `showsChrome` (`none` omits wrap; `gutterOnly` shifts
  without a check). Assigning `selectionAllowed` (or
  `reapplySelectionAllowed`) drops newly-non-selectable ids from the
  selected set and invalidates chrome wrap. If the gesture
  origin becomes absent, the span aborts (set kept, origin
  not retargeted) so delete recovery may write the origin.
- While a live span pointer occupies the top or bottom edge band, span
  auto-scroll is the sole origin writer (follow-tail and close-path
  animate yield). Delta is zero when content fits, applying it would
  unstick a boundary pin, or a select span is at the selection cap in
  the grow direction (unselect spans ignore the cap; auto-scroll toward
  the origin still runs). A refused grow bumps `capHits` once per wall.
  Newly laid-out present messages can become
  the span hit. Lift or span abort releases the writer.
- Scrollbar grab: pointer routing runs in this order.
  1. `hitTest` adds the runtime's strip target ahead of every child when
     the position lies in the mouse strip (no overlay mode), so its basic
     cursor beats message cursors and `MouseTracker` enter / exit drive
     strip hover. Wheel events still reach the viewport and scroll.
  2. `handleEvent` records every pointer down / up / cancel. Only a
     **fresh press** — a down while no other pointer is down on the
     viewport — is offered to `ChatScrollbarRuntime.tryStartGrab`, and only
     when the list can scroll. A press while another pointer holds a list
     drag, span gesture, or fling catch never grabs; a lone press on the
     scrollbar during a fling grabs and cancels the fling.
  3. `tryStartGrab` tests the last painted frame (resolved in
     `_paintScrollbar`), so a press lands on what was painted, and routes
     by pointer kind with the preset's `ChatScrollbarGrab`. Mouse and
     trackpad: the strip (`stripWidth`, live while hidden), primary button
     only; thumb press grabs, track press centres the thumb or falls
     through per `trackPress`. Touch, stylus, and unknown: only while
     visibility is above `0`, only inside the touch target (the thumb
     grown to `touchTargetWidth` from the edge and `touchTargetMinHeight`
     tall); everything else falls through. Both reach at least across the
     painter's track; RTL mirrors them to the left edge.
  4. A claimed press returns before fling catch, selection pointer, and
     drag, so no tap, long-press, span, or list drag starts from it. A
     declined press continues down the usual path.

  A message menu session covers the viewport with its own dismiss layer,
  so a strip press there closes the menu and never reaches `handleEvent`.
  A press on the thumb records its offset into the thumb and moves
  nothing; a press on the track centres the thumb on the pointer. The thumb
  length and the band's span share are frozen at the press. Each move
  repaints the thumb under the pointer and maps its progress through
  `_dragScrollbarTo` — the inverse of the painted progress,
  `oldest + progress × (idCount − visible ids)` — to a band-top fractional
  id, then `jumpToFraction(id, fraction)` (layout path, `FractionalPlacement`
  seated on the row's real height). Release releases the placement and
  eases the thumb rect back to the band's thumb on the ticker
  (`tickSettle`, over the visibility preset's fade-out and curve — 250 ms
  `easeOut` under always). A grab holds scrollbar visibility; see
  [Scrollbar visibility](09-day-groups-and-headers.md#scrollbar-visibility).

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
