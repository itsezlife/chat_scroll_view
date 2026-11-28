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
| `ChatOutbox<M>` | The facade. `send(chatId, plannedSend, payload:)` and `sendText` make one publish job per send, after slow mode and the chat's limits let it through (a refusal reaches `onDenied` and makes no job); `idStrategy(chatId)` is the chat's id strategy, which places each accepted message's row; `sendInFlight(chatId)` is on while one of the chat's messages is sending; `byClientMessageId(chatId, id)` matches the server's echo of the host's own message, so the host inserts no twin row; `isFreshOutgoing(chatId, id)` answers true once per message the user just sent, for the host's row appearance; `takeSendOrigin(mediaItemId)` answers an item's send origin once; `registerSender(sender)` makes the host's sender the chats' publisher; `cancel(chatId, id)` and `cancelItem(chatId, id, itemId)` cancel a message or one of its items (see Cancel); `pendingFor(chatId)` reads a chat's outgoing messages back from the engine's jobs after a restart; `debugSnapshot(chatId)` describes what it holds. |
| `OutgoingMessageSender<M>` | The host's transport: `send(OutgoingSendRequest)` once per attempt, with the chat, the `clientMessageId` (the idempotency key), the decoded payload, each item's remote references and, under `SequentialServerIds`, `proposedId`. |
| `OutgoingSendAnswer<M>` | What the server said: `sent` (`OutgoingSendResult(serverMessageId, serverKeys, payloadAsStored, missing)`), `reuploadItems(ids)`, `conflict(nextId, missing)`, `rejected(reason, retryable)` or `denied(action, reason)`. |
| `OutgoingSent<M>` | What `onSent` hands the host for a published message: its id from now on, the row to replace (`rowAt`), the payload as sent and as stored, the server keys. |
| `OutgoingMessage` | Chat id, `clientMessageId` (its identity), its current position in the provisional tail, its items (`OutgoingItem`: `MediaItemId` and local `ContentKey`), status and payload bytes. |
| `OutgoingIdStrategy` | The `allocate` / `rebase` seam of one chat's provisional tail: `allocate` places a new row, `incoming`, `publishStart`, `fail`, `retry`, `remove`, `removeAll` and `confirm` move it, each move one `rebaseTail`. It writes through `OutgoingTailTarget` (`OutgoingTailTarget.of(dataSource)`). A host may supply its own, held to `OutgoingIdStrategyContract` (`testing.dart`). |
| `SequentialServerIds` | For a server with one sequential id counter per chat that accepts a proposed id only if it is the next one: `proposedId` is `tip+1`, read at publish. |
| `LocalIds` | For global or UUID server ids: the host numbers rows with local ids (`nextIncomingId` for an incoming message) and keeps the server id in its model. `appendIncoming` puts incoming messages after the outgoing rows, which then stop moving. |
| `OutgoingStatus` | `preparing`, `uploading`, `publishing`, `sent`, `failed(OutgoingFailure)`, `cancelled`. |
| `OutgoingFailure` | The closed set of reasons: `network`, `rejected(reason)`, `denied(CapabilityAction)`, `sourceLost`, `tooLarge`, `unknown`. |
| `OutgoingPayloadCodec<M>` | The host's message model to bytes and back, a `dart:convert` `Codec`; the outbox stores bytes only. |
| `OutgoingSendItem` | The host's answer for one attach item: its local `ContentKey`, its `MediaKey` and where its bytes come from (`PublishSource`). |
| `OutgoingCancelOutcome` | What a cancel did: `cancelled`, `itemDropped`, `pending` (the server's answer is in flight), `tooLate` (the server accepted), `dropped` (a repeat), `unknown`. |
| `OutgoingCancelled`, `OutgoingItemDropped` | What `onCancelled` and `onItemDropped` hand the host: the cancelled message and whether its row left the tail; the message without the item, the item and its index. |
| `OutboxTransfers` | What the outbox uses of mpx's `Transfers`: `publish`, `watchJobs`, `registerPublisher`, and the owner's `cancel`, `removeItem` and `commit`. `OutboxTransfers.of(transfers)` wraps the host's facade; `FakeOutboxTransfers` (`testing.dart`) scripts job states and runs a registered publisher as the engine does. `RecordingOutgoingSender` (`testing.dart`) answers from a script. |
| `OutboxDebugSnapshot` | The strategy and tip, the tail row by row, the publisher, the send in flight and counters, as `toMap()`; no user content. |
| `OutboxOp` | The `outbox` diagnostics operations. |

## Host contract

| Duty | How |
| --- | --- |
| Make the outbox | `ChatOutbox(transfers: OutboxTransfers.of(transfers), codec:, itemOf:, idStrategyOf:, rowOf:, capabilitiesOf:, feedback:)` in the composition root. |
| Choose the ids | `idStrategyOf(chatId)` returns the chat's strategy over its data source: `SequentialServerIds(chatId:, tail: OutgoingTailTarget.of(dataSource))` or `LocalIds(…)`. Set the data source's `identityOf` to answer a row's client message id. |
| Build the row | `rowOf(message, payload)` returns the host's row for an accepted message, at `message.position`. |
| Hand incoming messages | An incoming message whose id falls inside the provisional tail goes to `idStrategy(chatId).incoming([...])`; when it answers false, insert it as usual. |
| Register the sender | `registerSender(sender)` once at start; jobs wait at their publish stage until then, after a restart too. |
| Restore after a restart | `await pendingFor(chatId)` for each chat that may hold outgoing messages, before the chat's first send of the run: each message the engine still holds gets a fresh row (sending ones first, then failed ones, each in creation order). A job of an earlier run waits at its publish stage until its chat is restored. Pass `localKeyOf(mediaKey)` (the inverse of the media key `itemOf` gives) to restore media items, and `undecodableRowOf(message)` for the row of a message whose payload the codec cannot read: it reads as failed, and without that builder it is left out. |
| Settle a sent row | `onSent(sent)` (a `ChatOutbox` argument) runs inside the publish call: replace the row at `sent.rowAt` with the confirmed message (`updateMessage`, a message `identityOf` answers null for), from `payloadAsStored` when given (the rich-text reconcile). With `rowAt` null the row has left; place the confirmed message at `sent.position` when the history reaches it. Address a provisional row by its current position (`positionOf`). |
| Follow a cancel | `onCancelled(cancelled)`: the row has left the tail; when `rowRemoved` is false (a row an appended message settled), remove the row at `message.position`. `onItemDropped(dropped)`: drop the item from the row at `message.position`. Both fire for the status control's cancel too, which reaches the outbox through the jobs. |
| Offer Retry and Delete | For a `failed` message the menu calls `retry(chatId, id)` and `delete(chatId, id)`. Whether a denial offers Retry is the host's per-platform choice; an `undecodable` answer means only Delete helps. For `failed(sourceLost)` ask the user for the file again and pass its bytes: `retry(chatId, id, sources: {itemId: SourceBytes.blob(file)})`. Delete is followed by `onCancelled`, as a cancel is. |
| Answer the server | Return a conflict or a replay with the confirmed messages between the tip and the server's id in `missing` when you have them, so the row can move to the server's id; return a server denial as `denied(action, reason)`, not a rejection. |
| Resolve attach items | `itemOf(item, form)` returns the item's keys (the media key through the content assets' key mapping) and its source: a preparation input with its intent, a prepared file, or `remote`. |
| Pass the chat's capabilities | `capabilitiesOf(chatId)` returns the listenable the chat's other consumers read; the outbox checks slow mode and the limits against it before each job. |
| Fold the send in flight | Put `sendInFlight(chatId)` into the chat's capabilities as `slowMode.pending`, so the composer and the picker hold the next send. |
| Hand the send origins | Pass the picker's rects by item order with the send (`send(..., origins:)`), and the outbox's `takeSendOrigin` to the media state as its one-shot origin lookup. |
| Set up the transfer envelope | The system envelope that keeps uploads going in the background is `mpx_transfer`'s, set up by the host there: its notification's strings, the iOS `Info.plist` entries, the Android permissions and the Play Console declaration (that package's README, "Android" and "iOS"). The outbox only reads what the jobs do (see System envelope). |
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

## Publishing

The outbox registers the host's sender as `chat.send`. Each call from the
engine moves the row to `tip+1` and asks the sender, proposing `tip+1` read
then:

| The sender answers | The engine hears | The outbox does |
| --- | --- | --- |
| `sent` at the proposal | `published(payloadAsStored, serverKeys)` | confirms the row, calls `onSent`; the job completes as `sent` |
| `sent` at another id (a replay) | `published` | moves the row to that id (after `missing`) and confirms it, or takes it out when it cannot reach it |
| `reuploadItems(ids)` | `reuploadItems` | the engine uploads them once more and calls again |
| `conflict(nextId, missing)` | nothing yet | places `missing` before the row and sends again in the same call; the third conflict is `rejected(chat.conflict, retryable)` |
| `rejected(reason)` | `rejected(reason)` | `failed(rejected(reason))` |
| `denied(action, reason)` | `rejected(chat.denied:<action>)` | `failed(denied(action))` and one `onDenied` |
| a throw | the publisher's error | `failed(unknown)` |

Codes starting with `chat.` are the outbox's own.

A job's state is the message's status: `preparing`, `uploading` and
`publishing` as they are, `completed` as `sent`, `failed` with its closed
reason; a paused job and one waiting for its publisher read as `uploading`
or `publishing` by how far its items got.

## Cancel

| The user cancels | The outbox does |
| --- | --- |
| the message (`cancel`) | cancels the job; status `cancelled`; the message is Absent and its row leaves the tail |
| one item of an album (`cancelItem`) | the item leaves the job; the rest publish |
| the only item, or the last one left, with no text | cancels the job, as above |
| the last item, with text | the item leaves; the text publishes alone, after the chat's other sending messages |
| an item's upload, from a cell's status control | reads the item's removal from the jobs and applies the rows above (a job left empty waits for the outbox, its owner) |

While the server's answer to the message's publish is in flight a cancel
waits for it (`pending`): an accept leaves the message sent, any other
answer cancels it. A cancel of a sent message is too late (`tooLate`); the
host deletes it as any sent message. A repeated cancel of a message, or of
one item, changes nothing (`dropped`). A cancelled message's
`clientMessageId` is never issued again; under `SequentialServerIds` the
next message may take its row's position.

## Failed, retry, delete

| Event | The outbox does |
| --- | --- |
| the job fails | status `failed(reason)`, the reason one of `network`, `rejected(code)`, `denied(action)`, `sourceLost`, `tooLarge`, `unknown`; any item's failure fails the message; the row sinks below every sending row, failed rows in creation order |
| a later row publishes | it moves to `tip+1`, above the failed rows, and proposes `tip+1` |
| `retry` after a prepare or upload failure | the failed items prepare or upload again, from the parts they journaled |
| `retry` after a publish failure | publish again only, with the same client message id |
| `retry` | the job joins the end of the chat's ordering group, and the row the end of the sending rows |
| `delete` | cancels the job; the message is Absent and its row leaves the tail |

A repeated retry changes nothing (`dropped`) until the message fails
again; a repeated delete changes nothing either.

## System envelope

| The envelope | The outbox does |
| --- | --- |
| the system ends it (an OS time limit, expiry, a low-memory kill), and its jobs pause `systemInterrupted` | by default keeps each message sending in its stage; it goes on once the app is in the foreground and the job resumes |
| the same, with `ChatOutbox(deleteOnSystemInterruption: true)` | cancels each job and deletes its message, as a cancel does |
| the user cancels all from its notification or the system's progress UI | reads the jobs' removal (it did not cancel them) and deletes every outgoing message among them, their rows leaving in one `rebaseTail` per chat |
| the app is force quit | nothing: the next start's `pendingFor` reads the jobs back and they resume |

`deleteOnSystemInterruption` is false on every platform. A message whose
server answer is in flight when its job is cancelled waits for it, as a
cancel does: an accept leaves it sent. A sent message stays sent when its
job leaves.

## Send origin

The picker hands each item's on-screen thumbnail rect with the planned
send, by the item's order in it (null for an item it did not show). The
outbox keys the rects by the items' `MediaItemId`s, the ones it issues or
the host's, and `takeSendOrigin` answers each once, then null. An origin
nobody takes goes when its message is sent or cancelled, or
`ChatOutbox.sendOriginLifetime` (5 s) after the send. Neither the picker
nor the media cells depend on the outbox: the lookup is a plain
`Rect? Function(MediaItemId)`.

## Identity and order

A row's id is a position in the provisional tail, `tip+1 … tip+k`, and moves
when an incoming message takes it. The message's identity is its
`clientMessageId`: look a message up by it, never by its row's id.

Sending rows keep creation order; a row that starts publishing moves to
`tip+1`; failed rows sit below every sending row, in creation order, so a
failed message is always at the bottom of the chat; a retried row joins the
end of the sending rows. A cancelled row's position may be taken by the
next row; confirmed ids are never reused. Rows the data source puts before
the tail on its own (a range fetch returning rows inside it) move the
strategy's positions and tip with them.

## Diagnostics

Every path reports through `ChatDiagnostics.current` (`content_model`) under
the `outbox` category. No event and no snapshot carries the payload, its
bytes or anything decoded from it; the payload is reported by its length.
