---
type: Architecture Reference
title: Animation Integration
description: Close/far animateTo paths, writer ownership, and clamp suspend rules.
tags: [animation, animateTo, dual-writer]
timestamp: 2026-07-04T00:00:00Z
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
   `ChatAnimateEnd` in `finally`.
3. If no animator bound → `jumpTo`.

## Path selection (`kCloseAnimateDistance = 2400`)

| Condition | Path |
|-----------|------|
| Target **built** and `\|offsetToTarget\| ≤ 2400` | **Close path** — continuous scroll |
| Target not built, or distance `> 2400` | **Far path** — opacity crossfade + midpoint `jumpTo` |
| `duration ≤ 0` | Instant `jumpTo`, no highlight |

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

## Far path

1. No anchor reassignment at start.
2. `fadeOpacity` goes `1 → 0` (first half), at `t ≥ 0.5` one-shot
   `jumpTo(targetId, alignment:)`, then `0 → 1`.
3. Curve applied **per half** so opacity is exactly 0 at midpoint.
4. Tick returns `0` (no scroll delta); paint uses `OpacityLayer`.

Post-jump contracts are the same as `jumpTo` (tail pin, alignment). Layout
owns pin/align.

## Writer ownership table

| Phase | Writes `anchorMessageId` | Writes `anchorPixelOffset` | Must not |
|-------|--------------------------|----------------------------|----------|
| Close start | Yes (`reassignAnchor`) | Yes (current Y) | — |
| Close tick | No | Yes (via delta) | Layout snap / renormalize |
| Close settle (`_completeAnimate`) | Yes | Yes (aligned end) | Second pin writer in animator |
| Far midpoint | Yes (`jumpTo`) | Yes (`0` + layout align/pin) | Animator-owned pin |
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
cancel animate without leaving fade opacity or stale completers.
`_cancelAnimate` clears fade layer when opacity ≠ 1.

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
