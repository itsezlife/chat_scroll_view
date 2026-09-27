---
type: Architecture Reference
title: Day Groups and Headers
description: startsDay, groupBy, dayBucket, row chrome delegates, day header policy, and scroll activity.
tags: [headers, startsDay, row-chrome, groupBy, scroll-activity]
timestamp: 2026-09-27T00:00:00Z
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
| `paintTop` | Viewport-local paint top: `offset` + stitch dual-translate dy |
| `headerZone` | `ChatFloatingHeaderZone` of the latest frame (rest top, extent, push offset, opacity) |
| `scrollActivity` | Scroll activity of the latest frame; `1` without a clock |
| `messageBodyTop` | Σ row-chrome heights; press above it is chrome |
| `offset` | Viewport-local top Y |

Chunk-error tiles force `startsDay = false`, `dayBucket = null`. Floating
header reuses this parent-data type; only `offset` is meaningful (`id = 0`).

**Invariant:** the per-frame header scan and chrome resolve are
**Tier-1-safe** — no `getMessage` on the hot path. They read parent-data
(`dayBucket`, `startsDay`, layout `offset`) and, while stitch is jumped, the
paint translation from the animator.

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

Element receives `startsNewDay` / `groupBucket` and chooses a `ChatRowChrome`
row (date chrome) vs plain row — it does not recompute boundaries.

## Row chrome (`ChatRowChrome`)

A row that carries viewport-owned chrome is a `ChatRowChrome`: an ordered
stack of chrome items above the message body. Each item pairs a widget with a
`ChatRowChromeDelegate`. `DatedMessage` is a deprecated forward to a
one-item `ChatRowChrome` with `fadeUnderHeader`.

The viewport composes up to two items, only on a **loaded** message row
(never shimmer, errored, or absent):

| Item | When | Delegate |
|------|------|----------|
| Inline date separator (`dateSeparatorBuilder`) | Row starts a day | Day header policy's `inlineSeparator` |
| Unread separator (`unreadSeparatorBuilder`) | Row id `== unreadBoundary.value` | `opaque()` — never fades or hides |

A row with neither is a plain `RepaintBoundary`. The unread separator does
not touch the day machinery: `startsDay`, `dayBucket`, the header scan, and
`leadingSeparatorTop` ignore it, and the divider fade applies to the date item
only. The render object listens to `unreadBoundary`; a value change rebuilds
only the old and the new boundary row (the separator flag is a skip-rebuild
input) and holds the row at the band bottom in place — see
[Layout Pipeline](./04-layout-pipeline.md). Swapping the builder clears the
skip-rebuild cache.

| Concern | Rule |
|---------|------|
| Order | Chrome items top to bottom in list order, body last (bottom) |
| Width / height | Every child at full row width, own height; row height = Σ chrome + body |
| Repaint | Each chrome child and the body in its own `RepaintBoundary`; the row itself is **not** one — it re-composites every viewport paint to apply resolved opacity |
| Delegate | Per item, on every paint and hit test: `resolve(ChatRowChromeMetrics)` → `ChatRowChromeEffect { opacity, hitTestable }`. Metrics: item paint top (`paintTop` + item offset), extent, `headerZone`, `scrollActivity`. Delegate swap to a non-`==` one repaints without re-inflating |
| Paint | Body first, then chrome in list order; an item uses an `OpacityLayer` only in (0.001, 0.999), is skipped ≤ 0.001, paints directly ≥ 0.999 |
| Hit-test | Body first, then chrome from the last item up, skipping items whose effect is not `hitTestable` (default: `opacity > 0`) |
| Hit height | Writes Σ chrome heights into `ChatMessageParentData.messageBodyTop` every layout |

Built-in row chrome delegates:

| Delegate | Effect |
|----------|--------|
| `opaque()` (item default) | Always visible and hit-testable |
| `fadeUnderHeader(band: 20)` | `((top - header.bottom) / band + 1).clamp(0, 1)`; visible with no header |
| `hideUnderHeader()` | Hidden once `top <= header.restTop`; visible with no header |

`messageBodyTop` is the single row-chrome line for pointer resolution: a
press above it is chrome, so long-press selection and the message menu never
start there. Full-row resolution (span-gesture sweeps) and presses under a
hit-testable floating header ignore the line. Every chrome child is covered by
that one rule — none needs its own exclusion.

Chrome **keeps laid-out height** whatever it resolves to — no layout jump.

## Day header policy (`ChatDayHeaderDelegate`)

`ChatScrollView.dayHeaderDelegate` decides how the floating header and the
inline separators share the viewport top. One policy owns both halves:
`resolveFloatingHeader(ChatDayHeaderMetrics)` → `ChatFloatingHeaderEffect
{ offset, opacity, holdsActivity, hitTestable }`, and `inlineSeparator` for
the rows.

Metrics: `restTop` (= `topPad`), `extent` (laid-out header height, fallback
`kHeaderFallbackHeight = 32` before first layout), `leadingSeparatorTop`, and
`activity`. `leadingSeparatorTop` is the smallest paint top among built
`startsDay` rows with `top > restTop - extent` — the separator that is not yet
fully above the rest line (separators are assumed header-tall).

| Policy | Header | Inline separator | Held |
|--------|--------|------------------|------|
| `ChatFadingDayHeader` (default) | Offset 0 | `fadeUnderHeader(fadeBand)` | `lead < restTop + extent` |
| `ChatPushingDayHeader` | `lead - restTop - extent` while `restTop < lead < restTop + extent`, else 0 | `hideUnderHeader()` | `lead <= restTop` |

Opacity = `hidesWhenIdle && !held ? activity : 1`; `holdsActivity =
hidesWhenIdle && held`. Held means the header is standing in for an inline
separator that is hidden or faded under it — hiding the header would leave an
empty band.

`holdsActivity` pins the clock (`pinned = true`: activity snaps to `1`, no
pending hide). When the header stops being held, the pin clears and activity
idles out from `1`, so a scroll that starts from a held header never shows a
hidden header for the frames before the drag's hold takes effect.

The pushing separator always opens a later day than the header shows: the
oldest row rests at the rest line (boundary pin), so the oldest separator is
held, never pushing.

The day switch needs no policy code: when the leading separator reaches the
rest line, the previous day's rows fall above `topPad`, the top-day scan picks
the new day, and the header rebuilds in the same frame — at offset 0 and held.

## Scroll activity

`ChatScrollView.scrollActivityTiming` (`ChatScrollActivityTiming`, `null` = no
clock, activity constant `1`) runs a viewport-owned clock (`ChatScrollActivityClock`):
a `Timer` for the idle hold, a dedicated `Ticker` for the fades.

| Edge | Clock call |
|------|------------|
| A tick consumes scroll delta | `hold(navigation: animate-only delta)` |
| Nothing moves the list (no drag, fling, animate, pending delta, span auto-scroll) | `release()` → hide after `idleDelay` (500 ms) or `navigationIdleDelay` (1000 ms) after navigation |
| Attach | none: the clock starts idle at `0`, so the list opens with idle-hidden chrome hidden |
| Jump (`_onJump`) | `pulse()` — show, hide after `navigationIdleDelay` unless holding |
| `scrollBy` | `pulse(navigation: false)` — hide after `idleDelay` unless holding |
| Day header effect, every resolve | `pinned = effect.holdsActivity` (false with no header) |

Fades: 150 ms in / out along an exact sine ease-in-out. A finger held still
mid-drag keeps activity up. Hiding takes two knobs: the timing supplies
activity, and each delegate chooses to follow it (`hidesWhenIdle` on the
built-in day header policies). `onChanged` fires only in ticker frames; the
viewport then re-resolves the chrome frame and repaints (no layout).

## Floating header ownership

| Concern | Owner |
|---------|--------|
| Header `RenderBox`, inflate/layout, paint opacity | `RenderChatScrollView` + element |
| Bucket/date state, scan | `ChatFloatingHeaderController` |
| Header offset / opacity, inline separator presentation | `ChatDayHeaderDelegate` |
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
4. Always layout header to full width.

End of `performLayout`: `_resolveRowChromeFrame()` places the header at
`restTop + effect.offset`, applies the activity pin, and publishes
`paintTop` / `headerZone` / `scrollActivity` into every child.

### Tier-1 path (`_tickFloatingHeader`)

1. `tickForDayChange` compares scan bucket to `headerBucket` **without**
   mutating state (same paint-aware scan as layout — stitch ticks can change
   the floating date from paint-visible content before settle).
2. If day changed → caller `markNeedsLayout` (header **text** needs rebuild).
3. `_resolveRowChromeFrame()` re-resolves placement and row inputs from paint
   Y.

**Must not:** call `buildFloatingHeader` from Tier-1. Mid-gap days are never
invented — the scan only reads buckets of currently built rows.

### Forced rebuild

`invalidateFloatingHeader()` → `headerDirty = true` + `markNeedsLayout`.
Triggered when `dateSeparatorBuilder` or `textDirection` changes.

Data-source swap: `resetOnDataSourceChange()`. Overlay: `clearForOverlay()` +
remove header.

## Header paint

The header paints after messages, outside the stretch transform, at its
resolved opacity: directly ≥ 0.999, skipped ≤ 0.001, through a retained
`OpacityLayer` in between. A skipped header stays built.

## Hit-test order

Floating header hit-tests **before** messages (paints on top) when its effect
is `hitTestable`; a hidden header neither takes taps nor counts as covering
row chrome for selection. Chunk-error tiles hit-test before messages during
error → valid transition frames.
