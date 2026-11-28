import 'dart:async';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:attach_model/attach_model.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_delivery.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outgoing_payload.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/fake_chat_server.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show Listenable, ValueNotifier;
import 'package:listen/listen.dart' as listen;
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// The demo host's outbox: one `ChatOutbox` for every chat of the app, over
/// the transfer engine's publish jobs, its sender answering through the
/// in-process [server].
///
/// Made once, in the composition root, with the sender registered at once;
/// each chat is bound through [chat]. The ids are the server's: a chat's
/// rows sit at `tip+1 …` (`SequentialServerIds`), and the server accepts a
/// send only at its next id.
final class DemoOutbox {
  /// An outbox making its jobs through [transfers], sending as [sender] to
  /// [server] (a new one unless given).
  DemoOutbox({
    required OutboxTransfers transfers,
    FakeChatServer? server,
    this.sender = 'Hixie',
  }) : server = server ?? FakeChatServer() {
    outbox = ChatOutbox<DemoOutgoingPayload>(
      transfers: transfers,
      codec: const DemoOutgoingPayloadCodec(),
      itemOf: _itemOf,
      idStrategyOf: (chatId) => SequentialServerIds(
        chatId: chatId,
        tail: OutgoingTailTarget.of(chat(chatId)._source),
      ),
      rowOf: (message, payload) =>
          chat(message.chatId)._rowOf(message, payload),
      capabilitiesOf: (chatId) => _$chats[chatId]?._capabilities,
      feedback: CapabilityFeedback(
        denialText: (action, reason) =>
            _$focused?._denialText?.call(action, reason),
        onDenied: (action, reason) =>
            _$focused?._onDenied?.call(action, reason),
      ),
      onSent: (sent) => chat(sent.chatId)._onSent(sent),
      onCancelled: (cancelled) =>
          chat(cancelled.message.chatId)._onCancelled(cancelled),
      onStatusChanged: (message) =>
          chat(message.chatId)._onStatusChanged(message),
      localKeyOf: localKeyOf,
      undecodableRowOf: (message) =>
          chat(message.chatId)._undecodableRow(message),
    )..registerSender(_ServerSender(this));
  }

  /// The server every chat sends to.
  final FakeChatServer server;

  /// The user the demo sends as.
  final String sender;

  /// The outbox itself: statuses, lookups, cancel, retry and delete.
  late final ChatOutbox<DemoOutgoingPayload> outbox;

  final Map<String, DemoOutboxChat> _$chats = {};

  /// The chat whose screen is open: the denial feedback goes to it, since
  /// the outbox's hook does not name the chat.
  DemoOutboxChat? _$focused;

  bool _$disposed = false;

  /// The binding of [chatId], made on first use and kept for the app's run.
  DemoOutboxChat chat(String chatId) =>
      _$chats.putIfAbsent(chatId, () => DemoOutboxChat._(this, chatId));

  /// The local content key a send item's [mediaKey] is cached under, the
  /// inverse of the media key a send gives it.
  static ContentKey localKeyOf(MediaKey mediaKey) =>
      ContentKey.document('$_localPrefix${mediaKey.encoded}');

  static const String _localPrefix = 'local:';

  // The prepared files of the send being accepted, by attach item: `send`
  // calls [_itemOf] synchronously, item by item.
  Map<AttachItemId, PreparedMedia> _$prepared = const {};

  // An item is uploaded from its prepared file. One the host could not
  // prepare (no work folder, as on the web) has no file the engine can
  // read: the demo sends it by its key alone, as content the server holds.
  OutgoingSendItem _itemOf(AttachItem item, SendForm form) {
    final mediaKey = switch (item.source) {
      AttachSource$Captured(:final localKey) ||
      AttachSource$Pasted(:final localKey) => MediaKey.parse(localKey),
      _ => MediaKey.local(_uuid()),
    };
    return OutgoingSendItem(
      localKey: localKeyOf(mediaKey),
      mediaKey: mediaKey,
      source: switch (_$prepared[item.id]) {
        final prepared? => PublishSource.prepared(prepared),
        null => const PublishSource.remote(),
      },
      fileName: item.facts.name,
    );
  }

  /// [message] as the chat's row.
  static UserChatMessage rowOfServer(FakeServerMessage message) {
    final at = message.sentAt.toLocal();
    return UserChatMessage(
      id: message.id,
      sender: message.sender,
      createdAt: at,
      updatedAt: at,
      content: message.body,
      payload: message.extras,
    );
  }

  static final Random _$random = Random.secure();

  static String _uuid() {
    final bytes = [for (var i = 0; i < 16; i++) _$random.nextInt(256)];
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [
      for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Stops the outbox and the server, and frees the chats' message sources;
  /// the jobs run on in the engine.
  Future<void> dispose() async {
    if (_$disposed) return;
    _$disposed = true;
    for (final chat in _$chats.values) {
      chat._dispose();
    }
    await outbox.dispose();
    server.dispose();
  }
}

/// One chat of the [DemoOutbox]: its message source, which the outbox's
/// rows live in, and the server's messages delivered into it.
///
/// [attach] hands it the chat's source once, on the chat's first open; the
/// binding keeps the source from then on, for the app's run, so the
/// outbox's rows and the sent messages are there when the chat opens again
/// and a send still in flight has its rows to move while the chat is
/// closed. Each open passes the screen's capabilities and denial feedback
/// ([attach]); [detach] takes them away when the screen goes.
final class DemoOutboxChat {
  DemoOutboxChat._(this._owner, this.chatId);

  final DemoOutbox _owner;

  /// The chat.
  final String chatId;

  ChatDataSource? _$source;
  StreamSubscription<FakeServerMessage>? _$deliveries;
  listen.ValueListenable<ChatCapabilities>? _capabilities;
  CapabilityDenialText? _denialText;
  CapabilityDeniedHandler? _onDenied;
  void Function(String announcement)? _announce;
  Future<SourceBytes?> Function(MediaItemId item)? _askForSource;

  /// The status of each outgoing message, as the outbox last reported it:
  /// the bubbles read it on every build, and the outbox's own lookup
  /// reports an echo match each time.
  final Map<String, OutgoingStatus> _$statuses = {};

  /// Ticks on each status change, for [deliveryChanges].
  final ValueNotifier<int> _$statusRevision = ValueNotifier(0);
  Listenable? _$deliveryChanges;

  /// The messages a retry is under way for: it may wait on the user for a
  /// lost source's file, and a second retry of one meanwhile is dropped.
  final Set<String> _$retrying = {};

  /// Which client message id each sent row had, by its server id: "logs of
  /// this message" follows a sent message by it.
  final Map<int, String> _$sentClientIds = {};

  /// The outgoing rows, by the row objects the outbox built: a moved row
  /// keeps its object, so its identity follows it.
  final Expando<String> _$identities = Expando('clientMessageId');

  ChatOutbox<DemoOutgoingPayload> get _outbox => _owner.outbox;

  /// The chat's message source, once attached.
  ChatDataSource? get source => _$source;

  ChatDataSource get _source =>
      _$source ??
      (throw StateError('Chat $chatId has no message source attached.'));

  /// Whether [source] is the one this binding holds (and frees).
  bool holds(ChatDataSource source) => identical(source, _$source);

  /// Binds the chat to [source] on its first open (a later open passes the
  /// same one, from [source]), reads back the messages an earlier run left
  /// sending ([ChatOutbox.pendingFor]) and takes the screen's
  /// [capabilities], [denialText] and [onDenied]. [announce] speaks a
  /// send's start and end to assistive technology; [askForSource] asks the
  /// user for the file of an item whose upload source was lost, for a
  /// retry.
  ///
  /// The server's counter starts after the history the source holds, and
  /// that history counts as read by the chat's peers.
  Future<void> attach(
    ChatDataSource source, {
    listen.ValueListenable<ChatCapabilities>? capabilities,
    CapabilityDenialText? denialText,
    CapabilityDeniedHandler? onDenied,
    void Function(String announcement)? announce,
    Future<SourceBytes?> Function(MediaItemId item)? askForSource,
  }) async {
    if (_$source case final held? when !identical(held, source)) {
      throw StateError('Chat $chatId is bound to another message source.');
    }
    _capabilities = capabilities;
    _denialText = denialText;
    _onDenied = onDenied;
    _announce = announce;
    _askForSource = askForSource;
    _owner._$focused = this;
    if (_$source == null) {
      _$source = source;
      source.identityOf = (message) => _$identities[message];
      final server = _owner.server..open(chatId, nextId: source.nextInsertId);
      if (source.nextInsertId > 0) {
        server.markRead(chatId, source.nextInsertId - 1);
      }
      _$deliveries = server.deliveries(chatId).listen(_onDelivery);
      _$deliveryChanges = Listenable.merge([
        _$statusRevision,
        server.readUpTo(chatId),
      ]);
    }
    for (final message in await _outbox.pendingFor(chatId)) {
      _$statuses.putIfAbsent(message.clientMessageId, () => message.status);
    }
  }

  /// The screen went: the outbox no longer reads its capabilities or shows
  /// its denials. The source and its rows stay.
  void detach() {
    _capabilities = null;
    _denialText = null;
    _onDenied = null;
    _announce = null;
    _askForSource = null;
    if (identical(_owner._$focused, this)) _owner._$focused = null;
  }

  /// Whether a send of the chat is in flight; see [ChatOutbox.sendInFlight].
  listen.ValueListenable<bool> get sendInFlight => _outbox.sendInFlight(chatId);

  /// Sends [body] (its [extras] beside it) as a text message; null when the
  /// chat's capabilities refuse it.
  OutgoingMessage? sendText(
    String body, {
    Map<String, Object?> extras = const {},
  }) => _accepted(
    _outbox.sendText(
      chatId,
      RichText.plain(body),
      payload: _payloadOf(body, extras),
    ),
  );

  /// Sends each of [sends], a send plan's, with the body the demo shows for
  /// it ([bodies], one per send) and the items' [prepared] files and send
  /// [origins] (the picker's, by planned send). Answers each message, or
  /// null for one the chat's capabilities refused.
  List<OutgoingMessage?> sendPlanned(
    List<PlannedSend> sends, {
    required List<String> bodies,
    Map<AttachItemId, PreparedMedia> prepared = const {},
    List<List<Rect?>>? origins,
  }) {
    if (bodies.length != sends.length) {
      throw ArgumentError.value(bodies.length, 'bodies', 'One per send.');
    }
    _owner._$prepared = prepared;
    try {
      return [
        for (final (index, send) in sends.indexed)
          _sendOne(send, bodies[index], origins?[index]),
      ];
    } finally {
      _owner._$prepared = const {};
    }
  }

  OutgoingMessage? _sendOne(
    PlannedSend send,
    String body,
    List<Rect?>? origins,
  ) {
    final message = _outbox.send(
      chatId,
      send,
      payload: _payloadOf(body, const {}),
      origins: origins,
    );
    _accepted(message);
    // The server shows the chat's peers that media is on its way.
    if (message != null && message.items.isNotEmpty) {
      _owner.server.sendStarted(chatId, message.clientMessageId);
    }
    return message;
  }

  // A send the outbox accepted starts: it reads sending, and says so.
  OutgoingMessage? _accepted(OutgoingMessage? message) {
    if (message == null) return null;
    _$statuses[message.clientMessageId] = message.status;
    _$statusRevision.value++;
    _announce?.call(DemoOutgoingStrings.sending);
    return message;
  }

  DemoOutgoingPayload _payloadOf(String body, Map<String, Object?> extras) =>
      DemoOutgoingPayload(sender: _owner.sender, body: body, extras: extras);

  /// Retries the failed message [clientMessageId]. A message whose source
  /// was lost (a web reload over the copy limit) asks the user for each
  /// item's file again through [askForSource] (the one [attach] took
  /// unless given) first; null when the user gave none, and nothing is
  /// retried.
  ///
  /// Guarded against a burst: while a retry of the message is under way
  /// (asking for a file, say), another one is dropped
  /// ([OutgoingRetryOutcome.dropped]); the outbox drops a repeat of an
  /// accepted retry as well. A retry the outbox accepts announces the
  /// send's start again.
  Future<OutgoingRetryOutcome?> retry(
    String clientMessageId, {
    Future<SourceBytes?> Function(MediaItemId item)? askForSource,
  }) async {
    if (!_$retrying.add(clientMessageId)) return OutgoingRetryOutcome.dropped;
    try {
      final message = _outbox.byClientMessageId(chatId, clientMessageId);
      final sources = <MediaItemId, SourceBytes>{};
      if ((message?.status, askForSource ?? _askForSource) case (
        OutgoingStatus$Failed(failure: OutgoingFailure$SourceLost()),
        final ask?,
      )) {
        for (final item in message!.items) {
          final bytes = await ask(item.id);
          if (bytes == null) return null;
          sources[item.id] = bytes;
        }
      }
      final outcome = _outbox.retry(chatId, clientMessageId, sources: sources);
      if (outcome == OutgoingRetryOutcome.retried) {
        _announce?.call(DemoOutgoingStrings.sending);
      }
      return outcome;
    } finally {
      _$retrying.remove(clientMessageId);
    }
  }

  /// [retry] of the outgoing message whose row is at [id]; null for a row
  /// that is not one.
  Future<OutgoingRetryOutcome?> retryAt(int id) async =>
      switch (_outgoingAt(id)) {
        final clientMessageId? => retry(clientMessageId),
        null => null,
      };

  /// Deletes the outgoing message whose row is at [id] (its menu's
  /// Delete): its job is cancelled and its row leaves the chat. Null for a
  /// row that is not one; the outbox drops a repeat
  /// ([OutgoingCancelOutcome.dropped]).
  OutgoingCancelOutcome? deleteAt(int id) => switch (_outgoingAt(id)) {
    final clientMessageId? => _outbox.delete(chatId, clientMessageId),
    null => null,
  };

  /// Whether the row at [id] is an outgoing message that failed: its menu
  /// is Retry and Delete.
  bool isFailedAt(int id) => deliveryOf(id) == DemoDelivery.notSent;

  /// What the time pill of the user's own message at [id] shows; null for
  /// a row the chat does not hold.
  ///
  /// A message on its way or failed reads the outbox's status. A sent one
  /// reads the server's: read once a peer read up to it, else one check.
  DemoDelivery? deliveryOf(int id) {
    final row = _$source?.getMessage(id);
    if (row == null) return null;
    if (_$identities[row] case final clientMessageId?) {
      return switch (_$statuses[clientMessageId]) {
        OutgoingStatus$Failed() => DemoDelivery.notSent,
        OutgoingStatus$Sent() => _readOrSent(id),
        OutgoingStatus$Preparing() ||
        OutgoingStatus$Uploading() ||
        OutgoingStatus$Publishing() ||
        OutgoingStatus$Cancelled() ||
        null => DemoDelivery.sending,
      };
    }
    return _readOrSent(id);
  }

  DemoDelivery _readOrSent(int id) =>
      (_owner.server.readUpTo(chatId).value ?? -1) >= id
      ? DemoDelivery.read
      : DemoDelivery.sent;

  /// Notifies when what [deliveryOf] answers may have changed: an outgoing
  /// message's status, or how far the chat's peers have read. A status
  /// change need not move the row, so the pill cannot wait for one.
  Listenable get deliveryChanges => _$deliveryChanges ?? _$statusRevision;

  /// The client message id of the outgoing row at [id], or null.
  String? _outgoingAt(int id) => switch (_$source?.getMessage(id)) {
    final row? => _$identities[row],
    null => null,
  };

  /// The client message id of the row at [id]: an outgoing row's, or a
  /// sent one's; null for any other message.
  String? clientMessageIdAt(int id) => switch (_$source?.getMessage(id)) {
    final message? => _$identities[message] ?? _$sentClientIds[id],
    null => null,
  };

  // --- The outbox's hooks ---------------------------------------------------

  UserChatMessage _rowOf(OutgoingMessage message, DemoOutgoingPayload payload) {
    final now = DateTime.now();
    final row = UserChatMessage(
      id: message.position,
      sender: payload.sender,
      createdAt: now,
      updatedAt: now,
      content: payload.body,
      payload: payload.extras,
    );
    _$identities[row] = message.clientMessageId;
    return row;
  }

  // A payload the codec cannot read: a row in the tail the user can still
  // delete, with nothing of the message to show.
  IChatMessage _undecodableRow(OutgoingMessage message) {
    final now = DateTime.now();
    final row = UserChatMessage(
      id: message.position,
      sender: _owner.sender,
      createdAt: now,
      updatedAt: now,
      content: '…',
    );
    _$identities[row] = message.clientMessageId;
    return row;
  }

  void _onSent(OutgoingSent<DemoOutgoingPayload> sent) {
    _$sentClientIds[sent.position] = sent.clientMessageId;
    final payload = sent.payloadAsStored ?? sent.payload;
    final source = _source;
    final previous = switch (sent.rowAt) {
      final at? => source.getMessage(at),
      null => null,
    };
    final confirmed = UserChatMessage(
      id: sent.position,
      sender: payload.sender,
      createdAt: previous?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      content: payload.body,
      payload: payload.extras,
    );
    switch (sent.rowAt) {
      case _?:
        source.updateMessage(confirmed, reason: 'outbox-sent');
      // The row left the tail (a replay at an id it could not reach): the
      // message goes in once the chat's history reaches its id.
      case null when sent.position == source.nextInsertId:
        source.insertMessage(confirmed, reason: 'outbox-sent');
      case null:
        break;
    }
  }

  // The end of a send is announced: sent, or not sent.
  void _onStatusChanged(OutgoingMessage message) {
    _$statuses[message.clientMessageId] = message.status;
    _$statusRevision.value++;
    switch (message.status) {
      case OutgoingStatus$Sent():
        _announce?.call(DemoOutgoingStrings.sent);
      case OutgoingStatus$Failed():
        _announce?.call(DemoOutgoingStrings.notSent);
      case OutgoingStatus$Preparing() ||
          OutgoingStatus$Uploading() ||
          OutgoingStatus$Publishing() ||
          OutgoingStatus$Cancelled():
        break;
    }
  }

  void _onCancelled(OutgoingCancelled cancelled) {
    _$statuses.remove(cancelled.message.clientMessageId);
    _$statusRevision.value++;
    if (cancelled.rowRemoved) return;
    _$source?.removeMessages([cancelled.message.position]);
  }

  // --- The server's deliveries -----------------------------------------------

  void _onDelivery(FakeServerMessage message) {
    final source = _$source;
    if (source == null) return;
    // The echo of the user's own message: the outgoing row is its one row.
    if (message.clientMessageId case final clientMessageId?
        when _outbox.byClientMessageId(chatId, clientMessageId) != null) {
      return;
    }
    // Already placed: a conflict's or a replay's missing messages go in
    // before their delivery arrives.
    if (source.getMessage(message.id) case final held?
        when _$identities[held] == null) {
      return;
    }
    final row = DemoOutbox.rowOfServer(message);
    if (_outbox.idStrategy(chatId).incoming([row])) return;
    if (message.id == source.nextInsertId) {
      source.insertMessage(row, reason: 'server');
    }
  }

  void _dispose() {
    _$statusRevision.dispose();
    unawaited(_$deliveries?.cancel());
    _$source?.dispose();
    _$source = null;
  }
}

/// The outbox's sender over the fake server: each attempt is one send to
/// it, and each answer the outbox's.
final class _ServerSender
    implements OutgoingMessageSender<DemoOutgoingPayload> {
  _ServerSender(this._owner);

  final DemoOutbox _owner;

  @override
  Future<OutgoingSendAnswer<DemoOutgoingPayload>> send(
    OutgoingSendRequest<DemoOutgoingPayload> request,
  ) async {
    final payload = request.payload;
    final answer = await _owner.server.send(
      FakeServerSend(
        chatId: request.chatId,
        clientMessageId: request.clientMessageId,
        proposedId: request.proposedId,
        sender: payload.sender,
        body: payload.body,
        extras: payload.extras,
        itemIds: [for (final id in request.items.keys) '$id'],
      ),
    );
    List<IChatMessage> rows(List<FakeServerMessage> messages) => [
      for (final message in messages) DemoOutbox.rowOfServer(message),
    ];
    return switch (answer) {
      FakeServerAccepted(:final message, :final missing) =>
        OutgoingSendAnswer.sent(
          serverMessageId: message.id,
          payloadAsStored: DemoOutgoingPayload(
            sender: message.sender,
            body: message.body,
            extras: message.extras,
          ),
          missing: rows(missing),
        ),
      FakeServerConflict(:final nextId, :final missing) =>
        OutgoingSendAnswer.conflict(nextId: nextId, missing: rows(missing)),
      FakeServerRejected(:final code) => OutgoingSendAnswer.rejected(
        code,
        retryable: true,
      ),
      FakeServerDenied() => OutgoingSendAnswer.denied(
        request.items.isEmpty
            ? CapabilityAction.sendText
            : CapabilityAction.sendPhoto,
        const DenialReason.everyone(),
      ),
      FakeServerReupload(:final itemIds) => OutgoingSendAnswer.reuploadItems([
        for (final id in itemIds) MediaItemId.parse(id),
      ]),
    };
  }
}
