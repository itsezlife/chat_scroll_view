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

| API                              | Anchor effect                                      | Notifications                                                                   |
| -------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------- |
| `jumpTo(id, {alignment, highlight, tailFitFraction, pixelOffset})` | id = target, offset = `0`; with `tailFitFraction`, layout may move it to the newest (see [Tail or target](#tail-or-target)); `pixelOffset` is additive after the alignment seat | Jump listeners + `ChatProgrammaticJump`; `highlight: true` then requests wash; tail-or-target listeners get the outcome in layout |
| `jumpToCenterBand(id, offset)`   | id = target; layout places ray at msg top + offset | Jump listeners + `ChatProgrammaticJump`; hard-clears highlight |
| `scrollBy(px)`                   | offset += px                                       | ScrollBy listeners + `ChatProgrammaticScroll`; no-op if `px == 0` or non-finite |
| `animateTo`                      | Animator drives; falls back to `jumpTo` (same `highlight` flag) if unbound | `ChatAnimateStart` / `ChatAnimateEnd` (with `path`); unbound: only `ChatProgrammaticJump` |
| `highlight(id)`                  | none (attention slot only)                         | None — animator paints/holds/fades when bound                                   |
| `applyScrollDelta` (`@internal`) | offset += delta                                    | None (tick / clamp / pad)                                                       |
| `reassignAnchor` (`@internal`)   | silent id + offset                                 | None (renormalize / align / animator)                                           |

**Sign convention:** positive `scrollBy` / drag reveals **older** (content moves
down) — opposite of Flutter `ScrollPosition.pixels`.

**Absent targets:** navigation completes without error; absent slots have zero
height — do not assume a visible row at that id. Check `statusOf` before
navigating if the user must see a specific message (ADR 002).

Consumers must **not** call `reassignAnchor`, `applyScrollDelta`,
`visibleRange=`, `centerBand=`, `isAtTail=`, `animator=`, or `notifyScrollEvent`.

## Alignment lifecycle

The controller keeps one `navigationPlacement` slot, typed as the sealed
`NavigationPlacement` (`lib/src/chat_scroll/navigation_placement.dart`,
engine-internal):

- `AlignmentPlacement(messageId, alignment, {tailFitFraction, pixelOffset})`:
  armed by `jumpTo` / `animateTo`. `alignment` runs from 0 (band top) to 1
  (band bottom). A non-null `tailFitFraction` (tail-or-target `jumpTo` only)
  marks a decision still to be made. `pixelOffset` is additive after the
  alignment seat (default `0`); hosts that need a fixed inset below the band
  top pass it because alignment alone cannot express a constant.
- `CenterBandPlacement(messageId, offsetFromMessageTop)`: armed by
  `jumpToCenterBand` (see [Center Band](#center-band)).

Each value carries `isHeld`, its phase. Arming either kind replaces the slot,
so at most one placement exists. Values are immutable: `hold()` and
`retarget(id)` (used after a jump-target clamp, via
`syncNavigationPlacementTarget`) return new values.

### Pending → held → released

| State | Entered by | Layout behavior |
|-------|-----------|-----------------|
| **Pending** | `jumpTo` / `animateTo` / `jumpToCenterBand` | Snap the target on every layout until it lands on a **loaded** row |
| **Held** | The snap lands on a loaded row (`holdNavigationPlacement`) | Snap again only on a trigger; otherwise silent |
| **Released** | See release table | Slot is `null`; the anchor stays where it is |

**Held triggers** (`reapplyHold` in `performLayout`):

- The top inset differs from the previous normal-mode layout
  (`_lastLaidOutTopPad`).
- A row chrome change touches the target while it is the anchor
  (`_isNavigationTargetChromeChange`). The target is the old or the new
  unread boundary row on the pass that moves the boundary, or its separator
  transition frame moved since the previous pass. The placement is
  therefore re-applied on every frame of the target's own transition.

On a pass where either trigger re-places an anchored held target, the row
chrome hold (step 6d) stands down, including for a boundary change on
another row in the same pass. Re-applying the placement is the only origin
writer on that pass. Later frames of a transition on another row run the
row chrome hold again, as for any row chrome change away from the target.

A held placement re-snaps only on these triggers, not every layout. If it
did, it would undo bottom-inset compensation, the boundary clamp, and height
changes elsewhere.

**Release:**

| Event | Where |
|-------|-------|
| Drag start (fling follows a drag), wheel | `_onDragStart`, `handleEvent` → `releaseNavigationPlacement` |
| Scrollbar drag start **and** end | `handleEvent`. The thumb's own `jumpTo` calls arm placements, and the end releases them |
| `scrollBy` | `ChatScrollController.scrollBy` |
| Next `jumpTo` / `animateTo` / `jumpToCenterBand` | New placement replaces the old one |
| Held target no longer the anchor (absent-anchor reassignment, renormalize) | `_applyNavigationPlacement` |
| Tail pin takes the geometry (`repinBottom`, e.g. follow-tail) | `performLayout` after tail-pin flags |
| Tail-or-target decides **tail** | `_resolveTailOrTarget` |
| Known-newest alignment target | `_applyNavigationPlacement` releases without snap |
| Center Band placement on an empty scroll band | `_applyNavigationPlacement` |

A **pending** placement survives an anchor mismatch. Far-path animate arms
it while the anchor is still on the outgoing strip.

Bottom-inset compensation is unchanged while held. A keyboard opening moves
the held target with the rest of the content, and a later top-inset change
re-seats it.

### Tail or target

`jumpTo(id, tailFitFraction: f)` arms an alignment placement that carries
`f`. `_resolveTailOrTarget` runs right before `_applyNavigationPlacement`,
on the first pass whose target is a loaded, laid-out row: a pre-mount jump
decides on the first layout, and a jump onto a loading row decides on the
layout that loads it. Frames before that paint the target region, never the
tail.

- **Measure:** target body top (below its row chrome — inline date, unread
  separator) to the newest message's bottom. When the newest is loaded but
  unbuilt, rows re-fan with the target body on the viewport top; fan-out
  then builds at least a viewport height below it, so an unbuilt newest
  means the span exceeds any fraction ≤ 1.
- **Tail:** `reachedNewest`, newest loaded, span ≤ `f × viewport height`.
  The placement is released, the anchor moves to the newest, and the tail
  pin is marked (`_markPinTailOnJumpIfNeeded`); the clamp pins the newest
  bottom this pass.
- **Target:** anything else. `markTailFitDecided` drops `f`, keeping target,
  alignment, and phase; the placement then runs the plain `jumpTo`
  lifecycle, boundary clamp included.

The outcome goes to `addTailOrTargetListener` callbacks inside
`invokeLayoutCallback`, before the pass paints. A listener may change the
`unreadBoundary` value; the pass detects the change, consumes
`_rowChromeChanged`, records `_laidOutUnreadBoundary`, cancels both rows'
separator transitions, and re-fans before placement and the pin, so the new
row chrome is settled in this frame's geometry.
Listeners must not `setState` or navigate (the element has no own build
scope). Because the decision rides the placement, every release before the
decision (drag, `scrollBy`, next navigation) cancels it and nothing is
reported; a decided jump reports once.

### `_applyNavigationPlacement(reapplyHold:)`

Runs after `_resolveTailOrTarget`: a tail outcome has already released the
placement; a target outcome is seated here as a plain jump.

1. Stitch-measured freeze and close-path animate → return (dual-writer guard).
2. Anchor ≠ target → release when held; keep when pending.
3. Alignment target is known newest → **release without snap** (tail pin owns
   geometry). A known-newest Center Band target goes on and is held. An
   undecided tail-or-target jump stays armed, unseated, until
   `_resolveTailOrTarget` decides it on the layout that loads the row.
4. Held and no trigger → return.
5. Needs built child with size. Seat by kind: alignment →
   `_alignedTopForMessage` + `pixelOffset`; Center Band → band ray minus the
   clamped offset (an empty band releases). `reassignAnchor(targetId,
   desiredTop)` + `_repositionFromAnchor` unless within `0.5px`.
6. Target loaded → mark held.

`_alignedTopForMessage` uses the scroll band (`topPad` .. `height - bottomPad`).
`pixelOffset` is added after that seat. Tall **non-newest** messages
(`height ≥ band`) always land at band top before the offset is applied.
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
advanced → `repinBottom` so the new message is not left below the bottom edge
— **except** while an off-tail self-insert `animateTo` is in flight
(`_deferTailAdvancedRepin`).

Self-insert (`isSelfMessage` + insert mutation):

- **Already at tail** (`_wasAtTailLastLayout` / `isAtTail`) → no `animateTo`;
  layout `tailAdvanced` pin only.
- **Off-tail** → `animateTo(newest, preferBuilt, highlight: false)`. Pinning
  is deferred to animate settle (`_onAnimateSettled`) / follow completion.

Same-id newest height growth while at tail still uses instant `repinBottom`
(edit expand).

`isAtTail` listenable uses `_DeferredValueNotifier` — pushes from
`performLayout` defer `notifyListeners` to post-frame so listeners may
`setState`. Initial value is `false` until first layout.

## Visible range

`ChatVisibleRange` includes `firstId` / `lastId`, paint-band metrics,
`firstRow` / `lastRow`, optional `anchorNextRow`. Chunk-error tiles can widen
id coverage. Same deferred notifier contract as `isAtTail`.

## Center Band

`ChatCenterBand` is the Message under the fixed 50% paint-band ray plus
`offsetFromMessageTop`. Live via deferred `centerBand` on
`ChatScrollController` (same listener safety as `visibleRange`). Pushed after
layout and Tier-1 — including silent Anchor origin renormalize frames that do
not emit `ChatViewportScrolled`. Geometric ray hit only; not an id-midpoint
heuristic. `null` before first layout or when no Message intersects the ray.

`jumpToCenterBand(messageId, offsetFromMessageTop)` places that ray in one
navigation (not host `jumpTo` + `scrollBy`). Layout applies the pending offset
after the target row is built — same pending → held → released lifecycle as
alignment (see [Alignment lifecycle](#alignment-lifecycle)). Jump-to-newest
tail pin is suppressed while Center Band apply is **pending** (not held) so
mid-bubble restore on the conversation newest is not fought. See
[ADR 009](../adr/009-center-band.md).

## Scroll events

Sealed `ChatScrollEvent` stream: drag start/end, fling start/end, programmatic
jump/scroll, animate start/end. Physics does not emit events — render does.

## Tail-pin flags

See [Boundaries](./06-boundaries.md) for `_pinTailOnJump`,
`_pendingTailPinUntilSettled`, `_userPreemptedTailSettle`. Drag start cancels
pending settle and sets user-preempted so passive pin does not yank back.

`repinBottom` when jump-to-tail, or when `_wasAtTailLastLayout && reachedNewest`
and either `newestKnownId` advanced **or** the newest row's laid-out height
grew (same-id edit / resize). Do **not** force `repinBottom` on every
at-tail→next layout — that fights manual scroll-away.

Manual scroll that dies within `_tailEdgeSlop` of `bottomEdge` still counts as
at-tail for follow (no pin-snap).

## Self-insert follow

When [ChatScrollView.isSelfMessage] is set, an [InsertMutation] /
[InsertBatchMutation] that includes a matching message forces
`animateTo(newestKnownId)` (smooth scroll — not `jumpTo`) even if the
viewport was scrolled into history. Incoming-only inserts still follow only
when `_wasAtTailLastLayout`.

`insertMessage` notifies mutations **before** storage write — the render
object defers the self check to a microtask so `getMessage` resolves.

Unread chrome (example FAB) should share the same predicate and advance
`lastSeenNewestId` when the newest id is self so own sends never inflate the
badge. A host that sets an **unread boundary** typically skips self messages
by the same predicate. Opening with `jumpTo(boundary, alignment: 0)` puts the
boundary row — its inline date, unread separator, then body — at the band
top. The alignment hold keeps it there when top chrome grows or the
separator is added to that row after the open. The hold lasts until the
reader first scrolls. With `tailFitFraction`, a short unread span opens at
the tail instead, and a host that clears its boundary on the tail outcome
gets no separator in any frame.

### `pinNewest` during delete recovery

When `_deleteCollapseRecoveryActive`, `pinNewest` inside `_clampBoundaries`
applies extra guards:

- Block when the user was **not** at tail before delete (`!wasAtTailBefore`).
- Block when the user had **preempted tail** and post-delete geometry satisfies
  `isAtTail` — prevents an unintended snap to newest after mid-history delete.

These guards use snapshot fields from `_recordLayoutBeforeDelete`. Normal tail
follow (user genuinely at tail, deletes newest) is unchanged. Emits
`pinNewestSuppressed` on `layout.deleteCollapse` when blocked.
