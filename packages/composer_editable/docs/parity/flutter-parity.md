---
type: Composer Selection Parity
title: Flutter parity — composer vs Telegram Android
description: >-
  Gap table for extended_text composer selection vs Telegram Android AOSP
  Editor stack. Status as of 2026-07-21 grilling. Bubble TextSelectionHelper
  is a separate track.
tags: [telegram, composer, parity, extended_text, roadmap]
timestamp: 2026-07-21T12:00:00.000Z
content_hash: composer-parity-v2
---

# Flutter parity (composer)

Reference: [architecture.md](architecture.md). Implementation:
`packages/extended_text/`. Spec: `.scratch/composer-handle-motion/`.

Status key: **Done** | **Partial** | **Missing**

## Handles & motion

| Behavior | Telegram / AOSP | Status | Notes |
| -------- | ----------------- | ------ | ----- |
| Appear overshoot ~250ms | ✓ | **Done** | `_SelectionHandleOverlay` |
| Hide instant | ✓ | **Done** | `_controller.value = 0` |
| Scale on grab (~1.2) | ✓ | **Done** | `isGrabbedHandleDragging`; decoupled from finger-tracked |
| Finger-tracked moving overlay (X+Y) | ✓ | **Partial** | Android mouse (scrcpy) included via `pointerKindUsesFingerTrackedHandle` |
| Grab offset at DOWN | ✓ | **Done** | `computeHandleGrabOffset` |
| Settle ~250ms easeOut on UP | ✓ | **Partial** | `endFingerTrackedHandleDrag`; needs polish with freeze |
| **Frozen handle chrome** until settle | ✓ | **Missing** | Locked grilling 2026-07-21; overlap bug when invert |
| Grabbed handle stays moving on invert | ✓ | **Missing** | `fingerTrackedMovingHandleIsStart` swaps overlay |
| Fixed handle caret-anchored | ✓ | **Done** | |
| Desktop unchanged | n/a | **Done** | `usesFingerTrackedHandleDrag` |

## Magnifier

| Behavior | Status | Notes |
| -------- | ------ | ----- |
| Pointer-line focal (X clamp, Y line center) | **Partial** | Helpers exist; wiring mixed with legacy builder |
| AOSP ~100ms unified smooth | **Partial** | `smoothMagnifierInfo`; DIVERGENCES still mentions 100/200 |
| Hide moving handle under loupe | **Missing** | `computeHandleDragChrome` seam; not fully wired |
| Suppress during one-touch | **Done** | |
| Direction settling: loupe follows finger | **Done** | |

## Gestures & highlight

| Behavior | Status | Notes |
| -------- | ------ | ----- |
| Universal enter (long-press, double-tap) | **Done** | |
| Direction settling | **Done** | |
| Bidirectional invert | **Done** | |
| `_avoidCollapseExtent` | **Done** | |
| Hybrid highlight + exclusive-end affinity | **Done** | Recent affinity preserve work |
| Paint vs ephemeral cache isolation | **Done** | |

## Next implementation (priority)

1. **Frozen handle chrome** — snapshot types + grabbed overlay identity until
   settle completes ([handles.md](handles.md)).
2. **Decouple drag scale** from finger-tracked gate; optional Android mouse for
   scrcpy overlay. **Done (2026-07-21):** scale 1.2 via `isGrabbedHandleDragging`;
   Android mouse in finger-tracked path.
3. Wire **hide-under-loupe** + pointer-line magnifier through one overlay path.
4. Update **DIVERGENCES.md** handle/magnifier section to composer AOSP target.
5. Manual scrcpy acceptance per `.scratch/composer-handle-motion/spec.md`.

## Explicitly out of scope (this track)

- Bubble `TextSelectionHelper` overlay ([bubble-selection/overview.md](../bubble-selection/overview.md))
- Read-only `flutter_md` `SelectionArea`
- Desktop / pointer-primary platforms

## Tests

| Seam | File |
| ---- | ---- |
| Grab offset, moving-handle identity | `finger_tracked_handle_test.dart` |
| Magnifier smooth, settle T | `selection_handle_motion_test.dart` |
| Drag chrome outputs | `handle_drag_chrome` (via `selection_handle_motion_test` / future) |
| Hybrid boxes | `selection_boxes_test.dart` |

Widget-level `ExtendedTextField` drag tests: not required for first land; scrcpy
vs Telegram composer is acceptance for feel.
