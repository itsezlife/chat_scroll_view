---
type: Architecture Reference
title: Navigation and Tail
description: jumpTo, scrollBy, animateTo, alignment lifecycle, follow-tail, and pinNewest guards during delete recovery.
tags: [navigation, jumpTo, tail, alignment]
timestamp: 2026-07-04T00:00:00Z
resource: lib/src/chat_scroll/chat_scroll_controller.dart
---

# Navigation and Tail

## Controller APIs

| API | Anchor effect | Notifications |
|-----|---------------|---------------|
| `jumpTo(id, {alignment})` | id = target, offset = `0` | Jump listeners + `ChatProgrammaticJump` |
| `scrollBy(px)` | offset += px | ScrollBy listeners + `ChatProgrammaticScroll`; no-op if `px == 0` or non-finite |
| `animateTo` | Animator drives; falls back to `jumpTo` if unbound | `ChatAnimateStart` / `ChatAnimateEnd` |
| `applyScrollDelta` (`@internal`) | offset += delta | None (tick / clamp / pad) |
| `reassignAnchor` (`@internal`) | silent id + offset | None (renormalize / align / animator) |

**Sign convention:** positive `scrollBy` / drag reveals **older** (content moves
down) — opposite of Flutter `ScrollPosition.pixels`.

**Absent targets:** navigation completes without error; absent slots have zero
height — do not assume a visible row at that id. Check `statusOf` before
navigating if the user must see a specific message (ADR 002).

Consumers must **not** call `reassignAnchor`, `applyScrollDelta`,
`visibleRange=`, `isAtTail=`, `animator=`, or `notifyScrollEvent`.

## Alignment lifecycle

`jumpTo` / `animateTo` set:

- `navigationAlignment` (0 = band top, 1 = band bottom)
- `navigationAlignmentMessageId`

Layout applies alignment via `_applyNavigationAlignment` after the target row
is built:

1. Needs matching `anchorMessageId`.
2. **Dual-writer guard:** returns false while close-path animate runs.
3. If target is known newest → **clear alignment without snap** (tail pin owns
   geometry).
4. Needs built child with size; if within `0.5px` of desired and message loaded
   → clear alignment.
5. Else `reassignAnchor(targetId, desiredTop)` + `_repositionFromAnchor`.

`_alignedTopForMessage` uses the scroll band (`topPad` .. `height - bottomPad`).
Tall **non-newest** messages (`height ≥ band`) always land at band top.
**Known-newest** close-path `animateTo` ends at tail-pin top (`bottomEdge −
height`) so scroll-to-end does not animate to band top and snap afterward. True
chat pin (`newest.bottom == bottomEdge`) is still enforced by layout `pinNewest`.
See [Animation Integration](./11-animation-integration.md).

## Render reactions

### `_onJump`

1. `_clampJumpTarget` (do not land past known newest when reached).
2. Sync navigation alignment target.
3. `_markPinTailOnJumpIfNeeded`.
4. Cancel fling, highlight, bounceback.
5. `_chunkFetchScheduler.onJump()`.
6. `markNeedsLayout`.

### `_onScrollBy`

Cancel fling/animate/bounceback, clear pending drag delta, `markNeedsLayout`
(full settle — not Tier-1).

### Pre-mount jump

`_normalizeAnchorToKnownTail` covers jumps that landed past `newestKnownId`
before the viewport attached.

### Attach

`_seedTailNavigationOnAttach` may mark pending tail pin for initial open at
newest.

## Follow-tail

Snapshot fields (updated in `_publishIsAtTail` on layout **and** tick, except
overlay):

- `_wasAtTailLastLayout`
- `_lastSeenNewestId`

On layout, when `reachedNewest` and `_wasAtTailLastLayout` and newest id
advanced → `repinBottom` so the new message is not left below the bottom edge.

`isAtTail` listenable uses `_DeferredValueNotifier` — pushes from
`performLayout` defer `notifyListeners` to post-frame so listeners may
`setState`. Initial value is `false` until first layout.

## Visible range

`ChatVisibleRange` includes `firstId` / `lastId`, paint-band metrics,
`firstRow` / `lastRow`, optional `anchorNextRow`. Chunk-error tiles can widen
id coverage. Same deferred notifier contract as `isAtTail`.

## Scroll events

Sealed `ChatScrollEvent` stream: drag start/end, fling start/end, programmatic
jump/scroll, animate start/end. Physics does not emit events — render does.

## Tail-pin flags

See [Boundaries](./06-boundaries.md) for `_pinTailOnJump`,
`_pendingTailPinUntilSettled`, `_userPreemptedTailSettle`. Drag start cancels
pending settle and sets user-preempted so passive pin does not yank back.

### `pinNewest` during delete recovery

When `_deleteCollapseRecoveryActive`, `pinNewest` inside `_clampBoundaries`
applies extra guards:

- Block when the user was **not** at tail before delete (`!wasAtTailBefore`).
- Block when the user had **preempted tail** and post-delete geometry satisfies
  `isAtTail` — prevents an unintended snap to newest after mid-history delete.

These guards use snapshot fields from `_recordLayoutBeforeDelete`. Normal tail
follow (user genuinely at tail, deletes newest) is unchanged. Emits
`pinNewestSuppressed` on `layout.deleteCollapse` when blocked.
