---
type: Composer Selection Concept
title: Pointer-line magnifier
description: >-
  Composer loupe during handle drag: focal X clamped to current line, focal Y at
  line center, AOSP ~100ms unified smoothing, moving handle hidden when loupe
  overlaps. Suppressed during one-touch long-press phase.
tags: [telegram, composer, magnifier, extended_text]
timestamp: 2026-07-21T12:00:00.000Z
content_hash: composer-magnifier-v1
---

# Magnifier

Glossary: **Pointer-line magnifier** — see
[extended-text](../../packages/extended-text.md)
(`packages/extended_text/CONTEXT.md`).

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

## Hide handle under loupe

While loupe bounds overlap the **moving** handle during drag, hide that handle
(AOSP `handleOverlapsMagnifier`). Fixed handle stays visible.

## Direction settling

When `_extentForHandleDrag` returns `null` (offsets frozen inside initial word),
magnifier (and moving overlay) **still** follow the pointer.

## Ephemeral geometry

Magnifier line probes must use **ephemeral hybrid boxes** — never overwrite
**paint selection cache** on `ExtendedRenderEditable`. See
[highlight.md](highlight.md).

## Code map

| File | Role |
| ---- | ---- |
| `handle_drag_chrome.dart` | Focal target + overlap hide + settle lerp seam |
| `selection_handle_motion.dart` | `smoothMagnifierInfo`, settle constants |
| `text_selection.dart` | `showMagnifier`, smooth tick, drag updates |
