import 'dart:typed_data';

import 'package:chat_outbox/src/message/outgoing_ids.dart';
import 'package:chat_outbox/src/message/outgoing_status.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// A message the user sent from this device that the server has not yet
/// confirmed, or that failed.
///
/// Its identity is [clientMessageId], never its [position]: the position is
/// the row's id in the chat's provisional tail, after the newest server
/// message, and it moves when an incoming message takes it or the tail is
/// reordered. The host matches the server's echo of the message by
/// [clientMessageId], never by slot.
///
/// Equal by value, [payload] compared byte by byte.
@immutable
final class OutgoingMessage {
  /// An outgoing message of [chatId]; [items] and [payload] are copied.
  OutgoingMessage({
    required this.chatId,
    required this.clientMessageId,
    required this.position,
    required this.status,
    required Uint8List payload,
    List<OutgoingItem> items = const [],
  }) : assert(clientMessageId != '', 'A clientMessageId must not be empty.'),
       items = List.unmodifiable(items),
       payload = Uint8List.fromList(payload).asUnmodifiableView();

  /// The chat the message is sent to.
  final ChatId chatId;

  /// The message's identity, issued before its publish job and never reused.
  final ClientMessageId clientMessageId;

  /// The row's current id in the chat's provisional tail: a position, not
  /// the message's identity. The chat's id strategy places the row when the
  /// outbox accepts the send and moves it with the tail.
  final int position;

  /// The message's media items in order; empty for a text message.
  final List<OutgoingItem> items;

  /// How far the message got.
  final OutgoingStatus status;

  /// The host's message model as bytes, through its `OutgoingPayloadCodec`.
  ///
  /// User content: reported by its length only.
  final Uint8List payload;

  /// This message with [status] in place of its own.
  OutgoingMessage withStatus(OutgoingStatus status) => OutgoingMessage(
    chatId: chatId,
    clientMessageId: clientMessageId,
    position: position,
    status: status,
    payload: payload,
    items: items,
  );

  /// This message at [position] in place of its own.
  OutgoingMessage withPosition(int position) => OutgoingMessage(
    chatId: chatId,
    clientMessageId: clientMessageId,
    position: position,
    status: status,
    payload: payload,
    items: items,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OutgoingMessage &&
        other.chatId == chatId &&
        other.clientMessageId == clientMessageId &&
        other.position == position &&
        other.status == status &&
        _listEquals(other.items, items) &&
        _listEquals(other.payload, payload);
  }

  @override
  int get hashCode => Object.hash(
    chatId,
    clientMessageId,
    position,
    status,
    Object.hashAll(items),
    Object.hashAll(payload),
  );

  // The payload stays out: it is the host's message.
  @override
  String toString() =>
      'OutgoingMessage($chatId, $clientMessageId at $position, '
      '$status, '
      '${items.length} items, ${payload.length} payload bytes)';

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One media item of an [OutgoingMessage]: its identity in the chat and the
/// local key its content is cached under until the server's key replaces it.
@immutable
final class OutgoingItem {
  /// The item [id], whose content is under [localKey].
  const OutgoingItem({required this.id, required this.localKey});

  /// The item's identity in the chat; media cells and transfers name it by
  /// its string form.
  final MediaItemId id;

  /// The key the item's local content is cached under; media cells read the
  /// item's upload state by it.
  final ContentKey localKey;

  @override
  bool operator ==(Object other) =>
      other is OutgoingItem && other.id == id && other.localKey == localKey;

  @override
  int get hashCode => Object.hash(id, localKey);

  @override
  String toString() => 'OutgoingItem($id)';
}
