# ADR 002: Position Model — Raw Message IDs as Scroll Positions

**Status**: Accepted
**Date**: 2026-06-29
**Context**: ChatScrollView enhancement plan — sparse message ID gaps feature

## Context

The scroll viewport positions every visible row using raw message IDs as scroll
positions: chunk index = `messageId >> kBits`, fan-out advances `id++` / `id--`, and
scrollbar progress is derived from content height (absent slots render at zero height).
This model implicitly assumes message IDs form a dense-enough sequence within each
conversation — i.e. that IDs are allocated per-chat sequentially.

> **Review note — design constraint, not a vulnerability**  
> Per-chat sequential ID allocation is a **mandatory integrator constraint**, not a
> runtime security boundary. The library does not cryptographically validate ID schemes;
> backends that use global auto-increment, random, or otherwise non-sequential ids per
> chat will get **incorrect absent-slot marking, scrollbar math, and navigation** (see
> [Why non-sequential IDs fail](#why-non-sequential-ids-fail)) rather than memory
> corruption or privilege escalation. Detect incompatibility at integration time via
> [Known Incompatibilities](#known-incompatibilities) and
> [Non-Compliant Backends](#non-compliant-backends--detection-and-fallback).

Two classes of real-world data can introduce gaps **within** the supported model:

1. **Batch deletions** — a moderator or sync process removes many consecutive messages,
   leaving permanent gaps in the per-chat ID sequence.
2. **Large cumulative gaps** — a long-lived conversation where many individual deletions
   have occurred over time.

Globally shared auto-increment ID sequences across unrelated chats are out of scope;
the existing storage model uses per-chat composite primary keys `(chat_id, id)` matching
the mainstream chat storage design.

## Decision

**Raw message IDs continue to serve as scroll positions.**

This is the correct and durable model given per-chat sequential ID allocation. The
absent-slot patch (PR-E0) corrects permanent skeleton rendering and scrollbar accuracy
for all deletion gap sizes within the per-chat sequential ID constraint.

A cursor-based fetch API (`fetchBefore`/`fetchAfter`/`fetchByIds`) is explicitly not
adopted. With per-chat sequential IDs, gaps are bounded by deletion counts and
`fetchRange` with absent-slot marking already covers the full problem space. Adding a
cursor API would introduce a breaking `ChatDataSource` interface change without solving
a real problem in this ID model.

## Mandatory Backend Constraints

Integrators MUST satisfy all of the following:

1. **Per-conversation IDs**: Message IDs are allocated per conversation (per `chat_id`),
   not from a single global auto-increment sequence shared across all chats.
2. **Sequential allocation**: IDs are assigned sequentially within each conversation.
   Non-sequential allocation (e.g. random IDs, globally sparse IDs) is incompatible.
3. **Full-chunk fetch invariant**: `fetchRange(fromId, toId)` MUST be called with
   `fromId == ChatScrollChunk.firstIdOf(chunkIndex)` and `toId == chunk.lastId`.
   Partial-range fetches within a chunk corrupt absent-slot marking.
4. **No renumbering**: Message IDs are immutable after assignment per ADR 001. This
   ADR does not modify that constraint.

## Why non-sequential IDs fail

Absent-slot marking, fan-out, and scrollbar height all treat **integer adjacency as
scroll adjacency** within a conversation:

| Mechanism | Sequential-id assumption |
|-----------|--------------------------|
| Post-fetch absent marking | Every null slot `s` in `[oldestKnownId, newestKnownId]` with no returned message is **permanently absent** — a deleted or never-assigned id at position `s`. |
| Fan-out (`id++` / `id--`) | The next row above/below in the viewport is at `id ± 1`. |
| Scrollbar / content height | Each id in the known boundary span contributes either a laid-out row or **zero height** (absent). |
| Chunk indexing | `chunkOf(id) = id >> kBits` — ids far apart in value land in different chunks even when they are adjacent messages in chat order. |

### Example: global or sparse IDs

Suppose a single chat stores messages at ids `1_000_001` and `1_000_002` (global
auto-increment) while `oldestKnownId = 1_000_001` and `newestKnownId = 1_000_002`:

- Chunk `15625` spans ids `1_000_000`–`1_000_063`. After `fetchRange`, slots
  `1_000_000` and `1_000_003`–`1_000_063` are marked **absent** even though most
  were never valid chat positions — only deletions should create absent holes.
- Fan-out from `1_000_002` walks `1_000_001`, then `1_000_000`, `999_999`, …
  through millions of phantom ids instead of the prior message in conversation order.
- `jumpTo(1_000_001)` and progressive read logic keyed off `id + 1` no longer align
  with server message order.

**This is incorrect behavior, not an exploit.** The fix is backend-side: allocate
ids per conversation (dense `1..N` or `1..N` with deletion gaps only), as in
[ADR 001](001-message-id-scheme.md). There is no in-library adapter for global or
random per-chat ids.

**Supported gaps** are holes *within* a per-chat sequential sequence (deletions,
never-assigned ids after the last message) — not arbitrary sparse ids chosen from a
global namespace.

## Navigation to absent IDs

`ChatScrollController.jumpTo` and `animateTo` accept any integer message id,
including ids confirmed absent (`ChatMessageStatus.absent`). The calls complete
without error, but **the viewport does not visually navigate to a deleted id**:

- Absent slots contribute **zero height** in layout — there is no row to align
  with the viewport band.
- The anchor message id is still set to the requested id; fan-out and boundary
  clamping position content relative to the nearest **built** non-absent
  neighbors.
- Users tapping a deep-link to a deleted message will see nearby surviving
  messages, not an empty viewport or a skeleton.

**Integrator guidance**:

1. Before programmatic navigation, call `dataSource.statusOf(targetId).isAbsent`.
   If absent, navigate to the nearest known-present id instead (e.g. the next
   lower non-absent id from a server hint).
2. Do not rely on `anchorMessageId` alone after `jumpTo` — verify visible
   content via `visibleRange` or `statusOf`.
3. `animateTo` follows the same rule: animation may play, but absent targets
   never produce a visible landing row.

## Known Incompatibilities

| Backend pattern | Status |
|-----------------|--------|
| Per-chat sequential IDs, no deletions | ✅ Fully supported |
| Per-chat sequential IDs, any deletion gaps | ✅ Fully supported after PR-E0 |
| Single global auto-increment across all chats in one view | ❌ Unsupported |
| Non-monotonic or random IDs per chat | ❌ Unsupported |

## Non-Compliant Backends — Detection and Fallback

This library does not silently adapt to backends that violate the mandatory
constraints above. Integrators should detect incompatibility early and choose
one of the following paths.

### Per-chat sequential IDs violated (global or random IDs)

**Symptom**: Scrollbar progress, fan-out, and absent-marking behave
unpredictably — large phantom gaps, permanent skeletons, messages hidden as
“absent”, or runaway fetch loops. See [Why non-sequential IDs fail](#why-non-sequential-ids-fail).

**This is a design / integration mismatch**, not a security defect. The library
cannot distinguish “id 42 was deleted” from “id 42 was never part of this chat’s
sequence” without the sequential-allocation guarantee.

**Fallback**: Migrate to per-conversation ID allocation before integrating
`ChatScrollView`. There is no in-library cursor or sparse-index fallback for
this model; a different scroll architecture is required.

### Full-chunk `fetchRange` invariant violated

**Symptom**: Partial-range requests (e.g. `fetchRange(70, 90)` inside chunk 1
instead of `64..127`) cause null slots *outside* the requested sub-range to be
incorrectly marked absent, hiding messages that were never fetched.

**Detection**: In debug builds, `ChatDataSource` asserts
`ChatScrollChunk.isFullChunkRange(fromId, toId)` before absent-marking runs.
Violations also emit a `dev.log` warning (level 900) in all build modes.
Subclasses that return message IDs outside `[fromId, toId]` trip a debug
assertion on upsert.

**Fallback**:

1. **Preferred** — Fix the integrator to always request full chunk boundaries
   (`firstIdOf(chunkIndex)` through `chunk.lastId`). The viewport's fetch
   scheduler already does this; custom `fetchRange` callers must match.
2. **If partial fetch is unavoidable** — Do not use absent-slot marking for
   that chunk: return all messages the server knows about for the full chunk in
   a single call, or invalidate and re-fetch the whole chunk after partial
   loads. Partial fetches and absent marking are mutually incompatible by design.

### `fetchRange` returns null placeholders instead of omitting absent IDs

**Symptom**: None expected — the API is `Future<List<IChatMessage>>`, not a
nullable list. Absent IDs are omitted from the return value; the framework
marks remaining null slots absent after the fetch resolves.

**Fallback**: Return only present messages. Never insert null entries into the
list; the absent-marking pass handles missing IDs.

### Empty conversation or unreachable backend

**Symptom**: Chunks stay in `error` or `fetching`; UI shows chunk-error tiles
or shimmers.

**Fallback**: Surface `ChatDataSource.retryChunk` / `invalidate()` to the user;
ensure `seedBoundaries` reflects server-reported `oldest_id` / `newest_id` when
the conversation is empty so the viewport does not fan out into unbounded ID
space.

## Consequences

### Positive

- No breaking API change to `ChatDataSource` — all existing integrators continue to work.
- `fetchRange` contract is retained; per-chat sequential ID guarantee makes cursor API
  unnecessary overhead.
- PR-E0 absent-slot patch is the complete and durable solution for all supported backends.
- Explicit documented constraints prevent silent failures for incompatible backends.

### Negative

- Integrators with globally-shared auto-increment ID sequences cannot use this library
  without migrating to per-chat IDs.

## References

- ADR 001: Message ID Scheme (`docs/adr/001-message-id-scheme.md`)
- PR-E0 absent-slot patch (`specs/015-sparse-message-gaps/`)
- Enhancement plan (`enhancement_spec.md`)
