import 'dart:async';
import 'dart:convert';

import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// The operation of the `outbox` diagnostics event the demo's fake server
/// emits.
enum FakeServerOp implements DiagnosticOp {
  /// The server played a scripted event (debug): `event` is `peer`,
  /// `conflict`, `reject`, `deny`, `reupload` or `replay`, with the chat and
  /// the client message id of the send it acted on (none for a peer posted
  /// on its own).
  fakeServer,
}

/// What the demo's fake server does to a chat's next send, armed by
/// [FakeChatServer.script] and played once.
enum FakeServerScript {
  /// A peer posts a message while the next send uploads: the outgoing row
  /// moves up by one under it.
  peer,

  /// A peer's message takes the next id unseen, so the next send's proposal
  /// conflicts; it arrives after the answer.
  conflict,

  /// The next send is rejected, retryable.
  reject,

  /// The next send is refused as a server denial.
  deny,

  /// The next send's items are asked for again, once.
  reupload,

  /// The next send is stored past a peer's message, at an id other than its
  /// proposal, as a replay of an earlier attempt would be answered.
  replay,
}

/// One message as the fake server stores it.
@immutable
final class FakeServerMessage {
  /// A message stored at [id].
  const FakeServerMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.sentAt,
    this.extras = const {},
    this.clientMessageId,
  });

  /// Its id in the chat: the server's sequential counter.
  final int id;

  /// Who sent it.
  final String sender;

  /// The markdown body.
  final String body;

  /// The message's other fields (link preview, `invertMedia`).
  final Map<String, Object?> extras;

  /// The author's client message id, for a message a client sent; null for
  /// one the server made (a peer's, in the demo).
  final String? clientMessageId;

  /// When the server stored it.
  final DateTime sentAt;

  @override
  bool operator ==(Object other) =>
      other is FakeServerMessage &&
      other.id == id &&
      other.sender == sender &&
      other.body == body &&
      other.clientMessageId == clientMessageId &&
      other.sentAt == sentAt &&
      jsonEncode(other.extras) == jsonEncode(extras);

  @override
  int get hashCode => Object.hash(
    id,
    sender,
    body,
    clientMessageId,
    sentAt,
    jsonEncode(extras),
  );

  // The body is user content: it stays out of logs.
  @override
  String toString() => 'FakeServerMessage($id, $clientMessageId)';
}

/// [FakeServerMessage] to the row the fake server stores, and back.
///
/// ## Format
///
/// One JSON-compatible map, the server's stored form:
///
/// | Key | Value |
/// |---|---|
/// | `id` | [FakeServerMessage.id], an int |
/// | `sender` | [FakeServerMessage.sender], a string |
/// | `body` | [FakeServerMessage.body], a string |
/// | `sentAt` | [FakeServerMessage.sentAt], microseconds since the epoch, UTC |
/// | `extras` | [FakeServerMessage.extras], a map; left out when empty |
/// | `clientMessageId` | [FakeServerMessage.clientMessageId]; left out when null |
///
/// A row missing a field, or holding a value of the wrong type, throws a
/// [FormatException] naming the field.
final class FakeServerMessageCodec
    extends Codec<FakeServerMessage, Map<String, Object?>> {
  /// The codec.
  const FakeServerMessageCodec();

  @override
  Converter<FakeServerMessage, Map<String, Object?>> get encoder =>
      const _RowEncoder();

  @override
  Converter<Map<String, Object?>, FakeServerMessage> get decoder =>
      const _RowDecoder();
}

abstract final class _Key {
  static const String id = 'id';
  static const String sender = 'sender';
  static const String body = 'body';
  static const String sentAt = 'sentAt';
  static const String extras = 'extras';
  static const String clientMessageId = 'clientMessageId';
}

final class _RowEncoder
    extends Converter<FakeServerMessage, Map<String, Object?>> {
  const _RowEncoder();

  @override
  Map<String, Object?> convert(FakeServerMessage input) => {
    _Key.id: input.id,
    _Key.sender: input.sender,
    _Key.body: input.body,
    _Key.sentAt: input.sentAt.toUtc().microsecondsSinceEpoch,
    if (input.extras.isNotEmpty) _Key.extras: input.extras,
    _Key.clientMessageId: ?input.clientMessageId,
  };
}

final class _RowDecoder
    extends Converter<Map<String, Object?>, FakeServerMessage> {
  const _RowDecoder();

  @override
  FakeServerMessage convert(Map<String, Object?> input) => FakeServerMessage(
    id: _read<int>(input, _Key.id),
    sender: _read<String>(input, _Key.sender),
    body: _read<String>(input, _Key.body),
    sentAt: DateTime.fromMicrosecondsSinceEpoch(
      _read<int>(input, _Key.sentAt),
      isUtc: true,
    ),
    extras: switch (input[_Key.extras]) {
      null => const {},
      final Map<String, Object?> extras => extras,
      _ => throw const FormatException(
        'Stored message field "${_Key.extras}" is not a map',
      ),
    },
    clientMessageId: switch (input[_Key.clientMessageId]) {
      null => null,
      final String id => id,
      _ => throw const FormatException(
        'Stored message field "${_Key.clientMessageId}" is not a string',
      ),
    },
  );

  static T _read<T>(Map<String, Object?> map, String key) => switch (map[key]) {
    final T value => value,
    null => throw FormatException('Stored message field "$key" is missing'),
    _ => throw FormatException('Stored message field "$key" is not a $T'),
  };
}

/// One send as a client hands it to the fake server.
@immutable
final class FakeServerSend {
  /// A send of [body] from [sender] to [chatId].
  const FakeServerSend({
    required this.chatId,
    required this.clientMessageId,
    required this.sender,
    required this.body,
    this.proposedId,
    this.extras = const {},
    this.itemIds = const [],
  });

  /// The chat.
  final String chatId;

  /// The client's id of the message: the server's idempotency key.
  final String clientMessageId;

  /// The id the client proposes; null to take whatever is next.
  final int? proposedId;

  /// Who sends it.
  final String sender;

  /// The markdown body.
  final String body;

  /// The message's other fields.
  final Map<String, Object?> extras;

  /// The ids of the items the send carries, as uploaded.
  final List<String> itemIds;
}

/// What the fake server answers a send.
@immutable
sealed class FakeServerAnswer {
  const FakeServerAnswer();
}

/// The send is stored as [message]; [missing] are the messages before it
/// that the client's proposal shows it lacks.
final class FakeServerAccepted extends FakeServerAnswer {
  /// See [FakeServerAccepted].
  const FakeServerAccepted(this.message, {this.missing = const []});

  /// The message as stored.
  final FakeServerMessage message;

  /// The messages between the client's proposal and [message].
  final List<FakeServerMessage> missing;
}

/// The proposal is not the next id: [nextId] is, after [missing].
final class FakeServerConflict extends FakeServerAnswer {
  /// See [FakeServerConflict].
  const FakeServerConflict({required this.nextId, this.missing = const []});

  /// The server's next id.
  final int nextId;

  /// The messages from the proposal up to [nextId].
  final List<FakeServerMessage> missing;
}

/// The send is rejected with [code]; a try again may pass.
final class FakeServerRejected extends FakeServerAnswer {
  /// See [FakeServerRejected].
  const FakeServerRejected(this.code);

  /// The server's code.
  final String code;
}

/// The server refuses the send as not allowed in the chat.
final class FakeServerDenied extends FakeServerAnswer {
  /// See [FakeServerDenied].
  const FakeServerDenied();
}

/// The server asks for [itemIds] again: their references expired.
final class FakeServerReupload extends FakeServerAnswer {
  /// See [FakeServerReupload].
  const FakeServerReupload(this.itemIds);

  /// The items to upload again.
  final Set<String> itemIds;
}

/// The demo's chat server, in the process: one sequential id counter per
/// chat that accepts a send only at its proposed id when that id is the
/// next one (accept-if-next), and peers whose messages it posts.
///
/// Every message it stores goes to the chat's [deliveries], the author's
/// own as its echo (with its client message id), after [deliveryDelay].
/// The same client message id sent again answers the stored message: the
/// server is idempotent by it.
///
/// [script] arms one event for the chat's next send ([FakeServerScript]);
/// each played event reports `outbox` / `fakeServer`. A peer reads what the
/// user sent [readDelay] after it is stored ([readUpTo], the second check);
/// null leaves it unread until [markRead].
///
/// Example only: it keeps its rows in memory, in their stored form
/// ([FakeServerMessageCodec]), for the app's run.
final class FakeChatServer {
  /// A server with no chats.
  FakeChatServer({
    this.deliveryDelay = Duration.zero,
    this.peerDelay = const Duration(milliseconds: 400),
    this.readDelay,
    DateTime Function() now = DateTime.now,
  }) : _now = now;

  /// How long a stored message takes to reach the chat's clients.
  final Duration deliveryDelay;

  /// How long after a send starts uploading an armed peer posts.
  final Duration peerDelay;

  /// How long after the user's message is stored a peer reads it.
  final Duration? readDelay;

  /// The name a peer's messages carry.
  static const String peerName = 'Peer';

  static const String _rejectedCode = 'demo.rejected';

  static const FakeServerMessageCodec _$codec = FakeServerMessageCodec();

  final DateTime Function() _now;
  final Map<String, _ChatLog> _$chats = {};
  bool _$disposed = false;

  /// Opens [chatId] with its counter at [nextId], the id after the history
  /// the client already holds; a chat already open keeps its counter.
  void open(String chatId, {required int nextId}) {
    _$chats.putIfAbsent(chatId, () => _ChatLog(nextId));
  }

  _ChatLog _chat(String chatId) =>
      _$chats[chatId] ??
      (throw StateError('Chat $chatId is not open on the fake server.'));

  /// The id the chat's next message takes.
  int nextIdOf(String chatId) => _chat(chatId).nextId;

  /// Every message stored in [chatId] from now on, as its clients receive
  /// them.
  Stream<FakeServerMessage> deliveries(String chatId) =>
      _chat(chatId).deliveries.stream;

  /// The id up to which a peer has read the chat, or null before any read.
  ValueListenable<int?> readUpTo(String chatId) => _chat(chatId).readUpTo;

  /// Marks the chat read up to [id].
  void markRead(String chatId, int id) {
    final read = _chat(chatId).readUpTo;
    if ((read.value ?? -1) < id) read.value = id;
  }

  /// Arms [script] for the chat's next send; a later arm replaces it.
  void script(String chatId, FakeServerScript script) =>
      _chat(chatId).armed = script;

  /// The script armed for [chatId], if any.
  FakeServerScript? armedOf(String chatId) => _chat(chatId).armed;

  /// A peer posts a message to [chatId] now; it is delivered as any other.
  ///
  /// Reports `fakeServer` (`peer`) with the chat alone.
  FakeServerMessage postPeer(String chatId, {String body = 'A peer replies'}) {
    _report(chatId, FakeServerScript.peer, null);
    return _postPeer(chatId, body);
  }

  FakeServerMessage _postPeer(String chatId, String body) {
    final message = _store(_chat(chatId), sender: peerName, body: body);
    _deliver(chatId, message);
    return message;
  }

  /// A client tells the server a send of [clientMessageId] started
  /// uploading, as a client shows its peers that it is sending media; an
  /// armed peer posts [peerDelay] later.
  void sendStarted(String chatId, String clientMessageId) {
    final chat = _chat(chatId);
    if (chat.armed != FakeServerScript.peer) return;
    chat.armed = null;
    _report(chatId, FakeServerScript.peer, clientMessageId);
    Timer(peerDelay, () {
      if (_$disposed) return;
      _postPeer(chatId, 'A peer replies');
    });
  }

  /// Answers [send].
  Future<FakeServerAnswer> send(FakeServerSend send) async {
    final chat = _chat(send.chatId);
    final cmid = send.clientMessageId;
    // Idempotent by the client message id: an earlier attempt's message is
    // the answer again.
    if (chat.byClientId[cmid] case final id?) {
      return FakeServerAccepted(
        chat.message(id),
        missing: chat.between(send.proposedId, id),
      );
    }
    final delivered = <FakeServerMessage>[];
    switch (chat.armed) {
      case FakeServerScript.reject:
        chat.armed = null;
        _report(send.chatId, FakeServerScript.reject, cmid);
        return const FakeServerRejected(_rejectedCode);
      case FakeServerScript.deny:
        chat.armed = null;
        _report(send.chatId, FakeServerScript.deny, cmid);
        return const FakeServerDenied();
      case FakeServerScript.reupload when send.itemIds.isNotEmpty:
        chat.armed = null;
        _report(send.chatId, FakeServerScript.reupload, cmid);
        return FakeServerReupload(send.itemIds.toSet());
      case FakeServerScript.conflict:
        chat.armed = null;
        _report(send.chatId, FakeServerScript.conflict, cmid);
        // Delivered after the answer: the client learns of it from the
        // conflict first.
        delivered.add(_store(chat, sender: peerName, body: 'A peer was first'));
      case FakeServerScript.replay:
        chat.armed = null;
        _report(send.chatId, FakeServerScript.replay, cmid);
        delivered.add(_store(chat, sender: peerName, body: 'A peer was first'));
        final message = _storeSend(chat, send);
        delivered.add(message);
        _later(send.chatId, delivered);
        return FakeServerAccepted(
          message,
          missing: chat.between(send.proposedId, message.id),
        );
      case FakeServerScript.peer || FakeServerScript.reupload || null:
        break;
    }
    if (send.proposedId case final proposed? when proposed != chat.nextId) {
      _later(send.chatId, delivered);
      return FakeServerConflict(
        nextId: chat.nextId,
        missing: chat.between(proposed, chat.nextId),
      );
    }
    final message = _storeSend(chat, send);
    delivered.add(message);
    _later(send.chatId, delivered);
    return FakeServerAccepted(message);
  }

  FakeServerMessage _storeSend(_ChatLog chat, FakeServerSend send) {
    final message = _store(
      chat,
      sender: send.sender,
      body: send.body,
      extras: send.extras,
      clientMessageId: send.clientMessageId,
    );
    if (readDelay case final delay?) {
      final chatId = send.chatId;
      Timer(delay, () {
        if (_$disposed) return;
        markRead(chatId, message.id);
      });
    }
    return message;
  }

  FakeServerMessage _store(
    _ChatLog chat, {
    required String sender,
    required String body,
    Map<String, Object?> extras = const {},
    String? clientMessageId,
  }) {
    final message = FakeServerMessage(
      id: chat.nextId,
      sender: sender,
      body: body,
      extras: extras,
      clientMessageId: clientMessageId,
      sentAt: _now().toUtc(),
    );
    chat.rows[message.id] = _$codec.encode(message);
    if (clientMessageId != null) chat.byClientId[clientMessageId] = message.id;
    chat.nextId++;
    return message;
  }

  void _later(String chatId, List<FakeServerMessage> messages) {
    if (messages.isEmpty) return;
    Timer(deliveryDelay, () {
      if (_$disposed) return;
      for (final message in messages) {
        _deliver(chatId, message);
      }
    });
  }

  void _deliver(String chatId, FakeServerMessage message) {
    final chat = _chat(chatId);
    if (!chat.deliveries.isClosed) chat.deliveries.add(message);
  }

  static void _report(
    String chatId,
    FakeServerScript script,
    String? clientMessageId,
  ) => ChatDiagnostics.current.emit(
    ChatEventLevel.debug,
    ChatEventCategory.outbox,
    FakeServerOp.fakeServer,
    correlation: ChatCorrelation(
      chatId: chatId,
      clientMessageId: clientMessageId,
    ),
    fields: () => {'event': script.name},
  );

  /// Closes every chat's deliveries; pending timers do nothing.
  void dispose() {
    if (_$disposed) return;
    _$disposed = true;
    for (final chat in _$chats.values) {
      chat.close();
    }
  }
}

/// One chat on the fake server: its rows by id, in their stored form.
final class _ChatLog {
  _ChatLog(this.nextId);

  int nextId;
  final Map<int, Map<String, Object?>> rows = {};
  final Map<String, int> byClientId = {};
  final StreamController<FakeServerMessage> deliveries =
      StreamController.broadcast();
  final ValueNotifier<int?> readUpTo = ValueNotifier(null);
  FakeServerScript? armed;

  void close() {
    unawaited(deliveries.close());
    readUpTo.dispose();
  }

  FakeServerMessage message(int id) => FakeChatServer._$codec.decode(rows[id]!);

  /// The stored messages from [from] up to, not including, [to]; none
  /// without a [from].
  List<FakeServerMessage> between(int? from, int to) => [
    if (from != null)
      for (var id = from; id < to; id++)
        if (rows.containsKey(id)) message(id),
  ];
}
