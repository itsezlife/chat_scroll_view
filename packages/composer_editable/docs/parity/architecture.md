---
type: Composer Selection Concept
title: Reference stack — composer vs bubble
description: >-
  Telegram chat composer uses stock AOSP Editor handle/magnifier physics;
  message bubbles use custom TextSelectionHelper. Agents must not port bubble
  code when fixing MarkdownTextField / ExtendedTextField.
tags: [telegram, composer, aosp, architecture]
timestamp: 2026-07-21T12:00:00.000Z
content_hash: composer-arch-v1
---

# Reference stack

## Composer (this bundle)

```
Telegram chat input
  └── EditTextBoldCursor          ← themes cursor + handle color only
        └── android.widget.Editor
              ├── HandleView / SelectionHandleView   ← drag overlay, grab offset
              ├── Magnifier + MagnifierMotionAnimator
              └── stock selection / hit-test
```

Telegram **does not** ship a custom handle-drag overlay for the composer in Java.
The “Telegram feel” is **composite AOSP behavior**: decoupled popup position,
~100ms magnifier smooth, handle hidden under loupe, scale on grab, orientation
refresh after motion settles.

Flutter implementation: **`extended_text`** `SelectionOverlay` on touch
`ExtendedTextField` only.

## Bubble (out of scope)

```
Telegram message / article text
  └── TextSelectionHelper         ← custom overlay class
        ├── handleViewProgress (appear/hide)
        ├── movingOffsetX/Y (grab offset)
        ├── lastX magnifier + 100/200ms settle
        └── drawSelection (caret-anchored handle *draw*)
```

Bubble helper is documented separately under
[bubble-selection/overview.md](../bubble-selection/overview.md) and
[flutter/ui/l10n-rich-text.md](../../flutter/ui/l10n-rich-text.md) (`flutter_md`
read-only selection).

## Platform split (Flutter)

| Target | Composer behavior |
| ------ | ----------------- |
| `android`, `iOS`, `fuchsia` | Universal field gestures + composer chrome (finger-tracked, settle, pointer-line loupe) |
| `linux`, `macOS`, `windows` | Stock Flutter caret-anchored handles; no finger-tracked overlay |

## Common mistake

Porting **`TextSelectionHelper`** rules (100/200ms magnifier split, bubble draw
loop, instant reversed handle-type swap from `_MarkdownSelectable`) into the
composer. Composer parity follows **AOSP Editor** + locked grilling decisions in
[handles.md](handles.md) and [flutter-parity.md](flutter-parity.md).
