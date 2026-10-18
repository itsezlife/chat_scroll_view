---
type: Composer Selection Concept
title: Pointer-line magnifier
description: >-
  Composer loupe during handle drag: focal X clamped to current line, focal Y at
  line center, AOSP ~100ms unified smoothing. Suppressed during one-touch
  long-press phase.
tags: [telegram, composer, magnifier, composer_editable]
timestamp: 2026-07-21T12:00:00.000Z
content_hash: composer-magnifier-v1
---

# Magnifier

Glossary: **Pointer-line magnifier** — see
[CONTEXT.md](../../CONTEXT.md).

## When shown

- Handle drag on touch **`ExtendedTextField`** (composer).
- **Not** during **one-touch phase** (finger still down after long-press word
  enter) until pointer up.
- Bubble `TextSelectionHelper` uses different rates (100/200ms X/Y) — **not**
  composer reference.

## Focal geometry (AOSP Editor)

| Axis | Rule |
| ---- | ---- |
| **X** | Pointer X clamped to current visual line bounds |
| **Y** | Vertical center of that line (not finger Y) |

Built by `pointerLineMagnifierTarget` / `computeHandleDragChrome` in
`handle_drag_chrome.dart`.

## Smoothing

AOSP `MagnifierMotionAnimator` parity: **~100ms** unified rate for X and Y
(`kAospMagnifierSettleMs`). Replaces legacy bubble 100ms X / 200ms Y split for
composer.

Clock: `currentSystemFrameTimeStamp` (not frame timestamp) — see
`smoothMagnifierInfo`.

## Handle under the loupe

The moving handle stays visible under the loupe. AOSP hides it
(`handleOverlapsMagnifier`); that is not implemented here.

## Direction settling

When `_extentForHandleDrag` returns `null` (offsets frozen inside initial word),
magnifier (and moving overlay) **still** follow the pointer.

## Code map

| File | Role |
| ---- | ---- |
| `handle_drag_chrome.dart` | Focal target + settle lerp seam (exercised by tests; the overlay runs its own settle) |
| `selection_handle_motion.dart` | `smoothMagnifierInfo`, settle constants |
| `text_selection.dart` | `showMagnifier`, smooth tick, drag updates |
