---
type: Architecture Reference
title: Data Source and IDs
description: Chunks, absent slots, fetch contract, boundaries, getMessage versus statusOf, and directed neighbor lookup via getPreviousPresentMessage / getNextPresentMessage.
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
| `getMessage(id)` | Message instance at **this id**, or `null` if chunk missing **or** slot empty |
| `statusOf(id)` | Chunk missing → `dirty`; absent flag → `absent`; else chunk status |

**`getMessage(id)` is exact slot lookup — not “previous / next message.”** Null
means absent **or** unloaded. It must **never** auto-walk to a neighbor id:
direction is caller-defined (previous vs next), and substituting would return
a payload for the wrong id.

For conversation-order neighbors that skip confirmed-absent holes, use the
**directed** APIs below — not `getMessage(id ± 1)`.

## Neighbor lookup (`Present` = skip confirmed-absent)

Public integrator/viewport helpers :

| API | Direction | Id walk | Payload |
|-----|-----------|---------|---------|
| `getPreviousPresentMessage(id)` | Older (↓ id) | `_previousPresentId` within `[oldestKnownId, id)` | `getMessage(probe)` or `null` |
| `getNextPresentMessage(id)` | Newer (↑ id) | `_nextPresentId` within `(id, newestKnownId]` | `getMessage(probe)` or `null` |

**Why `Present` in the name:** the walk skips ids that are **confirmed absent**
(deleted, removal-staging, absent flag set). It does **not** mean “payload
guaranteed” — the probe id may still be unloaded (`dirty`), so the method can
return `null` even when a further neighbor exists.

**Why not `getPreviousMessage` / `getNextMessage`:** without `Present` /
`NonAbsent`, the name reads like `getMessage(id ± 1)` or an ambiguous
“whichever neighbor is closer.” Keep direction and absent-skip explicit.

Viewport fan-out uses the same idea internally:
`_nextNonAbsentIdDown` / `_nextNonAbsentIdUp` (see [Invariants](./02-invariants.md)).

**Do not** fold neighbor walks into `getMessage` — see
[Known Limitations](./13-known-limitations.md). Call sites (`_startsDay`, demo
sender-run) use `getPreviousPresentMessage` — not `getMessage(id ± 1)`.

## Notifications

- Typed listeners (`addDataListener`), not `ChangeNotifier`.
- `upsertMessage` / `upsertMessages` already call `notifyDataChanged`.
- Subclasses must **not** call it again after `super`.
- `notifyDataChanged` is `@nonVirtual`.

## CRUD mutations

Integrator **CRUD** (`insertMessage`, `insertMessages`, `updateMessage`,
`updateMessages`, `removeMessages`) emits typed [ChatMutation] subtypes via
`addMutationListener` before storage writes. Fetch and silent upsert never
invoke mutation listeners.

| Bulk add need | Call | Mutation |
|---------------|------|----------|
| Animation-eligible batch insert | `insertMessages` | `InsertBatchMutation` (ids ascending) |
| Silent cache merge | `upsertMessages` | none |

| Edit need | Call | Mutation |
|-----------|------|----------|
| Single or bulk integrator edit | `updateMessage` / `updateMessages` | `UpdateMutation` / `UpdateBatchMutation` — **never silent** |
| Fetch re-fetch refresh | `upsertMessages` | none (not an edit API) |

Foundation does **not** auto-classify reconnect or background batches — the
integrator chooses the API explicitly.

`RenderChatScrollView` mounts a mutation listener stub; extent springs and
**coverage override during deferred collapse layout** are deferred to the
animation follow-on spec.

## Viewport integration

- Data change → `markNeedsLayout`.
- Boundary change → publish mirrored ids on controller + layout + semantics.
- Fetch poll / LRU eviction: `ChatChunkFetchScheduler` after layout completes.
- While `!reachedOldest`, fan-out oldest bound is `0`, not `oldestKnownId`
  (pagination deadlock otherwise).
