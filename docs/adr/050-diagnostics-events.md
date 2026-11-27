# ADR 050: Diagnostics events

Every chat package reports what it does as structured **diagnostics
events**: a level, a category, a closed operation, correlation ids and a few
numeric or short fields. One contract, `ChatDiagnostics` / `ChatEvent`, lives
in `content_model`, so chat packages emit through the shared leaf (only
`chat_capabilities` takes a new edge to it). The
policy is the one the bytes cache already uses: `silent` by default,
`developer` for `dart:developer` logging, `onEvent` for host routing. No
package logs user content. The example keeps the events in an on-disk ring
buffer with a Logs screen and an export, and device checks attach an
exported log.

**Status**: Accepted (2026-11-26, maintainer; decided in the
message-media-transfers map, ticket 27)  
**Date**: 2026-11-26  
**Relates to**: [ADR 020](020-package-topology.md) (rule 9 amended: `chat_capabilities` → `content_model`),
[ADR 023](023-data-layering-and-persistence.md) (`content_model` as the shared leaf),
[ADR 030](030-testing-policy.md) (fakes in `testing.dart`),
[ADR 041](041-engine-trace-seam.md) (timeline traces),
[ADR 047](047-message-media.md), [ADR 048](048-outgoing-messages.md),
[ADR 049](049-chat-capabilities.md) (the emitting packages),
mpx ADR 0012 (`MpxDiagnostics`, the media side of the same model)

Specs: the Diagnostics sections of `.scratch/chat-capabilities/spec.md` and
`.scratch/message-media-display/spec.md`; the other chat specs add theirs.

## Context

Outgoing messages, uploads, rebases, capabilities and media layout run mostly
out of sight: across restarts, in background envelopes, between the engine
and the host. Device checks of those paths need to show what happened, in
which order, for which message, and where it went wrong. The packages had no
shared way to say so; the bytes cache had its own `BytesDiagnostics` with a
policy and a typed event, and the media side's example had a log journal.
Diagnostics added after the fact miss the paths that matter.

## Decided

### Event

| Area | Decision |
| ---- | -------- |
| Shape | `ChatEvent`: `time`, `level`, `category`, `op`, correlation ids, `fields`, optional `error` and `stackTrace`. |
| Levels | `trace`, `debug`, `info`, `warning`, `error`. |
| Categories | A closed set: `capabilities`, `media`, `linkPreview`, `outbox`, `rebase`, `save`, and the others the chat specs add. A category is added by amending this ADR. |
| Operations | `content_model` declares only the operation contract, a `DiagnosticOp` interface (a stable `name`). Each emitting package keeps its own closed enum implementing it (for example `denied`, `layoutComputed`, `resolveCancelled`, `rebaseTail`), so the shared leaf knows no package's operations. An operation is what happened, never a free-form message. |
| Correlation ids | Optional strings: `chatId`, scroll id (the engine's message id), `clientMessageId`, `MediaItemId` (its string form), `MediaKey` (its stable string). They let one message or one item be followed through every package and into mpx's events. |
| Fields | Numbers, booleans, enum names and short strings: sizes, counts, durations, attempts, reasons, codes. |
| No user content | Never message text, captions, file names, URL paths, queries or fragments, tokens or credentials. A URL is reported by its host only. |

### Policy and sinks

| Area | Decision |
| ---- | -------- |
| Policy | `ChatDiagnostics`, in the shape of the bytes cache's `BytesDiagnostics`: `silent()` (the default), `developer()` (`dart:developer` log, one name per category), `onEvent(callback)` (the host routes events). |
| Reach | Process-wide: `ChatDiagnostics.current`, set once by the host at start, as `BytesDiagnostics.current` is; packages read it at the call site and take no diagnostics parameter. Tests that change it restore it (the packages' tests share one process). |
| Cost | `silent` costs one level check per call site; fields are built only after the check passes. |
| Host callback | Must not throw; a throw is caught inside the report so diagnostics never fail the path they describe. |
| Release | Packages send nothing anywhere themselves. A release host may keep `warning` and `error` through `onEvent`, for example into a crash reporter. |
| Testing | `RecordingDiagnostics` in `content_model`'s `testing.dart` records every event; a test installs it as `ChatDiagnostics.current` and restores the previous policy in its tear-down. Every issue tests the events of its paths through it. |
| Bridge | The host bridges mpx's `MpxDiagnostics` and the bytes cache's `BytesDiagnostics` into the same journal, so one log holds a message from the composer to the upload. |

### Inspection and traces

| Area | Decision |
| ---- | -------- |
| Snapshots | Stateful packages expose a debug description without user content: `capabilities.debugDescribe()` for chat capabilities, `outbox.debugSnapshot(chatId)` for the outbox (ADR 048). |
| Traces | Timeline sections follow [ADR 041](041-engine-trace-seam.md): compiled in only by `--dart-define=chat_scroll_view.trace=…`, enum names under `chat_scroll_view.<section>`, empty in the default build. Each package keeps its own internal section enum under that namespace. |

### On device (the example)

| Area | Decision |
| ---- | -------- |
| Journal | A ring buffer on disk (default 20 MiB), written in batches and flushed at once on `warning` and `error`, so the minutes before a kill survive. |
| Logs screen | Filters by category, level and correlation id, including "logs of this message" opened from a message; export of a file through the share sheet. |
| Device checks | A device check result attaches an exported log; a scenario without a log is not checked. |

### How specs and issues absorb it

Every code path emits the events of its category; an error without an event
is a defect. Each chat spec carries a Diagnostics table (category, operation,
level, fields, correlation ids). Each issue's acceptance includes its events,
tested with `RecordingDiagnostics`.

## Why

- One contract in the shared leaf lets every chat package emit with one new
  edge at most, and one vocabulary lets one log follow a message across
  packages.
- Closed operations and correlation ids make logs filterable and testable;
  free-form strings are neither.
- The bytes cache's policy shape is already understood by hosts and costs one
  check when off.
- A ring buffer on disk is the only record of what happened before a kill or
  a background expiry.
- Keeping user content out makes a log safe to export and share.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| A diagnostics package of its own | A new edge into every chat package for a handful of types; `content_model` is already the shared leaf |
| A diagnostics parameter on every controller | Threads one value through every constructor for no gain; the host sets one policy per process |
| Every category's operations in `content_model` | The shared leaf would change with every package's paths |
| Free-form log strings (`print`, a logger per package) | Not filterable by message, not testable, easy to leak content |
| Packages writing to a crash reporter or a file | Routing is the host's; packages stay free of sinks |
| Diagnostics added after the features | The paths that need them most would be the last to get them |
| Logging URLs or text for context | Leaks user content into exported files |

## Consequences

- `content_model` gains `ChatDiagnostics` (with `current`), `ChatEvent`,
  the category set, the `DiagnosticOp` interface and the correlation ids,
  with `RecordingDiagnostics` in `testing.dart`.
- `chat_capabilities`, `message_media`, `chat_outbox`, `chat_composer`,
  `attach_sheet`, `panel_shell` and the root engine emit their categories'
  events. `chat_capabilities` takes a `content_model` edge for it
  ([ADR 020](020-package-topology.md) rule 9, amended); no other edge
  changes.
- The example gains the on-disk journal, the Logs screen with correlation
  filters and export, and the bridges from `MpxDiagnostics` and
  `BytesDiagnostics`.
- Every chat spec gains a Diagnostics table; every issue tests its events;
  device checks attach a log.

## Amendment (2026-11-26, accepted): `jobId` and the `overlay` category

Decided with the maintainer while slicing the chat-outbox,
draft-options-overlay and media-save specs (acceptance-3 §5 in the
message-media-transfers map).

| Area | Decision |
| ---- | -------- |
| Correlation ids | `ChatCorrelation` gains an optional `jobId`: the publish job's id for the outbox, the save job's id for a save. Chat events for a job then join mpx's events for the same job, which carry `jobId` too. |
| Categories | `overlay` joins the set, for the draft options overlay and the chrome scrim. The scrim's operations are `overlay` operations prefixed `scrim`, not a category of their own. |
| The leaf | `chrome_foundation` stays a leaf and emits nothing: `ChromeScrim` reports its phases (captured, still ready, still skipped, dismissed, cancelled, disposed, capture failed) through a callback its owner passes, and the owner emits the `scrim…` events with an `owner` field. |

## Amendment (2026-11-27, accepted): the `diagnostics` category

Found implementing the example's log journal (chat-capabilities ticket 17):
the journal reports its own steps (opened, restored with a count, exported,
a store that failed) and is tested through `RecordingDiagnostics`, so they
need a category, and none of the set fits.

| Area | Decision |
| ---- | -------- |
| Categories | `diagnostics` joins the set, for the host's diagnostics pipeline itself: a journal opening, restoring what a previous run kept, exporting, a store failing. |
| Loops | A journal never reports from the path that records an event: a store failure is reported once, after the store is switched off, so the report cannot fail and report again. |
