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
}
