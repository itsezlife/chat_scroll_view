---
type: Architecture Reference
title: Boundaries
description: pinNewest, pinOldest, overscroll, reverse pin order, pads, and tail flags.
tags: [scroll, boundaries, overscroll, tail]
timestamp: 2026-07-04T00:00:00Z
resource: lib/src/chat_widgets/render_chat_scroll_view.dart
---

# Boundaries

Boundaries are **local geometric constraints** on the oldest/newest **built**
rows — not a global `minScrollExtent` / `maxScrollExtent`. Pins run only when
`reachedOldest` / `reachedNewest` and `_boundaryBox` finds a render box.

See [Coordinate Model](./01-coordinate-model.md) for the scroll band and
[Tier-1 Scroll](./05-tier1-scroll.md) for when clamp is suspended.

## `_boundaryBox`

Resolves the visual boundary for an id:

1. If a chunk-error tile exists for `chunkOf(id)` → that tile.
2. Else `_children[id]`.

Pins and overscroll measurement use this so an errored boundary chunk still
has something to pin against.

## `_clampBoundaries`

Returns `true` if any pin applied (caller cancels fling; on tick, also animate).

### Suspension

Returns immediately when `_dragInProgress || _physics.isBouncing` — overshoot
allowed; bounceback owns the return.

| Phase | Clamp? |
|-------|--------|
| Drag | Suspended |
| Bounceback | Suspended |
| Fling | Runs every tick |
| Close-path `animateTo` | Runs every tick (current code) |
| Idle layout | Runs |

### `pinNewest`

- Requires `reachedNewest` and `newestKnownId`.
- Suppressed if `_userPreemptedTailSettle && !_computeIsAtTail()` (user scrolled
  away during attach/jump settle).
- `bottomEdge = height - bottomPad`.
- Pins when `bottom < bottomEdge` **or** (`repinBottom && bottom > bottomEdge`).
  The second case pulls content **up** when follow-tail / jump-to-tail and the
  newest grew below the edge.
- Applies `applyScrollDelta(bottomEdge - bottom)` then `_repositionFromAnchor`.

### `pinOldest`

- Requires `reachedOldest`.
- If oldest top `> 0`, apply `delta = -topY` (pin to **`y = 0`**, not `topPad`).

### Short content / `reverse`

Both pins can fire when the conversation fits in the viewport; **last wins**:

| `reverse` | Order | Short content stacks |
|-----------|-------|----------------------|
| `true` (chat) | oldest, then **newest** | Bottom |
| `false` (list) | newest, then **oldest** | Top |

## Overscroll

### Measurement

| Side | Condition | Signed value |
|------|-----------|--------------|
| Top | oldest top `> 0` | Positive (`topY`) |
| Bottom | newest bottom `< bottomEdge` | Negative (`bottom - bottomEdge`) |

`_signedOverscroll` returns the dominant side when both are violated.
`_overscrollOnSide` reads one side only — bounceback **locks** the side at arm
time so short-content / composed fling cannot flip sign mid-spring.

### Resistance

`factor = 1 / (1 + |overscroll| / overscrollMax)` (default `overscrollMax = 200`).
Applied only when delta pushes **further** past the boundary, and **only while
dragging**. Fling / animate / wheel / keyboard use clamp, not resistance.

### Bounceback

- Armed on drag end if overscrolled (`_maybeStartBounceback`).
- Linear ramp of overscroll → 0 over `bounceDuration` (default 200 ms).
- Suspends clamp while active.
- Composes additively with fling in `_onTick`.
- Cancelled by: new drag, `scrollBy`, `animateTo`, jump, overlay, controller swap.

## Padding

### Bottom pad (compensated)

`_compensateBottomPaddingChange`:

- `delta = previousPad - currentPad`; `applyScrollDelta(delta)` so content
  **screen position** stays fixed when the composer/keyboard inset changes.
- Seeds `_lastLaidOutBottomPad` on first layout without scrolling.
- `_bottomPadCompensationBase` survives a concurrent dataSource swap that
  clears the last laid-out pad.
- Runs for **all** scroll positions — not only at the tail.

**Must not** implement keyboard follow via follow-tail `pinNewest` — that yanks
users reading history back to the newest message.

### Top pad (not compensated)

`_onTopPaddingChanged` only calls `markNeedsLayout`. Affects alignment band,
floating header Y, and scrollbar insets. `pinOldest` still uses `y = 0`.

## Tail-pin state machine

| Flag | Role |
|------|------|
| `_pinTailOnJump` | One-shot: force `repinBottom` on **next** layout even if `_wasAtTailLastLayout` is false |
| `_pendingTailPinUntilSettled` | Keep repinning across layouts until at-tail with loaded newest (lazy height / inset settle) |
| `_userPreemptedTailSettle` | User dragged during settle → block `pinNewest` until explicit tail nav |
| `_wasAtTailLastLayout` | Snapshot from `_publishIsAtTail` (layout **and** tick) |
| `_lastSeenNewestId` | Detect `tailAdvanced` |

### Setters

`_markPinTailOnJumpIfNeeded(targetId)` — if `targetId == newestKnownId` and
`reachedNewest`. Called from `_onJump`, `_normalizeAnchorToKnownTail`,
`_seedTailNavigationOnAttach`, `_onAnimateSettled`.

`_applyPendingTailPin` — clears if no newest, anchor ≠ newest, or user scrolled
newest top to/below bottom edge; else sets `_pinTailOnJump` again.

### Follow-tail (new messages)

`repinBottom` when `_wasAtTailLastLayout && newest > _lastSeenNewestId` and
`reachedNewest`. Default pin only lifts content when bottom is **above** the
edge; a new message below needs forced repin.

### `_computeIsAtTail`

Newest built, bottom within `0.5px` of `bottomEdge`, and newest top still above
`bottomEdge`. Overlay → `false`. Overlay must **not** update
`_wasAtTailLastLayout` (preserves follow-tail across overlay → normal).

## Layout integration

In `performLayout` (see [Layout Pipeline](./04-layout-pipeline.md)):

```
tailAdvanced = _wasAtTailLastLayout && newest advanced
_applyPendingTailPin()
repinBottom = _pinTailOnJump || (reachedNewest && wasAtTail && tailAdvanced)
_pinTailOnJump = false
_clampBoundaries(repinBottom: repinBottom)
```
