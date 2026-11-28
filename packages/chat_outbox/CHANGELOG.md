# Changelog

All notable changes to `chat_outbox` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Added

The package ([ADR 048](../../docs/adr/048-outgoing-messages.md)): outgoing
messages over mpx publish jobs. It depends on `attach_model`,
`chat_capabilities`, the root `chat_scroll_view` (for `rebaseTail`),
`content_model`, `listen`, `meta`, `mpx_core` and `mpx_transfer`; `flutter_test`
is for `testing.dart` only.

**Messages and status**

- `OutgoingMessage` (chat id, `clientMessageId`, position in the
  provisional tail, `OutgoingItem`s, status, payload bytes) and
  `OutgoingStatus` (`preparing`, `uploading`, `publishing`, `sent`,
  `failed`, `cancelled`), equal by value. `OutgoingFailure` is closed:
  `network`, `rejected`, `denied`, `sourceLost`, `tooLarge`, `unknown`.
- `OutgoingPayloadCodec<M>`, the host's model to payload bytes, a
  `dart:convert` `Codec`.
- The status is projected from the chat's jobs (`watchJobs` by the tag
  prefix `chat:<chatId>:`). A paused job and one waiting for its publisher
  read as `uploading` or `publishing` by how far its items got.
  `ChatOutbox(onStatusChanged:)` hands the host each change after the send,
  so a time pill and an error badge redraw when the row does not move.

**Sending**

- `ChatOutbox<M>.send` and `sendText`: one publish job per planned send or
  text (tag `chat:<chatId>:<clientMessageId>`, publisher `chat.send`, the
  client message id as the idempotency key, the chat as the ordering group,
  `system` durability, `wholeJob`). Media item ids are the client message
  id plus the item index unless the host gives its own. Slow mode and the
  chat's limits are checked first; a refusal reaches `onDenied` (consumer
  `outbox`) and makes no job.
- `sendInFlight(chatId)`, for the host to fold into `slowMode.pending`.
- `OutgoingSendItem`, the host's keys and source for an attach item
  (`itemOf`, with `localKeyOf` for a restart).
- `OutboxTransfers`, the seam over mpx's `Transfers`
  (`OutboxTransfers.of`), and `FakeOutboxTransfers` in `testing.dart`.

**The publisher**

- `OutgoingMessageSender<M>`, `OutgoingSendRequest`, `OutgoingSendAnswer`
  (`sent` as `OutgoingSendResult`, `reuploadItems`, `conflict`, `rejected`,
  `denied`) and `OutgoingSent`. `ChatOutbox.registerSender` registers the
  host's sender as `chat.send`; each attempt moves the row to `tip+1` and
  proposes it. A conflict sends again within the call, at most three
  conflicts, then `rejected(chat.conflict, retryable)`. A replay at another
  id moves the row there. A denial fails the message as `denied` with one
  `onDenied`. The host settles a published row in `onSent`.
- `RecordingOutgoingSender` in `testing.dart`.

**Id strategies**

- `OutgoingIdStrategy` (`allocate`, `incoming`, `publishStart`, `fail`,
  `retry`, `remove`, `removeAll`, `confirm`, `proposedId`, `positionOf`) over
  `OutgoingTailTarget` (`OutgoingTailTarget.of` a `ChatDataSource`), with
  `SequentialServerIds` and `LocalIds` (`nextIncomingId`, `appendIncoming`).
  Each move is one `rebaseTail`. A strategy reads its tail's first position
  back from the rows, so rows a range fetch put before the tail move it.
- `ChatOutbox.idStrategy(chatId)`; an accepted send places its row through
  it, and lookups and the snapshot read the row's current position.
- `OutgoingIdStrategyContract`, `FakeOutgoingTail` and
  `FakeOutgoingIdStrategy` in `testing.dart`.

**Lookups**

- `byClientMessageId` matches the server's echo of the host's own message;
  `isFreshOutgoing` answers true once per message the user just sent.

**Cancel, failed, retry, delete**

- `cancel(chatId, id)` cancels the job and makes the message Absent, its
  row leaving the tail; `cancelItem(chatId, id, itemId)` drops one item (the
  rest publish), cancels a message whose last item goes with no text, and
  publishes the text alone when it has some. A cell's status control cancel
  reaches the outbox through the jobs and applies the same rules. A cancel
  waits while the server's answer is in flight, and one the server's accept
  beat is too late. Both answer an `OutgoingCancelOutcome`; the host hears
  `onCancelled` and `onItemDropped`. A burst cancels once, and a cancelled
  client message id is never issued again.
- A job that fails sinks its row below every sending row, the failed rows in
  creation order. `retry(chatId, id, {sources})` repeats only what failed
  (journaled uploads kept; a publish failure publishes again only), and the
  row joins the end of the sending rows; `sources` gives a lost source's
  bytes again. It answers `OutgoingRetryOutcome`; a burst retries once
  until the message fails again. `delete(chatId, id)` cancels as `cancel`.
- `OutboxTransfers.cancel`, `removeItem`, `commit`, `retry` and `retryItem`.

**Restart and the system envelope**

- `pendingFor(chatId)` reads the chat's outgoing messages back from its jobs
  at fresh tail positions (sending ones, then failed ones, each in creation
  order), each row built again from the decoded payload
  (`ChatOutbox(localKeyOf:, undecodableRowOf:)`). A payload the codec cannot
  read is failed (unknown); a job under the prefix that is not a message's
  is left alone. A job of an earlier run waits at its publish stage until
  its chat is restored. `OutboxTransfers.payloadOf` reads the job's payload.
- A job the system's end of the envelope paused (`paused(systemInterrupted)`)
  keeps its message sending and resumes;
  `ChatOutbox(deleteOnSystemInterruption: true)` deletes the message
  instead. A cancel of all from the envelope's notification deletes every
  outgoing message among its jobs, each chat's rows in one `rebaseTail`.

**Send origin and appearance**

- `send(..., origins:)` takes the picker's thumbnail rectangles by item
  order and keys them by the items' `MediaItemId`s; `takeSendOrigin(id)`
  answers each once. An untaken origin goes when its message is sent or
  cancelled, or after `ChatOutbox.sendOriginLifetime`.
- `OutgoingAppearancePolicy` (`android()`, `ios()`, `desktop()`,
  `platform()`) and the sealed `OutgoingAppearance` it resolves to
  (`slideUp`, `fadeScale` with `delayAt`, `flight`, `none`), reduce motion
  answering `none`. `ChatOutbox(appearance:)` and
  `appearanceOf(chatId, id, atBottom:, reduceMotion:)`, which answers once
  per fresh message and reads its items and held send origins.

**Diagnostics**

- `OutboxOp`, the `outbox` operations (see the README), and
  `debugSnapshot(chatId)`: `OutboxDebugSnapshot` with the strategy, the tip,
  the tail row by row with its items and job, the publisher registration,
  the send in flight and counters, and a JSON-encodable `toMap()`. No user
  content.
