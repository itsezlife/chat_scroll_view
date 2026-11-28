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

  /// An outgoing row took its position in the provisional tail (debug):
  /// `offsetFromTip` (1 for `tip+1`), `strategy`, and `allocation` (`new`, or
  /// `restart` for a row placed again after a restart), with the position as
  /// the scroll id.
  positionAllocated,

  /// The provisional tail moved in one `rebaseTail` (debug), with `reason`
  /// (`incoming`, `publishStart`, `failedSink`, `retry`, `restart`,
  /// `removed`), `rows` in the tail after it and `inserted` confirmed
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
}
