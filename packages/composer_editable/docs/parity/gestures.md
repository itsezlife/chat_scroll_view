---
type: Composer Selection Concept
title: Universal field gestures (composer)
description: >-
  Touch-platform enter and dismiss for every ExtendedTextField: long-press and
  double-tap word enter, one-touch phase, direction settling, tap dismiss,
  bidirectional handle invert. Desktop keeps stock Flutter defaults.
tags: [telegram, composer, gestures, composer_editable]
timestamp: 2026-07-21T12:00:00.000Z
content_hash: composer-gestures-v1
---

# Gestures

Glossary: **Universal field gestures**, **Direction settling**, **One-touch
phase**, **Tap dismiss** — see [CONTEXT.md](../../CONTEXT.md). Decisions:
[ADR 0001](../adr/0001-universal-field-gestures.md),
[ADR 0002](../adr/0002-touch-scoped-universal-gestures.md).

## Scope

Defined once in **`composer_editable`** for every `ExtendedTextField`. Touch = `android` | `iOS` | `fuchsia`. Desktop =
`linux` | `macOS` | `windows` — stock Flutter matrix, not forced through touch
rules.

## Enter

| Gesture | Touch behavior |
| ------- | -------------- |
| **Long-press** | Word (or atomic span) select + handles + **one-touch phase** |
| **Double-tap** | Same word select; **skips** one-touch phase |
| **Capture** | Pre-select tracking; slop cancel; double-tap short-circuits |

No triple-tap → paragraph on touch (desktop may use stock triple-tap).

### iOS keeps two stock paths

| Gesture | iOS behavior |
| ------- | ------------ |
| **Long-press on a focused, editable field** | Moves the caret with the floating cursor (`updateFloatingCursor`), no word selection. Unfocused or read-only: the word-and-one-touch path above. |
| **Tap on the collapsed caret of a focused, editable field** | Toggles the toolbar (the Paste menu) instead of moving the caret. A tap elsewhere places the caret and hides the toolbar. |

Both are the platform's text-view behavior, and the default context menu there
is the system menu where `SystemContextMenu` is supported.

## Direction settling

After long-press word enter: ignore handle extents **strictly inside** the
initial word until pointer exits past `start` or `end`. Cleared when user
explicitly grabs a start/end handle.

While offsets frozen: **chrome follows pointer** (overlay + magnifier).

## Dismiss

Single tap in selection mode → clear selection, hide handles/toolbar, collapsed
caret at tap.

## Handle drag

- Invert model: dragged handle = extent (all platforms).
- `_avoidCollapseExtent`: never collapse to caret mid-drag.
- Letter/`_` run snap **not** applied during live drag (oscillates with
  character-precise tracking).

## Code map

`ExtendedTextSelectionGestureDetectorBuilder` in `text_selection.dart`;
direction settling via `beginDirectionSettling` / `_extentForHandleDrag`.
