import 'package:chat_outbox/src/message/outgoing_ids.dart';
import 'package:chat_outbox/src/message/outgoing_message.dart';
import 'package:chat_outbox/src/message/outgoing_status.dart';
import 'package:chat_outbox/src/outbox/outbox_send_origins.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// One outgoing message's key in the outbox's maps: its chat and its client
/// message id, each its own nominal type, so the two never swap.
@internal
typedef OutgoingRef = (ChatId, ClientMessageId);

/// The outbox's in-memory view of each chat's outgoing messages, by client
/// message id: what the facade's lookups and snapshot read.
///
/// Not a store: it is rebuilt from the publish jobs' journal, which stays the
/// truth across a restart. The paths that accept a send, project a job's
/// state, rebase the tail and cancel write it; a message they leave out is
/// Absent, and every lookup then answers as for a message never sent.
///
/// A message's position is not its own: while the chat's id strategy holds
/// its row, the strategy's position is the one every read answers
/// ([positionOf]); the position a message was put with stands only for one
/// the strategy no longer moves (sent, or settled).
///
/// Internal to the package: tests reach it to set up rows the public paths
/// do not make.
@internal
final class OutboxProjection {
  /// An empty projection.
  OutboxProjection();

  /// Where the chat's id strategy holds the row of a message now, or null
  /// when it holds none; the outbox sets it once. Read, never synced: the
  /// outbox brings each strategy up to date at its own entry points.
  int? Function(ChatId chatId, ClientMessageId clientMessageId) positionOf =
      _noPosition;

  static int? _noPosition(ChatId chatId, ClientMessageId clientMessageId) =>
      null;

  /// The key of [message].
  static OutgoingRef refOf(OutgoingMessage message) =>
      _ref(message.chatId, message.clientMessageId);

  static OutgoingRef _ref(ChatId chatId, ClientMessageId clientMessageId) =>
      (chatId, clientMessageId);

  final Map<ChatId, Map<ClientMessageId, OutgoingMessage>> _$chats = {};

  /// Messages whose fresh flag is still unread.
  final Set<OutgoingRef> _$fresh = {};

  /// The publish job of each message that has one.
  final Map<OutgoingRef, OutboxJobView> _$jobs = {};

  /// Messages restored with a payload the host's codec could not read: they
  /// read as failed whatever their job does, since no row of the host's can
  /// show them sending.
  final Set<OutgoingRef> _$undecodable = {};

  /// The send origins of the messages here: a message that is sent,
  /// cancelled or made Absent takes its untaken origins with it.
  final OutboxSendOrigins origins = OutboxSendOrigins();

  /// Messages that carry text besides their items (a caption): with their
  /// last item gone they still publish, as a text.
  final Set<OutgoingRef> _$withText = {};

  /// Each item's media key, from the send, for the events of an item that
  /// left its job (the job's snapshot no longer lists it).
  final Map<MediaItemId, MediaKey> _$mediaKeys = {};

  /// Where each message's send to the server stands; a message not here
  /// has no sender call out and no accept ([SendPhase]).
  final Map<OutgoingRef, SendPhase> _$phases = {};

  /// Records what the send of [message] said that its job does not keep:
  /// whether it [hasText], and its items' [mediaKeys] in item order.
  void putSendFacts(
    OutgoingMessage message, {
    required bool hasText,
    List<MediaKey> mediaKeys = const [],
  }) {
    if (hasText) _$withText.add(refOf(message));
    for (final (index, item) in message.items.indexed) {
      if (index < mediaKeys.length) _$mediaKeys[item.id] = mediaKeys[index];
    }
  }

  /// Whether the message [clientMessageId] of [chatId] carries text.
  bool hasText(ChatId chatId, ClientMessageId clientMessageId) =>
      _$withText.contains(_ref(chatId, clientMessageId));

  /// The media key of item [id], when its send gave one.
  MediaKey? mediaKeyOf(MediaItemId id) => _$mediaKeys[id];

  /// Puts [message] in its chat, in place of the one with its client
  /// message id if any.
  ///
  /// [fresh] marks a message the user has just sent, which the host animates
  /// in once; replacing a message keeps a mark not yet read, so a status
  /// change does not swallow it. [job] is the message's publish job as the
  /// outbox last saw it; replacing a message without one keeps its job.
  void put(OutgoingMessage message, {bool fresh = false, OutboxJobView? job}) {
    final ref = refOf(message);
    (_$chats[message.chatId] ??= {})[message.clientMessageId] = message;
    if (fresh) _$fresh.add(ref);
    if (job != null) _$jobs[ref] = job;
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
  void remove(ChatId chatId, ClientMessageId clientMessageId) {
    final chat = _$chats[chatId];
    if (chat == null) return;
    if (chat.remove(clientMessageId) case final message?) {
      for (final item in message.items) {
        _$mediaKeys.remove(item.id);
      }
    }
    if (chat.isEmpty) _$chats.remove(chatId);
    _$fresh.remove(_ref(chatId, clientMessageId));
    _$jobs.remove(_ref(chatId, clientMessageId));
    _$undecodable.remove(_ref(chatId, clientMessageId));
    _$withText.remove(_ref(chatId, clientMessageId));
    _$phases.remove(_ref(chatId, clientMessageId));
    origins.dropMessage(chatId, clientMessageId, SendOriginDrop.cancelled);
  }

  /// Marks the message [clientMessageId] of [chatId] as restored with a payload the host's codec
  /// could not read.
  void markUndecodable(ChatId chatId, ClientMessageId clientMessageId) =>
      _$undecodable.add(_ref(chatId, clientMessageId));

  /// Whether the message [clientMessageId] of [chatId] was restored with a payload the host's codec
  /// could not read.
  bool isUndecodable(ChatId chatId, ClientMessageId clientMessageId) =>
      _$undecodable.contains(_ref(chatId, clientMessageId));

  /// The message [clientMessageId] of [chatId] at its current position, or null when it is Absent.
  OutgoingMessage? lookup(ChatId chatId, ClientMessageId clientMessageId) =>
      switch (_$chats[chatId]?[clientMessageId]) {
        final message? => _live(message),
        null => null,
      };

  /// [message] at the position its strategy holds for it, when it holds one.
  OutgoingMessage _live(OutgoingMessage message) =>
      switch (positionOf(message.chatId, message.clientMessageId)) {
        final position? when position != message.position =>
          message.withPosition(position),
        _ => message,
      };

  /// The chats holding messages.
  Iterable<ChatId> get chats => _$chats.keys;

  /// The message [clientMessageId] of whichever chat holds it, or null when
  /// none does: a client message id is unique across chats, and the
  /// publisher, which hears only the job's idempotency key, finds its
  /// message by it.
  OutgoingMessage? find(ClientMessageId clientMessageId) {
    for (final chat in _$chats.values) {
      if (chat[clientMessageId] case final message?) return _live(message);
    }
    return null;
  }

  /// The publish job of the message [clientMessageId] of [chatId], or null when it has none or is
  /// Absent.
  OutboxJobView? jobOf(ChatId chatId, ClientMessageId clientMessageId) =>
      _$jobs[_ref(chatId, clientMessageId)];

  /// The message with an item [id], or null when no message here has one.
  OutgoingMessage? messageOfItem(MediaItemId id) {
    for (final chat in _$chats.values) {
      for (final message in chat.values) {
        if (message.items.any((item) => item.id == id)) return _live(message);
      }
    }
    return null;
  }

  /// Whether the message is fresh, clearing the mark: true at most once per
  /// mark.
  bool takeFresh(ChatId chatId, ClientMessageId clientMessageId) =>
      _$fresh.remove(_ref(chatId, clientMessageId));

  /// Whether the message's fresh mark is still unread, without reading it.
  bool isFresh(ChatId chatId, ClientMessageId clientMessageId) =>
      _$fresh.contains(_ref(chatId, clientMessageId));

  /// [chatId]'s outgoing messages in tail order, lowest position first, at
  /// their current positions.
  List<OutgoingMessage> tailOf(ChatId chatId) => [
    for (final message in [...?_$chats[chatId]?.values]) _live(message),
  ]..sort((a, b) => a.position.compareTo(b.position));

  /// Whether [chatId] has a message still on its way: preparing, uploading
  /// or publishing.
  bool hasInFlight(ChatId chatId) =>
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

  // --- The send phase ---------------------------------------------------------

  /// Where the send of message [clientMessageId] of [chatId] stands.
  SendPhase phaseOf(ChatId chatId, ClientMessageId clientMessageId) =>
      _$phases[_ref(chatId, clientMessageId)] ?? const SendPhase.idle();

  /// The sender call for message [clientMessageId] of [chatId] goes out: a cancel now waits for its
  /// answer.
  void beginSend(ChatId chatId, ClientMessageId clientMessageId) =>
      _$phases[_ref(chatId, clientMessageId)] = const SendPhase.sending();

  /// A cancel of message [clientMessageId] of [chatId] arrived while its sender call is out: [cancel]
  /// runs once the answer comes, unless the answer is an accept. Answers
  /// false, leaving nothing waiting, when no call is out.
  bool awaitAnswer(
    ChatId chatId,
    ClientMessageId clientMessageId,
    void Function() cancel,
  ) {
    if (_$phases[_ref(chatId, clientMessageId)] case SendPhase$Sending()) {
      _$phases[_ref(chatId, clientMessageId)] = SendPhase.sending(
        cancel: cancel,
      );
      return true;
    }
    return false;
  }

  /// The answer to message [clientMessageId] of [chatId]'s sender call came: [accepted] by the
  /// server or not. Answers the cancel that waited for it, if one did; an
  /// accept makes it too late, and the caller reports it rather than run it.
  void Function()? endSend(
    ChatId chatId,
    ClientMessageId clientMessageId, {
    required bool accepted,
  }) {
    final cancel = switch (_$phases[_ref(chatId, clientMessageId)]) {
      SendPhase$Sending(:final cancel) => cancel,
      SendPhase$Idle() || SendPhase$Accepted() || null => null,
    };
    if (accepted) {
      _$phases[_ref(chatId, clientMessageId)] = const SendPhase.accepted();
    } else {
      _$phases.remove(_ref(chatId, clientMessageId));
    }
    return cancel;
  }

  /// The server holds message [clientMessageId] of [chatId] (an accept, or the message met in
  /// fetched history), whose job may not have completed yet: a cancel of
  /// it is too late.
  void accept(ChatId chatId, ClientMessageId clientMessageId) =>
      _$phases[_ref(chatId, clientMessageId)] = const SendPhase.accepted();
}

/// Where one outgoing message's send to the server stands, between the
/// outbox's cancel and the chat publisher, which share it.
///
/// A closed set, so a cancel waiting on an accepted message cannot be
/// represented: [SendPhase$Sending] alone carries a waiting cancel.
@internal
@immutable
sealed class SendPhase {
  const SendPhase._();

  /// No sender call is out and the server has not accepted the message.
  const factory SendPhase.idle() = SendPhase$Idle;

  /// The sender call is out; [cancel] is the cancel waiting for its answer.
  const factory SendPhase.sending({void Function()? cancel}) =
      SendPhase$Sending;

  /// The server accepted the message: a cancel is too late.
  const factory SendPhase.accepted() = SendPhase$Accepted;
}

/// [SendPhase.idle].
@internal
final class SendPhase$Idle extends SendPhase {
  /// The phase.
  const SendPhase$Idle() : super._();
}

/// [SendPhase.sending].
@internal
final class SendPhase$Sending extends SendPhase {
  /// The phase, with [cancel] waiting for the answer if given.
  const SendPhase$Sending({this.cancel}) : super._();

  /// The cancel to run once the answer comes, unless it is an accept.
  final void Function()? cancel;
}

/// [SendPhase.accepted].
@internal
final class SendPhase$Accepted extends SendPhase {
  /// The phase.
  const SendPhase$Accepted() : super._();
}

/// A message's publish job as the outbox last saw it: its id, its state and
/// the stage it is in.
@internal
@immutable
final class OutboxJobView {
  /// Job [id], last seen in [state] at [stage]; with no state, a job made
  /// but not seen yet.
  const OutboxJobView(this.id, {this.state, this.stage});

  /// The job's id.
  final PublishJobId id;

  /// The job's state; null until the job's first snapshot.
  final PublishJobState? state;

  /// The stage the job is in; null once it completed, or while it waits
  /// for its owner.
  final PublishStage? stage;
}
