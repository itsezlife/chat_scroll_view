---
type: Composer Selection Concept
title: Selection handles — appear, drag, freeze, settle
description: >-
  Composer handle lifecycle on touch ExtendedTextField: overshoot appear,
  scale on grab, finger-tracked moving overlay, frozen orientation until settle,
  easeOut settle to caret. Logical selection updates live throughout.
tags: [telegram, composer, handles, extended_text]
timestamp: 2026-07-21T12:00:00.000Z
content_hash: composer-handles-v2
---

# Handles

Glossary: **Composer selection chrome**, **Finger-tracked handle**, **Frozen
handle chrome**, **Handle settle** — see
[extended-text](../../packages/extended-text.md)
(`packages/extended_text/CONTEXT.md`).

## Appear / hide (AOSP + bubble parity)

| Phase | Behavior | Code |
| ----- | -------- | ---- |
| Appear | ~250ms fade + scale, `OvershootInterpolator` tension 2.0 | `_SelectionHandleOverlay` `_scale` |
| Hide | **Instant** (`progress = 0`, no reverse) | Telegram `clear()` / `handleViewProgress` |

## Scale on grab (Telegram composer)

When the user captures a handle, the **grabbed** handle scales to **~1.5**
(`kComposerHandleDragScale`, ~250ms easeOut). Scale and finger-tracked overlay
start on **pointer DOWN** (not after touch slop). Driven by
**`isGrabbedHandleDragging`** — independent of finger-tracked overlay delta
(scrcpy mouse gets scale before pan slop via `Listener.onPointerDown`).

Extent hit-test during drag uses **caret-equivalent X**
(`pointer + grabOffset` on X; Y keeps line-jump logic) so highlight stays aligned
with the moving handle.

**Locked grilling 2026-07-21:** A + C — scale on any touch-platform handle drag;
Android `PointerDeviceKind.mouse` also enables finger-tracked overlay (scrcpy).
**Locked grilling 2026-07-21 (06):** grab-on-DOWN, compensated hit-test X, scale 1.5.

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

**Anti-pattern in current code (partial):** `fingerTrackedMovingHandleIsStart()`
switches moving overlay on invert; `_applySelectionOverlayMetrics()` updates
types every `update()`.

## Invert model

All platforms: dragged handle becomes **extent**; opposite end is **fixed base**
from `_dragStartSelection`. `_avoidCollapseExtent` keeps minimum one character.

Distinct from stock Android (“don’t allow order swapping”).

## Geometry

Material circle+stem, 22dp — `materialTextSelectionHandleControls` on all
composer consumers (including iOS) via `MarkdownTextField`.

## Code seams

| Concern | Module |
| ------- | ------ |
| Grab offset, moving-handle identity | `finger_tracked_handle.dart` |
| Settle duration, appear overshoot | `selection_handle_motion.dart` |
| Overlay wiring, freeze (target) | `text_selection.dart` `SelectionOverlay` |

## Acceptance (manual)

scrcpy vs Telegram Android **composer** (not bubble):

1. Grab handle — visible scale-up.
2. Drag far from line — handle follows finger; fixed handle stays on text.
3. Drag past other handle — no inward overlap; orientations unchanged until UP.
4. Release — settle to caret; then orientations match final selection.
