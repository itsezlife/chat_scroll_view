# ADR 001: Message ID Scheme

**Status**: Accepted  
**Date**: 2026-06-28  
**Context**: ChatScrollView enhancement plan Phase 0

## Context

The scroll engine paginates messages in fixed-size **chunks** keyed by message id. Chunk index math uses a bit shift that must remain encapsulated. Integrators supply message ids from backends that may delete, edit, or tombstone messages. Incorrect assumptions about id mutability or chunk layout cause broken pagination, anchor drift, and duplicate layout notifications.

This ADR records the **system-wide ID contract** that all phases of the enhancement plan depend on.

## Decision

### 1. Integer IDs with immutability contract

- Message ids are **signed integers** (`int` in Dart).
- Each id is **unique within a conversation** and **immutable after first assignment**.
- No backend operation — delete, edit, reaction, tombstone — may **renumber** or replace an id for an existing logical message.
- When the message at a boundary is removed, update `ChatDataSource` boundaries via `seedBoundaries` with new boundary ids; do not recycle ids.

### 2. Negative IDs are valid

- Negative ids are first-class. Example: `chunkOf(-1) == -1` because Dart's `>>` is **arithmetic** right shift.
- Integrators MUST NOT assume ids are non-negative or contiguous.

### 3. Chunk encoding (internal)

| Constant | Value | Meaning |
|----------|-------|---------|
| `kBits` | `6` | Shift width |
| `kSize` | `64` | Messages per chunk (`1 << kBits`) |

- `chunkIndex = messageId >> kBits` (arithmetic)
- `firstId = chunkIndex << kBits`
- `lastId = firstId + kSize - 1`

**Encapsulation rule**: The literals `>> 6` / `<< 6` (or equivalent bit-shift by `kBits`) MUST appear **only** in `ChatScrollChunk` (`lib/src/chat_scroll/chat_scroll_chunk.dart`). Application and widget code MUST use `ChatScrollChunk.chunkOf` / `firstIdOf` / chunk properties — never open-coded shifts.

### 4. Sparse chunks

- A chunk may contain **null slots** when ids in `[firstId, lastId]` were deleted or never fetched.
- `firstId` / `lastId` describe the chunk's **index range**, not the set of live messages.
- `getMessage(id)` returns `null` for missing slots; debug builds assert slot bounds.
- Conversation-order neighbors skip confirmed-absent ids via
  `getPreviousPresentMessage` / `getNextPresentMessage` — not by changing
  `getMessage` semantics. See [07-data-source-and-ids](../architecture/07-data-source-and-ids.md).

### 5. ChatMessageStatus as extension type

`ChatMessageStatus` is an `extension type` over `int` (bitfield):

| Name | Value | Bit |
|------|-------|-----|
| `valid` | `0` | — |
| `dirty` | `1` | `1 << 0` |
| `error` | `2` | `1 << 1` |
| `fetching` | `4` | `1 << 2` |

Bits `1 << 3` … `1 << 31` are **reserved**.

**Footgun**: A raw `int` can be passed where `ChatMessageStatus` is expected with **no runtime error**. Public APIs document this; integrators should use named constants.

**Decision**: Keep `extension type` for zero allocation overhead on the hot path. Migration to a sealed class is deferred.

### 6. ChatDataSource notification contract

- `upsertMessage` / `upsertMessages` on the base class call `notifyDataChanged()` once.
- Subclasses MUST NOT call `notifyDataChanged()` after delegating to `super.upsertMessage` / `super.upsertMessages`.
- `notifyDataChanged` is `@nonVirtual` — cannot be overridden.

### 7. Boundary updates on delete

When a delete removes the message currently at `oldestKnownId` or `newestKnownId`, the subclass MUST call `seedBoundaries` **atomically** with updated ids and `reachedOldest` / `reachedNewest` flags as appropriate.

## Consequences

### Positive

- Single documented contract for all enhancement PRs.
- Chunk math stays testable and encapsulated (PR-0B adds parametric tests).
- `@nonVirtual` prevents future override bugs on notification dispatch.

### Negative

- Integrators with renumbering backends must map to stable ids before `ChatDataSource`.
- Extension-type footgun remains until a future API revision.

## Compliance

```bash
# Bit-shift only in chat_scroll_chunk.dart
grep -rE '>>\s*6|<<\s*6' lib/ --include='*.dart' | grep -v chat_scroll_chunk.dart
# expect empty
```

## References

- `lib/src/chat_scroll/chat_scroll_chunk.dart`
- `lib/src/chat_scroll/chat_scroll_common.dart` (`IChatMessage`, `ChatMessageStatus`)
- `lib/src/chat_scroll/chat_data_source.dart`
- `specs/010-message-id-contract/`

## Amendment (2026-11-26, accepted): provisional tail positions

Accepted with [ADR 048](048-outgoing-messages.md) (outgoing messages).

An outgoing message is shown before the server has given it an id. It sits
after the newest server message, at `tip+1 … tip+k`: the **provisional
tail**. When an incoming message takes `tip+1`, the outgoing rows move up by
one; when a row starts publishing it moves to `tip+1`; failed rows sink to
the bottom of the tail.

- **Provisional tail slots are positions, not identity.** The id of a row in
  the provisional tail names where the row is, not which message it is.
  Moving such a row is not a renumbering under §1.
- **The outgoing message's identity is the host's `clientMessageId`**, as a
  streamed reply's identity is the host's ([ADR 039](039-streaming-message-body.md)).
  The host supplies `identityOf(message)` returning it for a provisional row,
  and matches the server's answer and echo by it, never by slot.
- **`rebaseTail` is the only sanctioned move.** `ChatDataSource.rebaseTail`
  (`rebaseTail({required List<Object> order, List<IChatMessage> insert =
  const []})`) takes a new order of the provisional rows' identities plus
  the confirmed messages inserted before them (a reorder, not only a shift)
  in one atomic write, with one notification and its own mutation, carrying
  row-keyed state to the new ids (a moved row's text selection is cleared),
  and applying a range fetch's rows inside the tail through the same move
  instead of writing them into provisional slots. An identity left out of
  `order` leaves the tail in the same write, which is how a cancelled or
  deleted outgoing row goes. The tail is computed from `identityOf` at each
  call and its chunks are kept from eviction. Removing a provisional row and inserting a different
  message at its id through the ordinary calls is still a recycled id and
  is still forbidden.
- **"Do not recycle ids" (§1) applies to server-confirmed ids and to
  host-local ids.** Under sequential server ids a provisional position is a
  position the next message may take: when an outgoing message is cancelled,
  the next message may take its position. The cancelled message's
  `clientMessageId` is not reused.
- Once the server confirms a message, its row id is a Message ID under §1:
  unique and immutable from then on.
- Every id outside the provisional tail keeps the contract above unchanged.
