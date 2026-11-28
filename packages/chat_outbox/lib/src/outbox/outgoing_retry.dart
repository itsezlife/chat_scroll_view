/// What a retry of a failed outgoing message did.
enum OutgoingRetryOutcome {
  /// The message's job repeats what failed, and its row joined the end of
  /// the sending rows: the message reads as sending again.
  retried,

  /// A retry of the message was already accepted and it has not failed
  /// since; this one changes nothing.
  dropped,

  /// The message has not failed: it is on its way.
  notFailed,

  /// The message was restored with a payload the host's codec cannot read:
  /// a retry would fail at the same decode, so the outbox does not try. Only
  /// a delete helps it.
  undecodable,

  /// There is no such outgoing message, or the engine no longer has its
  /// job.
  unknown,
}
