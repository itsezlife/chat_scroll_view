---
type: Architecture Reference
title: Data Source and IDs
description: Chunks, absent slots, fetch contract, boundaries, and getMessage versus statusOf.
tags: [data, chunks, absent, ids]
timestamp: 2026-07-04T00:00:00Z
resource: lib/src/chat_scroll/chat_data_source.dart
---

# Data Source and IDs

Authoritative policy lives in:

- [ADR 001: Message ID Scheme](../adr/001-message-id-scheme.md)
- [ADR 002: Position Model](../adr/002-position-model.md)

This concept summarizes runtime contracts the viewport depends on.

## ID model

- Signed integers, immutable after assignment, unique per conversation.
- Negative ids are valid (arithmetic `>>` for chunk index).
- **Per-conversation sequential** allocation; deletion gaps only.
- Global auto-increment / random ids are unsupported (break absent marking,
  fan-out, scrollbar).

Integer adjacency **is** scroll adjacency: fan-out uses `id±1` with absent
skips.

## Chunks

| Constant | Value | Meaning |
|----------|-------|---------|
| `kBits` | `6` | Shift width |
| `kSize` | `64` | Messages per chunk |

- `chunkIndex = messageId >> kBits` (arithmetic)
- `firstId = chunkIndex << kBits`
- `lastId = firstId + kSize - 1`

Bit-shift literals must appear **only** in `ChatScrollChunk`. Everyone else
uses `chunkOf` / `firstIdOf`.

Each chunk stores: `messages[64]`, `status`, `lastError`, `failedAttempts`,
per-slot absent flags (`0`/`1`) with an O(1) absent-slot count,
`lastAccessTick` (LRU).

## Fetch

`fetchRange({fromId, toId})` — subclass returns a **sparse** list of existing
messages only (omit missing ids; never embed null placeholders).

### Full-chunk boundary invariant

`fromId` must be `firstIdOf(chunkOf(fromId))` and `toId` must be the last id
of `chunkOf(toId)`. Verify with `ChatScrollChunk.isFullChunkRange`.

Partial ranges corrupt absent-marking: null slots outside the partial range
are incorrectly marked permanently absent.

Post-success pass: every null slot in fetched chunks → `markAbsentSlot`.

## Absent slots

- Flag N is non-zero (`1`) iff `messages[N] == null` **and** server confirmed
  absent. Storage is per-slot flags plus an absent-slot count — not a packed
  integer bitset (unreliable as a 64-slot container on web/dart2js).
- Non-null slot must never have its absent flag set.
- `upsertMessage` / `upsertMessages` **must** `clearAbsentSlot` before write
  (realtime insert at a previously-absent id).
- `invalidate()` clears all absent flags (`clearAbsentMask`) so re-fetch can
  restore messages.
- Fully-absent chunks (`isFullyAbsent`, count == 64) are skipped in O(1)
  during fan-out.

Fan-out helpers: `_nextNonAbsentIdDown` / `_nextNonAbsentIdUp` — terminate with
`bound±1`, never `bound` (infinite-loop hazard). See
[Invariants](./02-invariants.md).

## Boundaries

| Field | Meaning |
|-------|---------|
| `oldestKnownId` / `newestKnownId` | Extent of known id span |
| `reachedOldest` / `reachedNewest` | Conversation edge known |

Atomic update: `seedBoundaries(...)` — notifies only if something changed.

Derived:

- `isEmpty`: both reached, both ids null (confirmed empty).
- `isInitialLoading`: no ids yet and neither reached.

**Must not:** on boundary deletes, update fields piecemeal — use
`seedBoundaries` atomically.

## `getMessage` vs `statusOf`

| API | Returns |
|-----|---------|
| `getMessage(id)` | Message instance, or `null` if chunk missing **or** slot empty |
| `statusOf(id)` | Chunk missing → `dirty`; absent flag → `absent`; else chunk status |

**`getMessage(id)` is not “previous / next message.”** Null means absent **or**
unloaded. Neighbor logic must walk past confirmed-absent ids (same idea as
fan-out helpers). Today `_startsDay` only checks `id - 1` — see
[Known Limitations](./13-known-limitations.md).

## Notifications

- Typed listeners (`addDataListener`), not `ChangeNotifier`.
- `upsertMessage` / `upsertMessages` already call `notifyDataChanged`.
- Subclasses must **not** call it again after `super`.
- `notifyDataChanged` is `@nonVirtual`.

## Viewport integration

- Data change → `markNeedsLayout`.
- Boundary change → publish mirrored ids on controller + layout + semantics.
- Fetch poll / LRU eviction: `ChatChunkFetchScheduler` after layout completes.
- While `!reachedOldest`, fan-out oldest bound is `0`, not `oldestKnownId`
  (pagination deadlock otherwise).
