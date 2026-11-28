import 'package:chat_outbox/src/message/outgoing_message.dart';
import 'package:chat_outbox/src/message/outgoing_status.dart';
import 'package:chat_outbox/src/outbox/outbox_send_origins.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// The outbox's in-memory view of each chat's outgoing messages, by client
/// message id: what the facade's lookups and snapshot read.
///
/// Not a store: it is rebuilt from the publish jobs' journal, which stays the
/// truth across a restart. The paths that accept a send, project a job's
/// state, rebase the tail and cancel write it; a message they leave out is
/// Absent, and every lookup then answers as for a message never sent.
///
/// Internal to the package: tests reach it to set up rows the public paths
/// do not make.
@internal
final class OutboxProjection {
  /// An empty projection.
  OutboxProjection();

  final Map<String, Map<String, OutgoingMessage>> _$chats = {};

  /// Messages whose fresh flag is still unread, as (chat id, client message
  /// id).
  final Set<(String, String)> _$fresh = {};

  /// The publish job of each message that has one, as (chat id, client
  /// message id).
  final Map<(String, String), OutboxJobView> _$jobs = {};

  /// The send origins of the messages here: a message that is sent,
  /// cancelled or made Absent takes its untaken origins with it.
  final OutboxSendOrigins origins = OutboxSendOrigins();

  /// Puts [message] in its chat, in place of the one with its client
  /// message id if any.
  ///
  /// [fresh] marks a message the user has just sent, which the host animates
  /// in once; replacing a message keeps a mark not yet read, so a status
  /// change does not swallow it. [job] is the message's publish job as the
  /// outbox last saw it; replacing a message without one keeps its job.
  void put(OutgoingMessage message, {bool fresh = false, OutboxJobView? job}) {
    final key = (message.chatId, message.clientMessageId);
    (_$chats[message.chatId] ??= {})[message.clientMessageId] = message;
    if (fresh) _$fresh.add(key);
    if (job != null) _$jobs[key] = job;
    final drop = switch (message.status) {
      OutgoingStatus$Sent() => SendOriginDrop.sent,
      OutgoingStatus$Cancelled() => SendOriginDrop.cancelled,
      // A failed message keeps them until they expire: a retry does not
      // fly again, but the row may not have been drawn yet.
      OutgoingStatus$Preparing() ||
      OutgoingStatus$Uploading() ||
      OutgoingStatus$Publishing() ||
      OutgoingStatus$Failed() => null,
    };
    if (drop case final drop?) {
      origins.dropMessage(message.chatId, message.clientMessageId, drop);
    }
  }

  /// Makes the message [clientMessageId] of [chatId] Absent.
  void remove(String chatId, String clientMessageId) {
    final chat = _$chats[chatId];
    if (chat == null) return;
    chat.remove(clientMessageId);
    if (chat.isEmpty) _$chats.remove(chatId);
    _$fresh.remove((chatId, clientMessageId));
    _$jobs.remove((chatId, clientMessageId));
    origins.dropMessage(chatId, clientMessageId, SendOriginDrop.cancelled);
  }

  /// The message [clientMessageId] of [chatId], or null when it is Absent.
  OutgoingMessage? lookup(String chatId, String clientMessageId) =>
      _$chats[chatId]?[clientMessageId];

  /// The publish job of the message [clientMessageId] of [chatId], or null
  /// when it has none or is Absent.
  OutboxJobView? jobOf(String chatId, String clientMessageId) =>
      _$jobs[(chatId, clientMessageId)];

  /// The message with an item [id], or null when no message here has one.
  OutgoingMessage? messageOfItem(MediaItemId id) {
    for (final chat in _$chats.values) {
      for (final message in chat.values) {
        if (message.items.any((item) => item.id == id)) return message;
      }
    }
    return null;
  }

  /// Whether the message is fresh, clearing the mark: true at most once per
  /// mark.
  bool takeFresh(String chatId, String clientMessageId) =>
      _$fresh.remove((chatId, clientMessageId));

  /// Whether the message's fresh mark is still unread, without reading it.
  bool isFresh(String chatId, String clientMessageId) =>
      _$fresh.contains((chatId, clientMessageId));

  /// [chatId]'s outgoing messages in tail order, lowest position first; a
  /// message no strategy has placed yet comes after the placed ones, and
  /// messages of the same position keep the order they were first put in.
  List<OutgoingMessage> tailOf(String chatId) {
    // List.sort is not stable: the first-put order breaks ties explicitly.
    final indexed = [...?_$chats[chatId]?.values.indexed]
      ..sort(
        (a, b) => switch ((a.$2.position, b.$2.position)) {
          (final a?, final b?) when a != b => a.compareTo(b),
          (null, _?) => 1,
          (_?, null) => -1,
          _ => a.$1.compareTo(b.$1),
        },
      );
    return [for (final (_, message) in indexed) message];
  }

  /// Whether [chatId] has a message still on its way: preparing, uploading
  /// or publishing.
  bool hasInFlight(String chatId) =>
      _$chats[chatId]?.values.any(
        (message) => switch (message.status) {
          OutgoingStatus$Preparing() ||
          OutgoingStatus$Uploading() ||
          OutgoingStatus$Publishing() => true,
          OutgoingStatus$Sent() ||
          OutgoingStatus$Failed() ||
          OutgoingStatus$Cancelled() => false,
        },
      ) ??
      false;
}

/// A message's publish job as the outbox last saw it: its id, its state's
/// name and the stage it is in.
@internal
@immutable
final class OutboxJobView {
  /// Job [id], last seen in the state named [state] at [stage]; with no
  /// state, a job made but not seen yet.
  const OutboxJobView(this.id, {this.state, this.stage});

  /// The job's id.
  final PublishJobId id;

  /// The job state's name (`PublishJobState.name`); null until the job's
  /// first snapshot.
  final String? state;

  /// The stage the job is in; null once it completed, or while it waits
  /// for its owner.
  final PublishStage? stage;
}
