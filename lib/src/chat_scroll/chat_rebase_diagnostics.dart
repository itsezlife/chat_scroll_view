import 'package:content_model/content_model.dart' show DiagnosticOp;

/// The operations of the diagnostics events a move of the provisional tail
/// (`ChatDataSource.rebaseTail`) emits through `ChatDiagnostics.current`,
/// under the `rebase` category.
///
/// The engine knows no chat and no outgoing message: these events carry
/// scroll ids and counts only. The host's own event for the same move, emitted
/// in the same call, carries the chat and the message identities, so the two
/// join in a log by order.
///
/// Closed: an operation is added here with the path that emits it. Names are
/// stable, since logs filter by them.
enum ChatRebaseOp implements DiagnosticOp {
  /// The tail moved (debug): `provisionalBefore`, `provisionalAfter`,
  /// `inserted`, `moved` (rows whose position changed), `reorderOnly` (no
  /// insertion and no removal), `removed`, `durationUs`, with the scroll id
  /// of the first provisional row after the move.
  rebaseTail,

  /// A move refused and the data source left unchanged (error): the
  /// [ChatRebaseRejection] as `rule`, with the scroll id the rule tripped on
  /// when there is one.
  orderRejected,

  /// Removal staging cleared for the positions the move took over (trace):
  /// `freed` (staged positions the move leaves empty) and `reused` (staged
  /// positions it writes a row into).
  stagingFinalised,

  /// A move that would have pulled a reader scrolled into history to the
  /// tail had it been an insert (debug): `distanceFromTailPx` when the
  /// newest row is built.
  followSuppressed,

  /// A navigation animation kept running across a move (debug):
  /// `target` (`tail` or `history`) and `pinned` (whether a moved or removed
  /// position was held by the animation).
  animationKept,
}

/// Why `ChatDataSource.rebaseTail` refused a move; the `rule` of a
/// [ChatRebaseOp.orderRejected] event.
enum ChatRebaseRejection {
  /// An identity in `order` names no current provisional row.
  notProvisional,

  /// An identity appears twice in `order`, or two inserted messages share an
  /// id.
  duplicateIdentity,

  /// No `ChatDataSource.identityOf` is set, so no row can be matched.
  identityOfNull,

  /// An inserted message is itself provisional (`identityOf` answers for
  /// it): it would sit inside the tail instead of before it.
  insertInsideTail,

  /// An inserted message's id is below the tail's first position: it would
  /// land among confirmed rows the move does not own.
  insertBelowTail,
}
