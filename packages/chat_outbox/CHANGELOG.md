# Changelog

All notable changes to `chat_outbox` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Added

- The package ([ADR 048](../../docs/adr/048-outgoing-messages.md)), on
  `content_model` and `chat_capabilities`.
- `OutgoingMessage` and `OutgoingItem`; `OutgoingStatus` (`preparing`,
  `uploading`, `publishing`, `sent`, `failed`, `cancelled`) and the closed
  `OutgoingFailure` reasons, equal by value, with stable `name`s.
- `OutgoingPayloadCodec<M>`, the host's model to payload bytes, a
  `dart:convert` `Codec`.
- `ChatOutbox` with `byClientMessageId` and the one-shot `isFreshOutgoing`,
  which report `echoMatched` and `freshOutgoingTaken` (`OutboxOp`).
- `debugSnapshot(chatId)`: `OutboxDebugSnapshot` with every section
  declared (strategy, tip, tail rows with their items, publisher, send in
  flight, counters) and a JSON-encodable `toMap()`. Sections the outbox does
  not know yet are null.
- `ChatOutbox<M>.send` and `sendText`: one publish job per planned send or
  text (tag `chat:<chatId>:<clientMessageId>`, publisher `chat.send`, the
  client message id as the idempotency key, the chat as the ordering group,
  `system` durability, `wholeJob`), the media item ids issued from the
  client message id and the item index unless the host gives its own.
  Slow mode and the chat's limits are checked first; a refusal reaches the
  host's `onDenied` (consumer `outbox`) and makes no job.
- `sendInFlight(chatId)`, for the host to fold into `slowMode.pending`.
- The status projected from the chat's jobs (`watchJobs` by the chat's tag
  prefix); the snapshot's jobs section (job id, state, stage) and its send
  in flight and accepted count.
- `OutgoingSendItem`, the host's keys and source for an attach item.
- `OutboxTransfers`, the seam over mpx's `Transfers`, and
  `FakeOutboxTransfers` in `testing.dart`.
- `OutboxOp`: `accepted`, `refusedBeforeJob`, `jobCreated`,
  `statusChanged`, `sendInFlight`.
- Send origins: `send(..., origins:)` takes the picker's thumbnail rects
  by item order and keys them by the items' `MediaItemId`s;
  `takeSendOrigin(id)` answers each once. An untaken origin goes when its
  message is sent or cancelled, or after `ChatOutbox.sendOriginLifetime`.
  The snapshot's items say whether their origin is still held.
  `OutboxOp`: `sendOriginStored`, `sendOriginTaken`, `sendOriginDropped`.
- The package now depends on `attach_model`, `listen`, `mpx_core` and
  `mpx_transfer`.
- Id strategies: the `OutgoingIdStrategy` seam (`allocate`, `incoming`,
  `publishStart`, `fail`, `retry`, `remove`, `confirm`) over
  `OutgoingTailTarget` (`OutgoingTailTarget.of` a `ChatDataSource`), with
  `SequentialServerIds` (`proposedId`, `tip+1` at publish) and `LocalIds`
  (`nextIncomingId`, `appendIncoming`). Each move is one `rebaseTail`.
- `ChatOutbox.idStrategy(chatId)`; an accepted send places its row through
  the chat's strategy, and lookups and the snapshot read the row's current
  position. The snapshot holds the strategy, the tip and the rebase counts
  by reason.
- `OutboxOp`: `positionAllocated`, `tailRebased`, `incomingAppended`;
  `accepted` names the strategy.
- `testing.dart`: `OutgoingIdStrategyContract`, `FakeOutgoingTail` and
  `FakeOutgoingIdStrategy`.
- The package now depends on the root `chat_scroll_view`, and on
  `flutter_test` for `testing.dart`.
- The publisher: `OutgoingMessageSender<M>`, `OutgoingSendRequest`,
  `OutgoingSendAnswer` (`sent` as `OutgoingSendResult`, `reuploadItems`,
  `conflict`, `rejected`, `denied`) and `OutgoingSent`.
  `ChatOutbox.registerSender` registers the host's sender as `chat.send`;
  each attempt moves the row to `tip+1` and proposes it; a conflict sends
  again within the call, at most three conflicts; a replay at another id
  moves the row there; a denial fails the message as `denied` with one
  `onDenied`; the host settles a published row in `onSent`.
- `OutgoingIdStrategy.proposedId` (null under `LocalIds`) and
  `OutgoingTailTarget.positionOf`: a strategy reads its tail's first
  position back from the rows, so rows a range fetch put before the tail
  move it (`tailRebased` reason `fetch`).
- `OutboxTransfers.registerPublisher`; `FakeOutboxTransfers` runs a
  registered publisher; `RecordingOutgoingSender` in `testing.dart`.
- The snapshot's publisher registration, attempts per row and conflicts.
- `OutboxOp`: `publisherRegistered`, `publishAttempt`, `publishConflict`,
  `publishConflictExhausted`, `published`, `replayRebased`,
  `reuploadRequested`, `rejected`, `denied`, `senderFailed`,
  `payloadDecodeFailed`.
- Cancel: `ChatOutbox.cancel(chatId, id)` cancels the message's job and
  makes it Absent, its row leaving the tail; `cancelItem(chatId, id,
  itemId)` drops one item (the rest publish), cancels a message whose only
  or last item goes with no text, and publishes the text alone when it has
  some. A cell's status control cancel reaches the outbox through the
  jobs and applies the same rules. A cancel waits while the server's
  answer is in flight, and one the server's accept beat is too late: the
  message stays sent. Both answer an `OutgoingCancelOutcome`; the host
  hears `onCancelled` (`OutgoingCancelled`) and `onItemDropped`
  (`OutgoingItemDropped`). A burst cancels once, and a cancelled client
  message id is never issued again.
- `OutboxTransfers.cancel`, `removeItem` and `commit`; `FakeOutboxTransfers`
  records them and scripts a status control cancel with `cancelUpload`.
- The snapshot's `cancels`, `itemsDropped` and `cancelsTooLate` counters.
- `OutboxOp`: `cancelled`, `itemDropped`, `cancelTooLate`,
  `awaitingOwner`, `actionDropped`.

### Changed

- `ChatOutbox` takes the transfer seam, the payload codec, the item
  resolver, the chat's id strategy (`idStrategyOf`) and the host's row
  builder (`rowOf`). `OutgoingMessage.position` is required: every
  accepted message has its row.
