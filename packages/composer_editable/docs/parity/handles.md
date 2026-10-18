---
type: Composer Selection Concept
title: Selection handles — appear, drag, freeze, settle
description: >-
  Composer handle lifecycle on touch ExtendedTextField: overshoot appear,
  finger-tracked moving overlay, frozen orientation until settle, easeOut
  settle to caret. Logical selection updates live throughout.
tags: [telegram, composer, handles, composer_editable]
timestamp: 2026-07-21T12:00:00.000Z
content_hash: composer-handles-v2
---

# Handles

Glossary: **Composer selection chrome**, **Finger-tracked handle**, **Frozen
handle chrome**, **Handle settle** — see [CONTEXT.md](../../CONTEXT.md).

## Appear / hide (AOSP + bubble parity)

| Phase | Behavior | Code |
| ----- | -------- | ---- |
| Appear | ~250ms fade + scale, `OvershootInterpolator` tension 2.0 | `_SelectionHandleOverlay` `_scale` |
| Hide | **Instant** (`progress = 0`, no reverse) | Telegram `clear()` / `handleViewProgress` |

## Grab (pointer DOWN)

Finger-tracking starts on **pointer DOWN** (not after touch slop), through
`Listener.onPointerDown` on the handle, so an Android `PointerDeviceKind.mouse`
(scrcpy) takes the same path. The grabbed handle is **not scaled**: three
documented values disagreed (1.2, 1.4, 1.5) and no Telegram source states one.

Extent hit-test during drag uses **caret-equivalent X**
(`pointer + grabOffset` on X; Y keeps line-jump logic) so the highlight stays
aligned with the moving handle.

## Drag — moving vs fixed

| Handle | During drag | On release |
| ------ | ----------- | ---------- |
| **Grabbed (moving)** | Overlay = `pointer + grabOffset` (both axes); offsets from hit-test | ~250ms easeOut **settle** to caret anchor (visual only) |
| **Fixed** | Caret-anchored via `CompositedTransformFollower` + endpoints | Stays anchored |

Grab offset frozen at DOWN (AOSP `mTouchToWindowOffset`).

## Frozen handle chrome (Telegram crossover parity)

From DOWN until settle **completes**:

1. **Moving overlay** = always the **physical handle grabbed** (start or end
   widget). Must **not** swap when selection inverts (`extent` crosses
   `fixedBase`).
2. **Handle types** (left/right orientation) = snapshot at DOWN. Must **not**
   live-update while dragging or settling.
3. After settle: one `_applySelectionOverlayMetrics()` refresh.

**Why:** When selection reverses, live start=left / end=right types make both
handles point **inward** and overlap. Telegram keeps pre-cross orientations until
motion settles, then flips both if needed.

## Invert model

All platforms: dragged handle becomes **extent**; opposite end is **fixed base**
from `_dragStartSelection`. `_avoidCollapseExtent` keeps minimum one character.

Distinct from stock Android (“don’t allow order swapping”).

## Geometry

Material circle+stem, 22dp — `extendedMaterialTextSelectionHandleControls` on
every platform for the composer (Telegram's handles are Telegram-drawn, not the
iOS bars); the Cupertino controls stay available to a host that passes them.

## Code seams

| Concern | Module |
| ------- | ------ |
| Grab offset, moving-handle identity | `finger_tracked_handle.dart` |
| Settle duration, appear overshoot | `selection_handle_motion.dart` |
| Overlay wiring, freeze | `text_selection.dart` `ExtendedSelectionOverlay` |

## Acceptance (manual)

scrcpy vs Telegram Android **composer** (not bubble):

1. Grab handle — it follows the finger from the grab point.
2. Drag far from line — handle follows finger; fixed handle stays on text.
3. Drag past other handle — no inward overlap; orientations unchanged until UP.
4. Release — settle to caret; then orientations match final selection.
