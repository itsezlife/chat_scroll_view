---
type: Composer Selection Concept
title: Composer and bubble selection stacks
description: >-
  The composer's handles and magnifier are its own overlay on the editable;
  message bubbles use the chat viewport's text selection. Do not port bubble
  code when changing ExtendedTextField.
tags: [composer, selection, architecture]
timestamp: 2026-07-21T12:00:00.000Z
content_hash: composer-arch-v1
---

# Selection stacks

## Composer (this package)

```
Chat input
  └── cursor and handle colour theming
        └── editable: selection, hit-test, handles, magnifier
              ├── handle overlay, grab offset
              ├── magnifier + settle motion
              └── stock selection / hit-test
```

The composer's touch behaviour is a set of rules layered on the editable:
the handle and magnifier popup position are decoupled from the finger, the
magnifier smooths over ~100 ms, the handle orientation refreshes after motion
settles, and the handle grabbed on touch follows the finger. Each rule, and
which ones are not implemented, is listed in
[flutter-parity.md](flutter-parity.md).

Flutter implementation: **`composer_editable`** `ExtendedSelectionOverlay` on
touch `ExtendedTextField` only.

## Message bubbles (out of scope)

Message bubble text is selected by the chat viewport's own text selection, not
by this package.

## Platform split (Flutter)

| Target | Composer behavior |
| ------ | ----------------- |
| `android`, `iOS`, `fuchsia` | Universal field gestures + composer chrome (finger-tracked, settle, pointer-line loupe) |
| `linux`, `macOS`, `windows` | Stock Flutter caret-anchored handles; no finger-tracked overlay |

## Common mistake

Porting the bubble's selection timing (the 100/200 ms magnifier split, the
bubble draw loop, or an instant reversed handle-type swap) into the composer.
Composer behaviour is specified in [handles.md](handles.md),
[magnifier.md](magnifier.md), and [flutter-parity.md](flutter-parity.md).
