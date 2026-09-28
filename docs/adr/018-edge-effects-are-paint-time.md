# ADR 018: Edge effects are paint-time on every platform

**Status**: Accepted  
**Date**: 2026-09-29  
**Relates to**: [ADR 002](002-position-model.md)

User motion that presses past a reached conversation edge produces an
**edge effect**: a paint-only response of the message layer. The anchor
origin never passes a **boundary pin** — layout stays clamped on every
drag and fling frame, on every platform. **Stretch** scales the message
layer from the pressed edge; **Rubber-band** translates it with growing
resistance, then springs back; a host may also choose none.

Hosts choose motion through **scroll physics**: an immutable pair of one
**fling** curve and one edge effect, passed on the viewport widget. Both
axes are closed sets with tunable parameters. A platform default pairs the
fling and edge effect native to the OS family.

Because the rubber-band translate can be large, hit-testing, paint
transforms reported to descendants, and row chrome paint positions MUST
include the edge transform. The floating date header and scrollbar stay
outside it.

## Considered options

- **Layout-level overshoot for rubber-band** (the origin passes the pin,
  as Flutter's bouncing physics moves the scroll position) — rejected.
  Every writer that assumes a clamped origin would need a "past the pin"
  state: the per-frame boundary clamp, bottom-inset compensation, follow
  tail and at-tail detection, band-stable delete recovery, renormalize,
  and the short-content single pin. A second origin writer at the edges
  competes with all of them.
- **One fixed physics for all platforms** — rejected: the iOS reference
  list rubber-bands and decelerates differently from the Android one.
- **Open (host-implementable) fling and edge-effect contracts** — deferred.
  A custom edge effect could break paint-only and hit-test invariants;
  opening a closed set later is additive, closing an open one is not.
- **Paint-time edge effect over a clamped layout, closed pairings,
  platform default** — accepted.
