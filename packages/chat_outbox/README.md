# chat_outbox

The **outbox**: a message the user sends is an **outgoing message**, shown at
once as a row after the newest server message, until the server confirms
it. The outbox keeps no store of its own; it projects the publish jobs, so a
restart reads the same messages back.

Decision: [ADR 048](../../docs/adr/048-outgoing-messages.md). Diagnostics:
[ADR 050](../../docs/adr/050-diagnostics-events.md).

## Types

| Type | Role |
| --- | --- |
| `ChatOutbox<M>` | The facade. `send(chatId, plannedSend, payload:)` and `sendText` make one publish job per send, after slow mode and the chat's limits let it through (a refusal reaches `onDenied` and makes no job); `idStrategy(chatId)` is the chat's id strategy, which places each accepted message's row; `sendInFlight(chatId)` is on while one of the chat's messages is sending; `byClientMessageId(chatId, id)` matches the server's echo of the host's own message, so the host inserts no twin row; `isFreshOutgoing(chatId, id)` answers true once per message the user just sent, for the host's row appearance; `debugSnapshot(chatId)` describes what it holds. |
| `OutgoingMessage` | Chat id, `clientMessageId` (its identity), its current position in the provisional tail, its items (`OutgoingItem`: `MediaItemId` and local `ContentKey`), status and payload bytes. |
| `OutgoingIdStrategy` | The `allocate` / `rebase` seam of one chat's provisional tail: `allocate` places a new row, `incoming`, `publishStart`, `fail`, `retry`, `remove` and `confirm` move it, each move one `rebaseTail`. It writes through `OutgoingTailTarget` (`OutgoingTailTarget.of(dataSource)`). A host may supply its own, held to `OutgoingIdStrategyContract` (`testing.dart`). |
| `SequentialServerIds` | For a server with one sequential id counter per chat that accepts a proposed id only if it is the next one: `proposedId` is `tip+1`, read at publish. |
| `LocalIds` | For global or UUID server ids: the host numbers rows with local ids (`nextIncomingId` for an incoming message) and keeps the server id in its model. `appendIncoming` puts incoming messages after the outgoing rows, which then stop moving. |
| `OutgoingStatus` | `preparing`, `uploading`, `publishing`, `sent`, `failed(OutgoingFailure)`, `cancelled`. |
| `OutgoingFailure` | The closed set of reasons: `network`, `rejected(reason)`, `denied(CapabilityAction)`, `sourceLost`, `tooLarge`, `unknown`. |
| `OutgoingPayloadCodec<M>` | The host's message model to bytes and back, a `dart:convert` `Codec`; the outbox stores bytes only. |
| `OutgoingSendItem` | The host's answer for one attach item: its local `ContentKey`, its `MediaKey` and where its bytes come from (`PublishSource`). |
| `OutboxTransfers` | What the outbox uses of mpx's `Transfers`: `publish` and `watchJobs`. `OutboxTransfers.of(transfers)` wraps the host's facade; `FakeOutboxTransfers` (`testing.dart`) scripts job states. |
| `OutboxDebugSnapshot` | The strategy and tip, the tail row by row, the publisher, the send in flight and counters, as `toMap()`; no user content. |
| `OutboxOp` | The `outbox` diagnostics operations. |

## Host contract

| Duty | How |
| --- | --- |
| Make the outbox | `ChatOutbox(transfers: OutboxTransfers.of(transfers), codec:, itemOf:, idStrategyOf:, rowOf:, capabilitiesOf:, feedback:)` in the composition root. |
| Choose the ids | `idStrategyOf(chatId)` returns the chat's strategy over its data source: `SequentialServerIds(chatId:, tail: OutgoingTailTarget.of(dataSource))` or `LocalIds(…)`. Set the data source's `identityOf` to answer a row's client message id. |
| Build the row | `rowOf(message, payload)` returns the host's row for an accepted message, at `message.position`. |
| Hand incoming messages | An incoming message whose id falls inside the provisional tail goes to `idStrategy(chatId).incoming([...])`; when it answers false, insert it as usual. |
| Confirm a row | `idStrategy(chatId).confirm(id)` answers the position the confirmed message replaces the row at (`updateMessage`). Address a provisional row by its current position (`positionOf`). |
| Resolve attach items | `itemOf(item, form)` returns the item's keys (the media key through the content assets' key mapping) and its source: a preparation input with its intent, a prepared file, or `remote`. |
| Pass the chat's capabilities | `capabilitiesOf(chatId)` returns the listenable the chat's other consumers read; the outbox checks slow mode and the limits against it before each job. |
| Fold the send in flight | Put `sendInFlight(chatId)` into the chat's capabilities as `slowMode.pending`, so the composer and the picker hold the next send. |
| Dispose | `dispose()` when the outbox goes; the jobs run on in the engine. |

## The publish job

| Field | Value |
| --- | --- |
| `tag` | `chat:<chatId>:<clientMessageId>` |
| `items` | one per attach item, in order; the item id is the `MediaItemId`'s string form, `<clientMessageId>:<index>` unless the host gives its own; empty for a text |
| `payload` | the host's model through its codec |
| `publisher` | `chat.send` |
| `idempotencyKey` | the `clientMessageId` |
| `durability`, `failurePolicy`, `orderingGroup`, `hold` | `system`, `wholeJob`, the chat id, not used |

A job's state is the message's status: `preparing`, `uploading` and
`publishing` as they are, `completed` as `sent`, `failed` with its closed
reason; a paused job and one waiting for its publisher read as `uploading`
or `publishing` by how far its items got.

## Identity and order

A row's id is a position in the provisional tail, `tip+1 … tip+k`, and moves
when an incoming message takes it. The message's identity is its
`clientMessageId`: look a message up by it, never by its row's id.

Sending rows keep creation order; a row that starts publishing moves to
`tip+1`; failed rows sit below every sending row, in creation order, so a
failed message is always at the bottom of the chat; a retried row joins the
end of the sending rows. A cancelled row's position may be taken by the
next row; confirmed ids are never reused.

## Diagnostics

Every path reports through `ChatDiagnostics.current` (`content_model`) under
the `outbox` category. No event and no snapshot carries the payload, its
bytes or anything decoded from it; the payload is reported by its length.
