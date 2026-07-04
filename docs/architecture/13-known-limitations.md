---
type: Limitation Catalog
title: Known Limitations
description: Documented debt in the current implementation — facts, not fixes.
tags: [limitations, debt]
timestamp: 2026-07-04T00:00:00Z
---

# Known Limitations

Facts of the **current** implementation. Do not paper over these with unrelated
hacks; fix at the root when restarting a feature (especially animations).

## `_startsDay` does not walk past absent predecessors

**Symptom:** Delete a group’s first message (the row with the inline day
separator). On the next layout, the surviving next message does **not** gain
`startsDay` / an inline separator.

**Root cause:** `_startsDay` only inspects `id - 1`:

```dart
final prevBucket = _bucketOf(id - 1);
if (prevBucket == null) return false;
```

If `id - 1` is confirmed absent, `getMessage` is null → `_bucketOf` is null →
`startsDay` stays false. Skip-rebuild is **not** the primary bug: even a full
rebuild keeps `startsNewDay: false`.

**Intentional case:** predecessor not yet loaded (`dirty` / missing chunk) —
separator is deferred until data arrives.

**Wrong case:** predecessor is **confirmed absent** — should walk to the
previous present message (or treat as group start when no present predecessor
in-range), same idea as `_nextNonAbsentIdUp`.

**Fix direction (not implemented):** walk previous non-absent ids until a
loaded message or conversation oldest.

## No automatic anchor replacement on delete

If the current `anchorMessageId` becomes absent/deleted, core layout does
**not** automatically reassign the anchor to a surviving neighbor. Fan-out may
build around a zero-height absent slot; behavior depends on clamp/renormalize
finding nearby built children.

Animation branches may have attempted replacement; **core does not**.

## Neighbor lookup via `getMessage` alone is wrong

`getMessage(id)` returns null for both absent and unloaded slots. Any
“previous / next message” logic must use `statusOf` and walk past
`isAbsent` (fan-out helpers already do this). Using `getMessage(id ± 1)` as
the sole neighbor probe is incorrect.

## Blank-viewport snap is not implemented

A comment near the absent-skip helpers describes snapping the anchor when
absent-marking collapses shimmer rows and leaves a blank viewport. **No method
body follows** — aspirational / removed. Do not assume this protection exists.

## Close-path animate vs clamp

Current code runs `_clampBoundaries` during close-path `animateTo`. A pin can
`_cancelAnimate` mid-flight (no highlight). Spec 027 intends suspend clamp
during close animate only — not implemented. See
[Animation Integration](./11-animation-integration.md).

## Tail pin after animate future

`animateCompleter` completes in `_completeAnimate` **before** layout
`pinNewest`. Tall newest messages end at band top via
`_alignedTopForMessage`; true bottom pin happens on a **later** layout after
`_onAnimateSettled` sets `_pinTailOnJump`. Callers awaiting `animateTo` may
observe a post-future snap.

## No force-jump when anchor ≠ newest after tail animate

Spec Defect C (force `jumpTo(newest)` if settle leaves anchor ≠ newest) is
**not** present. Only `_markPinTailOnJumpIfNeeded` + alignment snap.

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

## Skip-rebuild identity

In-place mutation of an `IChatMessage` instance without replacing it will not
rebuild the child (`identical` check). Integrators must upsert a new instance
(or change status / `startsDay`) to force rebuild.
