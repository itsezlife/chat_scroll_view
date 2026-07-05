---
type: Limitation Catalog
title: Known Limitations
description: Documented debt in the current implementation — facts, not fixes; includes resolved delete-scroll jump, short-content bounce, and neighbor lookup rules.
tags: [limitations, debt, absent, anchor]
timestamp: 2026-07-05T00:00:00Z
---

# Known Limitations

Facts of the **current** implementation. Do not paper over these with unrelated
hacks; fix at the root when restarting a feature (especially animations).

## `_startsDay` walks previous present message (fixed 2026-07-05)

**Was:** `_startsDay` only inspected `_bucketOf(id - 1)`; confirmed-absent
predecessors blocked inline day separators after delete.

**Fix:** compare against `getPreviousPresentMessage(id)` bucket — same absent
skip as fan-out. Unloaded predecessor still defers separator until data arrives.

## No automatic anchor replacement on delete (fixed 2026-07-05)

**Was:** deleted anchor still entered `_buildMessage` → shimmer or selectable
ghost row (`SelectableMessage` wraps builder output regardless of size).

**Fix:** `_reassignAnchorIfAbsent` before fan-out; `_buildMessage` and
`buildChild` bail on `statusOf.isAbsent`; `_purgeAbsentBuiltChildren` removes
stale elements. See invariant §18 in [02-invariants.md](02-invariants.md) and
step 6b in [04-layout-pipeline.md](04-layout-pipeline.md).

## Neighbor lookup via `getMessage` alone is wrong

`getMessage(id)` returns null for both absent and unloaded slots. Any
“previous / next message” logic must use **`getPreviousPresentMessage` /
`getNextPresentMessage`** (or `statusOf` + an absent walk — fan-out helpers
already do this). Using `getMessage(id ± 1)` as the sole neighbor probe is
incorrect.

Do **not** teach `getMessage` to substitute neighbors when [id] is absent —
direction (previous vs next) is caller-defined, and the returned instance must
match the requested id for widget lookup and CRUD.

## Delete scroll jump on tall anchor (fixed 2026-07-05)

**Was:** Deleting a tall anchor mid-scroll caused `_renormalizeAnchor` to jump to
an unrelated visible row, a silent band shift when anchor Y stayed unchanged, or
spurious `pinNewest` when the user had scrolled away from tail.

**Fix:** `_recordLayoutBeforeDelete` → `_preserveViewportAfterDelete` keeps band
bottom/gap stable; `_skipRenormalizeDuringDeleteRecovery` blocks renormalize for
one pass; `pinNewest` / `pinOldest` guards during recovery. See invariant §19 in
[02-invariants.md](02-invariants.md) and step 6c in
[04-layout-pipeline.md](04-layout-pipeline.md).

**Remaining:** Non-anchor visible tall delete path not yet implemented.

## Short-content bounce jitter (fixed 2026-07-05)

**Was:** When all messages fit in the viewport, both `pinOldest` and `pinNewest`
fired on every fling/clamp tick with equal-and-opposite deltas; bounceback
treated dual-boundary geometry as overscroll, causing visible jitter. Scrollbar
drew a track with no thumb.

**Fix:** `_contentFitsInViewport` disables overscroll, drag, fling, bounceback,
dual pin, and scrollbar paint; single-pin stack at bottom (chat) or top (list).
See invariant §20 and [06-boundaries.md](./06-boundaries.md).

## Blank-viewport snap is not implemented

A comment near the absent-skip helpers describes snapping the anchor when
absent-marking collapses shimmer rows and leaves a blank viewport. **No method
body follows** — aspirational / removed. Do not assume this protection exists.

## Close-path animate vs clamp

Current code runs `_clampBoundaries` during close-path `animateTo`. A pin can
`_cancelAnimate` mid-flight (no highlight). Suspending clamp during close animate
only is planned — not implemented. See
[Animation Integration](./11-animation-integration.md).

## Tail pin after animate future (fixed 2026-07-05)

**Was:** close-path `animateTo` to the known newest used `_alignedTopForMessage`
(band top for tall messages); `pinNewest` on the next layout caused a visible
post-animate snap.

**Fix:** close-path endpoint for known-newest targets is tail-pin top
(`bottomEdge − height`) via `_closePathEndOffsetFor`; layout `pinNewest` still
runs as authority but should be a no-op when already pinned.

## No force-jump when anchor ≠ newest after tail animate

Force `jumpTo(newest)` when settle leaves anchor ≠ newest is **not**
present. Only `_markPinTailOnJumpIfNeeded` + alignment snap.

## No extent coordinator / removal ghosts

`chat_extent_coordinator.dart`, `_effectiveTailBottom`, and selective
`pinNewest` suppression for collapsing removal ghosts are **not** in this
tree. Do not assume removal-overlay geometry exists.

## `pinOldest` ignores `topPad`

Oldest is pinned to `y = 0`, not `topPad`. Top chrome is reserved visually but
does not shift the oldest pin edge.

## Overlay clears `isAtTail` computation but not the snapshot

`_computeIsAtTail` is false in overlay mode, but `_wasAtTailLastLayout` is
**not** updated during overlay (intentional) so follow-tail survives
overlay → normal. Callers reading `isAtTail` during overlay see `false`.

## Skip-rebuild identity and layout context (fixed 2026-07-05)

**Was:** neighbor-dependent chrome (avatar, sender label, bubble tail) computed
inside `messageBuilder` via `getPreviousPresentMessage` was not part of the
skip-rebuild cache. After delete, survivors kept stale chrome when
`identical(message)` and status were unchanged.

**Fix:** `ChatSenderRunLayout.resolve` runs in the render object; `MessageRunLayout`
is cached per id alongside message identity. `ChatMessageBuilder` receives a
5th `runLayout` parameter. Demo chrome uses last-in-run (Telegram-style).
