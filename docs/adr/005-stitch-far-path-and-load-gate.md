# ADR 005: Stitch far path with navigation load-gate

Far `animateTo` is a continuity **illusion** (Telegram
`RecyclerAnimationScrollHelper`: capture → teleport → dual-translate), not
scrolling through the gap and not a viewport crossfade. Stitch runs only after
a **navigation load-gate** (target ready via a host **destination window**
fetch — never shimmer-stitch or contiguous gap-fill for readiness). Target and
outgoing strip stay **presence-pinned** for the wait and flight; tall rows use
**full-strip travel**. Day chrome follows destination-visible built rows during
the flight. Immediate vs prefer-built differ only in close-path chance for a
warming row — neither may timeout into force-stitch.

**Status**: Accepted  
**Date**: 2026-08-21

## Layout phases during stitch

| Phase | `farAnimateJumped` | `stitchMeasured` | Layout path |
| ----- | ------------------ | ---------------- | ----------- |
| Load-gate wait | false | false | Normal fan-out; presence pins only |
| Post-jump measure | true | false | Normal fan-out until target built; then measure travel |
| Measured flight | true | true | **Stitch slim** — no refan/GC |
| Settle | false | false | Normal; deferred inset + tail pin flush |

## Dual-translate paint contract

- Outgoing rows keep **capture-time layout offsets**; paint adds
  [`_stitchPaintDy`](../../lib/src/chat_widgets/render_chat_scroll_view.dart)
  per progress.
- [`_repositionFromAnchor`](../../lib/src/chat_widgets/render_chat_scroll_view.dart)
  **skips** outgoing ids while jumped (`_skipStitchOutgoingReposition`).
  Refan or reposition without that skip **double-applies** travel → blank
  viewport mid-flight.
- After any full reposition during stitch, call `_refreezeStitchOutgoing`.

## Stitch slim layout

When `farAnimateActive && stitchMeasured`, `performLayout` returns early after:

1. Re-laying outgoing pins at frozen tops
2. Refreezing outgoing offsets
3. Floating header + semantics publish

No renormalize, refan, GC, or boundary clamp in this path. Ticker-driven
coverage checks use paint-only updates until stitch ends.

## Stitch inset compensation

**Domain invariant:** while `farAnimateActive && farAnimateJumped`, a bottom
inset delta must never leave the scroll band with zero intersection from built
message rows (outgoing and/or incoming). Paint-only dual-translate frames
count — blank is forbidden on any displayed frame. Applies equally to tail
navigation (`alignment = 0`) and mid-band navigation (`alignment > 0`,
`towardNewer = false` with multiple outgoing rows).

### Post-jump, pre-measure (`farAnimateJumped && !stitchMeasured`)

Route bottom inset compensation through the **uniform layout shift** used during
measured flight — anchor delta plus the same delta on every non-outgoing layout
offset and on `_stitchFrozenTops`, then refreeze outgoing. Do **not** use
anchor-only `applyScrollDelta`; incoming rows are paint-offset off-screen and
anchor-only compensation breaks outgoing frozen geometry → blank viewport.

Inset-driven layouts in this window take a slim path that refreezes outgoing
pins without refan or tail-pin so frozen geometry survives until
`stitch.measure`. Logged as `layout.stitchPostJumpInset` /
`layout.bottomPadCompensate.stitchFlight`.

The **initial post-jump measure layout** (no inset change) is **not** frozen:
tail `pinNewest` must run there so scroll-to-bottom stitch starts from the
message bottom (especially tall rows). Mid-band alignment layout on that same
measure pass is allowed to refan once.

### Measured flight (`stitchMeasured`)

**Bottom inset (Telegram `additionalY`):** keyboard/composer inset changes
during measured flight do **not** run uniform layout shift or inset travel
rebase. Paint applies `additionalY = bottomPadAtMeasure − bottomPad` on
**both** outgoing and incoming rows (`layout.bottomPadCompensate.stitchPaint`)
so the dual-translate strips stay aligned when the scroll band shrinks or
grows. Outgoing frozen layout tops stay fixed; continuity is paint-owned like
Telegram `RecyclerAnimationScrollHelper`.

**Geometry rebase:** when outgoing/incoming extents change (jump fetch completes,
row heights update), recompute full-strip `stitchScrollLength` via
[`rebaseStitchTravelGeometry`](../../lib/src/chat_scroll/chat_animator.dart) —
scale `stitchProgress` so effective travel (`progress × oldLen`) stays
monotonic. Logged as `stitch.rebase.geom`.

**Inset-only rebase (contract / tests):**
[`rebaseStitchTravelInset`](../../lib/src/chat_scroll/chat_animator.dart)
updates `stitchScrollLength` **without** changing `stitchProgress`. Logged as
`stitch.rebase.inset`. Prefer paint `additionalY` for live inset motion during
measured flight.

Do **not** call full `_repositionFromAnchor` during measured flight — the
id-walk skips outgoing without reserving strip height and collapses
dual-translate (blank viewport).

**Jump fetch during measured flight:** stitch slim runs even when
`jumpFetchPending` — no full refan/tail-pin between outgoing and incoming
strips. Geometry rebase runs at the end of each slim layout before paint.

### Deferred stitch measure

`stitch.measure` must not run while the animate target is still a fetch stub
(shimmer) or not among built children. Post-jump layouts keep fanning out until
[`_stitchTargetReadyForMeasure`](../../lib/src/chat_widgets/render_chat_scroll_view.dart)
passes; inset-driven layouts in this window stay on the post-jump slim path and
do not promote to measured flight early. Diagnostics:
`stitch.awaitMeasure.deferred` (reason: `targetNotBuilt` / `targetShimmer`) vs
`stitch.measure` once geometry is ready.

### Outside stitch

Idle and close-path animate inset compensation are unchanged — anchor-only
bottom-padding follow, not uniform shift or stitch travel rebase.

## Stitch layout freeze (inset + tail pin)

See **Stitch inset compensation** for uniform shift and paint-inset rules.
While **`stitchMeasured`** dual-translate is running, additionally:

- **Navigation alignment** is suppressed — [`_applyNavigationAlignment`](../../lib/src/chat_widgets/render_chat_scroll_view.dart)
  returns false so mid-band targets are not repositioned mid-flight.
- **Refan / GC / renormalize** are skipped via [`_shouldFreezeStitchLayout`](../../lib/src/chat_widgets/render_chat_scroll_view.dart).
- **Ticker** skips `_repositionFromAnchor` while post-jump; paint owns motion.
- **`pendingTailPin` / `pinNewest` / `_clampBoundaries`** remain suppressed.

Mid-history stitch (`alignment > 0`, toward older) uses the same freeze contract
as tail stitch — multiple outgoing rows stay pinned; incoming rows paint from
off-screen offsets.

### Close-path inset rebase

During close-path animate, bottom inset changes call
[`rebaseClosePathEnd`](../../lib/src/chat_scroll/chat_animator.dart) so the
live end offset tracks band geometry without a visible snap.

## Settle: commit-at-progress

Dual-translate paint offsets must be baked into layout offsets before stitch
capture is cleared — on **normal completion** and on **user cancel**.

1. Capture `StitchCancelSnapshot` (target, progress, scrollLength, direction)
2. Bake paint dy into layout offsets (`stitch.commit`)
3. Clear stitch capture, renormalize, refan

On cancel, progress is wherever the user interrupted. On complete, progress is
`1.0` (outgoing baked off-screen; incoming dy is zero). Without this bake,
outgoing rows snap back to frozen layout tops for one frame when paint stops
applying stitch dy — visible as blank viewport or a giant stale strip.

## Day chrome during flight

- `_logStitchDayChrome(phase)` emits deduped `stitch.chrome.*` diagnostics.
- Day scan during stitch: progress &lt; 0.5 → outgoing rows only; ≥ 0.5 →
  incoming rows (both stitch directions).
- Header bucket change during measured flight: slim relayout; otherwise
  `markNeedsPaint` only.

## Diagnostics

Filter tags: `ChatScrollAnimate`, `ChatScrollFetchAnchor`.

Key events: `stitch.begin`, `stitch.measure`, `stitch.measureGeom`,
`stitch.awaitMeasure`, `stitch.awaitMeasure.deferred`, `stitch.awaitMeasure.pending`,
`layout.stitchSlim`, `layout.stitchPostJumpInset`,
`layout.bottomPadCompensate.stitchFlight`, `layout.bottomPadCompensate.stitchPaint`,
`stitch.rebase.inset`, `stitch.rebase.geom`, `stitch.commit`,
`stitch.chrome.*`.
