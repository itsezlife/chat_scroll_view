---
okf_version: "0.1"
---

# Chat Scroll Architecture

OKF knowledge bundle for the anchor-based chat viewport. Read this set
**before** implementing scroll, layout, day headers, or animations.

Feature specs under `specs/` are incremental contracts; ADRs under
`docs/adr/` define ID and position policy. This bundle is the **runtime
constitution**.

Format: [Open Knowledge Format (OKF) v0.1](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md).

## Mental model

All scroll geometry is derived from exactly two fields on
`ChatScrollController`: `anchorMessageId` (layout origin) and
`anchorPixelOffset` (viewport-Y of that message’s **top edge**). There is no
global content height, no `minScrollExtent` / `maxScrollExtent`, and no absolute
`ScrollPosition.pixels`. Layout fans children out from the anchor; Tier-1 scroll
only mutates the offset and repositions cached layers. Boundaries are local
geometric pins on the oldest/newest **built** rows when the data source reports
`reachedOldest` / `reachedNewest`.

**Sign convention (anchor-relative, opposite of Flutter `ScrollPosition`):**
positive delta increases `anchorPixelOffset` → content moves down → older
messages are revealed.

## Foundation

* [Coordinate Model](./01-coordinate-model.md) - Anchor vs `ScrollPosition`; scroll band
* [Invariants](./02-invariants.md) - Hard rules — what must never be violated
* [Layers](./03-layers.md) - Widget / Element / RenderObject / headless

## Pipelines

* [Layout Pipeline](./04-layout-pipeline.md) - `performLayout` step-by-step
* [Tier-1 Scroll](./05-tier1-scroll.md) - Ticker path, physics, paint vs layout
* [Boundaries](./06-boundaries.md) - Pins, overscroll, reverse, pads

## Subsystems

* [Data Source and IDs](./07-data-source-and-ids.md) - Chunks, absent, fetch, boundaries
* [ChatScrollElement](./08-chat-scroll-element.md) - Slots, `invokeLayoutCallback`, skip-rebuild
* [Day Groups and Headers](./09-day-groups-and-headers.md) - `startsDay`, bucket, floating header, fade
* [Navigation and Tail](./10-navigation-and-tail.md) - `jumpTo`, alignment, follow-tail

## Animation and catalogs

* [Animation Integration](./11-animation-integration.md) - Close/far path; writer ownership
* [Function Reference](./12-function-reference.md) - Exhaustive function catalog
* [Known Limitations](./13-known-limitations.md) - Documented debt (not fixes)

## Host integration

* [Host Chrome Insets](./14-host-chrome-insets.md) - Reserved vs overlay; listenables into `topPadding` / `bottomPadding`

## Reading order

Full pass: concepts **01 → 13** in order.

Before animation work: **01 → 02 → 04 → 05 → 06 → 11**, plus **§18 absent
build exclusion**, **§19 band-stable delete recovery**, and **§20 short content**.

## Related (outside this bundle)

* [CONTEXT.md](../../CONTEXT.md) — ubiquitous language used in this bundle
* [ADR 001: Message ID Scheme](../adr/001-message-id-scheme.md)
* [ADR 002: Position Model](../adr/002-position-model.md)

## How to use this when implementing features

1. Name which phase writes `anchorMessageId` / `anchorPixelOffset`.
2. List which core steps that phase suspends (renormalize, nav-align, clamp).
3. Do not introduce a second coordinate system or a second pin writer.
4. Prefer extending an existing writer phase over a one-off compensate/fix.

See [Animation Integration](./11-animation-integration.md) for the writer
ownership table and [Known Limitations](./13-known-limitations.md) for
current gaps that must not be papered over with unrelated hacks.

## Primary source files

| Area | Path |
|------|------|
| Render / layout / scroll | `lib/src/chat_widgets/render_chat_scroll_view.dart` |
| Element / lazy inflate | `lib/src/chat_widgets/chat_scroll_element.dart` |
| Public widget | `lib/src/chat_widgets/chat_scroll_view.dart` |
| Anchor / nav API | `lib/src/chat_scroll/chat_scroll_controller.dart` |
| Data / chunks | `lib/src/chat_scroll/chat_data_source.dart`, `chat_scroll_chunk.dart` |
| Floating header math | `lib/src/chat_scroll/chat_floating_header_controller.dart` |
| Animate | `lib/src/chat_scroll/chat_animator.dart` |
| Physics | `lib/src/chat_scroll/chat_scroll_physics.dart` |
