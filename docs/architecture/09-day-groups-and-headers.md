---
type: Architecture Reference
title: Day Groups and Headers
description: startsDay, groupBy, dayBucket, floating header, and divider fade band.
tags: [headers, startsDay, divider, groupBy]
timestamp: 2026-07-04T00:00:00Z
resource: lib/src/chat_scroll/chat_floating_header_controller.dart
---

# Day Groups and Headers

Day grouping is optional and enabled only when `dateSeparatorBuilder` is set.
Effective grouper: `groupBy ?? defaultGroupBy` (local calendar day
`DateTime(y, m, d)`).

## Parent data

`ChatMessageParentData` fields used by day chrome:

| Field | Meaning |
|-------|---------|
| `startsDay` | Row has an inline date separator |
| `dayBucket` | `groupBy` key; null if unloaded / grouping off |
| `dividerOpacity` | 0..1 fade for the inline separator |
| `offset` | Viewport-local top Y |

Chunk-error tiles force `startsDay = false`, `dayBucket = null`. Floating
header reuses this parent-data type; only `offset` is meaningful (`id = 0`).

**Invariant:** per-frame header scan and fade are **Tier-1-safe** — no
`getMessage` on the hot path. Scan/fade read parent-data (`dayBucket`,
`startsDay`, layout `offset`) and, while stitch is jumped, the paint
translation from the animator.

## How `startsDay` is computed

Render-side (`_buildMessage` → `_startsDay`):

1. `bucket == null` → false (unloaded or grouping off).
2. If `reachedOldest` and `id <= oldestKnownId` → true (conversation first).
3. Else compare previous **present** message bucket to `bucket` via
   `getPreviousPresentMessage(id)`; null prev → false; unequal → true.

`_bucketOf(id)` = `groupBy(getMessage(id))` or null.

**Intentional for loading:** separator appears only when **both** current and
the previous present predecessor are loaded (except conversation-oldest case).

**Fixed (2026-07-05):** absent predecessors no longer block `startsDay` — walk
uses `getPreviousPresentMessage`, not `getMessage(id - 1)`.

Element receives `startsNewDay` / `groupBucket` and chooses `DatedMessage` vs
plain row — it does not recompute boundaries.

## `DatedMessage`

- Widget: separator + body, each in `RepaintBoundary`.
- Outer widget is **not** a `RepaintBoundary` — must repaint every scroll frame
  for opacity.
- `RenderDatedMessage` stacks separator above body; size = sum of heights.
- Reads `dividerOpacity` from viewport parent data.
- Hit-test: body first; separator ignored when opacity ≤ 0.
- Paint: body always; separator via `OpacityLayer` only in (0.001, 0.999).

Inline separator **keeps laid-out height** while fading — no layout jump.

## Floating header ownership

| Concern | Owner |
|---------|--------|
| Header `RenderBox`, inflate/layout | `RenderChatScrollView` + element |
| Bucket/date state, scan, fade math | `ChatFloatingHeaderController` |
| Parent-data reads | Callbacks from render |

Controller never inflates widgets.

### Layout path (`_updateFloatingHeader`)

1. `_scanTopDay()` — topmost child by **paint** Y whose rect crosses `topPad`
   with non-null `dayBucket` (layout offset, plus stitch dual-translate dy while
   the far path is jumped). Children are not assumed Y-sorted — stitch can
   invert id order vs paint order.
2. `evaluateLayoutRebuild` — rebuild if `scan.bucket != headerBucket` **or**
   `headerDirty`.
3. On rebuild: `buildFloatingHeader(bucket, firstMessageDate)`.
4. Always layout header to full width; pin Y to `topPad`
   (`placeHeaderOffset`).

### Tier-1 path (`_tickFloatingHeader`)

1. Re-pin header offset (does not scroll with content).
2. `tickForDayChange` compares scan bucket to `headerBucket` **without**
   mutating state (same paint-aware scan as layout — stitch ticks can change
   the floating date from paint-visible content before settle).
3. If day changed → caller `markNeedsLayout` (header **text** needs rebuild).

**Must not:** call `buildFloatingHeader` from Tier-1. Fade opacity updates stay
on Tier-1 via `_setOffset` / stitch paint-Y refresh. Mid-gap days are never
invented — the scan only reads buckets of currently built rows.

### Forced rebuild

`invalidateFloatingHeader()` → `headerDirty = true` + `markNeedsLayout`.
Triggered when `dateSeparatorBuilder` or `textDirection` changes.

Data-source swap: `resetOnDataSourceChange()`. Overlay: `clearForOverlay()` +
remove header.

## Divider fade band

Constants:

- `kHeaderFallbackHeight = 32` (before first header layout)
- `kDividerFadeBand = 20`

```
fadeEnd = topPad + floatingHeaderHeight
opacity = ((topY - fadeEnd) / kDividerFadeBand + 1.0).clamp(0.0, 1.0)
```

- Opacity 1 when separator top is fully below the header zone.
- Opacity 0 when separator top is under the header zone.
- Written in `_setOffset` only when `pd.startsDay`.

Inline separator and floating header never both fully visible: as the
separator rises into the header zone it fades out; the sticky header holds
the date.

## Hit-test order

Floating header hit-tests **before** messages (paints on top). Chunk-error
tiles hit-test before messages during error → valid transition frames.
