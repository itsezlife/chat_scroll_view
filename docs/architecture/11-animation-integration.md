---
type: Architecture Reference
title: Animation Integration
description: Close/far animateTo paths, stitch far path, load-gate, writer ownership.
tags: [animation, animateTo, dual-writer, stitch, load-gate]
timestamp: 2026-08-21T00:00:00Z
resource: lib/src/chat_scroll/chat_animator.dart
---

# Animation Integration

Animations are a **secondary layer**. They write the same
`(anchorMessageId, anchorPixelOffset)` origin as drag and layout — they must
not invent a parallel coordinate system. This document is the antidote to
“compensate / fix / ultra fix” patches.

Domain terms: [CONTEXT.md](../../CONTEXT.md) (stitch, navigation load-gate,
destination window fetch, stitch presence pin, full-strip travel).
Core model: [Coordinate Model](./01-coordinate-model.md),
[Invariants](./02-invariants.md).
Decision record: [ADR 005](../adr/005-stitch-far-path-and-load-gate.md).

**Authority when sources disagree:** Telegram
`RecyclerAnimationScrollHelper` / `ChatActivity.scrollToMessageId` behavior →
glossary → this document → older animateTo prose or changelog notes.

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
use [AnimateToLoadPolicy.immediate]; reserve `preferBuilt` for self-insert /
follow-tail (close-path chance when the newest is already warming).

## Navigation load-gate

Far-path **stitch must not run** until the target is a real destination row
(loaded, measurable — not an unresolved shimmer stand-in).

Telegram `ChatActivity.scrollToMessageId`: if the message is not in the
adapter → load around that id (`LOAD_AROUND_MESSAGE` / progress) → scroll
**after** load. The helper never dual-translates an unloaded placeholder
band across a gap.

| Rule | Contract |
|------|----------|
| Readiness | Target chunk (plus the minimum neighbor window needed to paint the band) is loaded |
| Fetch extent | **Destination window** owned by host/data-source — around-target, not contiguous fill of every chunk between current origin and target |
| Forbidden | Timeout → force stitch on shimmers; min…max chunk storms as a readiness requirement |
| Presence | **Stitch presence pin** on target + outgoing strip for the wait and the flight; explicit host delete cancels; silent Absent / delete-collapse / soft retarget of the target is forbidden |

## Load policy

| Policy | Unready target | Ready + built | Ready + not built |
|--------|----------------|---------------|-------------------|
| `immediate` (default) | Enter load-gate → then close or stitch | Close | Stitch |
| `preferBuilt` | Same readiness rule, plus a short wait for a row already entering the build range | Close | Stitch |

Neither policy may fall back to shimmer-stitch. `preferBuilt` only improves
the chance that self-insert / follow-tail takes the **close path** when the
newest is already building.

## Path selection (Telegram `found` → close)

Only after the target is ready (or already built). Mirrors Telegram
`ChatActivity.scrollToMessageId`: **found among current children** →
`smoothScrollBy` (close); otherwise stitch helper / load.

| Condition | Path |
|-----------|------|
| Target **built** (`offsetToTarget != null`) | **Close path** — continuous scroll, regardless of pixel distance or paint-band hit |
| Target ready but **not built** | **Far path** — stitch (`reason=notBuilt`) |
| `duration ≤ 0` | Instant `jumpTo`, no highlight |

Do **not** invent pixel distance across unloaded gaps. After the load-gate,
path selection uses built presence only (not a pixel-distance cutoff). Tall
anchors that alone fill past the build zone must still keep one present edge
neighbor built so a reverse hop can remain `found`.

## Close path

1. `reassignAnchor(targetId, offsetToTarget)` — anchor **id** becomes the
   target immediately; offset stays at current on-screen Y.
2. `animateStartOffset = offsetToTarget`,
   `animateEndOffset = _closePathEndOffsetFor(targetId, height, alignment)`
   — band alignment for ordinary targets; **tail-pin top** (`bottomEdge − height`)
   when the target is the known newest (`reachedNewest` + `newestKnownId`).
3. **Timing** — same Telegram formula as stitch:
   `duration = clamp(((travel / vh) + 1) * 200, 300, 1300)` with
   `Curves.easeOutQuint`. Caller `animateTo` duration/curve are not used for
   path motion (`duration ≤ 0` still means instant jump).
4. Each tick: optional `rebaseClosePathEnd` (tail target or `alignment ≠ 0`),
   curve-interpolate; return `delta = target − anchorPixelOffset`.
5. Render applies via `applyScrollDelta` → `_repositionFromAnchor`.
6. At `t ≥ 1`: `_completeAnimate` → `reassignAnchor(targetId, end)`,
   **restart highlight hold** (if select), set `_pendingSettleTargetId`,
   complete completer.

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
`alignment ≠ 0`) resets start/end from the live child height / insets and,
when `elapsed` is supplied, restarts the travel clock from that elapsed so
the interpolator tracks the new end without inventing a parallel endpoint
writer. Bottom-pad compensate during close path stays layout-owned (same as
idle); do not shift animate endpoints inside the animator.

## Far path (stitch)

Telegram `RecyclerAnimationScrollHelper` — a **continuity illusion**, not
scrolling through the gap and not a viewport opacity fade:

1. **Capture outgoing** — message boxes intersecting the paint band (id,
   frozen top Y / height, scroll direction). Apply **stitch presence pin**.
2. **Teleport** — `jumpTo(targetId, alignment:)` so fan-out builds the
   **incoming** band (only after load-gate).
3. **Measure** — post-jump layout: **full-strip travel** from outgoing strip
   + incoming extents (including off-screen parts of tall rows). Duration
   scales with travel (~300–1300ms, `Curves.easeOutQuint`). Clock starts at
   measure time. Align scrollLength with Telegram’s strip/incoming formula;
   do not viewport-cap travel for product reasons.
4. **Paint invariant:** from the first post-jump frame, incoming rows use
   full entry offset (`scrollLength * (1−t)` at `t=0`), even before measure
   completes (provisional = viewport height). Never show destination rows at
   rest between teleport and dual-translate.
5. **Animate** one factor `t ∈ [0,1]`:
   - Outgoing: paint Y `±scrollLength * t` (exit)
   - Incoming: paint Y from `∓scrollLength * (1−t)` to layout Y
6. **Day chrome:** inline date separators that are built rows ride the same
   translate sets (Telegram `ChatActionCell`). Floating date follows
   destination-visible content during the flight (Telegram
   `scrollListener` → `invalidateMessagesVisiblePart`), not a fake mid-gap
   timeline and not “update only after settle.”
7. **End** — bake dual-translate paint dy into layout offsets
   (`StitchCancelSnapshot` / `stitch.commit`), then clear pin, GC outgoing,
   `stitchProgress = 0`, complete completer, **restart highlight hold** /
   pinNewest settle as usual. Cancel uses the same bake at interrupted
   progress so outgoing rows do not snap back one frame.

Paint drives **per-child translation**, not `OpacityLayer`.

**Freeze after measure:** layout freeze (skip refan / nav-align snap) applies
only once `stitchMeasured`. The post-jump measure layout must still run
`pinNewest` / alignment so travel is measured from the correct end (tall
newest). While jumped, fan-out skips outgoing capture ids so paint dy is not
double-applied.

Post-jump contracts are the same as `jumpTo` (tail pin, alignment). Layout
owns pin/align.

## Writer ownership table

| Phase | Writes `anchorMessageId` | Writes `anchorPixelOffset` | Must not |
|-------|--------------------------|----------------------------|----------|
| Load-gate wait | No (until jump/close starts) | No | Stitch / shimmer dual-translate |
| Close start | Yes (`reassignAnchor`) | Yes (current Y) | — |
| Close tick | No | Yes (via delta) | Layout snap / renormalize |
| Close settle (`_completeAnimate`) | Yes | Yes (aligned end) | Second pin writer in animator |
| Stitch start | Yes (`jumpTo`) | Yes (`0` + layout align/pin) | Animator-owned pin; unload target |
| Stitch tick | No | No (paint translation only) | Opacity fade; gap-fill fetch as readiness |
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
**next** `performLayout` — known post-future snap risk for tall newest.

## Highlight

Telegram navigate-select (`highlightMessageId` / `setHighlighted`):

1. **Arm at animate start** when `highlight: true` (solid, factor 1). Deferred
   via `pendingHighlightTargetId` until message loaded **and** `RenderBox`
   exists. Dropped if status is absent/error.
2. **Stitch teleport must not clear** — `_onJump` skips hard-clear when
   `farAnimateActive && animateTargetId == jump target`. After jump,
   animator re-asserts `_requestHighlight` (pending until incoming row
   builds). Paint Y includes stitch dual-translate so the tint rides the
   incoming row (Telegram paints highlight on the cell itself).
3. **Hold clock paused** during the flight (solid remains).
4. **Settle** (`_completeAnimate`) restarts solid hold for
   `highlightDuration` (default 1000ms — Telegram `startMessageUnselect`).
5. **Fade** ~300ms (`kHighlightFadeDuration`) after hold — Telegram
   `setHighlighted(false)` / `getHighlightAlpha`.
6. **Already-there** arms solid and starts hold immediately.
7. **Cancel / user drag** → fade (skip remaining hold). **Host jumpTo /
   overlay / dispose / controller swap** → hard clear.
8. Paint: full-width **underlay** (`key_chat_selectedBackground` /
   `0x280A90F0`) behind the target row; messages paint on top. Bubble
   selected-fill is host-owned.

`highlightDuration: Duration.zero` disables the feature.

## Cancel rules

Drag and `scrollBy` cancel animate and **fade** highlight (Telegram drag
clears selection). Clamp-hit (current), presence-pin removal, and span
auto-scroll cancel animate with fade. Overlay, controller dispose / swap,
and `jumpTo` hard-clear highlight. Explicit host deletion of the animate
target or outgoing strip must cancel animate without leaving stitch pins or
stale completers.

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
6. Far path keeps continuity via stitch translation, not fade.
7. Honor load-gate + destination window + presence pin before any stitch.
8. Day chrome follows destination-visible rows during stitch (Telegram), not
   a synthetic mid-gap date timeline.
