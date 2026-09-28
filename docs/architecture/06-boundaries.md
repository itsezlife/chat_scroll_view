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

Returns immediately when stitch layout is frozen. Drag never skips clamp.
Overshoot feeds the paint-only edge effect, not a skipped pin.

| Phase | Clamp? |
|-------|--------|
| Drag | Runs |
| Edge-effect spring | Runs (layout already pinned) |
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
| `_signedOverscroll` / `_overscrollOnSide` | **Not used**. The edge effect uses `_unconsumedOverscrollDelta` |
| Drag / fling | Travel and fling suppressed; unconsumed drag dy still feeds the edge effect |
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

A paint-time edge effect, chosen by `ChatScrollPhysics.edgeEffect`:
`ChatEdgeEffect.stretch` (the Android 12 EdgeEffect stretch, run by
`ChatStretchOverscroll`), `ChatEdgeEffect.rubberBand` (the `UIScrollView`
translate, run by `ChatRubberBandOverscroll`), or `ChatEdgeEffect.none`.
Layout never rubber-bands — the rubber-band translate is paint-only too.

`_unconsumedOverscrollDelta` is the portion of a tick delta that exceeds
remaining travel to a reached pin (`max(0, distance-to-pin)`). Measured from
boundary **boxes** before apply, not from `anchorPixelOffset` after
renormalize. A missing boundary box means that edge is not in play
(unconsumed = 0). Sub-pixel remainder is consumed, not treated as a full
overscroll. Short content has zero travel on both pins, so the full delta
is unconsumed.

The render object passes `claim` the travel available to each drag delta
(`|delta| − |unconsumed|`). The strategy starts a release only when the frame
actually travels back into content while the effect is painted. A return
spring that is still active on a mid-list drag tick does not count, and
neither does short content, which has no travel.

Wheel / keyboard / `scrollBy` stay hard-clamped (no edge effect).

## Padding

### Bottom pad (compensated)

`_compensateBottomPaddingChange`:

- `delta = previousPad - currentPad`; `applyScrollDelta(delta)` so content
  **screen position** stays fixed when the composer/keyboard inset changes.
- Seeds `_lastLaidOutBottomPad` on first layout without scrolling.
- `_bottomPadCompensationBase` survives a concurrent dataSource swap that
  clears the last laid-out pad.
- Runs for **all** scroll positions — not only at the tail.
- While `_bottomPaddingDirty`, tick-path `pinNewest` is skipped so a live
  edge-effect ticker cannot pin to the new pad before compensate runs (that
  double-shift pushed the newest under the composer). The edge effect is
  reset on pad change.

**Must not** implement keyboard follow via follow-tail `pinNewest` — that yanks
users reading history back to the newest message.

### Top pad (not compensated)

`_onTopPaddingChanged` only calls `markNeedsLayout`. Affects alignment band,
floating header Y, and scrollbar insets. `pinOldest` still uses `y = 0`.
On-screen rows do not move. The exception is a held navigation placement:
the next layout sees the top pad differ from `_lastLaidOutTopPad` and re-applies
the placement against the new band top. See
[alignment lifecycle](./10-navigation-and-tail.md#alignment-lifecycle).

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
followTailRepin = !navigationMoved && (tailAdvanced || newestHeightGrew)
repinBottom = _pinTailOnJump || (reachedNewest && wasAtTail && followTailRepin)
_pinTailOnJump = false
_clampBoundaries(repinBottom: repinBottom)
```

`navigationMoved` is whether `_applyNavigationPlacement` seated its target
this pass. That navigation owns the origin, so follow-tail does not pull it
back. The previous layout's tail state may come from skeleton rows the clamp
pinned before the target's chunk loaded.
