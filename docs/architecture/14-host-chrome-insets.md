---
type: Architecture Reference
title: Host Chrome Insets
description: How a host reserves the scroll band for occluding chrome without folding that chrome into the viewport render object.
tags: [insets, host, chrome, padding]
timestamp: 2026-08-19T00:00:00Z
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
bottomPadding = composerHeight + keyboard
```

`safeTop` is persistent view padding (notch / status bar). `headerReserve` is
only the overlay header’s occupancy (often `progress × barHeight`).
`composerHeight` is the composer’s laid-out height **including** its own
bottom safe-area pad, **excluding** keyboard. `keyboard` is live IME height.

## Reserved inset vs overlay chrome

**Reserved inset** is space the scroll band yields so messages are not
drawn under occluding chrome. Only widgets that cover the message list
write it.

**Overlay chrome** sits on top of the viewport and **reads** the reserved
edge to position itself (unread pill, jump-to-latest). It must not increase
`topPadding` / `bottomPadding`. Including it in the reserve would shrink the
band for chrome that does not occlude messages.

## Keyboard

Keyboard height is a live geometric signal, not a second scroll writer.
The host lifts the composer by that height and adds the same value into
`bottomPadding`. The viewport then compensates the pad change (invariant 16).
Do not implement keyboard follow by pinning the newest row.

## Measurement

A one-shot or layout-driven measure of composer height is a **bootstrap and
correction**, not a second coordinate system. Seed `bottomPadding` with idle
occupancy so the first frame is not zero, then publish measured height.
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
