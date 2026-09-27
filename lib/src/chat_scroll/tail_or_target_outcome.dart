/// Where a tail-or-target [ChatScrollController.jumpTo] (one with a
/// `tailFitFraction`) placed the chat, reported to
/// [ChatScrollController.addTailOrTargetListener] listeners.
///
/// The viewport decides once, in the first layout that lays out the jump
/// target as a loaded message row, by measuring the span from the target
/// row's body top — its row chrome (inline date separator, unread
/// separator) excluded — to the bottom of the newest message.
enum TailOrTargetOutcome {
  /// The newest message is known ([ChatDataSource.reachedNewest]) and
  /// loaded, and the span fits within `tailFitFraction` of the viewport
  /// height: the chat opened pinned at the tail, with the newest message's
  /// bottom on the bottom inset. The alignment the jump asked for is
  /// dropped, and nothing is held on the target.
  tail,

  /// The span does not fit, or the newest message is not known or not
  /// loaded: the target is placed at the jump's alignment, as a plain
  /// [ChatScrollController.jumpTo] would place it, and the alignment hold
  /// applies.
  target,
}
