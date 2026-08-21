---
type: Architecture Reference
title: Animation Integration
description: Close/far animateTo paths, stitch far path, load policy, writer ownership.
tags: [animation, animateTo, dual-writer, stitch]
timestamp: 2026-08-21T00:00:00Z
resource: lib/src/chat_scroll/chat_animator.dart
---

# Animation Integration

Animations are a **secondary layer**. They write the same
`(anchorMessageId, anchorPixelOffset)` origin as drag and layout — they must
not invent a parallel coordinate system. This document is the antidote to
“compensate / fix / ultra fix” patches.

Core model: [Coordinate Model](./01-coordinate-model.md),
[Invariants](./02-invariants.md).

## Entry

`ChatScrollController.animateTo`:

1. Sets `navigationAlignment` + `navigationAlignmentMessageId`.
2. Emits `ChatAnimateStart`, awaits `ChatAnimator.animate(...)`, emits
   `ChatAnimateEnd` in `finally` (skipped when coalesced onto an in-flight
   same-target animate, or when the call is ignored while busy).
3. If no animator bound → `jumpTo`.
4. Optional `loadPolicy` (default `immediate`) — see below.

### Spam / re-entry (Telegram-style)

Telegram `RecyclerAnimationScrollHelper.scrollToPosition`:

```java
if (recyclerView.fastScrollAnimationRunning) {
    return;
}
```

| Case | Behavior |
|------|----------|
| Any [animateTo] while animating, **different** target | **Ignored** — in-flight motion continues; call returns immediately |
| Same `messageId` + alignment while animating | **Coalesce** — return the in-flight future |
| Target built and already at close-path end Y | **No-op** — optional highlight only |
| Close path with `\|end − start\| < 1px` | **Instant complete** — no empty 300ms tween |

Drag / clamp cancel the in-flight animation separately. Search / deep-link
should use [AnimateToLoadPolicy.immediate]; reserve `preferBuilt` for
self-insert / follow-tail.

## Load policy

| Policy | Unbuilt target | Built + near | Built + far |
|--------|----------------|--------------|-------------|
| `immediate` (default) | Stitch now (incoming may be shimmers) | Close | Stitch |
| `preferBuilt` | One layout wait, then close if near else stitch | Close | Stitch |

Self-insert / FAB follow-tail pass `preferBuilt` so one layout that builds
newest can take the **close path**. Far navigation stays `immediate` — no
idle wait before the teleport (Telegram `scrollToPositionWithOffset` is
synchronous when content is loaded).

## Path selection (`kCloseAnimateDistance = 2400`)

| Condition | Path |
|-----------|------|
| Target **built** and `\|offsetToTarget\| ≤ 2400` | **Close path** — continuous scroll |
| Target not built (after policy), or distance `> 2400` | **Far path** — stitch |
| `duration ≤ 0` | Instant `jumpTo`, no highlight |

Do **not** invent pixel distance across unloaded gaps. If not built after
`preferBuilt` wait → stitch.

## Close path

1. `reassignAnchor(targetId, offsetToTarget)` — anchor **id** becomes the
   target immediately; offset stays at current on-screen Y.
2. `animateStartOffset = offsetToTarget`,
   `animateEndOffset = _closePathEndOffsetFor(targetId, height, alignment)`
   — band alignment for ordinary targets; **tail-pin top** (`bottomEdge − height`)
   when the target is the known newest (`reachedNewest` + `newestKnownId`). Or
   `0` if not built yet.
3. Each tick: optional `rebaseClosePathEnd` (tail target or `alignment ≠ 0`), curve-
   interpolate; return `delta = target − anchorPixelOffset`.
4. Render applies via `applyScrollDelta` → `_repositionFromAnchor`.
5. At `t ≥ 1`: `_completeAnimate` → `reassignAnchor(targetId, end)`, arm
   highlight, set `_pendingSettleTargetId`, complete completer.

Does **not** write alignment on the controller each tick — only interpolates
`anchorPixelOffset` while holding `anchorMessageId` on the target.

### Suspended during close path

| Step | Suspended? |
|------|------------|
| `_renormalizeAnchor` | Yes (`_skipRenormalizeDuringClosePath`) |
| `_applyNavigationAlignment` | Yes (dual-writer guard) |
| GC of animate/nav targets | Pinned (`_gcPinnedDuringClosePath`) |
| `_clampBoundaries` | **No** (current code — pin can cancel animate) |

### Mid-flight geometry

`rebaseClosePathEnd` (layout end + each close tick for tail target or when
`alignment ≠ 0`)
resets start/end from live child height / insets so keyboard/height changes
do not leave a stale endpoint.

## Far path (stitch)

Telegram `RecyclerAnimationScrollHelper` pattern — **not** a viewport opacity
fade:

1. **Capture outgoing** — message boxes intersecting the paint band (id,
   frozen top Y, scroll direction). Pin against GC for the stitch window.
2. **Teleport** — `jumpTo(targetId, alignment:)` so fan-out builds the
   destination band (same call stack — no preferBuilt idle when using
   `immediate`).
3. **Measure** — on the post-jump layout, scroll travel from outgoing strip +
   incoming extents. Duration scales with travel (~300–1300ms,
   `Curves.easeOutQuint`). Animation clock starts at measure time.
4. **Paint invariant:** from the first post-jump frame, incoming rows are
   painted with full entry offset (`scrollLength * (1−t)` at `t=0`), even
   before measure completes (provisional = viewport height). Never show
   destination rows at rest between teleport and dual-translate.
5. **Animate** one factor `t ∈ [0,1]`:
   - Outgoing: paint Y `±scrollLength * t` (exit)
   - Incoming: paint Y from `∓scrollLength * (1−t)` to layout Y
6. **End** — clear pin, GC outgoing, `stitchProgress = 0`, complete
   completer, highlight / pinNewest settle as usual.

Paint drives **per-child translation**, not `OpacityLayer`. Cancel clears
stitch capture so mid-flight pins do not stick.

Post-jump contracts are the same as `jumpTo` (tail pin, alignment). Layout
owns pin/align.

## Writer ownership table

| Phase | Writes `anchorMessageId` | Writes `anchorPixelOffset` | Must not |
|-------|--------------------------|----------------------------|----------|
| Close start | Yes (`reassignAnchor`) | Yes (current Y) | — |
| Close tick | No | Yes (via delta) | Layout snap / renormalize |
| Close settle (`_completeAnimate`) | Yes | Yes (aligned end) | Second pin writer in animator |
| Stitch start | Yes (`jumpTo`) | Yes (`0` + layout align/pin) | Animator-owned pin |
| Stitch tick | No | No (paint translation only) | Opacity fade |
| Layout nav-align | No (id must match) | Yes | Run during close path |
| Layout `pinNewest` / `pinOldest` | No | Yes (delta) | Implement keyboard follow |
| Drag / fling / bounce | No | Yes (delta) | — |
| Bottom-pad compensate | No | Yes | — |

**Rejected pattern:** `tailPinnedTop` (or any second endpoint) on the animator.
Tall **mid-history** messages still end at band top via `_alignedTopForMessage`;
tall **newest** close-path animate uses the same top offset layout `pinNewest`
would apply (`bottomEdge − height`). True chat pin enforcement remains layout
`pinNewest` only.

## Settle ordering (current)

```
tickAnimate t≥1
  → _completeAnimate (reassignAnchor + completer.complete)
  → applyScrollDelta(0) / reposition
  → clamp (may no-op — already idle)
  → takePendingSettleTargetId → _onAnimateSettled
```

`_onAnimateSettled`:

- May apply navigation alignment snap.
- `_markPinTailOnJumpIfNeeded` → `markNeedsLayout` if `_pinTailOnJump`.

Completer completes **before** layout `pinNewest`. Tail pin is deferred to the
**next** `performLayout` — source of post-future snap for tall newest (Defect A
in feature specs).

## Highlight

- On successful settle only (`cancelAnimate` skips).
- Deferred via `pendingHighlightTargetId` until message loaded **and**
  `RenderBox` exists.
- Dropped if status is absent/error.
- Paint: full-width tint over target row; chrome paints after.

## Cancel rules

Drag, `scrollBy`, clamp-hit (current), overlay, and controller dispose must
cancel animate without leaving stitch pins or stale completers.

## Close-path animate vs clamp (planned vs current)

| Topic | Intended | Current |
|-------|----------|---------|
| Animator endpoint | Tail newest → pin top; else `_alignedTopForMessage` | Matches |
| Tail pin owner | Layout `pendingTailPin` / `pinNewest` | Same, but **after** completer |
| Pin before future resolves | Layout pin before completer | Completer first |
| Clamp during close animate | Suspend | Does **not** suspend |
| Clamp during fling | Always | Always |
| Resistance during fling | Drag only | Drag only |
| Force `jumpTo(newest)` if anchor ≠ newest after tail animate | Planned | Not present |
| Effective-tail / removal ghosts | Extent coordinator | **Not in tree** |

No `chat_extent_coordinator.dart` in this codebase.

## Checklist for new animation features

1. Name the writer phase and which fields it mutates.
2. List suspended core steps (renormalize, nav-align, clamp).
3. Do not add a second geometry writer for pin/tail.
4. Prefer extending close/far paths over a one-off compensate path.
5. Settle must leave layout as the authority for boundary pins.
6. Far path must keep visual continuity via stitch translation, not fade.
