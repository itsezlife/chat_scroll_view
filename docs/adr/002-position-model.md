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

Two classes of real-world data can introduce gaps:

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

## Known Incompatibilities

| Backend pattern | Status |
|-----------------|--------|
| Per-chat sequential IDs, no deletions | ✅ Fully supported |
| Per-chat sequential IDs, any deletion gaps | ✅ Fully supported after PR-E0 |
| Single global auto-increment across all chats in one view | ❌ Unsupported |
| Non-monotonic or random IDs per chat | ❌ Unsupported |

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
