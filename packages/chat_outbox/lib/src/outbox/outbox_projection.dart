import 'package:chat_outbox/src/message/outgoing_message.dart';
import 'package:meta/meta.dart';

/// The outbox's in-memory view of each chat's outgoing messages, by client
/// message id: what the facade's lookups and snapshot read.
///
/// Not a store: it is rebuilt from the publish jobs' journal, which stays the
/// truth across a restart. The paths that accept a send, project a job's
/// state, rebase the tail and cancel write it; a message they leave out is
/// Absent, and every lookup then answers as for a message never sent.
///
/// Internal to the package: tests reach it to set up rows before the paths
/// that write it exist.
@internal
final class OutboxProjection {
  /// An empty projection.
  OutboxProjection();

  final Map<String, Map<String, OutgoingMessage>> _$chats = {};

  /// Messages whose fresh flag is still unread, as (chat id, client message
  /// id).
  final Set<(String, String)> _$fresh = {};

  /// Puts [message] in its chat, in place of the one with its client
  /// message id if any.
  ///
  /// [fresh] marks a message the user has just sent, which the host animates
  /// in once; replacing a message keeps a mark not yet read, so a status
  /// change does not swallow it.
  void put(OutgoingMessage message, {bool fresh = false}) {
    (_$chats[message.chatId] ??= {})[message.clientMessageId] = message;
    if (fresh) _$fresh.add((message.chatId, message.clientMessageId));
  }

  /// Makes the message [clientMessageId] of [chatId] Absent.
  void remove(String chatId, String clientMessageId) {
    final chat = _$chats[chatId];
    if (chat == null) return;
    chat.remove(clientMessageId);
    if (chat.isEmpty) _$chats.remove(chatId);
    _$fresh.remove((chatId, clientMessageId));
  }

  /// The message [clientMessageId] of [chatId], or null when it is Absent.
  OutgoingMessage? lookup(String chatId, String clientMessageId) =>
      _$chats[chatId]?[clientMessageId];

  /// Whether the message is fresh, clearing the mark: true at most once per
  /// mark.
  bool takeFresh(String chatId, String clientMessageId) =>
      _$fresh.remove((chatId, clientMessageId));

  /// Whether the message's fresh mark is still unread, without reading it.
  bool isFresh(String chatId, String clientMessageId) =>
      _$fresh.contains((chatId, clientMessageId));

  /// [chatId]'s outgoing messages in tail order, lowest position first.
  List<OutgoingMessage> tailOf(String chatId) =>
      [...?_$chats[chatId]?.values]
        ..sort((a, b) => a.position.compareTo(b.position));
}
