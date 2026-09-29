# ADR 019: Scrollbar — open painter, closed behavior

**Status**: Accepted  
**Date**: 2026-09-29  
**Amended**: 2026-09-30 — thumb squash dropped as not planned  
**Relates to**: [ADR 002](002-position-model.md), [ADR 012](012-cross-platform-selection-policies.md), [ADR 018](018-edge-effects-are-paint-time.md)

Hosts choose the **scrollbar** through a **scrollbar preset** on the viewport
widget: an immutable, value-equal combination of **scrollbar visibility**,
**scrollbar grab**, and a **scrollbar painter**. The platform picks the
default preset per OS family (mobile: thumb only; desktop: track and thumb),
detected like scroll physics and the selection policy. The input device in
use adjusts behavior inside a preset per event — hover reveals, touch needs a
visible thumb — and never switches presets.

The concerns are split by what a host may break:

- **Thumb metrics** stay viewport-owned. Position and length come from
  anchor and id math only the render object can compute
  ([ADR 002](002-position-model.md)); edge effects leave the thumb
  untouched.
- **Scrollbar visibility** and **scrollbar grab** are closed sets with
  tunable parameters. Visibility shares motion signals, the ticker, and the
  pointer routing order with the viewport; grab decides which presses leave
  message scrolling, selection, and the span gesture.
- **Look** is open: the painter draws from track and thumb rects the
  viewport already resolved, plus shown, hover, and grab factors. Hit
  geometry never depends on what it draws.

Scrollbar visibility is its own factor, not **scroll activity**. Hovering the
scrollbar must not hold the day header, a held day header must not pin the
scrollbar, and the two want different delays.

Conditions the viewport cannot see (a host swipe, a media viewer) reach
visibility through counted **scrollbar hold** and **scrollbar suppression**
handles on the controller, not through state inside the preset, so an equal
preset on rebuild stays a no-op.

## Considered options

- **Open visibility and grab contracts** — rejected for now. A custom
  visibility could pin the viewport's clock or stall repaints; a custom grab
  could steal the span gesture, taps, or a fling catch. Opening a closed set
  later is additive; closing an open one is not.
- **Everything in the theme extension** (Flutter `ScrollbarThemeData`
  shape) — rejected: behavior is not branding, and physics already set the
  precedent that motion-adjacent choices live on the widget, not the theme.
- **Reuse scroll activity for visibility** — rejected: couples scrollbar
  hover and day-header holds in both directions.
- **Switch presets live by last pointer kind** — rejected: flickers on
  hybrid devices; same reasoning as pointer-kind policy switching in
  [ADR 012](012-cross-platform-selection-policies.md).
- **Thumb squash** (the thumb pinned to the pressed end of the track and
  shortened by the rubber-band overshoot) — not planned. At the desktop
  reference's scaled rate (overshoot × track ÷ scrollable) it is invisible,
  since our scrollable extent spans the whole known conversation; at 1:1 it
  was built, tried on device, felt off, and was reverted. The thumb
  ignores every edge effect, and a moving edge effect does not show the
  scrollbar.
