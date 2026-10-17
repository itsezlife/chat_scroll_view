---
type: Composer Selection Concept
title: Universal field gestures (composer)
description: >-
  Touch-platform enter and dismiss for every ExtendedTextField: long-press and
  double-tap word enter, one-touch phase, direction settling, tap dismiss,
  bidirectional handle invert. Desktop keeps stock Flutter defaults.
tags: [telegram, composer, gestures, extended_text]
timestamp: 2026-07-21T12:00:00.000Z
content_hash: composer-gestures-v1
---

# Gestures

Glossary: **Universal field gestures**, **Direction settling**, **One-touch
phase**, **Tap dismiss** — see
[extended-text](../../packages/extended-text.md)
(`packages/extended_text/CONTEXT.md`).

## Scope

Defined once in **`extended_text`** for all `ExtendedTextField` consumers
(chat composer, forms). Touch = `android` | `iOS` | `fuchsia`. Desktop =
`linux` | `macOS` | `windows` — stock Flutter matrix, not forced through touch
rules.

## Enter

| Gesture | Touch behavior |
| ------- | -------------- |
| **Long-press** | Word (or atomic span) select + handles + **one-touch phase** |
| **Double-tap** | Same word select; **skips** one-touch phase |
| **Capture** | Pre-select tracking; slop cancel; double-tap short-circuits |

No triple-tap → paragraph on touch (desktop may use stock triple-tap).

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
- Exclusive-end affinity preserve when fixed base is exclusive line end — see
  [highlight.md](highlight.md).
- Letter/`_` run snap **not** applied during live drag (oscillates with
  character-precise tracking).

## Code map

`ExtendedTextSelectionGestureDetectorBuilder` in `text_selection.dart`;
direction settling via `beginDirectionSettling` / `_extentForHandleDrag`.
