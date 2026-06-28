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
