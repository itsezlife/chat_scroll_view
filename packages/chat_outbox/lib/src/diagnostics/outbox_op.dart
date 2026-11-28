import 'package:content_model/content_model.dart';

/// The operations of the `outbox` diagnostics events this package emits
/// through `ChatDiagnostics.current`.
///
/// Closed: an operation is added here with the path that emits it. Names are
/// stable, since logs filter by them. Every event carries the chat id, and
/// the client message id when it concerns one message; none carries the
/// payload or anything decoded from it.
enum OutboxOp implements DiagnosticOp {
  /// The host looked up an outgoing message by its client message id to
  /// match the server's echo of it (debug): whether one matched and, if so,
  /// its status and position (as the scroll id).
  echoMatched,

  /// The host asked whether an outgoing row is fresh, to animate its
  /// appearance (trace): the answer, true once per message.
  freshOutgoingTaken,

  /// The outbox accepted a send (info): its kind (`text`, `single`,
  /// `group`), its item count and who issued the items' ids (`outbox`,
  /// `host`).
  accepted,

  /// A send was refused before any job was made (info): the rule that
  /// refused it (`sendNow`, or a limit's name) and the reason's form. The
  /// host's `onDenied` hears of it too, as `capabilities` / `denied`.
  refusedBeforeJob,

  /// The publish job of an accepted send was made (debug): its durability,
  /// failure policy, whether an ordering group is set, its items' sources
  /// by kind (`prepare`, `prepared`, `remote`) and the payload's length.
  jobCreated,

  /// An outgoing message's status changed with its job (debug): from, to,
  /// the job state's name and the stage.
  statusChanged,

  /// Whether a send of the chat is in flight changed (debug): on or off.
  sendInFlight,

  /// An outgoing row took its position in the provisional tail (debug):
  /// `offsetFromTip` (1 for `tip+1`), `strategy`, and `allocation` (`new`, or
  /// `restart` for a row placed again after a restart), with the position as
  /// the scroll id.
  positionAllocated,

  /// The provisional tail moved in one `rebaseTail` (debug), with `reason`
  /// (`incoming`, `publishStart`, `failedSink`, `retry`, `restart`,
  /// `removed`, `fetch`), `rows` in the tail after it and `inserted` confirmed
  /// messages on every event of the move.
  ///
  /// One event per row whose position changed, with its client message id,
  /// its new position as the scroll id and `from`, its old one; then one for
  /// the row that caused the move when it did not move itself (a removed
  /// row, or a row whose place stayed), with no `from`. So a log filtered by
  /// one client message id follows that row through every move. The data
  /// source's own `rebaseTail` event for the same move comes just before.
  tailRebased,

  /// Under local ids with the append flag, incoming messages went after the
  /// outgoing rows (debug): `appendIncoming`, `incoming` (their count) and
  /// `settled` (the rows above them that stop moving), with the first
  /// incoming id as the scroll id.
  incomingAppended,

  /// An accepted send came with the picker's send origins (debug): how many
  /// items have one, and how many have none (scrolled off, or not from the
  /// picker's grid).
  sendOriginStored,

  /// A media cell asked for an outgoing item's send origin (debug): whether
  /// one was held and, if so, the milliseconds since its send was accepted.
  sendOriginTaken,

  /// The outbox let go of a send origin nobody took (debug): why (`sent`,
  /// `cancelled`, `expired`).
  sendOriginDropped,

  /// The host registered its sender as the chat publisher (info): `waiting`,
  /// the chat's jobs that were waiting for it. One event per chat the
  /// outbox holds messages of, or one with no chat when it holds none.
  publisherRegistered,

  /// The chat publisher called the host's sender (info): `attempt` within
  /// the publish call (from 1), `proposedId` when the strategy proposes one,
  /// and `remoteRefs`, the items it passed; the row's position as the
  /// scroll id.
  publishAttempt,

  /// The server's next id was not the proposed one (warning): `attempt`, the
  /// conflict's number in the call (1 to 3), and `distance` from the
  /// proposal to the server's next id.
  publishConflict,

  /// The third conflict of one publish call ended it (error): `attempts`,
  /// the sends it made. The message fails, retryable.
  publishConflictExhausted,

  /// The server published the message (info): `attempts`, `durationMs` of
  /// the publish call, `serverKeys` (their count) and
  /// `payloadAsStoredDiffers`; the message's id from now on as the scroll
  /// id.
  published,

  /// The server answered an idempotent replay with an id other than the
  /// proposal, and the row moved to it (warning): `distance` from the
  /// proposal; the server's id as the scroll id.
  replayRebased,

  /// The server asked for an item's upload again (warning): one event per
  /// item, its media item id in the ids, with `items`, their count.
  reuploadRequested,

  /// The server rejected the message (warning): `reason`'s form
  /// (`rejected`; never the server's code) and `retryable`.
  rejected,

  /// The server denied the message's action in the chat (info): `action`
  /// and the reason's form. The host's `onDenied` hears of it once, as
  /// `capabilities` / `denied` with consumer `outbox`.
  denied,

  /// The host's sender threw (error): `errorType`, never the error's text;
  /// `in: onSent` when the host's settling of a published row threw
  /// instead, which leaves the message sent. `errorType: unknownMessage`
  /// for a job whose message this run does not hold.
  senderFailed,

  /// A job's payload did not decode through the host's codec (error):
  /// `errorType` and `payloadBytes`, its length.
  payloadDecodeFailed,
}
