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
  /// `errorType` and `payloadBytes`, its length. After a restart the
  /// message is restored as failed for an unknown reason; at publish the
  /// job fails as its publisher's error.
  payloadDecodeFailed,

  /// The outbox cancelled a message's job, and the message is Absent
  /// (info): `trigger` (`menu`; `onlyItem`, the cross on its only item with
  /// no text; `lastItemNoText`, the cross on the last item left of an album
  /// with no text; `statusControl`, a cell's cancel of the last item's
  /// upload with no text; `delete`, the menu's delete, followed by
  /// `deleted`; `systemInterruption`, the system ended the transfer envelope
  /// and the host chose to delete; `notificationCancelAll`, the user
  /// cancelled every job of the envelope from the system's UI) and `stage`,
  /// the job's stage at the cancel
  /// (`prepare`, `upload`, `publish`) or the status it read (`failed`).
  cancelled,

  /// An item left its message, which goes on (info): `index`, the item's
  /// index before it left, `itemsLeft`, `hasText`, and `trigger` (`cross`,
  /// the host's call; `statusControl`, a cell's cancel of its upload); the
  /// item's media item id and media key in the ids.
  itemDropped,

  /// A cancel came after the server accepted the message, which stays sent
  /// (info): `stage`, what the cancel found (`publish`, the server's answer
  /// in flight; `sent`).
  cancelTooLate,

  /// A message's job lost its last item and waits for the outbox, its owner
  /// (warning): `itemsLeft` (0), `hasText`, and `action` taken (`commit`:
  /// the text publishes alone; `cancel`: nothing is left to send).
  awaitingOwner,

  /// An action on a message was dropped by its input guard (debug):
  /// `action` (`cancel`, `retry`, `delete`), `msSinceAccepted`, the time
  /// since the one it repeats was accepted.
  actionDropped,

  /// A chat's outgoing messages were read back from the engine's jobs after
  /// a restart (info): `sending` (awaiting the publisher included),
  /// `failed` and `awaitingPublisher` counts.
  restored,

  /// A job under the chat's tag prefix that is not an outgoing message's was
  /// left alone after a restart (warning): `why` (`emptyId` or `separator`,
  /// a tag that names no client message id, the latter for a remainder
  /// holding `:`; `itemId`, an item id that is no media item id's string
  /// form); the job's id in the ids, never its tag.
  foreignJob,

  /// An outgoing message's job failed, and its row sank below every sending
  /// row (warning): `reason` (`network`, `rejected`, `denied`,
  /// `sourceLost`, `tooLarge`, `unknown`; never a rejection's code),
  /// `stage` (`prepare`, `upload`, `publish`) and `itemsFailed`, the job's
  /// items that failed.
  failed,

  /// The user retried a failed message, and its row joined the end of the
  /// sending rows (info): `stage` repeated (`prepare`, `upload`,
  /// `publish`), `uploadsKept` (false when the host gave a source again)
  /// and `newSources`, the items given one.
  retried,

  /// The user deleted an outgoing message, which is Absent (info): `status`
  /// it had at the delete. The `cancelled` event of its job, trigger
  /// `delete`, comes just before.
  deleted,

  /// The system ended the transfer envelope a message's job ran in, and the
  /// job paused (info): `action`, `kept` (the message keeps sending and
  /// resumes in the foreground) or `deleted` (the outbox was made with
  /// `deleteOnSystemInterruption`).
  systemInterrupted,

  /// A job the system's end of its envelope paused goes on (info): `stage`,
  /// the one it resumed in (`prepare`, `upload`, `publish`).
  resumed,

  /// The user cancelled every job of the transfer envelope from the system's
  /// UI, and the chat's messages among them are deleted (info): `deleted`,
  /// the messages made Absent at once, and `pending`, those whose server
  /// answer was in flight, which go once it comes unless it is an accept;
  /// the chat's id only.
  envelopeCancelAll,
}
