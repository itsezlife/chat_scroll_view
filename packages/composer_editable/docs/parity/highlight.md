---
type: Composer Selection Concept
title: Hybrid selection highlight (composer)
description: >-
  Composer uses hybrid highlight: full-width completed lines, tight content end
  line, exclusive-end affinity branches, paint cache vs ephemeral subrange
  probes. Shared with bubble geometry rules but owned by extended_text.
tags: [telegram, composer, highlight, extended_text]
timestamp: 2026-07-21T12:00:00.000Z
content_hash: composer-highlight-v1
---

# Highlight

Canonical glossary: [extended-text](../../packages/extended-text.md)
(`packages/extended_text/CONTEXT.md`)
— **Hybrid selection highlight**, **Exclusive line end**, **Content-less
exclusive end**, **Empty-edge handle**, **Exclusive-end affinity**, **Paint
selection cache**, **Ephemeral hybrid boxes**.

## Rules (summary)

| Line kind | Paint width |
| --------- | ----------- |
| Completed lines | `BoxWidthStyle.max` |
| Content end line | `tight`, unless downstream exclusive empty-edge → `max` on content line + handle on next line |

Hard-break exclusive end omits trailing `\n` from painted range; may
**synthesize** trailing box (content-less exclusive end).

## Handle drag + affinity

When moving extent hits an exclusive line end, hit-test affinity updates it.
When `selection.end` is the **fixed base** of drag and is an exclusive line
end, **preserve** drag-start affinity — moving the other end must not flip
empty-edge ↔ tight.

Flutter `TextSelection.==` ignores affinity — affinity-only updates must go
through controller / `userUpdateTextEditingValue`.

## Cache isolation (critical for magnifier)

| Query | Storage |
| ----- | ------- |
| Current editable `selection` (paint) | **Paint selection cache** on `ExtendedRenderEditable` |
| Magnifier / subrange / debug probes | **Ephemeral** — compute and discard |

Log prefix `[ext_sel] hybridEphemeral` vs `hybridRebuild` marks ephemeral vs
paint paths in debug builds.

## Code map

`selection_boxes.dart`, `computeHybridSelectionBoxes`,
`ExtendedRenderEditable.getBoxesForSelection`.

## Bubble note

Read-only markdown bubbles (`flutter_md` `_MarkdownSelectable`) use a **live**
reversed handle-type swap for overlap avoidance — **different** from composer
**frozen chrome until settle**. Do not conflate the two when reading parity
docs.
