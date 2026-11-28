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
}
