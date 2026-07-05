---
type: Architecture Reference
title: ChatScrollElement
description: Lazy child inflation, slot namespaces, invokeLayoutCallback, skip-rebuild cache, and absent-slot build exclusion contract.
tags: [element, slots, skip-rebuild, absent]
timestamp: 2026-07-05T00:00:00Z
resource: lib/src/chat_widgets/chat_scroll_element.dart
---

# ChatScrollElement

`ChatScrollElement` is the `RenderObjectElement` for `ChatScrollView`. It
implements `ChatChildManager`, which `RenderChatScrollView` drives during
layout — the same lazy-child idea as `SliverMultiBoxAdaptorElement`, without
the sliver protocol.

## Slot namespaces

Four disjoint identity spaces so insert/remove/visit never confuse children:

| Slot type | Key | Element map | Render attachment |
|-----------|-----|-------------|-------------------|
| Message | `int` message id | `_children` (`SplayTreeMap`) | `insertChild` / `removeChild` |
| Chunk error | `_ChunkErrorSlot(chunkIndex)` | `_chunkErrors` | `insertChunkError` / `removeChunkError` |
| Floating header | `_ChatSlot.floatingHeader` | `_floatingHeader` (0–1) | `floatingHeader =` |
| Overlay | `_ChatSlot.overlay` | `_overlay` (0–1) | `overlay =` |

**Invariant:** `moveRenderObjectChild` always asserts — children never change
slots. Chunk-error tiles must not share the message-id map (avoids overwrite
when a chunk recovers from error).

## `invokeLayoutCallback` contract

Render side (`_invokeChildManagerLayout`):

```
invokeLayoutCallback → insideLayoutCallback = true → fn() → false
```

Every `ChatChildManager` method asserts `insideLayoutCallback`.

**Must not:** call any manager method from the ticker, gestures, or async
callbacks. Lazy inflation is only legal during layout inside
`invokeLayoutCallback` (Flutter rule).

Used by: fan-out, GC, floating header rebuild, overlay mode, jump-fetch stale
drop.

## `buildChild`

```
buildChild(id, {startsNewDay, groupBucket, runLayout})
```

1. Read `getMessage(id)`, `statusOf(id)`.
2. If `statusOf(id).isAbsent`, deactivate any existing child, clear skip-cache
   maps, and return `null` without calling `messageBuilder` (confirmed-absent
   ids must not inflate widgets or selection chrome). Render also skips before
   `buildChild`; this step is defense in depth.
3. Skip-rebuild fast path → return existing `RenderBox`.
4. Else `owner!.buildScope` → `updateChild(existing, _buildWidget(...), id)`.
5. On success: store element + cache; on null: remove maps.

`runLayout` is resolved by `RenderChatScrollView` via `ChatSenderRunLayout.resolve`
(live present neighbors + optional `groupBy` bucket). The element does **not**
walk neighbors itself — same pattern as `startsNewDay`.

### `_buildWidget`

- Optional `Directionality` override + `Builder` so builders see the same
  direction as chrome.
- Optional `SelectableMessage` wrap (selection chrome) — **only for ids that
  pass the absent exclusion gate**; wrapping zero-size shrink output for absent
  ids still produces selectable ghost rows.
- If `startsNewDay && separator != null && message != null && groupBucket != null`
  → `DatedMessage(separator, body)`; else `RepaintBoundary` + body.
- Separator is **outside** selection so date chrome is never tinted.

The element does **not** compute day boundaries — it only consumes
`startsNewDay` / `groupBucket` from the render object. See
[Day Groups and Headers](./09-day-groups-and-headers.md).

## Skip-rebuild cache

| Map | Key meaning |
|-----|-------------|
| `_builtMessage[id]` | `IChatMessage?` — **identity** via `identical` |
| `_builtStatus[id]` | `ChatMessageStatus` |
| `_builtStartsDay[id]` | `bool` |
| `_builtRunLayout[id]` | `MessageRunLayout` — value equality |

**Hit:** existing element **and** status equal **and** `startsNewDay` equal
**and** `runLayout` equal **and** `identical(message)`.

**Miss → full `updateChild`.**

**Cleared entirely** on widget `update` when builders / selection /
`textDirection` change. Use `==` on builder tear-offs, not `identical`
(otherwise every parent rebuild drops the cache).

**Per-id cleared** on remove / failed update / `forgetChild`.

**Must not:** mutate a message in place without replacing the instance —
rebuild will be skipped. **Must not** compute neighbor-dependent chrome inside
`messageBuilder` without consuming `runLayout` — neighbor changes after delete
or insert will not invalidate the cache otherwise.

Inherited widgets (Theme, etc.) still rebuild via normal element dependencies.
Width changes are handled by subsequent `child.layout()`, not this cache.

## Other manager methods

| Method | Role |
|--------|------|
| `removeChildren(ids)` | Deactivate message elements; clear skip-cache |
| `buildFloatingHeader(bucket, date)` | `null` args remove header; else separator builder |
| `buildChunkError(chunkIndex, firstId, lastId)` | One tile per failed chunk; `Builder` reads DS at build time |
| `removeChunkErrors` | Symmetric to `removeChildren` |
| `buildOverlay(kind)` | `none` / `loading` / `empty`; render owns active kind |

Chunk-error `Builder` reads `_widget.dataSource` at **build** time so retry
targets the current source and error/attempt refresh without re-keying.

## Mount / update

- `mount`: sets `renderObject.childManager = this`.
- `update`: propagates to `updateRenderObject`; may drop skip-cache and
  `invalidateFloatingHeader` when separator builder or `textDirection` changes.
