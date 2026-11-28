import 'package:chat_outbox/src/message/outgoing_message.dart';
import 'package:meta/meta.dart';

/// What a cancel of an outgoing message, or of one of its items, did.
enum OutgoingCancelOutcome {
  /// The message's job is cancelled and the message is Absent; its row left
  /// the provisional tail (or, see [OutgoingCancelled.rowRemoved], is the
  /// host's to remove).
  cancelled,

  /// The item left the message, which goes on with the rest: the other
  /// items of an album, or its text alone.
  itemDropped,

  /// The message's publish is in flight: the cancel applies once the server
  /// answers, unless it accepted the message, which then stays sent.
  pending,

  /// The server already accepted the message: it stays sent, and the host
  /// may delete it as any sent message.
  tooLate,

  /// A cancel of the message (or of this item) was already accepted; this
  /// one changes nothing.
  dropped,

  /// There is no such outgoing message, or no such item in it.
  unknown,
}

/// A message the outbox cancelled, as `ChatOutbox(onCancelled:)` hands it
/// to the host.
@immutable
final class OutgoingCancelled {
  /// [message], cancelled; [rowRemoved] tells whether its id strategy took
  /// its row out of the tail.
  const OutgoingCancelled({required this.message, required this.rowRemoved});

  /// The message as it was last, its status `cancelled`, at its last
  /// position. Absent from now on: the outbox answers nothing for it.
  final OutgoingMessage message;

  /// Whether the row left the provisional tail with the cancel. False for a
  /// row the strategy no longer moves (an appended message settled it): the
  /// host's duty is then to remove the row at `message.position` itself.
  final bool rowRemoved;

  @override
  String toString() =>
      'OutgoingCancelled(${message.clientMessageId}, '
      'rowRemoved: $rowRemoved)';
}

/// An item that left its outgoing message, which goes on, as
/// `ChatOutbox(onItemDropped:)` hands it to the host.
@immutable
final class OutgoingItemDropped {
  /// [item], which was at [index], left [message].
  const OutgoingItemDropped({
    required this.message,
    required this.item,
    required this.index,
  });

  /// The message without the item, at its current position: the host's
  /// duty is to drop the item from its row there.
  final OutgoingMessage message;

  /// The item that left.
  final OutgoingItem item;

  /// The item's index in the message before it left.
  final int index;

  @override
  String toString() =>
      'OutgoingItemDropped(${message.clientMessageId}, ${item.id})';
}
