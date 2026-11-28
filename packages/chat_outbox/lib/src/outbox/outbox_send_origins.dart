import 'dart:ui' show Rect;

import 'package:chat_outbox/src/diagnostics/outbox_op.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// Why the outbox let go of a send origin nobody took.
@internal
enum SendOriginDrop {
  /// Its message was sent: the row's appearance is over.
  sent,

  /// Its message was cancelled or deleted.
  cancelled,

  /// It outlived the outbox's bound on how long an origin is kept.
  expired,
}

/// The send origins the outbox holds: each item's on-screen thumbnail rect
/// in the picker at send time, by the item's `MediaItemId`, until a media
/// cell takes it once.
///
/// One-shot by design: the cell flies from the origin on its first frame,
/// and an origin read twice would fly a rebuilt cell again. An origin
/// nobody takes is dropped with its message (sent, cancelled) or once it
/// is past its expiry, so the store never grows with sends whose rows were
/// never drawn. Expiry is checked by [expire] on the outbox's own calls
/// rather than by a timer: an origin that is past its bound is never
/// handed out, and the store holds at most the origins of the sends made
/// before the outbox was last touched.
///
/// Reports `sendOriginDropped`; storing and taking are the facade's to
/// report, since it knows the send and the item's message.
@internal
final class OutboxSendOrigins {
  /// A store with no origins.
  OutboxSendOrigins();

  final Map<MediaItemId, _HeldOrigin> _$held = {};

  /// Holds [origins] of the message [clientMessageId] of [chatId], accepted
  /// [at], until [expiresAt]; an item's earlier origin is replaced.
  void store(
    String chatId,
    String clientMessageId,
    Map<MediaItemId, Rect> origins, {
    required DateTime at,
    required DateTime expiresAt,
  }) {
    for (final MapEntry(key: id, value: rect) in origins.entries) {
      _$held[id] = _HeldOrigin(
        rect: rect,
        chatId: chatId,
        clientMessageId: clientMessageId,
        acceptedAt: at,
        expiresAt: expiresAt,
      );
    }
  }

  /// The origin of [id] and when its send was accepted, removed from the
  /// store; null when none is held.
  ({Rect rect, DateTime acceptedAt})? take(MediaItemId id) =>
      switch (_$held.remove(id)) {
        final held? => (rect: held.rect, acceptedAt: held.acceptedAt),
        null => null,
      };

  /// Whether the origin of [id] is still held.
  bool holds(MediaItemId id) => _$held.containsKey(id);

  /// Drops every origin of the message [clientMessageId] of [chatId], for
  /// [why].
  void dropMessage(String chatId, String clientMessageId, SendOriginDrop why) =>
      _dropWhere(
        (held) =>
            held.chatId == chatId && held.clientMessageId == clientMessageId,
        why,
      );

  /// Drops every origin past its expiry at [now].
  void expire(DateTime now) {
    if (_$held.isEmpty) return;
    _dropWhere((held) => !now.isBefore(held.expiresAt), SendOriginDrop.expired);
  }

  void _dropWhere(bool Function(_HeldOrigin held) test, SendOriginDrop why) {
    final dropped = [
      for (final MapEntry(key: id, value: held) in _$held.entries)
        if (test(held)) (id, held),
    ];
    for (final (id, held) in dropped) {
      _$held.remove(id);
      ChatDiagnostics.current.emit(
        ChatEventLevel.debug,
        ChatEventCategory.outbox,
        OutboxOp.sendOriginDropped,
        correlation: ChatCorrelation(
          chatId: held.chatId,
          clientMessageId: held.clientMessageId,
          mediaItemId: '$id',
        ),
        fields: () => {'why': why.name},
      );
    }
  }
}

/// One held origin and the message it came with.
final class _HeldOrigin {
  const _HeldOrigin({
    required this.rect,
    required this.chatId,
    required this.clientMessageId,
    required this.acceptedAt,
    required this.expiresAt,
  });

  final Rect rect;
  final String chatId;
  final String clientMessageId;
  final DateTime acceptedAt;
  final DateTime expiresAt;
}
