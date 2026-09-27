import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_linkify_util.dart';
import 'package:flutter/foundation.dart'
    show Listenable, ValueChanged, VoidCallback;
import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Invokes a demo Edge Function and returns parsed JSON (test override supported).
typedef EdgeFunctionInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> body,
    );

/// A realtime reconnect after which the chat has messages newer than
/// [newestBeforeDrop], the newest id known when the feed dropped — `null`
/// when the chat was empty then, so every message may have been missed.
/// [lastReadMessageId] is the stored read mark re-read with the newest id,
/// or `null` when there is none.
typedef RealtimeReconnectGap = ({
  int? newestBeforeDrop,
  int? lastReadMessageId,
});

/// Supabase-backed [ChatDataSource] for the demo (Edge Functions + Realtime).
///
/// ## Realtime
///
/// While subscribed, one channel for [chatId] delivers message inserts and
/// read-state changes of [userId] in that chat. Message inserts upsert the
/// row and advance [newestKnownId]. A read-state change whose `write_tag`
/// is not [writeTag] — another client's write, or an untagged server move of
/// the cursor — notifies [readElsewhere]; an echo of this client's own
/// [updateLastReadMessageId] is dropped. [dispose] removes the channel and
/// silences [readElsewhere] and the reconnect gap listeners.
///
/// ## Reconnect gap
///
/// Inserts that land while the channel is down are never delivered. When a
/// channel that was subscribed reports an error, a close, or a timeout, the
/// source keeps [newestKnownId] as the newest id before the drop. On the
/// next subscribe it re-reads the chat's newest message id and the stored
/// read mark. If the newest id moved past the one before the drop, it seeds
/// the new [newestKnownId] — the missed rows then load like any unloaded
/// tail — and reports a [RealtimeReconnectGap] to every listener added with
/// [addReconnectGapListener]. A chat that was empty at the drop and has
/// messages now is reseeded like a fresh connect: the newest id is known,
/// [reachedOldest] is `false`, and older pages load from the tail.
///
/// Re-reads run one at a time. After a drop during a re-read, the next gap
/// starts at the newest id that re-read saw, so no missed span is reported
/// twice. A reconnect with nothing new, the first subscribe (even after
/// failed attempts), and a failed re-read (logged) report nothing.
class BackendChatDataSource extends ChatDataSource {
  /// Creates a new [BackendChatDataSource] instance.
  ///
  /// [writeTag] defaults to a fresh random tag, so each instance counts as
  /// its own client.
  BackendChatDataSource({
    required SupabaseClient client,
    this.chatId = DemoConfig.demoChatId,
    this.userId = 1,
    this.requestTimeout = const Duration(seconds: 10),
    EdgeFunctionInvoker? invokeOverride,
    bool subscribeRealtime = true,
    String? writeTag,
  }) : _client = client,
       _invokeOverride = invokeOverride,
       writeTag = writeTag ?? _newWriteTag() {
    if (subscribeRealtime && invokeOverride == null) {
      _subscribeRealtime();
    }
  }

  /// Creates a new [BackendChatDataSource] instance for testing.
  @visibleForTesting
  factory BackendChatDataSource.forTest({
    required EdgeFunctionInvoker invoke,
    int chatId = 1,
    String? writeTag,
  }) => BackendChatDataSource(
    client: _placeholderClient,
    chatId: chatId,
    invokeOverride: invoke,
    subscribeRealtime: false,
    writeTag: writeTag,
  );

  /// Connect via `load_chat` and seed newest boundary from `last_message.id`.
  static Future<BackendChatDataSource> connect({
    required SupabaseClient client,
    int? chatId,
  }) async {
    final source = BackendChatDataSource(
      client: client,
      chatId: chatId ?? DemoConfig.demoChatId,
    );
    await source._loadChatAndSeedBoundaries();
    return source;
  }

  /// Connects to the test backend and seeds boundaries.
  @visibleForTesting
  static Future<BackendChatDataSource> connectForTest(
    EdgeFunctionInvoker invoke, {
    int chatId = 1,
  }) async {
    final source = BackendChatDataSource.forTest(
      invoke: invoke,
      chatId: chatId,
    );
    await source._loadChatAndSeedBoundaries();
    return source;
  }

  static final SupabaseClient _placeholderClient = SupabaseClient(
    'http://127.0.0.1:54321',
    'test-anon-key',
  );

  final SupabaseClient _client;

  /// The chat id.
  final int chatId;

  /// The signed-in user whose read state this source reads, writes, and
  /// follows.
  final int userId;

  /// The request timeout.
  final Duration requestTimeout;

  /// Tag stored with every read-state write of this client, so realtime can
  /// tell its echoes from other clients' writes.
  final String writeTag;

  /// The invoke override.
  final EdgeFunctionInvoker? _invokeOverride;

  RealtimeChannel? _channel;

  /// Notifies once per realtime read-state change of [userId] in [chatId]
  /// that this client did not write — including one whose read id equals
  /// the current one. Never notifies without a realtime subscription, and
  /// never after [dispose].
  Listenable get readElsewhere => _readElsewhere;
  final _readElsewhere = _ReadElsewhereSignal();

  final _reconnectGapListeners = <ValueChanged<RealtimeReconnectGap>>[];

  /// Whether the channel is subscribed; `false` before the first subscribe
  /// and after a drop.
  bool _realtimeLive = false;

  /// The drop of the live channel not yet consumed by a resubscribe, with
  /// [newestKnownId] at that moment (`null` for an empty chat); `null` when
  /// there is none.
  ({int? newestKnownId})? _drop;

  /// The last queued resync; each resync starts after the previous one
  /// settles, even when a gap listener of the previous one threw.
  Future<void> _resyncs = Future<void>.value();

  /// The newest id the last re-read that found a gap saw. A drop during a
  /// re-read records a [newestKnownId] from before that re-read's seed; the
  /// next resync reports from this id instead, so no missed span is
  /// reported twice.
  int? _rereadNewestId;

  static String _newWriteTag() {
    final random = math.Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  Future<void> _loadChatAndSeedBoundaries() async {
    switch (await _loadNewestMessageId()) {
      case final newestId?:
        seedBoundaries(newestKnownId: newestId, reachedNewest: true);
      case null:
        seedBoundaries(reachedOldest: true, reachedNewest: true);
    }
  }

  /// Id of the chat's newest message from `load_chat`, or `null` when the
  /// chat has none. Throws [BackendConnectionException] on a backend error.
  Future<int?> _loadNewestMessageId() async {
    final body = await _invokeJson(
      'load_chat',
      body: <String, dynamic>{'chat_id': chatId},
    );
    final error = body['error'];
    if (error is Map<String, Object?>) {
      final slug = error['slug'];
      if (slug == 'chat_not_found' || slug == 'service_unavailable') {
        throw BackendConnectionException(
          'Supabase is not seeded.\n'
          'Run: supabase db reset',
        );
      }
      throw BackendConnectionException(_formatError(error));
    }

    final chat = body['chat'];
    if (chat is! Map<String, Object?>) {
      throw BackendConnectionException('load_chat returned no chat');
    }

    return switch (chat['last_message']) {
      {'id': final int newestId} => newestId,
      _ => null,
    };
  }

  void _subscribeRealtime() {
    _channel = _client
        .channel('demo-chat-$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: _chatFilter,
          callback: (payload) {
            _applyRealtimeInsert(payload.newRecord);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_read_state',
          filter: _chatFilter,
          callback: (payload) => _applyRealtimeReadState(payload.newRecord),
        )
        .subscribe((status, error) {
          if (error != null) {
            dev.log(
              'Realtime channel $status',
              name: 'backend_chat',
              error: error,
            );
          }
          unawaited(_onRealtimeStatus(status));
        });
  }

  /// Tracks drops and resubscribes of the live channel — see the class
  /// overview. Completes when a resubscribe's re-read has been applied.
  Future<void> _onRealtimeStatus(RealtimeSubscribeStatus status) async {
    if (isDisposed) return;
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        _realtimeLive = true;
        final drop = _drop;
        _drop = null;
        if (drop case (:final newestKnownId)) {
          final resync = _resyncs.then(
            (_) => _resyncAfterReconnect(newestKnownId),
          );
          _resyncs = resync.catchError((Object _) {});
          await resync;
        }
      case RealtimeSubscribeStatus.channelError ||
          RealtimeSubscribeStatus.closed ||
          RealtimeSubscribeStatus.timedOut:
        if (!_realtimeLive) return;
        _realtimeLive = false;
        _drop = (newestKnownId: newestKnownId);
    }
  }

  /// Re-reads the newest message id and the stored read mark after a
  /// resubscribe. When the newest id moved past [recordedBeforeDrop] — or
  /// past [_rereadNewestId] when that is later — seeds it and then reports
  /// the gap from there, so listeners see the new
  /// [ChatDataSource.newestKnownId]. With neither (the chat was empty), any
  /// newest id counts and reseeds the chat like a fresh connect. A failed
  /// re-read is logged and reports nothing. Callers queue it on [_resyncs].
  Future<void> _resyncAfterReconnect(int? recordedBeforeDrop) async {
    if (isDisposed) return;
    final newestBeforeDrop = switch ((recordedBeforeDrop, _rereadNewestId)) {
      (final recorded?, final reread?) => math.max(recorded, reread),
      (final recorded, final reread) => recorded ?? reread,
    };
    final (int?, int?) reread;
    try {
      reread = await (_loadNewestMessageId(), getLastReadMessageId()).wait;
    } on Object catch (error, stackTrace) {
      dev.log(
        'Re-read after realtime reconnect failed; the gap is not reported',
        name: 'backend_chat',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    if (isDisposed) return;
    final (newest, lastRead) = reread;
    switch ((newest, newestBeforeDrop)) {
      case (null, _):
        return;
      case (final newest?, final before?) when newest <= before:
        return;
      case (final newest?, _):
        _rereadNewestId = newest;
        seedBoundaries(
          newestKnownId: math.max(newest, newestKnownId ?? newest),
          reachedOldest: newestBeforeDrop == null ? false : null,
          reachedNewest: true,
        );
    }
    final gap = (
      newestBeforeDrop: newestBeforeDrop,
      lastReadMessageId: lastRead,
    );
    for (final listener in List.of(_reconnectGapListeners, growable: false)) {
      listener(gap);
    }
  }

  /// Subscribes [listener] to reconnect gaps — see the class overview.
  /// Adding the same listener twice is a no-op; no-op after [dispose].
  void addReconnectGapListener(ValueChanged<RealtimeReconnectGap> listener) {
    if (isDisposed || _reconnectGapListeners.contains(listener)) return;
    _reconnectGapListeners.add(listener);
  }

  /// Unsubscribes [listener] from reconnect gaps. Safe after [dispose] and
  /// from inside a dispatch: a dispatch in flight still reaches every
  /// listener subscribed when it began.
  void removeReconnectGapListener(
    ValueChanged<RealtimeReconnectGap> listener,
  ) => _reconnectGapListeners.remove(listener);

  /// Test hook for a realtime channel status without a live channel;
  /// completes once a resubscribe's re-read has been applied.
  @visibleForTesting
  Future<void> applyRealtimeStatusForTest(RealtimeSubscribeStatus status) =>
      _onRealtimeStatus(status);

  /// Realtime filters take one column; the user is matched in
  /// [_applyRealtimeReadState].
  PostgresChangeFilter get _chatFilter => PostgresChangeFilter(
    type: PostgresChangeFilterType.eq,
    column: 'chat_id',
    value: chatId,
  );

  /// A DELETE carries an empty new record, which matches no chat and is
  /// dropped.
  void _applyRealtimeReadState(Map<String, Object?> record) {
    if (record['chat_id'] != chatId || record['user_id'] != userId) return;
    if (record['write_tag'] == writeTag) return;
    _readElsewhere.notify();
  }

  /// Test hook for a Realtime `chat_read_state` INSERT or UPDATE without a
  /// live channel.
  @visibleForTesting
  void applyRealtimeReadStateForTest(Map<String, Object?> record) {
    _applyRealtimeReadState(record);
  }

  /// Shared by Realtime subscription and tests (US5).
  void _applyRealtimeInsert(Map<String, Object?> record) {
    if (record.isEmpty) return;
    final message = _messageFromProtocolJson(Map<String, dynamic>.from(record));
    upsertMessage(message);
    final id = message.id;
    final newest = newestKnownId;
    if (newest == null || id > newest) {
      seedBoundaries(newestKnownId: id, reachedNewest: true);
    }
    notifyDataChanged();
  }

  /// Test hook for Realtime INSERT without a live channel.
  @visibleForTesting
  void applyRealtimeInsertForTest(Map<String, Object?> record) {
    _applyRealtimeInsert(record);
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    // Scroll chunk math includes id 0; Postgres message ids start at 1.
    final apiFromId = math.max(1, fromId);
    // Lift toId only when the scroll range started below 1 — preserves
    // intentional invalid ranges (e.g. toId < fromId) for API validation.
    final apiToId = fromId < 1 ? math.max(apiFromId, toId) : toId;
    final limit = math.min(apiToId - apiFromId + 1, 256);
    final batch = await _invokeJson(
      'load_messages',
      body: <String, dynamic>{
        'chat_id': chatId,
        'from_id': apiFromId,
        'to_id': apiToId,
        'limit': limit,
      },
    );

    final error = batch['error'];
    if (error is Map<String, Object?>) {
      Error.throwWithStackTrace(
        BackendConnectionException(_formatError(error)),
        StackTrace.current,
      );
    }

    final list = (batch['messages'] as List<Object?>? ?? const <Object?>[])
        .cast<Map<String, Object?>>();
    final messages = <IChatMessage>[
      for (final item in list) _messageFromProtocolJson(item),
    ];

    _applyBoundaryUpdate(
      messages,
      batch,
      scrollFromId: fromId,
      scrollToId: toId,
      apiFromId: apiFromId,
      apiToId: apiToId,
    );
    return messages;
  }

  /// Sends a text message via the `send_message` Edge Function.
  ///
  /// Linkifies [content] before the network call so the stored body matches
  /// host materialize (ADR 017).
  Future<UserChatMessage> sendMessage(String content) async {
    final linkified = ChatBodyLinkifyUtil.materialize(content);
    final body = await _invokeJson(
      'send_message',
      body: <String, dynamic>{
        'chat_id': chatId,
        'content': linkified,
        'sender_id': userId,
      },
    );

    final error = body['error'];
    if (error is Map<String, Object?>) {
      Error.throwWithStackTrace(
        BackendConnectionException(_formatError(error)),
        StackTrace.current,
      );
    }

    final messageJson = body['message']! as Map<String, Object?>;
    final message = _messageFromProtocolJson(messageJson);
    insertMessage(message, reason: 'backend-send');
    return message;
  }

  /// Fetches persisted last-read message id from Postgres (`get_read_state`).
  Future<int?> getLastReadMessageId() async {
    final body = await _invokeJson(
      'get_read_state',
      body: <String, dynamic>{'chat_id': chatId, 'user_id': userId},
    );

    final error = body['error'];
    if (error is Map<String, Object?>) {
      Error.throwWithStackTrace(
        BackendConnectionException(_formatError(error)),
        StackTrace.current,
      );
    }

    final id = body['last_read_message_id'];
    return id is int ? id : null;
  }

  /// Persists last-read at tail (`update_read_state`), tagged with
  /// [writeTag] so its realtime echo never reaches [readElsewhere].
  Future<void> updateLastReadMessageId(int messageId) async {
    final body = await _invokeJson(
      'update_read_state',
      body: <String, dynamic>{
        'chat_id': chatId,
        'user_id': userId,
        'last_read_message_id': messageId,
        'write_tag': writeTag,
      },
    );

    final error = body['error'];
    if (error is Map<String, Object?>) {
      Error.throwWithStackTrace(
        BackendConnectionException(_formatError(error)),
        StackTrace.current,
      );
    }
  }

  Future<Map<String, dynamic>> _invokeJson(
    String functionName, {
    required Map<String, dynamic> body,
  }) async {
    if (_invokeOverride != null) {
      return _invokeOverride(functionName, body);
    }
    try {
      final response = await _client.functions
          .invoke(functionName, body: body)
          .timeout(requestTimeout);
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is String && data.isNotEmpty) {
        return jsonDecode(data) as Map<String, dynamic>;
      }
      return <String, dynamic>{};
    } on TimeoutException {
      throw BackendConnectionException(
        'Timed out after ${requestTimeout.inSeconds}s calling $functionName\n'
        'Is Supabase running locally?\n'
        '  supabase start\n'
        '  supabase db reset\n'
        '  supabase functions serve',
      );
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map<String, dynamic> && details['error'] is Map) {
        throw BackendConnectionException(
          _formatError(details['error']! as Map<String, Object?>),
        );
      }
      throw BackendConnectionException(
        '$functionName failed (${e.status}): ${e.reasonPhrase ?? e.details}',
      );
    }
  }

  void _applyBoundaryUpdate(
    List<IChatMessage> messages,
    Map<String, Object?> meta, {
    required int scrollFromId,
    required int scrollToId,
    required int apiFromId,
    required int apiToId,
  }) {
    // `has_older` / `has_newer` in [meta] were computed for [apiFromId,
    // apiToId]. [scrollFromId] may be 0 (chunk-0 slot) while [apiFromId] is
    // 1 — missing scroll id 0 in [messages] is expected, not incomplete fetch.
    assert(() {
      final requestedFrom = meta['requested_from'];
      final requestedTo = meta['requested_to'];
      if (requestedFrom is int && requestedFrom != apiFromId) return false;
      if (requestedTo is int && requestedTo != apiToId) return false;
      return true;
    }(), 'load_messages meta range must match apiFromId/apiToId');

    final ids = messages.map((m) => m.id);
    final loadedMin = ids.isEmpty ? null : ids.reduce(math.min);
    final loadedMax = ids.isEmpty ? null : ids.reduce(math.max);

    var oldest = oldestKnownId;
    var newest = newestKnownId;
    if (loadedMin != null) {
      oldest = oldest == null ? loadedMin : math.min(oldest, loadedMin);
    }
    if (loadedMax != null) {
      newest = newest == null ? loadedMax : math.max(newest, loadedMax);
    }

    final hasOlder = meta['has_older'] == true;
    final hasNewer = meta['has_newer'] == true;
    final terminalOldest = meta['oldest_id'] as int?;
    final terminalNewest = meta['newest_id'] as int?;

    seedBoundaries(
      oldestKnownId: hasOlder ? oldest : terminalOldest,
      newestKnownId: hasNewer ? newest : terminalNewest,
      reachedOldest: hasOlder ? null : true,
      reachedNewest: hasNewer ? null : true,
    );
  }

  UserChatMessage _messageFromProtocolJson(Map<String, Object?> json) {
    final extra = json['extra'];
    final legacySender = extra is Map<String, Object?>
        ? extra['legacy_sender'] as String?
        : null;
    final senderId = json['sender_id'] as int? ?? 1;
    final createdAt = switch (json['created_at']) {
      final int createdSec => DateTime.fromMillisecondsSinceEpoch(
        createdSec * 1000,
        isUtc: true,
      ),
      final String createdAtStr =>
        DateTime.tryParse(createdAtStr) ?? DateTime.now().toUtc(),
      _ => DateTime.now().toUtc(),
    };
    final updatedAt = switch (json['updated_at']) {
      final int updatedSec => DateTime.fromMillisecondsSinceEpoch(
        updatedSec * 1000,
        isUtc: true,
      ),
      final String updatedAtStr => DateTime.tryParse(updatedAtStr) ?? createdAt,
      _ => createdAt,
    };

    return UserChatMessage(
      id: json['id']! as int,
      sender: legacySender ?? 'user$senderId',
      createdAt: createdAt,
      updatedAt: updatedAt,
      // Host materialize — plain or already-linked bodies from the protocol.
      content: ChatBodyLinkifyUtil.materialize(json['content']! as String),
    );
  }

  String _formatError(Map<String, Object?> error) {
    final slug = error['slug'];
    final message = error['message'];
    final base = slug != null ? '[$slug] $message' : '$message';
    if (slug == 'service_unavailable') {
      return '$base\nIs Supabase running?\n  supabase start\n  supabase db reset';
    }
    return base.toString();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      _client.removeChannel(channel);
      _channel = null;
    }
    _readElsewhere.dispose();
    _reconnectGapListeners.clear();
    super.dispose();
  }
}

/// Event-only [Listenable] behind [BackendChatDataSource.readElsewhere]:
/// dedup on add, snapshot dispatch, silent after [dispose].
final class _ReadElsewhereSignal implements Listenable {
  final _listeners = <VoidCallback>[];
  bool _disposed = false;

  @override
  void addListener(VoidCallback listener) {
    if (_disposed || _listeners.contains(listener)) return;
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void notify() {
    if (_disposed) return;
    for (final listener in List.of(_listeners, growable: false)) {
      listener();
    }
  }

  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}

/// Thrown when the demo backend is unreachable or returns an error status.
class BackendConnectionException implements Exception {
  /// Creates a new [BackendConnectionException] instance.
  BackendConnectionException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => message;
}
