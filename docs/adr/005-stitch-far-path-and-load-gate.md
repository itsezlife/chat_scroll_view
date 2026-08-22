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

## Layout freeze vs measure

| Phase | `farAnimateJumped` | `stitchMeasured` | Layout |
| ----- | ------------------ | ---------------- | ------ |
| Load-gate wait | false | false | Normal fan-out; presence pins only |
| Post-jump measure | true | false | Full layout — **allow** `pinNewest` / align so travel measures from the correct end |
| Measured flight | true | true | Freeze fan-out / refan / nav-align snap; paint owns dual-translate |
| Settle | false | false | Normal; commit bake then clear capture |

Freeze **after** measure only. Freezing the measure layout pins tall newest
from the row top and produces a hitch once travel is measured from the bottom.

## Dual-translate paint contract

- Outgoing rows keep **capture-time layout offsets**; paint adds stitch dy per
  progress.
- Fan-out **skips** outgoing capture ids while jumped so layout does not
  double-apply travel that paint already owns.
- After any full reposition during jumped stitch, refreeze outgoing tops.

## Settle: commit-at-progress

Before clearing stitch capture (complete or user cancel):

1. Capture `StitchCancelSnapshot` (target, progress, scrollLength, direction)
2. Bake paint dy into layout offsets (`stitch.commit`)
3. Clear capture, renormalize, refan

Without the bake, outgoing rows snap back to frozen layout tops for one frame
when paint stops applying stitch dy.

## Close-path inset

Outside stitch, bottom-padding follow uses `bottomPadCompensate` plus
`shiftClosePathByInset` during close-path animate so the travel clock keeps
running while the keyboard moves. `rebaseClosePathEnd` (clock restart) remains
for height / non-inset geometry only — after an inset shift it should no-op.

## Diagnostics

Filter tags: `ChatScrollAnimate`, `ChatScrollFetchAnchor`.

Key events: `stitch.begin`, `stitch.measure`, `stitch.commit`, `close.rebase`,
`layout.bottomPadCompensate`, `layout.pinNewest`.
