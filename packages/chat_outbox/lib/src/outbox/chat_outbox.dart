import 'package:chat_outbox/src/diagnostics/outbox_debug_snapshot.dart';
import 'package:chat_outbox/src/diagnostics/outbox_op.dart';
import 'package:chat_outbox/src/message/outgoing_message.dart';
import 'package:chat_outbox/src/outbox/outbox_projection.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// The outbox: the outgoing messages of every chat, as the host and the
/// chat's rows read them.
///
/// It keeps no store of its own; its view of each chat is a projection of
/// the publish jobs, so a restart reads the same messages back. Every
/// lookup is per chat and by the message's client message id, its identity,
/// never by its row's position, which moves with the provisional tail.
final class ChatOutbox {
  /// An outbox with no outgoing messages.
  ChatOutbox() : this.over(OutboxProjection());

  /// An outbox reading [projection], for tests that set rows up directly.
  @visibleForTesting
  ChatOutbox.over(this._projection);

  final OutboxProjection _projection;

  /// The outgoing message [clientMessageId] of [chatId], or null when there
  /// is none (never sent from here, or Absent: cancelled or deleted).
  ///
  /// The host calls it when the server's echo of a message arrives: a match
  /// is the host's own message, which it settles in place instead of
  /// inserting a twin row. Reports `echoMatched`.
  OutgoingMessage? byClientMessageId(String chatId, String clientMessageId) {
    final message = _projection.lookup(chatId, clientMessageId);
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.outbox,
      OutboxOp.echoMatched,
      correlation: ChatCorrelation(
        chatId: chatId,
        clientMessageId: clientMessageId,
        scrollId: switch (message) {
          final message? => '${message.position}',
          null => null,
        },
      ),
      fields: () => {
        'matched': message != null,
        if (message case final message?) 'status': message.status.name,
      },
    );
    return message;
  }

  /// Whether the outgoing row [clientMessageId] of [chatId] is new, so the
  /// host animates its appearance: true once per message the user just
  /// sent, false on every later call and for any other message.
  ///
  /// The whole-row animation is the host's, since it owns the row. Reports
  /// `freshOutgoingTaken`.
  bool isFreshOutgoing(String chatId, String clientMessageId) {
    final fresh = _projection.takeFresh(chatId, clientMessageId);
    ChatDiagnostics.current.emit(
      ChatEventLevel.trace,
      ChatEventCategory.outbox,
      OutboxOp.freshOutgoingTaken,
      correlation: ChatCorrelation(
        chatId: chatId,
        clientMessageId: clientMessageId,
      ),
      fields: () => {'answered': fresh},
    );
    return fresh;
  }

  /// What the outbox holds for [chatId] right now, without user content;
  /// see [OutboxDebugSnapshot].
  ///
  /// Reading it changes nothing: a row's fresh flag stays unread.
  OutboxDebugSnapshot debugSnapshot(String chatId) => OutboxDebugSnapshot(
    chatId: chatId,
    tail: [
      for (final message in _projection.tailOf(chatId))
        OutboxDebugRow.of(
          message,
          fresh: _projection.isFresh(chatId, message.clientMessageId),
        ),
    ],
  );
}
