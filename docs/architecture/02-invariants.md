---
type: Architecture Reference
title: Invariants
description: Hard rules that must never be violated when extending the scroll system.
tags: [scroll, invariants]
timestamp: 2026-07-04T00:00:00Z
---

# Invariants (Do Not Violate)

These rules are enforced by control flow, asserts, or comments in the
implementation. Violating them is the usual root cause of “compensate / fix /
ultra fix” patches. Treat them as non-negotiable when adding features.

## 1. Single geometric origin

All child Y positions derive from `(anchorMessageId, anchorPixelOffset)` via
`_fanOutFromAnchor` or `_repositionFromAnchor`.

**Must not:** invent a second absolute coordinate system, a parallel “visual
offset,” or an animator-only endpoint that layout also writes (e.g. a rejected
`tailPinnedTop` on the animator).

## 2. Integer id adjacency = scroll adjacency

Per [ADR 002](../adr/002-position-model.md), message ids are per-conversation
sequential. Fan-out advances with `id++` / `id--` and skips confirmed-absent
slots. Scrollbar and content-height estimates treat the id span as the document.

**Must not:** assume global auto-increment or random ids work. Gaps are
**deletions within** a sequential sequence, not sparse namespaces.

## 3. Child inflation only inside `invokeLayoutCallback`

Every `ChatChildManager` method (`buildChild`, `removeChildren`,
`buildFloatingHeader`, `buildChunkError`, `buildOverlay`) asserts
`insideLayoutCallback`. The render object sets that flag only inside
`_invokeChildManagerLayout` → `invokeLayoutCallback`.

**Must not:** inflate or deactivate children from the ticker, gestures, or
async callbacks.

## 4. Tier-1 is paint-only unless coverage fails

On the tick path, after reposition/clamp/header tick:

- If `_rangeNoLongerCovers()` **or** the floating header’s day bucket changed →
  `markNeedsLayout`.
- Else → `markNeedsPaint` only.

Tier-1 **must not** call `buildChild`, `child.layout`, or mutate widget trees.
Parent-data writes (`offset`, `dividerOpacity`) are allowed.

## 5. Clamp ownership

`_clampBoundaries` returns immediately (no pin) when:

- `_dragInProgress` — overshoot allowed; resistance applies on drag only
- `_physics.isBouncing` — bounceback owns the return to the edge

Fling **always** clamps each tick. Overscroll resistance is **drag-only** —
fling, animate, wheel, and keyboard go through clamp, not resistance.

**Current code:** close-path `animateTo` does **not** suspend clamp; a pin can
cancel the animation. Spec 027 intends suspend during close animate only —
document intent in [11-animation-integration.md](11-animation-integration.md);
do not invent ad-hoc clamp skips elsewhere.

## 6. Dual-writer discipline

At most **one active writer** of `anchorPixelOffset` for a given phase:

| Phase | Offset writer | Suspended |
|-------|---------------|-----------|
| Close-path animate | `tickAnimate` → `applyScrollDelta` | Renormalize; `_applyNavigationAlignment` |
| Layout settle / jump | `_applyNavigationAlignment`, pins | — |
| Drag / fling / bounce | Tick deltas + clamp (when not suspended) | Clamp during drag/bounce |

**Must not:** snap alignment in layout while close-path animate interpolates
(guarded by `_animator.isAnimating && !_animator.farAnimateActive`).

**Must not:** add a second pin writer in the animator for tall-tail geometry —
tail pin is layout’s `pinNewest` / pending-tail flags.

## 7. Reposition must span the built id range

`_repositionFromAnchor` / `_repositionMessagesOnly` walk from
`minBuiltId` to `maxBuiltId` and **skip** null children. Never `break` on the
first missing id — absent gaps would leave messages beyond the gap with stale
offsets.

## 8. Absent-skip termination

`_nextNonAbsentIdDown` returns `bound + 1` when the entire range is absent (or
`startId > bound`). `_nextNonAbsentIdUp` returns `bound - 1`.

**Must not** return `bound` itself when `bound` is absent — the caller would
re-enter the helper with the same arguments and loop forever.

## 9. Fan-out oldest bound

While `!reachedOldest`, upward fan-out’s lower bound is **`0`**, not
`oldestKnownId`. `oldestKnownId` is only the oldest *loaded* page; clamping
fan-out there prevents building placeholders for older chunks and **deadlocks
lazy pagination**.

When `reachedOldest`, the bound is `oldestKnownId`.

## 10. Slot namespaces are disjoint

Four separate identity spaces (see [08-chat-scroll-element.md](08-chat-scroll-element.md)):

| Slot | Key |
|------|-----|
| Messages | `int` message id |
| Chunk errors | `_ChunkErrorSlot(chunkIndex)` |
| Floating header | `_ChatSlot.floatingHeader` |
| Overlay | `_ChatSlot.overlay` |

`moveRenderObjectChild` always asserts — children never change slots.
Chunk-error tiles must not share the message-id map (avoids overwrite when a
chunk recovers from error).

## 11. Full-chunk fetch invariant

`fetchRange(fromId, toId)` must cover whole chunks only
(`ChatScrollChunk.isFullChunkRange`). Partial ranges corrupt absent-slot
marking (unfetched null slots marked permanently absent).

Fetch results are **sparse** — omit missing ids; never embed null placeholders.

## 12. Boundary deletes are atomic

When a delete removes the message at `oldestKnownId` or `newestKnownId`, update
via `seedBoundaries` in one call. Do not mutate boundary fields piecemeal.

## 13. Notification contract

`upsertMessage` / `upsertMessages` already call `notifyDataChanged`. Subclasses
must **not** call it again after `super`. `notifyDataChanged` is `@nonVirtual`.

## 14. Skip-rebuild uses message identity

`ChatScrollElement` caches `identical(message)`, status, and `startsNewDay`.
Mutating a message **in place** without replacing the instance will not rebuild
the child.

## 15. `getMessage` is not “previous / next message”

`getMessage(id)` returns null for absent **and** unloaded slots. Neighbor
logic must walk past confirmed-absent ids (same idea as fan-out helpers).
Today `_startsDay` only checks `id - 1` — a known limitation
([13-known-limitations.md](13-known-limitations.md)).

## 16. Bottom-pad compensation is universal; follow-tail pin is not

Keyboard / composer inset changes shift the anchor for **all** scroll
positions so content does not jump. Follow-tail `pinNewest(repinBottom:)` must
**not** be used to implement keyboard follow — that yanks users reading history
back to the newest message.

## Quick checklist for new code

1. Does this write `anchorMessageId` or `anchorPixelOffset`? Name the phase.
2. Does another writer run in the same frames? If yes, suspend one explicitly.
3. Does this need widgets? Only inside `_invokeChildManagerLayout`.
4. Does this need only offsets? Tier-1 + `markNeedsPaint`.
5. Does this assume a global extent or absolute pixels? Redesign.
6. Does this look up “previous message” with `getMessage(id - 1)` only? Walk
   absent slots.
