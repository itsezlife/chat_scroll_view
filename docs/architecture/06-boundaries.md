---
type: Architecture Reference
title: Boundaries
description: pinNewest, pinOldest, overscroll, short-content no-scroll mode, reverse pin order, pads, and tail flags.
tags: [scroll, boundaries, overscroll, tail, short-content]
timestamp: 2026-07-05T00:00:00Z
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
  away during attach/jump settle). Within `_tailEdgeSlop` past the band still
  counts as at-tail (follow only); that also clears preempt on publish.
- `bottomEdge = height - bottomPad`.
- Pins when `bottom < bottomEdge` **or** (`repinBottom && bottom > bottomEdge`).
  No automatic pin-up merely because the user is within the at-tail slop —
  that fought small intentional scroll-away.
- Applies `applyScrollDelta(bottomEdge - bottom)` then `_repositionFromAnchor`.

### `pinOldest`

- Requires `reachedOldest`.
- If oldest top `> 0`, apply `delta = -topY` (pin to **`y = 0`**, not `topPad`).

### Short content — `_contentFitsInViewport`

When the built span from oldest to newest fits inside the scroll band
(`height - topPad - bottomPad`) **and** both `reachedOldest` / `reachedNewest`
are true, there is **no scroll range** — behavior matches a non-scrollable
`ListView`.

Detection:

```
span = newestBottom - oldestTop
fits = span <= bandHeight + 0.5
```

When `fits`:

| Subsystem | Behavior |
|-----------|----------|
| `_signedOverscroll` / `_overscrollOnSide` | Always **0** — no overshoot to measure |
| Drag / fling / bounceback | **Ignored** — deltas not applied; fling not started |
| `_clampBoundaries` | **Single pin** only (not dual pin); skipped during delete recovery |
| Scrollbar paint | **Skipped** — nothing to scroll |
| Scrollbar drag | **Blocked** at pointer down |

Single-pin stacking (when not in delete recovery and not a top-band handoff):

| `reverse` | Pin | Stacks messages at |
|-----------|-----|-------------------|
| `true` (chat) | `pinNewest` only | Bottom (composer edge) |
| `false` (list) | oldest → `y = 0` via `applyScrollDelta(-topY)` | Top |

**Top-band handoff guard** — when `anchorPixelOffset ≥ -0.5` and `repinBottom`
is false, skip the short-content pin so a neighbor at the top edge after a
tall-message delete is not tail-snapped on the next layout. Tail jump
(`repinBottom`) still stacks at bottom / top as usual.

**Delete recovery** — the short-content fast path is **disabled** while
`_deleteCollapseRecoveryActive`; normal dual-pin clamp runs with delete-recovery
guards instead.

Previously, dual pin (oldest then newest in chat mode) fired on every fling
tick when both boundaries looked violated, producing equal-and-opposite deltas
and visible bounce jitter.

### Long content — dual pin / `reverse`

When content **does not** fit, both pins may run in one clamp; **last wins**:

| `reverse` | Order | Effect when both fire |
|-----------|-------|------------------------|
| `true` (chat) | oldest, then **newest** | Bottom wins |
| `false` (list) | newest, then **oldest** | Top wins |

## Overscroll

### Measurement

| Side | Condition | Signed value |
|------|-----------|--------------|
| Top | oldest top `> 0` | Positive (`topY`) |
| Bottom | newest bottom `< bottomEdge` | Negative (`bottom - bottomEdge`) |

When [_contentFitsInViewport](#short-content--_contentfitsinviewport)
is true, both sides report **0** — there is no scroll range to overshoot.

`_signedOverscroll` returns the dominant side when both are violated on **long**
content only. `_overscrollOnSide` reads one side only — bounceback **locks** the
side at arm time so composed fling cannot flip sign mid-spring.

### Resistance

`factor = 1 / (1 + |overscroll| / overscrollMax)` (default `overscrollMax = 200`).
Applied only when delta pushes **further** past the boundary, and **only while
dragging**. Fling / animate / wheel / keyboard use clamp, not resistance.

### Bounceback

- Armed on drag end if overscrolled (`_maybeStartBounceback`) — **no-op** when
  content fits in the viewport.
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

### Follow-tail (new messages + same-id height)

`repinBottom` when jump-to-tail, or `_wasAtTailLastLayout && reachedNewest` and
(`newest` id advanced **or** newest laid-out height grew vs the previous
layout). Default pin only lifts content when bottom is **above** the edge; a
new message below the edge **or** a same-id height jump past the edge needs
forced repin. `_tailEdgeSlop` widens `isAtTail` only — it does not snap.

### `_computeIsAtTail`

Newest built, `bottom ≤ bottomEdge + _tailEdgeSlop` (12px), and newest top still
above `bottomEdge`. Slop is **follow-tail detection only** — it does not snap
scroll. Overlay → `false`. Overlay must **not** update `_wasAtTailLastLayout`
(preserves follow-tail across overlay → normal). When true, publish clears
`_userPreemptedTailSettle`.

## Layout integration

In `performLayout` (see [Layout Pipeline](./04-layout-pipeline.md)):

```
tailAdvanced = _wasAtTailLastLayout && newest advanced
newestHeightGrew = wasAtTail && same newest id taller than last layout
_applyPendingTailPin()
repinBottom = _pinTailOnJump || (reachedNewest && wasAtTail && (tailAdvanced || newestHeightGrew))
_pinTailOnJump = false
_clampBoundaries(repinBottom: repinBottom)
```
