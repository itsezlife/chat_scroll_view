---
type: Architecture Reference
title: Coordinate Model
description: Anchor-based scroll origin versus ScrollPosition; sign convention, scroll band, and visible-band stability on delete.
tags: [scroll, anchor, coordinates]
timestamp: 2026-07-04T00:00:00Z
resource: lib/src/chat_scroll/chat_scroll_controller.dart
---

# Coordinate Model

## Origin of all scroll geometry

The viewport has **no** absolute scroll offset and **no** total content height.
Every child’s viewport-Y is derived from exactly two fields on
`ChatScrollController`:

| Field | Meaning |
|-------|---------|
| `anchorMessageId` | Message id (or chunk-error first-id) whose **top edge** is the layout origin |
| `anchorPixelOffset` | Viewport-local **Y of that top edge** (may be negative or below the viewport) |

Message IDs increase toward **newer** content: lower id = older (above), higher
id = newer (below).

These fields are the **only** scroll state. Paint, hit-test, floating header
placement, and boundary pins all read positions that ultimately come from this
pair via fan-out or reposition.

## How children get their Y

### Layout (Tier-2): `_fanOutFromAnchor`

1. Resolve the anchor render box (message tile or chunk-error tile).
2. Place it at `y = anchorPixelOffset`.
3. Walk **down** (newer, `id++`): `y += height` for each built row.
4. Walk **up** (older, `id--`): `y -= height` for each built row.
5. Stop when the build zone is filled (`cacheExtent + extraBuildExtent` plus a
   directional lead biased by scroll velocity).

Absent IDs contribute **zero height** and are never inserted into `_children`.
Fan-out advances past them with `_nextNonAbsentIdDown` / `_nextNonAbsentIdUp`.

### Scroll (Tier-1): `_repositionFromAnchor`

Same stacking math, but only over **already-built** children. No
`buildChild`, no `child.layout` — only parent-data `offset` writes. Used every
ticker frame after `applyScrollDelta`.

**Critical:** reposition walks `minBuiltId..maxBuiltId` and **skips** null
slots (`continue`). It must never `break` on the first missing id — absent gaps
would leave far-side messages with stale offsets (visible “shifting” on
animation ticks).

## Sign convention

Anchor-relative, **opposite** of Flutter `ScrollController.position.pixels`:

| Delta | Effect on `anchorPixelOffset` | Content motion | Reveals |
|-------|-------------------------------|----------------|---------|
| Positive | Increases | Moves down | Older messages (smaller ids above) |
| Negative | Decreases | Moves up | Newer messages |

Applies to drag (`details.delta.dy`), `scrollBy`, fling, bounceback, and
close-path animate deltas. When porting from a `ListView` listener, **negate**.

`scrollBy(0)` and non-finite values are silent no-ops (no listeners, no events).

## Scroll band (insets)

Alignment and tail pin use the **scroll band**, not the raw viewport edges:

```
y = 0                         viewport top
y = topPad                    scroll band top (alignment 0, floating header)
y = height - bottomPad        scroll band bottom (tail pin, alignment 1)
y = height                    viewport bottom
```

- **`bottomPadding`**: reserved for composer / keyboard chrome. Changes are
  **compensated** by shifting the anchor so on-screen content stays put
  (`_compensateBottomPaddingChange`).
- **`topPadding`**: reserved for top chrome. Changes only trigger
  `markNeedsLayout` — **no** anchor compensation. Floating header pins to
  `topPad`. `pinOldest` pins the oldest row’s top to **`y = 0`**, not `topPad`.

**Host ownership.** The viewport only consumes these listenables. The host
aggregates occluding chrome (safe area, header reserve, composer, keyboard)
into them. Overlay widgets that sit above the reserved edge must not add
to the pad. See [14-host-chrome-insets.md](./14-host-chrome-insets.md).

`_alignedTopForMessage(height, alignment)`:

```
topEdge = topPad
bottomEdge = height - bottomPad
travel = bottomEdge - topEdge - messageHeight
if travel <= 0: return topEdge   // tall message: always band top
return topEdge + clamp(alignment, 0, 1) * travel
```

`alignment = 0` → message top at band top; `1` → message bottom at band bottom.
When `messageHeight >= band`, travel is ≤ 0 and the result is always `topEdge`
**except** close-path `animateTo` to the known newest — endpoint is
`bottomEdge − messageHeight` (tail-pin top). True chat **tail pin**
(`newest.bottom == bottomEdge`) is still owned by `pinNewest` in layout (see
[06-boundaries.md](06-boundaries.md)).

## Contrast with standard Flutter scroll

| Concern | `ListView` / `ScrollPosition` / slivers | This viewport |
|---------|----------------------------------------|---------------|
| Scroll state | Absolute `pixels` in `[minScrollExtent, maxScrollExtent]` | `(anchorMessageId, anchorPixelOffset)` |
| Content height | Required for extents and scrollbar | Never known globally |
| Jump to item N | Needs pixel offset of N (or estimate + `correctBy`) | `jumpTo(id)` — O(viewport) fan-out from new anchor |
| Insert/delete above viewport | Shifts all pixels; must correct position | Anchor id unchanged; only local geometry changes |
| Teleport far away | Rebuild path through intermediate offsets | Instant re-anchor; far animate uses fade + jump |
| Boundary | Clamp `pixels` to extents | Pin oldest/newest **built** boxes when `reached*` |
| Scrollbar | Often needs full extent | Id-linear / band-density math (no full height) |

### Why not `ListView.builder`

Requires `maxScrollExtent` (total height). Jump to an arbitrary message id
without knowing its pixel offset is impossible without hacks. Scrollbar and
insertions above the viewport fight the absolute coordinate system.

### Why not the sliver protocol

`SliverConstraints.scrollOffset` is an absolute pixel offset from the start.
Teleporting to message 1500 requires inventing a new `scrollOffset` and
constantly correcting via `ScrollPosition.correctBy()`. None of the sliver
benefits (coordinated multi-sliver scroll, `SliverGrid`) are used.

### Why anchor-based works for chat

- Conversations are bidirectional and unbounded in both directions.
- Messages have variable height; total height is expensive and unstable.
- Teleport (search, deep link, jump to reply) is a first-class operation.
- Deletion gaps are modeled as **absent** ids with zero height, not renumbering.

## Writers of the origin

| API | Mutates | Notifies consumers? | Typical caller |
|-----|---------|---------------------|----------------|
| `applyScrollDelta(delta)` | `anchorPixelOffset` only | No | Tick path, clamp pins, bottom-pad compensate |
| `reassignAnchor(id, y)` | Both | No | Renormalize, nav-align, animator close-path |
| `scrollBy(pixels)` | `anchorPixelOffset` | Yes → `markNeedsLayout` | Programmatic scroll |
| `jumpTo(id, {alignment})` | id + offset `0` + alignment | Yes → `markNeedsLayout` | Navigation |

Consumers (`_fanOutFromAnchor`, `_repositionFromAnchor`, paint) **must not**
invent a parallel “visual offset” or absolute Y. See
[02-invariants.md](02-invariants.md) and
[11-animation-integration.md](11-animation-integration.md).

## Renormalization (same pixels, new origin)

When the anchor box drifts outside `[-cacheExtent, height + cacheExtent]`,
`_renormalizeAnchor` silently picks the topmost visible child and
`reassignAnchor(bestId, bestOffset)`. Visually nothing moves; the next fan-out
builds a tight range around a visible origin instead of a long chain back to a
drifted anchor.

Close-path `animateTo` **suspends** renormalize so the anchor id can stay on
the off-screen target while the offset interpolates.

Delete recovery **suspends** renormalize for one layout pass when
`_preserveViewportAfterDelete` runs — post-delete off-screen anchor is intentional,
not drift.

## Visible band (delete stability reference)

`_bottomBandMessage()` returns the built message whose bottom edge is closest
to the scroll band bottom (`height - bottomPad`). Fields: `id`, `top`, `bottom`,
`gapToBottomEdge`.

When the layout anchor becomes absent (message delete), absent-anchor
reassignment moves to a present neighbor but preserves the deleted top offset.
That alone is insufficient for tall messages scrolled into their interior. `_preserveViewportAfterDelete`
shifts `anchorPixelOffset` so **band bottom** (or band gap) stays within 8 logical
px of the pre-delete value — the reading position near the composer, not raw
anchor Y.

Top-of-tall delete (deleted top on screen, height ≥ 2× viewport): `scrollDelta ≈ 0`.
Medium-tall deletes may need band-bottom delta even when anchor Y is unchanged.
See [04-layout-pipeline.md](04-layout-pipeline.md) §6c.
