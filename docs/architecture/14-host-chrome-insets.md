---
type: Architecture Reference
title: Host Chrome Insets
description: How a host reserves the scroll band for occluding chrome without folding that chrome into the viewport render object.
tags: [insets, host, chrome, padding]
timestamp: 2026-10-16T00:00:00Z
resource: lib/src/chat_widgets/chat_scroll_view.dart
---

# Host Chrome Insets

The viewport consumes reserved space as `topPadding` and `bottomPadding`
listenables. It does **not** own composer, keyboard, or selection widgets.
Those belong to the host. Folding them into the render object would mix
message layout with overlay hit-testing, safe area, and IME geometry.

## Contract

| Role | Responsibility |
|------|----------------|
| Viewport | Reads `topPadding` / `bottomPadding`. Compensates **bottom** changes so on-screen messages stay put ([01](./01-coordinate-model.md), invariant 16). |
| Host | Aggregates occluding chrome into those listenables. Positions overlay chrome against the reserved edge. |

Typical aggregation (names are roles, not required types):

```text
topPadding    = safeTop + headerReserve
bottomPadding = composerExtent + max(safeBottom, panelOccupancy.bottom)
inlineEnd     = panelOccupancy.inlineEnd   // applied in layout, not as padding
```

`safeTop` is persistent view padding (notch / status bar). `headerReserve` is
only the overlay header’s occupancy (often `progress × barHeight`).
`composerExtent` is the height the composer publishes as data, **excluding**
its bottom safe-area pad, the panel and the keyboard. The bottom band is the
host's, `max(safeBottom, panelOccupancy.bottom)`, computed from the occupancy
at once: the extent is measured after layout and arrives a frame late, so the
pad must not ride on it. The
composer imports no inset types ([ADR 026](../adr/026-composer-model.md)).
`panelOccupancy` is the `ValueListenable` (`package:listen`) the active panel presentation publishes
([ADR 028](../adr/028-panel-presentation.md)): for a keyboard-replacement
presentation `bottom` is the animated `max(IME, panel)` and already contains
the live IME height; an anchored popup publishes zero; a docked section
publishes its width as `inlineEnd`. The host reads the occupancy of the
presentation currently shown and never adds IME height a second time.

## Reference wiring

The reference host (`example/`) keeps the aggregation in one small object,
`ChatViewportInsets`, created with the chat screen's controller set and
disposed with it. It is handed the two listenables and follows them; it owns
neither:

| Input | Role |
|-------|------|
| The composer's extent `ValueListenable` | Frame-by-frame height of the composer, own safe pad included. Until the first publication the aggregation uses a seed so the first frame is not zero. |
| The presentation's `occupancy` `ValueListenable` | `bottom` in the sum above, `inlineEnd` as the width the host takes from the chat region. |

| Output | Consumer |
|--------|----------|
| `bottomPadding` | The viewport, and overlay chrome that positions against the reserved edge (never adds to it). |
| `inlineEnd` | A padding at the end edge of the whole chat region (viewport, composer and overlays), mirrored in right-to-left text, around the box a docked panel is drawn over. |
| `topPadding`, `chromeTop` | The viewport, and chrome that sits below the safe area and the selection header. |

The soft keyboard enters once, through the presentation's input port: the host
forwards every reading it has (height, whether the system is animating it, the
bottom safe area from the same `MediaQuery` update) and invents none. The
composer is handed `composerSafeInset` as its bottom safe area only where a
keyboard-replacement presentation exists. Where the panel is a popup or a
dock, the host draws the presentation view over the chat in a box it owns and
reports the composer's rectangle to the popup with `anchor`.

## Reserved inset vs overlay chrome

**Reserved inset** is space the scroll band yields so messages are not
drawn under occluding chrome. Only widgets that cover the message list
write it.

**Overlay chrome** sits on top of the viewport and **reads** the reserved
edge to position itself (unread pill, jump-to-latest). It must not increase
`topPadding` / `bottomPadding`. Including it in the reserve would shrink the
band for chrome that does not occlude messages.

## Keyboard

Keyboard height is a live geometric signal, not a second scroll writer. The
host feeds raw IME samples to the presentation through its single input port;
without a panel presentation, or with one that publishes zero, the host lifts
the composer by that height and adds the same value into `bottomPadding`. The viewport then compensates the pad change (invariant 16).
Do not implement keyboard follow by pinning the newest row.

## Safe area

The bottom safe band (navigation bar, home indicator) is covered once by
whatever is taller: the composer's own pad, or the occupancy. A
keyboard-replacement presentation therefore publishes, next to its
occupancy, the part of the band the occupancy has not covered yet
(`max(0, band - occupancy.bottom)`), and the host hands that to the composer
as its bottom safe area. The bottom of the window is `max(band, occupancy)`
at every frame of an open, a close or a keyboard hand-off: no step when the
keyboard appears and no band counted twice. The presentation takes the band
from the same readings as the keyboard height, never from a second observer.

## Measurement

A one-shot or layout-driven measure of composer height is a **bootstrap and
correction**, not a second coordinate system. Seed `bottomPadding` with idle
occupancy so the first frame is not zero, then publish measured height
(the composer's extent).
Do not treat post-layout size as the animation driver if the host later
animates composer height — publish the animated occupancy on the same
listenable the viewport already consumes.

## What not to do

- Do not parent composer/header widgets inside the chat render object to
  “get animation for free.”
- Do not add overlay chrome into reserved padding.
- Do not add bottom safe-area twice (composer measure and a second observer).
- Do not capture `MediaQuery` once in a `late final` field; view padding
  changes on rotation and must be pushed again.
