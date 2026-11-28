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
| `ChatOutbox` | The facade. `byClientMessageId(chatId, id)` matches the server's echo of the host's own message, so the host inserts no twin row; `isFreshOutgoing(chatId, id)` answers true once per message the user just sent, for the host's row appearance; `debugSnapshot(chatId)` describes what it holds. |
| `OutgoingMessage` | Chat id, `clientMessageId` (its identity), its current position in the provisional tail, its items (`OutgoingItem`: `MediaItemId` and local `ContentKey`), status and payload bytes. |
| `OutgoingStatus` | `preparing`, `uploading`, `publishing`, `sent`, `failed(OutgoingFailure)`, `cancelled`. |
| `OutgoingFailure` | The closed set of reasons: `network`, `rejected(reason)`, `denied(CapabilityAction)`, `sourceLost`, `tooLarge`, `unknown`. |
| `OutgoingPayloadCodec<M>` | The host's message model to bytes and back, a `dart:convert` `Codec`; the outbox stores bytes only. |
| `OutboxDebugSnapshot` | The strategy and tip, the tail row by row, the publisher, the send in flight and counters, as `toMap()`; no user content. |
| `OutboxOp` | The `outbox` diagnostics operations. |

## Identity

A row's id is a position in the provisional tail and moves when an incoming
message takes it. The message's identity is its `clientMessageId`: look a
message up by it, never by its row's id.

## Diagnostics

Every path reports through `ChatDiagnostics.current` (`content_model`) under
the `outbox` category. No event and no snapshot carries the payload, its
bytes or anything decoded from it; the payload is reported by its length.
