---
type: Composer Selection Status
title: Composer selection status
description: >-
  Status of each composer selection behaviour in composer_editable: done, not
  implemented, or dropped. Message-bubble selection is a separate track.
tags: [composer, status, composer_editable]
timestamp: 2026-10-18T12:00:00.000Z
content_hash: composer-parity-v3
---

# Composer selection status

Architecture: [architecture.md](architecture.md). Implementation:
`packages/composer_editable/`. What differs from stock Flutter, and why:
[DIVERGENCES.md](../../DIVERGENCES.md).

Status key: **Done** | **Not implemented** | **Dropped**

## Handles & motion

| Behavior | Expected | Status | Notes |
| -------- | -------- | ------ | ----- |
| Appear overshoot ~250ms | ✓ | **Done** | `_SelectionHandleOverlay`, `OvershootCurve` tension 2.0 |
| Hide instant | ✓ | **Done** | `_controller.value = 0` |
| Finger-tracked moving overlay (X+Y) | ✓ | **Done** | Android mouse (scrcpy) included via `pointerKindUsesFingerTrackedHandle` |
| Grab offset at DOWN | ✓ | **Done** | `computeHandleGrabOffset` |
| Settle ~250ms easeOut on UP | ✓ | **Done** | `endFingerTrackedHandleDrag` |
| Frozen handle chrome until settle | ✓ | **Done** | Grabbed overlay and handle types held until the settle ends |
| Grabbed handle stays the moving one on invert | ✓ | **Done** | `isFingerTrackedMovingStartHandle` |
| Fixed handle caret-anchored | ✓ | **Done** | |
| Scale on grab | ✗ | **Dropped** | Three candidate values (1.2, 1.4, 1.5) disagree and none is verified |
| Desktop unchanged | n/a | **Done** | `usesFingerTrackedHandleDrag` |

## Magnifier

| Behavior | Status | Notes |
| -------- | ------ | ----- |
| Pointer-line focal (X clamp, Y line center) | **Done** | `pointerLineMagnifierTarget`, `ExtendedSelectionOverlay` |
| ~100ms unified smoothing | **Done** | `smoothMagnifierInfo`, `kAospMagnifierSettleMs` |
| Hide the moving handle under the loupe | **Not implemented** | The handle stays visible |
| Suppress during one-touch | **Done** | |
| Direction settling: loupe follows finger | **Done** | |

## Gestures & highlight

| Behavior | Status | Notes |
| -------- | ------ | ----- |
| Universal enter (long-press, double-tap) | **Done** | Touch platforms |
| iOS: floating cursor on a focused long-press | **Done** | Stock path kept |
| iOS: caret tap toggles the Paste menu | **Done** | Stock path kept |
| Direction settling | **Done** | |
| Bidirectional invert | **Done** | |
| `_avoidCollapseExtent` | **Done** | |
| Highlight | stock | [highlight.md](highlight.md) |

## Out of scope

- Message-bubble selection (the chat viewport's text selection)
- Read-only selectable text
- Desktop / pointer-primary platforms (stock handles)

## Tests

| Seam | File |
| ---- | ---- |
| Grab offset, moving-handle identity | `finger_tracked_handle_test.dart` |
| Magnifier smooth, settle T | `selection_handle_motion_test.dart` |
| Drag chrome outputs | `selection_handle_motion_test.dart` |
| Touch gesture matrix | `universal_field_gestures_test.dart` |
| iOS paths, system menu | `ios_restored_paths_test.dart` |
| Visibility without debug-only flags, stock highlight | `release_parity_test.dart` |
| Overscroll handoff, select-all scroll | `nested_overscroll_handoff_test.dart`, `select_all_page_scroll_test.dart` |

Handle motion and magnifier feel are checked on a device (ADR 030), not in
widget tests.
