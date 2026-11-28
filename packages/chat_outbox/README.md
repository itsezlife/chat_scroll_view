# chat_outbox

The **outbox**: a message the user sends is an **outgoing message**, shown at
once as a row after the newest server message, until the server confirms
it. The outbox keeps no store of its own; it projects the publish jobs, so a
restart reads the same messages back.

Decision: [ADR 048](../../docs/adr/048-outgoing-messages.md). Diagnostics:
[ADR 050](../../docs/adr/050-diagnostics-events.md).
The example app is a working host: [its README](../../example/README.md#outgoing-messages-and-the-outbox-debug-panel)
and `example/lib/src/features/chat/outbox/`.

## Types

| Type | Role |
| --- | --- |
| `ChatOutbox<M>` | The facade. `send(chatId, plannedSend, payload:)` and `sendText` make one publish job per send, after slow mode and the chat's limits let it through (a refusal reaches `onDenied` and makes no job); `idStrategy(chatId)` is the chat's id strategy, which places each accepted message's row; `sendInFlight(chatId)` is on while one of the chat's messages is sending; `byClientMessageId(chatId, id)` matches the server's echo of the host's own message, so the host inserts no twin row; `isFreshOutgoing(chatId, id)` answers true once per message the user just sent, and `appearanceOf(chatId, id, …)` how that row appears; `takeSendOrigin(mediaItemId)` answers an item's send origin once; `registerSender(sender)` makes the host's sender the chats' publisher; `cancel(chatId, id)` and `cancelItem(chatId, id, itemId)` cancel a message or one of its items (see Cancel); `pendingFor(chatId)` reads a chat's outgoing messages back from the engine's jobs after a restart, and `settleFromHistory(chatId, id, serverId:)` settles one the server already had; `debugSnapshot(chatId)` describes what it holds. Chats and messages are named by `ChatId` and `ClientMessageId`, nominal strings. |
| `OutgoingMessageSender<M>` | The host's transport: `send(OutgoingSendRequest)` once per attempt, with the chat, the `clientMessageId` (the idempotency key), the decoded payload, each item's remote references and, under `SequentialServerIds`, `proposedId`. |
| `OutgoingSendAnswer<M>` | What the server said: `sent` (`OutgoingSendResult(serverMessageId, serverKeys, payloadAsStored, missing)`), `reuploadItems(ids)`, `conflict(nextId, missing)`, `rejected(reason, retryable)` or `denied(action, reason)`. |
| `OutgoingSent<M>` | What `onSent` hands the host for a published message: its id from now on, the row to replace (`rowAt`), the payload as sent and as stored, the server keys. |
| `OutgoingMessage` | Chat id, `clientMessageId` (its identity), its current position in the provisional tail, its items (`OutgoingItem`: `MediaItemId` and local `ContentKey`), status and payload bytes. |
| `OutgoingIdStrategy` | The `allocate` / `rebase` seam of one chat's provisional tail: `allocate` places a new row, `incoming`, `publishStart`, `fail`, `retry`, `remove`, `removeAll` and `confirm` move it, each move one `rebaseTail`; its getters (`tip`, `proposedId`, `positionOf`) only read, and `sync()` brings it up to rows a range fetch moved. It writes through `OutgoingTailTarget` (`OutgoingTailTarget.of(dataSource)`). A host may supply its own, held to `OutgoingIdStrategyContract` (`testing.dart`). |
| `SequentialServerIds` | For a server with one sequential id counter per chat that accepts a proposed id only if it is the next one: `proposedId` is `tip+1`, read at publish. |
| `LocalIds` | For global or UUID server ids: the host numbers rows with local ids (`nextIncomingId` for an incoming message) and keeps the server id in its model. `appendIncoming` puts incoming messages after the outgoing rows, which then stop moving. |
| `OutgoingStatus` | `preparing`, `uploading`, `publishing`, `sent`, `failed(OutgoingFailure)`, `cancelled`. |
| `OutgoingFailure` | The closed set of reasons: `network`, `rejected(reason)`, `denied(CapabilityAction)`, `sourceLost`, `tooLarge`, `unknown`. |
| `OutgoingPayloadCodec<M>` | The host's message model to bytes and back, a `dart:convert` `Codec`; the outbox stores bytes only. |
| `OutgoingSendItem` | The host's answer for one attach item: its local `ContentKey`, its `MediaKey` and where its bytes come from (`PublishSource`). |
| `OutgoingCancelOutcome` | What a cancel did: `cancelled`, `itemDropped`, `pending` (the server's answer is in flight), `tooLate` (the server accepted), `dropped` (a repeat), `unknown`. |
| `OutgoingCancelled`, `OutgoingItemDropped` | What `onCancelled` and `onItemDropped` hand the host: the cancelled message and whether its row left the tail; the message without the item, the item and its index. |
| `OutboxTransfers` | What the outbox uses of mpx's `Transfers`: `publish`, `watchJobs`, `registerPublisher`, and the owner's `cancel`, `removeItem` and `commit`. `OutboxTransfers.of(transfers)` wraps the host's facade; `FakeOutboxTransfers` (`testing.dart`) scripts job states and runs a registered publisher as the engine does. `RecordingOutgoingSender` (`testing.dart`) answers from a script. |
| `OutgoingAppearancePolicy`, `OutgoingAppearance` | How a fresh row appears per platform and the answer a row's situation resolves to (see Appearance). |
| `OutboxDebugSnapshot` | The strategy and tip, the tail row by row, the publisher, the send in flight and counters, as `toMap()`; no user content. |
| `OutboxOp` | The `outbox` diagnostics operations. |

## Host contract

| Duty | How |
| --- | --- |
| Make the outbox | `ChatOutbox(transfers: OutboxTransfers.of(transfers), codec:, itemOf:, idStrategyOf:, rowOf:, onSent:, capabilitiesOf:, feedbackOf:)` in the composition root. |
| Choose the ids | `idStrategyOf(chatId)` returns the chat's strategy over its data source: `SequentialServerIds(chatId:, tail: OutgoingTailTarget.of(dataSource))` or `LocalIds(…)`. Set the data source's `identityOf` to answer a row's client message id. |
| Build the row | `rowOf(message, payload)` returns the host's row for an accepted message, at `message.position`. |
| Say which rows are outgoing | Set `identityOf` on the chat's `ChatDataSource`: it answers a provisional row's `clientMessageId` and null for every other row. The data source reads the provisional tail through it, so `rebaseTail` needs nothing else. The outbox's `OutgoingTailTarget.of(dataSource)` is how a strategy writes. |
| Hand incoming messages | An incoming message whose id falls inside the provisional tail goes to `idStrategy(chatId).incoming([...])`; when it answers false, insert it as usual. |
| Register the sender | `registerSender(sender)` once at start; jobs wait at their publish stage until then, after a restart too. |
| Restore after a restart | `await pendingFor(chatId)` for each chat that may hold outgoing messages, before the chat's first send of the run: each message the engine still holds gets a fresh row (sending ones first, then failed ones, each in creation order), inserted with no self-insert follow, so a reader scrolled up stays put. A job of an earlier run waits at its publish stage until its chat is restored. Pass `localKeyOf(mediaKey)` (the inverse of the media key `itemOf` gives) to restore media items, and `undecodableRowOf(message)` for the row of a message whose payload the codec cannot read: it reads as failed, and without that builder it is left out. |
| Match fetched history | Once `pendingFor` answered, hand each message of fetched history whose client message id `byClientMessageId` answers for to `settleFromHistory(chatId, id, serverId:)`: the server stored it before the app went, the restored row leaves and the history's row is its one row, so it does not show twice until the job's replay answers. |
| Settle a sent row | `onSent(sent)` (a required `ChatOutbox` argument) runs inside the publish call: replace the row at `sent.rowAt` with the confirmed message, synchronously (`updateMessage`, a message `identityOf` answers null for), from `payloadAsStored` when given (the rich-text reconcile); a row left provisional would leave the chat at the tail's next move. With `rowAt` null the row has left, since it could not sit at the server's id (a peer's message or a fetch moved the tail past it while the call was out, or a replay at another id): place the confirmed message at `sent.position`, in the slot the move left unloaded, unless a fetch brought it there already, or when the history reaches it. Address a provisional row by its current position (`positionOf`). |
| Follow a cancel | `onCancelled(cancelled)`: the row has left the tail; when `rowRemoved` is false (a row an appended message settled), remove the row at `message.position`. `onItemDropped(dropped)`: drop the item from the row at `message.position`. Both fire for the status control's cancel too, which reaches the outbox through the jobs. |
| Draw the status | `onStatusChanged(message)` hears each change of a message's status after its send (the job moving on, a failure, a retry, the server's accept), with the message as it is now: the time pill and the error badge redraw on it, since a change need not move the row. A cancel is `onCancelled`'s. |
| Animate a fresh row | As a row is first built, `appearanceOf(chatId, id, atBottom:, reduceMotion:, policy:)` answers once how it appears (see Appearance), null for a row that is not fresh; the host animates its own row with the answer's values. On the web pass the policy of the moment, `OutgoingAppearancePolicy.web(compactTouch:)` from the live width class and input class. |
| Draw the time pill and the error badge | The pill reads the status: a clock while sending, one check on `sent`; the second check is the server's read state, which the host owns. A `failed` message shows an error badge by the time, and a tap or click on it opens the message menu through the viewport's selection facade. |
| Offer Retry and Delete | For a `failed` message the menu calls `retry(chatId, id)` and `delete(chatId, id)`. Whether a denial offers Retry is the host's per-platform choice; an `undecodable` answer means only Delete helps. For `failed(sourceLost)` ask the user for the file again and pass its bytes: `retry(chatId, id, sources: {itemId: SourceBytes.blob(file)})`. A retry is one more send unit: slow mode holds it as it holds a send (`refused`, with `onDenied(sendNow)`). Delete is followed by `onCancelled`, as a cancel is. |
| Say why a send was refused | Pass `feedbackOf: (chatId) => …` so a refusal before the job and a server denial reach that chat's `onDenied`, with the host's `denialText`, whichever chat is on screen. |
| Answer the server | Return a conflict or a replay with the confirmed messages between the tip and the server's id in `missing` when you have them, so the row can move to the server's id; return a server denial as `denied(action, reason)`, not a rejection. |
| Resolve attach items | `itemOf(item, form)` returns the item's keys (the media key through the content assets' key mapping) and its source: a preparation input with its intent, a prepared file, or `remote`. What only one send knows (the files prepared for it, the keys its payload names) goes with that send: `send(..., itemOf:)`. |
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
| `sent` at the proposal | `published(payloadAsStored, serverKeys)` | confirms the row where it sits at the proposal, or takes it out when a peer's message or a fetch moved it past while the call was out; calls `onSent`; the job completes as `sent` |
| `sent` at another id (a replay) | `published` | moves the row to that id (after `missing`) and confirms it, or takes it out when it cannot reach it |
| `reuploadItems(ids)` | `reuploadItems` | the engine uploads them once more and calls again |
| `conflict(nextId, missing)` | nothing yet | places `missing` before the row and sends again in the same call; the third conflict is `rejected(chat.conflict, retryable)` |
| `rejected(reason)` | `rejected(chat.rejected:<reason>)` | `failed(rejected(reason))` |
| `denied(action, reason)` | `rejected(chat.denied:<action>)` | `failed(denied(action))` and one `onDenied` |
| a throw | the publisher's error | `failed(unknown)` |

Every code of the chat publisher carries the `chat.` prefix, apart from the
engine's own reasons, so a server's rejection code reads back as that
rejection whatever it spells (`network` included), after a restart too.

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

## Appearance

`OutgoingAppearancePolicy` holds how a fresh row appears on each platform
(`android()`, `ios()`, `desktop()`, `web(compactTouch:)`, `platform()`, the
outbox's `appearance`) and resolves a row's situation to an
`OutgoingAppearance`. A policy's own row motions are `OutgoingRowMotion`s
(`slideUp`, `fadeScale`, `none`): a flight comes from a send origin only.

The web is not the desktop: a page takes its form from its window and its
input, live. A compact window used by touch moves as Android does (no
flight); any other window is still. `platform()` gives the web's wide form
on the web whatever the system, and the host passes the live one to
`appearanceOf`.

| | Android | iOS | Desktop |
| --- | --- | --- | --- |
| list at the bottom | `slideUp`: the rows translate up by the added height, 250 ms on `(0.199, 0.011, 0.279, 0.910)` | `flight` while an item holds its send origin (the media cells fly, the row stays still); otherwise as Android | `none` |
| list scrolled up | `fadeScale`: opacity 0 → 1 and scale 0.9 → 1 around the bubble centre, 250 ms, after `(1 − rowBottom / listHeight) · 100 ms` (`delayAt`) | the same | `none` |
| text-only message | as media | as media, never a flight | `none` |

Reduce motion answers `none`. `appearanceOf` reads the message's items and
held origins itself (asking leaves the origin for the cell), shares
`isFreshOutgoing`'s one-shot, and reports `rowAppeared`. The motion itself
is the host's, since it owns the row.

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
strategy's positions and tip with them, at its next `sync()`, which every
move and every outbox entry point runs first.

## Diagnostics

Every path reports through `ChatDiagnostics.current` (`content_model`) under
the `outbox` category, with `chatId` on every event and, where they exist,
`clientMessageId`, the row's scroll id, `MediaItemId`, `MediaKey` and the
publish job's `jobId`. No event and no snapshot carries the payload, its
bytes or anything decoded from it; the payload is reported by its length.
A server's rejection code is never logged, only its form.

| `OutboxOp` | Reports |
| --- | --- |
| `accepted`, `refusedBeforeJob`, `jobCreated`, `sendInFlight` | a send entering, a refusal before any job, the job's shape, the send in flight turning on or off |
| `statusChanged`, `echoMatched`, `freshOutgoingTaken`, `rowAppeared` | the status moving, a lookup by client message id, the one-shot flag, how a fresh row appeared |
| `positionAllocated`, `tailRebased`, `incomingAppended` | a row placed, a row moved (one event per moved row, with its reason: `incoming`, `publishStart`, `failedSink`, `retry`, `restart`, `removed`, `fetch`), `LocalIds` appending an incoming message |
| `publisherRegistered`, `publishAttempt`, `publishConflict`, `publishConflictExhausted`, `published`, `replayRebased`, `reuploadRequested`, `rejected`, `denied`, `senderFailed` | the `chat.send` publisher and what the sender answered; a conflict's or a replay's moves are `incoming` right after |
| `cancelled`, `itemDropped`, `cancelTooLate`, `awaitingOwner`, `actionDropped` | cancel, with its trigger, and the input guard on cancel, retry and delete |
| `failed`, `retried`, `deleted` | a failure with its closed reason, a retry, a delete |
| `restored`, `payloadDecodeFailed`, `foreignJob` | the restart query and what it could not read |
| `systemInterrupted`, `resumed`, `envelopeCancelAll` | the system envelope |
| `sendOriginStored`, `sendOriginTaken`, `sendOriginDropped` | the send origin hand-off |

The tail's moves in the engine are the root package's `rebase` operations.
The trace sections `chat_scroll_view.outbox.project` (one job update
projected) and `chat_scroll_view.outbox.publish` (one publisher call, the
conflict loop included) cost nothing in a default build.

## Snapshot

`debugSnapshot(chatId)` returns an `OutboxDebugSnapshot`, and `toMap()` its
JSON form. It has the same shape every time; a part the outbox does not
know yet is null.

| Part | Holds |
| --- | --- |
| `strategy`, `tip` | the chat's id strategy and its last confirmed position; null before the chat has one |
| `tail` | each provisional row in order: position, `clientMessageId`, status, failure, fresh, payload bytes, job id, job state, stage, attempts, and its items (`MediaItemId`, local key, media key, transfer state, whether its send origin is still held) |
| `publisherRegistered`, `sendInFlight` | whether the sender is registered, whether a send is in flight |
| `counters` | accepted, rebases by reason, conflicts, retries, cancels, items dropped, cancels too late, restores |

An external key is reported as `external`, never its id, which may be a URL.
Reading a snapshot creates nothing and consumes no one-shot.

